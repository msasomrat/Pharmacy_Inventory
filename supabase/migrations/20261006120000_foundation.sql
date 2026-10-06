-- =============================================================================
-- Migration: foundation
-- Schemas, privilege hardening, shared enums, utility functions, audit log.
--
-- Conventions (docs/database/database-design.md):
--   * money      BIGINT paisa, columns suffixed _paisa (1 BDT = 100 paisa)
--   * percents   INTEGER basis points, suffixed _bp (100 bp = 1%)
--   * quantities INTEGER base units (smallest sellable unit)
--   * ids        UUID; human readable numbers (invoice_no, card_no) are separate columns
--   * times      TIMESTAMPTZ (UTC); business dates are computed in the org time zone
--   * schemas    public = API surface (RLS on every table)
--                app    = private helpers, never exposed through PostgREST
--                audit  = append-only audit log
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists btree_gist with schema extensions;

create schema if not exists app;
create schema if not exists audit;

comment on schema app is 'Private helper functions and internal tables. Not exposed via the API.';
comment on schema audit is 'Append-only audit trail of sensitive changes.';

-- -----------------------------------------------------------------------------
-- Privilege hardening
-- Supabase grants broad default privileges to anon/authenticated and relies on RLS. We go further:
-- deny by default, then grant explicitly per table/function in each migration.
-- -----------------------------------------------------------------------------
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated, public;
alter default privileges in schema app revoke execute on functions from public;
alter default privileges in schema audit revoke execute on functions from public;
alter default privileges revoke execute on functions from public;

revoke all on schema app from public;
revoke all on schema audit from public;
grant usage on schema app to authenticated, service_role;
grant usage on schema audit to authenticated, service_role;

-- Called at the end of every migration: re-asserts that anon can touch nothing and that no
-- function is executable by PUBLIC. Grants for authenticated are explicit per object.
create or replace procedure app.harden_privileges()
language plpgsql
set search_path = ''
as $$
declare
  fn record;
begin
  execute 'revoke all on all tables in schema public from anon';
  execute 'revoke all on all sequences in schema public from anon';
  execute 'revoke all on all tables in schema app from anon, authenticated';
  execute 'revoke all on all tables in schema audit from anon';
  for fn in
    select p.oid::regprocedure as signature
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'app', 'audit')
       and p.prokind in ('f', 'p')
  loop
    execute format('revoke execute on routine %s from public, anon', fn.signature);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
create type public.org_role as enum ('owner', 'manager', 'salesman', 'accountant', 'auditor');

create type public.payment_method as enum (
  'cash', 'bkash', 'nagad', 'rocket', 'card', 'bank_transfer', 'loyalty_points'
);

create type public.dosage_form as enum (
  'tablet', 'capsule', 'syrup', 'suspension', 'solution', 'injection', 'infusion', 'drops',
  'cream', 'ointment', 'gel', 'lotion', 'inhaler', 'nebuliser_solution', 'powder', 'sachet',
  'suppository', 'spray', 'patch', 'device', 'other'
);

-- OTC = over the counter, rx = prescription only, controlled = narcotic/psychotropic (DGDA).
create type public.drug_schedule as enum ('otc', 'rx', 'controlled');

create type public.movement_type as enum (
  'purchase_receipt', 'sale', 'sale_void', 'sale_return', 'purchase_return',
  'transfer_out', 'transfer_in', 'adjustment', 'expiry_writeoff', 'count_correction', 'opening_balance'
);

create type public.adjustment_reason as enum (
  'damage', 'loss', 'theft', 'count_correction', 'expired_writeoff', 'opening_balance', 'other'
);

create type public.cash_rounding as enum ('none', 'nearest_taka');

-- -----------------------------------------------------------------------------
-- Generic utility functions
-- -----------------------------------------------------------------------------

-- Raises a business error with a stable machine-readable code in the DETAIL so clients can map
-- it to a translated message. SQLSTATE P0001 (raise_exception).
create or replace function app.fail(p_code text, p_message text, p_hint text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = p_message,
    detail = p_code,
    hint = coalesce(p_hint, '');
end;
$$;

-- Percentage of an amount in basis points, rounded half away from zero to the nearest paisa.
-- Mirrors percentOf() in src/domain/money.ts.
create or replace function app.percent_of(p_amount bigint, p_bp integer)
returns bigint
language sql
immutable
strict
set search_path = ''
as $$
  select round((p_amount::numeric * p_bp) / 10000)::bigint
$$;

-- Splits p_total across p_weights proportionally using the largest remainder method so that the
-- parts always sum exactly to p_total. Used to spread invoice-level discounts over lines.
create or replace function app.allocate_proportionally(p_total bigint, p_weights bigint[])
returns bigint[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  n integer := coalesce(array_length(p_weights, 1), 0);
  weight_sum numeric := 0;
  parts bigint[] := '{}';
  remainders numeric[] := '{}';
  allocated bigint := 0;
  leftover bigint;
  i integer;
  best integer;
  exact numeric;
begin
  if n = 0 then
    return parts;
  end if;
  for i in 1..n loop
    if p_weights[i] < 0 then
      perform app.fail('invalid_weights', 'Allocation weights must be non-negative');
    end if;
    weight_sum := weight_sum + p_weights[i];
  end loop;
  if weight_sum = 0 then
    parts := array_fill(0::bigint, array[n]);
    parts[1] := p_total;
    return parts;
  end if;
  for i in 1..n loop
    exact := p_total::numeric * p_weights[i] / weight_sum;
    parts[i] := trunc(exact)::bigint;
    remainders[i] := abs(exact - trunc(exact));
    allocated := allocated + parts[i];
  end loop;
  leftover := p_total - allocated;
  while leftover <> 0 loop
    best := 1;
    for i in 2..n loop
      if remainders[i] > remainders[best] then
        best := i;
      end if;
    end loop;
    parts[best] := parts[best] + sign(leftover)::bigint;
    remainders[best] := -1;
    leftover := leftover - sign(leftover)::bigint;
  end loop;
  return parts;
end;
$$;

-- Normalises Bangladeshi mobile numbers to E.164 (+8801XXXXXXXXX). Returns NULL for NULL/blank.
create or replace function app.normalize_bd_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  digits text;
begin
  if p_phone is null or btrim(p_phone) = '' then
    return null;
  end if;
  digits := regexp_replace(p_phone, '[^0-9]', '', 'g');
  if digits ~ '^8801[3-9][0-9]{8}$' then
    return '+' || digits;
  elsif digits ~ '^01[3-9][0-9]{8}$' then
    return '+88' || digits;
  end if;
  perform app.fail('invalid_phone', 'Invalid Bangladeshi mobile number', 'Use the format 01XXXXXXXXX');
  return null;
end;
$$;

-- Bangladesh fiscal year (July-June by default) label, e.g. 2026-10-06 -> '2627'.
create or replace function app.fiscal_year_label(p_date date, p_start_month integer default 7)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when extract(month from p_date)::integer >= p_start_month
      then to_char(p_date, 'YY') || to_char(p_date + interval '1 year', 'YY')
    else to_char(p_date - interval '1 year', 'YY') || to_char(p_date, 'YY')
  end
$$;

-- Luhn check digit, used for loyalty card numbers so typos are detected at the counter.
create or replace function app.luhn_check_digit(p_digits text)
returns integer
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  total integer := 0;
  d integer;
  i integer;
  len integer := length(p_digits);
begin
  if p_digits !~ '^[0-9]+$' then
    perform app.fail('invalid_digits', 'Luhn input must be digits');
  end if;
  for i in 0..len - 1 loop
    d := substr(p_digits, len - i, 1)::integer;
    if i % 2 = 0 then
      d := d * 2;
      if d > 9 then
        d := d - 9;
      end if;
    end if;
    total := total + d;
  end loop;
  return (10 - (total % 10)) % 10;
end;
$$;

-- Pure utility functions may run inside triggers/policies on behalf of signed-in users.
grant execute on function
  app.fail(text, text, text),
  app.percent_of(bigint, integer),
  app.allocate_proportionally(bigint, bigint[]),
  app.normalize_bd_phone(text),
  app.fiscal_year_label(date, integer),
  app.luhn_check_digit(text)
to authenticated, service_role;

-- Keeps updated_at / updated_by current.
create or replace function app.touch_updated()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if to_jsonb(new) ? 'updated_by' then
    new := jsonb_populate_record(new, jsonb_build_object('updated_by', auth.uid()));
  end if;
  return new;
end;
$$;

-- Ledgers and logs are immutable: corrections are new compensating rows, never edits.
create or replace function app.forbid_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = format('%s.%s is append-only; %s is not allowed', tg_table_schema, tg_table_name, tg_op),
    detail = 'append_only';
end;
$$;

-- -----------------------------------------------------------------------------
-- Audit log
-- -----------------------------------------------------------------------------
create table audit.log (
  id bigint generated always as identity primary key,
  organization_id uuid,
  branch_id uuid,
  table_name text not null,
  record_id uuid,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_data jsonb,
  new_data jsonb,
  changed_fields text[],
  actor_id uuid,
  actor_role text,
  transaction_id bigint not null default txid_current(),
  occurred_at timestamptz not null default now()
);

comment on table audit.log is 'Append-only record of changes to sensitive tables (who, what, when, before/after).';

create index log_org_time_idx on audit.log (organization_id, occurred_at desc);
create index log_record_idx on audit.log (table_name, record_id);

create trigger log_append_only
  before update or delete on audit.log
  for each row execute function app.forbid_mutation();

alter table audit.log enable row level security;

create or replace function app.audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_json jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  new_json jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  row_json jsonb := coalesce(new_json, old_json);
  changed text[];
begin
  if tg_op = 'UPDATE' then
    select coalesce(array_agg(n.key order by n.key), '{}')
      into changed
      from jsonb_each(new_json) n
     where n.key not in ('updated_at', 'updated_by')
       and n.value is distinct from old_json -> n.key;
    if cardinality(changed) = 0 then
      return null;
    end if;
  end if;

  insert into audit.log (
    organization_id, branch_id, table_name, record_id, action,
    old_data, new_data, changed_fields, actor_id, actor_role
  ) values (
    coalesce((row_json ->> 'organization_id')::uuid,
             case when tg_table_name = 'organizations' then (row_json ->> 'id')::uuid end),
    case when tg_table_name = 'branches' then (row_json ->> 'id')::uuid
         else (row_json ->> 'branch_id')::uuid end,
    tg_table_schema || '.' || tg_table_name,
    (row_json ->> 'id')::uuid,
    tg_op,
    old_json,
    new_json,
    changed,
    auth.uid(),
    auth.role()
  );
  return null;
end;
$$;

-- Attaches the audit trigger to a table (used by later migrations).
create or replace procedure app.enable_audit(p_table regclass)
language plpgsql
set search_path = ''
as $$
begin
  execute format(
    'create trigger audit_row after insert or update or delete on %s for each row execute function app.audit_row()',
    p_table
  );
end;
$$;

call app.harden_privileges();
