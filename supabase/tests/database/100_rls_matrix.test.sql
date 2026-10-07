-- RLS / privilege matrix (security model 8.6: SEC-TC-01 .. SEC-TC-09).
--
-- Fixture: organizations A and B, each with branches 1 and 2, every public table seeded through the RPCs.
-- Users per organization: owner (aal2), manager (aal2, branch 1 only), salesman (aal1, branch 1 only),
-- accountant (aal2), auditor (aal2), the owner again WITHOUT two-factor (aal1); plus an outsider with no
-- membership and anon. A second salesman (branch 2) only seeds branch-2 data.
--
-- Every row of every public relation is labelled by superuser as <org><branch>: A1, A2 (branch rows), A*
-- (organization rows), and profiles by person. For each role and EVERY relation in schema public the test
-- compares one outcome line:  select=<labels seen> insert_own=.. insert_other=.. update=.. delete=..
--   {..}           labels of the rows read / inserted / updated / deleted (writes are rolled back)
--   denied         42501 permission denied (no grant)
--   rls            42501 new row violates row-level security policy
--   not_updatable  55000 the view is not updatable
-- against the reviewed matrices tests.rls_read / tests.rls_write below. A new table, view or function in
-- public fails this file until it is added to the matrices (relation/function list assertions + plan count).
--
-- Sections: 1 API surface inventory + fixture coverage, 2 read/write matrix (14 roles x 42 relations),
-- 3 row-level details, 4 cost columns per role, 5 RPCs (anon, cross-tenant, mixed ids, unassigned branch,
-- unchanged-data fingerprint), 6 app.* helpers granted to authenticated.
begin;
select plan(840);

-- =============================================================================
-- Test helpers (rolled back with the file)
-- =============================================================================
create table tests.rls_ids (key text primary key, val text not null);
create table tests.rls_orgs (letter text primary key, org_id uuid not null, b1 uuid not null, b2 uuid not null,
  spare_medicine uuid not null);
create table tests.rls_users (key text primary key, id uuid not null unique, letter text);
create table tests.rls_rows (rel text not null, pk text not null, label text not null, primary key (rel, pk));
-- Per relation: primary-key expression over alias t, the column a generic UPDATE sets to itself, and the
-- INSERT template (%1$L org, %2$L branch 1, %3$L spare medicine of the target organization).
create table tests.rls_rels (rel text primary key, relkind "char" not null, pk_expr text not null,
  upd_col text not null, ins_sql text);
create table tests.rls_calls (id serial primary key, who text not null, fn text not null, sql text not null,
  expect text not null, note text not null);

-- Id lookup for call templates (fails loudly on a typo instead of passing NULL).
create function tests.rid(p_key text) returns uuid language plpgsql stable as $$
declare
  v text;
begin
  select val into v from tests.rls_ids where key = p_key;
  if v is null then
    raise exception 'unknown fixture id %', p_key;
  end if;
  return v::uuid;
end;
$$;
create function tests.rtxt(p_key text) returns text language plpgsql stable as $$
declare
  v text;
begin
  select val into v from tests.rls_ids where key = p_key;
  if v is null then
    raise exception 'unknown fixture id %', p_key;
  end if;
  return v;
end;
$$;

-- '{A1,A2}' style sorted label set.
create function tests.rls_set(p_labels text[]) returns text language sql immutable as $$
  select '{' || coalesce(string_agg(distinct l, ',' order by l), '') || '}' from unnest(p_labels) l
$$;

create function tests.rls_label(p_org uuid, p_branch uuid) returns text language sql stable as $$
  select coalesce((select o.letter || case when p_branch is null then '*'
                                           when p_branch = o.b1 then '1'
                                           when p_branch = o.b2 then '2'
                                           else '?' end
                     from tests.rls_orgs o where o.org_id = p_org), '?')
$$;

-- Runs a statement returning text as the CURRENT role. p_rollback = true undoes its effects.
-- Errors are classified (see header); anything else is 'SQLSTATE:detail-or-message'.
create function tests.rls_try(p_sql text, p_rollback boolean default true) returns text language plpgsql as $$
declare
  v text;
  v_state text;
  v_msg text;
  v_detail text;
begin
  begin
    execute p_sql into v;
    if p_rollback then
      raise exception 'rls_try rollback' using errcode = 'PRB01';
    end if;
    return 'ok:' || coalesce(v, 'null');
  exception
    when sqlstate 'PRB01' then
      return coalesce(v, 'null');
    when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text, v_detail = pg_exception_detail;
      return case
        when v_state = '42501' and v_msg like 'new row violates row-level security policy%' then 'rls'
        when v_state = '42501' then 'denied'
        when v_state = '55000' and v_msg like 'cannot % view %' then 'not_updatable'
        else v_state || ':' || coalesce(nullif(v_detail, ''), v_msg)
      end;
  end;
end;
$$;

-- =============================================================================
-- Reviewed access matrices. 'O' = the role's own organization; '' = no rows.
-- Read: rows each role sees (the aal1 owner and the outsider see nothing, anon is denied everywhere).
-- =============================================================================
create table tests.rls_read (rel text primary key, owner text, manager text, salesman text, accountant text,
  auditor text, why text);
insert into tests.rls_read values
  ('organizations',            'O*',       'O*',       'O*', 'O*',       'O*',       'member organizations'),
  ('organization_settings',    'O*',       'O*',       'O*', 'O*',       'O*',       'member organizations'),
  ('branches',                 'O1,O2',    'O1,O2',    'O1,O2', 'O1,O2', 'O1,O2',    'branch list is organization-wide'),
  ('profiles',                 'members',  'members',  'members', 'members', 'members', 'self + members of own organizations'),
  ('memberships',              'O*',       'O*',       'O*', 'O*',       'O*',       'staff directory'),
  ('branch_assignments',       'O1,O2',    'O1,O2',    'O1,O2', 'O1,O2', 'O1,O2',    'staff directory'),
  ('invitations',              'O*',       '',         '',   '',         '',         'users.manage'),
  ('member_permissions',       'O*',       '',         '',   '',         '',         'users.manage'),
  ('manufacturers',            'O*',       'O*',       'O*', 'O*',       'O*',       'shared catalog'),
  ('generics',                 'O*',       'O*',       'O*', 'O*',       'O*',       'shared catalog'),
  ('medicines',                'O*',       'O*',       'O*', 'O*',       'O*',       'shared catalog'),
  ('medicine_packs',           'O*',       'O*',       'O*', 'O*',       'O*',       'shared catalog'),
  ('medicine_barcodes',        'O*',       'O*',       'O*', 'O*',       'O*',       'shared catalog'),
  ('branch_medicine_settings', 'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('batches',                  'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('inventory_movements',      'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('stock_adjustments',        'O1,O2',    'O1',       '',   'O1,O2',    'O1,O2',    'branch-scoped + reports.view'),
  ('opening_stock_loads',      'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('suppliers',                'O*',       'O*',       '',   'O*',       'O*',       'purchases.view'),
  ('supplier_balances',        'O*',       'O*',       '',   'O*',       'O*',       'purchases.view (security_invoker view)'),
  -- Organization-wide for purchases.view (P-43 note): a supplier's due is one organization-wide figure, so a
  -- Branch Manager paying from branch 1 sees the whole ledger; goods receipts and returns stay branch-scoped.
  ('supplier_ledger_entries',  'O*,O1,O2', 'O*,O1,O2', '',   'O*,O1,O2', 'O*,O1,O2', 'purchases.view, organization-wide'),
  ('supplier_payments',        'O*,O1,O2', 'O*,O1,O2', '',   'O*,O1,O2', 'O*,O1,O2', 'purchases.view, organization-wide'),
  ('customers',                'O*',       'O*',       'O*', 'O*',       'O*',       'customers are organization-wide'),
  ('customer_balances',        'O*',       'O*',       'O*', 'O*',       'O*',       'security_invoker view'),
  -- Current behaviour: customer dues are organization-wide (customers.collect or reports.view).
  ('customer_ledger_entries',  'O1,O2',    'O1,O2',    'O1,O2', 'O1,O2', 'O1,O2',    'customers.collect / reports.view, organization-wide'),
  ('goods_receipts',           'O1,O2',    'O1',       '',   'O1,O2',    'O1,O2',    'branch-scoped + purchases.view'),
  ('goods_receipt_items',      'O1,O2',    'O1',       '',   'O1,O2',    'O1,O2',    'branch-scoped + purchases.view'),
  ('purchase_returns',         'O1,O2',    'O1',       '',   'O1,O2',    'O1,O2',    'branch-scoped + purchases.view'),
  ('purchase_return_items',    'O1,O2',    'O1',       '',   'O1,O2',    'O1,O2',    'branch-scoped + purchases.view'),
  ('loyalty_plans',            'O*',       'O*',       'O*', 'O*',       'O*',       'loyalty works in every branch'),
  ('loyalty_cards',            'O*',       'O*',       'O*', 'O*',       'O*',       'loyalty works in every branch'),
  ('loyalty_memberships',      'O1,O2',    'O1,O2',    'O1,O2', 'O1,O2', 'O1,O2',    'loyalty works in every branch'),
  ('loyalty_point_ledger',     'O1,O2',    'O1,O2',    'O1,O2', 'O1,O2', 'O1,O2',    'loyalty works in every branch'),
  ('loyalty_usage_daily',      'O*',       'O*',       'O*', 'O*',       'O*',       'security_invoker view over visible sales'),
  ('prescriptions',            'O1,O2',    'O1',       'O1', '',         'O1,O2',    'controlled.register.view or own captures'),
  ('sales',                    'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('sale_items',               'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('sale_item_batches',        'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('sale_payments',            'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('sale_returns',             'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('sale_return_items',        'O1,O2',    'O1',       'O1', 'O1,O2',    'O1,O2',    'branch-scoped'),
  ('controlled_drug_register', 'O1,O2',    'O1',       '',   '',         'O1,O2',    'branch-scoped + controlled.register.view'),
  ('daily_branch_sales',       'O1,O2',    'O1',       '',   'O1,O2',    'O1,O2',    'branch-scoped + reports.view');

-- Direct writes. op: insert = INSERT into the own organization (branch 1); update / delete = every row the
-- role can reach. Values: labels written, 'rls', '' (no row affected). Anything not listed is 'denied'
-- (no grant); INSERT into the OTHER organization is 'rls' wherever an insert row exists.
create table tests.rls_write (rel text not null, op text not null, owner text, manager text, salesman text,
  accountant text, auditor text, primary key (rel, op));
insert into tests.rls_write values
  ('organizations',            'update', 'O*',    '',   '',   '',  ''),
  ('organization_settings',    'update', 'O*',    '',   '',   '',  ''),
  ('branches',                 'update', 'O1,O2', '',   '',   '',  ''),
  ('profiles',                 'update', 'self',  'self', 'self', 'self', 'self'),
  ('manufacturers',            'insert', 'O*',    'O*', 'rls', 'rls', 'rls'),
  ('manufacturers',            'update', 'O*',    'O*', '',   '',  ''),
  ('generics',                 'insert', 'O*',    'O*', 'rls', 'rls', 'rls'),
  ('generics',                 'update', 'O*',    'O*', '',   '',  ''),
  ('medicines',                'insert', 'O*',    'O*', 'rls', 'rls', 'rls'),
  ('medicines',                'update', 'O*',    'O*', '',   '',  ''),
  ('medicine_packs',           'insert', 'O*',    'O*', 'rls', 'rls', 'rls'),
  ('medicine_packs',           'update', 'O*',    'O*', '',   '',  ''),
  ('medicine_packs',           'delete', 'O*',    'O*', '',   '',  ''),
  ('medicine_barcodes',        'insert', 'O*',    'O*', 'rls', 'rls', 'rls'),
  ('medicine_barcodes',        'delete', 'O*',    'O*', '',   '',  ''),
  ('branch_medicine_settings', 'insert', 'O1',    'O1', 'rls', 'rls', 'rls'),
  ('branch_medicine_settings', 'update', 'O1,O2', 'O1', '',   '',  ''),
  ('suppliers',                'insert', 'O*',    'O*', 'rls', 'rls', 'rls'),
  ('suppliers',                'update', 'O*',    'O*', '',   '',  ''),
  ('customers',                'insert', 'O*',    'O*', 'O*', 'rls', 'rls'),
  ('customers',                'update', 'O*',    'O*', 'O*', '',  ''),
  ('loyalty_plans',            'insert', 'O*',    'rls', 'rls', 'rls', 'rls'),
  ('loyalty_plans',            'update', 'O*',    '',   '',   '',  '');

-- Translates a matrix cell for organization p_own into the outcome vocabulary.
create function tests.rls_cell(p_cell text, p_own text) returns text language sql immutable as $$
  select case
    when p_cell in ('rls', 'denied', 'not_updatable') then p_cell
    else tests.rls_set(array(select p_own || substr(x, 2) from unnest(string_to_array(p_cell, ',')) x where x <> ''))
  end
$$;

create function tests.rls_expected(p_rel text, p_kind text, p_own text, p_self text) returns text
language plpgsql stable as $$
declare
  v_member boolean := p_kind in ('owner', 'manager', 'salesman', 'accountant', 'auditor');
  v_view boolean := exists (select 1 from tests.rls_rels r where r.rel = p_rel and r.relkind = 'v');
  v_read tests.rls_read;
  v_sel text;
  v_ops text[] := array['insert', 'update', 'delete'];
  v_out text[] := '{}';
  v_cell text;
  v_has_insert boolean := exists (select 1 from tests.rls_write w where w.rel = p_rel and w.op = 'insert');
  w tests.rls_write;
  v_op text;
begin
  select * into v_read from tests.rls_read where rel = p_rel;
  if v_read.rel is null then
    return 'NO EXPECTATION: add ' || p_rel || ' to tests.rls_read';
  end if;
  if p_kind = 'anon' then
    v_sel := 'denied';
  elsif p_rel = 'profiles' then
    v_sel := case when v_member
                  then tests.rls_set(array(select u.key from tests.rls_users u where u.letter = p_own))
                  else tests.rls_set(array[p_self]) end;
  elsif not v_member then
    v_sel := '{}';
  else
    v_sel := tests.rls_cell(case p_kind when 'owner' then v_read.owner when 'manager' then v_read.manager
      when 'salesman' then v_read.salesman when 'accountant' then v_read.accountant else v_read.auditor end, p_own);
  end if;

  foreach v_op in array v_ops loop
    select * into w from tests.rls_write x where x.rel = p_rel and x.op = v_op;
    if v_view then
      v_cell := 'not_updatable';
    elsif p_kind = 'anon' or w.rel is null then
      v_cell := 'denied';
    elsif w.owner = 'self' then
      v_cell := tests.rls_set(array[p_self]);
    elsif not v_member then
      v_cell := case when v_op = 'insert' then 'rls' else '{}' end;
    else
      v_cell := tests.rls_cell(case p_kind when 'owner' then w.owner when 'manager' then w.manager
        when 'salesman' then w.salesman when 'accountant' then w.accountant else w.auditor end, p_own);
    end if;
    v_out := v_out || v_cell;
  end loop;

  return format('select=%s insert_own=%s insert_other=%s update=%s delete=%s', v_sel, v_out[1],
    case when v_view then 'not_updatable' when p_kind <> 'anon' and v_has_insert then 'rls' else 'denied' end,
    v_out[2], v_out[3]);
end;
$$;

-- Actual outcome of one relation for the current role.
create function tests.rls_outcome(p_rel text, p_own text, p_other text) returns text language plpgsql as $$
declare
  r tests.rls_rels;
  o_own tests.rls_orgs;
  o_other tests.rls_orgs;
  v_labels constant text := 'select tests.rls_set(array(select coalesce(m.label, ''?'') from %s left join tests.rls_rows m on m.rel = %L and m.pk = %s))';
  v_sel text;
  v_ins_own text;
  v_ins_other text;
  v_upd text;
  v_del text;
begin
  select * into r from tests.rls_rels where rel = p_rel;
  select * into o_own from tests.rls_orgs where letter = p_own;
  select * into o_other from tests.rls_orgs where letter = p_other;
  v_sel := tests.rls_try(format(v_labels, format('public.%I t', p_rel), p_rel, r.pk_expr), false);
  if v_sel like 'ok:%' then
    v_sel := substr(v_sel, 4);
  end if;
  v_ins_own := tests.rls_try(format(r.ins_sql, o_own.org_id, o_own.b1, o_own.spare_medicine));
  v_ins_other := tests.rls_try(format(r.ins_sql, o_other.org_id, o_other.b1, o_other.spare_medicine));
  v_upd := tests.rls_try(format('with x as (update public.%I t set %I = t.%I returning %s as pk) ' || v_labels,
    p_rel, r.upd_col, r.upd_col, r.pk_expr, 'x', p_rel, 'x.pk'));
  v_del := tests.rls_try(format('with x as (delete from public.%I t returning %s as pk) ' || v_labels,
    p_rel, r.pk_expr, 'x', p_rel, 'x.pk'));
  return format('select=%s insert_own=%s insert_other=%s update=%s delete=%s', v_sel, v_ins_own, v_ins_other,
    v_upd, v_del);
end;
$$;

-- One assertion per relation in schema public (from the catalog, so new relations are always checked).
create function tests.rls_matrix(p_who text, p_kind text, p_own text, p_other text, p_self text)
returns setof text language plpgsql as $$
declare
  v_rel text;
begin
  for v_rel in
    select c.relname::text
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
     order by 1
  loop
    return next is(tests.rls_outcome(v_rel, p_own, p_other), tests.rls_expected(v_rel, p_kind, p_own, p_self),
      format('%s: %s', p_who, v_rel));
  end loop;
end;
$$;

-- Cost columns that must never be selectable directly; returns the ones that did not refuse.
create function tests.rls_cost_probe() returns text[] language plpgsql as $$
declare
  c record;
  v text;
  v_bad text[] := '{}';
begin
  for c in select * from tests.rls_ids where key like 'cost:%' order by key loop
    v := tests.rls_try(format('select count(t.%I)::text from public.%I t', split_part(c.val, '.', 2),
      split_part(c.val, '.', 1)));
    if v <> 'denied' then
      v_bad := v_bad || (c.val || '=' || v);
    end if;
  end loop;
  return v_bad;
end;
$$;

-- RPC calls of one group, run as the current role WITHOUT rollback (changes would be visible).
create function tests.rls_run_calls(p_who text, p_label text) returns setof text language plpgsql as $$
declare
  c tests.rls_calls;
begin
  for c in select * from tests.rls_calls where who = p_who order by id loop
    return next is(tests.rls_try(c.sql, false), c.expect, format('%s: %s %s', p_label, c.fn, c.note));
  end loop;
end;
$$;

-- anon may execute no public function: each one is called with NULL arguments.
create function tests.rls_anon_rpcs() returns setof text language plpgsql as $$
declare
  f record;
begin
  for f in
    select p.proname::text as name,
           format('select 1 from (select public.%I(%s)) x', p.proname,
             coalesce((select string_agg('null::' || format_type(t.oid, null), ', ' order by a.ord)
                         from unnest(p.proargtypes::oid[]) with ordinality a(typ, ord)
                         join pg_catalog.pg_type t on t.oid = a.typ), '')) as call
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
     order by 1
  loop
    return next is(tests.rls_try(f.call), 'denied', format('anon: cannot execute public.%s', f.name));
  end loop;
end;
$$;

-- Superuser-side fingerprint of everything organization p_org owns (all public tables with an
-- organization_id, its organization row, its document counters and audit rows).
create function tests.rls_fingerprint(p_org uuid) returns text language plpgsql as $$
declare
  t record;
  v text;
  v_all text := '';
begin
  for t in
    select c.relname from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attname = 'organization_id' and not a.attisdropped
     where n.nspname = 'public' and c.relkind = 'r'
     order by 1
  loop
    execute format('select coalesce(md5(string_agg(to_jsonb(x)::text, '','' order by to_jsonb(x)::text)), ''-'')
                      from public.%I x where x.organization_id = %L', t.relname, p_org) into v;
    v_all := v_all || t.relname || ':' || v || ';';
  end loop;
  select v_all || coalesce(md5(string_agg(to_jsonb(o)::text, ',')), '-') into v_all
    from public.organizations o where o.id = p_org;
  select v_all || coalesce(md5(string_agg(to_jsonb(s)::text, ',' order by to_jsonb(s)::text)), '-') into v_all
    from app.document_sequences s
   where s.scope_id = p_org or s.scope_id in (select b.id from public.branches b where b.organization_id = p_org);
  select v_all || (select count(*) from audit.log l where l.organization_id = p_org)::text into v_all;
  return md5(v_all);
end;
$$;

grant select on all tables in schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;

-- =============================================================================
-- Fixture: one organization per letter, every table seeded through the RPCs
-- =============================================================================
create function tests.rls_seed(p_letter text) returns jsonb language plpgsql as $$
declare
  l text := lower(p_letter);
  u_owner uuid := tests.user_id_by_email('owner_' || l || '@rls.test');
  u_manager uuid := tests.user_id_by_email('manager_' || l || '@rls.test');
  u_sales uuid := tests.user_id_by_email('salesman_' || l || '@rls.test');
  u_sales2 uuid := tests.user_id_by_email('salesman2_' || l || '@rls.test');
  v_org uuid;
  v_b uuid[];
  v_today date;
  v_mfr uuid;
  v_gen uuid;
  v_napa uuid;
  v_sedil uuid;
  v_spare uuid;
  v_sup uuid;
  v_cust uuid;
  v_plan uuid;
  v_enrol jsonb;
  v_card text;
  v_inv uuid;
  v_mgr_membership uuid;
  v_rx jsonb;
  v_sale jsonb;
  v_sale_ids uuid[] := '{}';
  v_item uuid;
  v_batch uuid;
  v_na uuid[] := '{}';
  v_mem uuid[] := '{}';
  v_out jsonb;
begin
  perform tests.authenticate_as(u_owner);
  v_org := public.create_organization('RLS Pharmacy ' || p_letter, p_letter || ' Mohammadpur', p_letter || 'MP');
  v_b := array[(select id from public.branches where organization_id = v_org),
               public.create_branch(v_org, p_letter || 'DH', p_letter || ' Dhanmondi')];
  v_today := app.business_date(v_org);
  v_mgr_membership := tests.add_member(v_org, 'manager_' || l || '@rls.test', 'manager', array[v_b[1]]);
  perform tests.add_member(v_org, 'salesman_' || l || '@rls.test', 'salesman', array[v_b[1]]);
  perform tests.add_member(v_org, 'salesman2_' || l || '@rls.test', 'salesman', array[v_b[2]]);
  perform tests.add_member(v_org, 'accountant_' || l || '@rls.test', 'accountant');
  perform tests.add_member(v_org, 'auditor_' || l || '@rls.test', 'auditor');
  v_inv := public.add_member(v_org, 'pending_' || l || '@rls.test', 'salesman', array[v_b[1]]);

  -- Catalog, branch settings, supplier, customer, loyalty plan (direct writes allowed by RLS)
  insert into public.manufacturers (organization_id, name) values (v_org, 'Mfr ' || p_letter) returning id into v_mfr;
  insert into public.generics (organization_id, name) values (v_org, 'Paracetamol') returning id into v_gen;
  insert into public.medicines (organization_id, brand_name, generic_id, manufacturer_id, dosage_form, strength, base_unit_label)
    values (v_org, 'Napa', v_gen, v_mfr, 'tablet', '500 mg', 'tablet') returning id into v_napa;
  insert into public.medicines (organization_id, brand_name, dosage_form, strength, schedule, base_unit_label)
    values (v_org, 'Sedil', 'tablet', '5 mg', 'controlled', 'tablet') returning id into v_sedil;
  insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
    values (v_org, 'Spare', 'syrup', 'bottle') returning id into v_spare;
  insert into public.medicine_packs (organization_id, medicine_id, name, units_per_pack, is_default)
    values (v_org, v_napa, 'Strip', 10, true);
  insert into public.medicine_barcodes (organization_id, medicine_id, barcode)
    values (v_org, v_napa, '89410000000' || case p_letter when 'A' then '1' else '2' end);
  insert into public.branch_medicine_settings (organization_id, branch_id, medicine_id, reorder_level, rack_location)
    values (v_org, v_b[1], v_napa, 1000, 'R1'), (v_org, v_b[2], v_napa, 1000, 'R2');
  insert into public.suppliers (organization_id, name, phone) values (v_org, 'Depot ' || p_letter, '01711000000')
    returning id into v_sup;
  insert into public.customers (organization_id, name, phone)
    values (v_org, 'Customer ' || p_letter, case p_letter when 'A' then '01811000001' else '01922000002' end)
    returning id into v_cust;
  perform public.set_customer_credit_limit(v_cust, 10000000);
  update public.loyalty_plans
     set is_active = true, discount_bp = 500, points_per_100_taka = 1, point_value_paisa = 100
   where organization_id = v_org and duration_months = 3
  returning id into v_plan;

  -- Stock in both branches: branch 1 by the manager, branch 2 by the owner
  for i in 1..2 loop
    perform tests.authenticate_as(case i when 1 then u_manager else u_owner end);
    perform public.receive_goods(v_b[i], v_sup, jsonb_build_array(
      jsonb_build_object('medicine_id', v_napa, 'batch_no', 'NA-' || i, 'expiry_date', v_today + 300,
        'quantity', 300, 'unit_cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120),
      jsonb_build_object('medicine_id', v_sedil, 'batch_no', 'SD-' || i, 'expiry_date', v_today + 400,
        'quantity', 20, 'unit_cost_paisa', 200, 'mrp_paisa', 300, 'sale_price_paisa', 300)),
      gen_random_uuid(), 'INV-' || p_letter || '-' || i, v_today, 0, 1000, 'cash');
    perform public.add_opening_stock(v_b[i], jsonb_build_array(jsonb_build_object(
      'medicine_id', v_napa, 'batch_no', 'OB-' || i, 'expiry_date', v_today + 200, 'quantity', 50,
      'cost_paisa', 70, 'mrp_paisa', 120, 'sale_price_paisa', 110)), gen_random_uuid());
    select id into v_batch from public.batches where branch_id = v_b[i] and batch_no = 'OB-' || i;
    perform public.adjust_stock(v_batch, -1, 'damage', gen_random_uuid());
    select id into v_batch from public.batches where branch_id = v_b[i] and batch_no = 'NA-' || i;
    v_na := v_na || v_batch;
    perform public.process_purchase_return(v_b[i], v_sup,
      jsonb_build_array(jsonb_build_object('batch_id', v_batch, 'quantity', 5)), 'Near expiry', gen_random_uuid());
  end loop;
  perform tests.authenticate_as(u_owner);
  perform public.record_supplier_payment(v_sup, 500, 'bkash', gen_random_uuid());  -- organization-level payment

  -- Loyalty: enrolled at branch 1, renewed at branch 2
  perform tests.authenticate_as(u_sales, 'aal1');
  v_enrol := public.enroll_loyalty(v_cust, v_plan, v_b[1], gen_random_uuid());
  v_card := v_enrol ->> 'card_no';
  v_mem := v_mem || (v_enrol ->> 'membership_id')::uuid;
  perform tests.authenticate_as(u_sales2, 'aal1');
  v_mem := v_mem || (public.enroll_loyalty(v_cust, v_plan, v_b[2], gen_random_uuid()) ->> 'membership_id')::uuid;

  -- Sales: credit + loyalty + controlled medicine with prescription, in both branches
  v_rx := jsonb_build_object('patient_name', 'Patient ' || p_letter, 'doctor_name', 'Dr. Karim',
    'doctor_reg_no', 'A-12345', 'prescription_date', v_today);
  for i in 1..2 loop
    perform tests.authenticate_as(case i when 1 then u_sales else u_sales2 end, 'aal1');
    v_sale := public.create_sale(v_b[i],
      jsonb_build_array(jsonb_build_object('medicine_id', v_napa, 'quantity', 100),
                        jsonb_build_object('medicine_id', v_sedil, 'quantity', 1)),
      '[{"method": "cash", "amount_paisa": 5000}]'::jsonb, gen_random_uuid(), v_cust, v_card, 0, v_rx);
    v_sale_ids := v_sale_ids || (v_sale ->> 'sale_id')::uuid;
    perform public.record_customer_payment(v_cust, v_b[i], 100, 'cash', gen_random_uuid());
  end loop;
  -- A prescription captured by the manager in branch 1 (the salesman must not read it).
  perform tests.authenticate_as(u_manager);
  perform public.create_sale(v_b[1], jsonb_build_array(jsonb_build_object('medicine_id', v_napa, 'quantity', 2)),
    '[{"method": "cash", "amount_paisa": 240}]'::jsonb, gen_random_uuid(), null, null, 0,
    jsonb_build_object('patient_name', 'Walk-in ' || p_letter, 'doctor_name', 'Dr. Rahman', 'prescription_date', v_today));

  -- Returns: branch 1 by the manager, branch 2 by the owner
  for i in 1..2 loop
    perform tests.authenticate_as(case i when 1 then u_manager else u_owner end);
    select id into v_item from public.sale_items where sale_id = v_sale_ids[i] and medicine_id = v_napa;
    perform public.process_sale_return(v_sale_ids[i],
      jsonb_build_array(jsonb_build_object('sale_item_id', v_item, 'quantity', 1)), 'Damaged strip', gen_random_uuid());
  end loop;

  perform tests.clear_authentication();
  select jsonb_build_object(
    'org', v_org, 'b1', v_b[1], 'b2', v_b[2], 'napa', v_napa, 'sedil', v_sedil, 'spare', v_spare,
    'generic', v_gen, 'manufacturer', v_mfr,
    'supplier', v_sup, 'customer', v_cust, 'plan', v_plan, 'card_no', v_card,
    'card', (select id from public.loyalty_cards where card_no = v_card and organization_id = v_org),
    'membership_b1', v_mem[1], 'membership_b2', v_mem[2], 'sale_b1', v_sale_ids[1], 'sale_b2', v_sale_ids[2],
    'item_b1', (select id from public.sale_items where sale_id = v_sale_ids[1] and medicine_id = v_napa),
    'item_b2', (select id from public.sale_items where sale_id = v_sale_ids[2] and medicine_id = v_napa),
    'batch_b1', v_na[1], 'batch_b2', v_na[2], 'invitation', v_inv, 'manager_membership', v_mgr_membership)
    into v_out;
  return v_out;
end;
$$;

do $$ begin
  perform tests.create_user(k || '@rls.test')
     from unnest(array['owner_a', 'manager_a', 'salesman_a', 'salesman2_a', 'accountant_a', 'auditor_a',
                       'owner_b', 'manager_b', 'salesman_b', 'salesman2_b', 'accountant_b', 'auditor_b',
                       'outsider']) k;
end $$;
insert into tests.rls_users (key, id, letter)
select k, tests.user_id_by_email(k || '@rls.test'), nullif(upper(right(k, 1)), 'R')
  from unnest(array['owner_a', 'manager_a', 'salesman_a', 'salesman2_a', 'accountant_a', 'auditor_a',
                    'owner_b', 'manager_b', 'salesman_b', 'salesman2_b', 'accountant_b', 'auditor_b',
                    'outsider']) k;

insert into tests.rls_ids (key, val)
select lower(s.letter) || '_' || e.key, e.value
  from (select 'A' as letter, tests.rls_seed('A') as j union all select 'B', tests.rls_seed('B')) s
 cross join lateral jsonb_each_text(s.j) e;
insert into tests.rls_ids (key, val) select key, id::text from tests.rls_users;
insert into tests.rls_orgs (letter, org_id, b1, b2, spare_medicine)
select l, tests.rid(lower(l) || '_org'), tests.rid(lower(l) || '_b1'), tests.rid(lower(l) || '_b2'),
       tests.rid(lower(l) || '_spare')
  from unnest(array['A', 'B']) l;

-- One per-member override per organization (managers lose pricing.manage), so member_permissions has rows.
insert into public.member_permissions (organization_id, membership_id, permission, allowed)
select m.organization_id, m.id, 'pricing.manage', false
  from public.memberships m
 where m.role = 'manager' and m.organization_id in (select org_id from tests.rls_orgs);

select tests.rid('owner_a') as owner_a, tests.rid('manager_a') as manager_a, tests.rid('salesman_a') as salesman_a,
       tests.rid('accountant_a') as accountant_a, tests.rid('auditor_a') as auditor_a,
       tests.rid('owner_b') as owner_b, tests.rid('manager_b') as manager_b, tests.rid('salesman_b') as salesman_b,
       tests.rid('accountant_b') as accountant_b, tests.rid('auditor_b') as auditor_b,
       tests.rid('outsider') as outsider, tests.rid('a_org') as org_a, tests.rid('b_org') as org_b,
       tests.rid('a_b1') as a1, tests.rid('a_b2') as a2 \gset

-- Per relation: row identity expression and generic write statements.
insert into tests.rls_rels (rel, relkind, pk_expr, upd_col, ins_sql)
select c.relname, c.relkind,
       case c.relname
         when 'organization_settings' then 't.organization_id::text'
         when 'member_permissions' then 't.membership_id::text || ''/'' || t.permission'
         when 'branch_medicine_settings' then 't.branch_id::text || ''/'' || t.medicine_id::text'
         when 'daily_branch_sales' then 't.branch_id::text || ''/'' || t.business_date::text'
         when 'customer_balances' then 't.customer_id::text'
         when 'supplier_balances' then 't.supplier_id::text'
         when 'loyalty_usage_daily' then 't.loyalty_card_id::text || ''/'' || t.business_date::text'
         else 't.id::text' end,
       coalesce(
         (select min(a.attname) from pg_attribute a
           where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
             and has_column_privilege('authenticated', c.oid, a.attnum, 'UPDATE')),
         (select a.attname from pg_attribute a
           where a.attrelid = c.oid and a.attname = 'organization_id' and not a.attisdropped),
         'id'),
       null
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f');

-- Generic INSERT (one column) for relations without an insert row in the matrix; real rows otherwise.
update tests.rls_rels r
   set ins_sql = format('with x as (insert into public.%I (%I) values (%s) returning 1) select ''inserted''',
                        r.rel, case when r.rel in ('organizations', 'profiles') then 'id' else 'organization_id' end,
                        case when r.rel in ('organizations', 'profiles') then 'gen_random_uuid()' else '%1$L' end);
update tests.rls_rels r set ins_sql = v.sql
  from (values
    ('manufacturers', 'insert into public.manufacturers (organization_id, name) values (%1$L, ''Mfr '' || left(gen_random_uuid()::text, 8)) returning organization_id, null::uuid'),
    ('generics', 'insert into public.generics (organization_id, name) values (%1$L, ''Gen '' || left(gen_random_uuid()::text, 8)) returning organization_id, null::uuid'),
    ('medicines', 'insert into public.medicines (organization_id, brand_name, dosage_form) values (%1$L, ''Brand '' || left(gen_random_uuid()::text, 8), ''tablet'') returning organization_id, null::uuid'),
    ('medicine_packs', 'insert into public.medicine_packs (organization_id, medicine_id, name, units_per_pack) values (%1$L, %3$L, ''Box'', 100) returning organization_id, null::uuid'),
    ('medicine_barcodes', 'insert into public.medicine_barcodes (organization_id, medicine_id, barcode) values (%1$L, %3$L, ''RLS-'' || left(md5(random()::text), 12)) returning organization_id, null::uuid'),
    ('branch_medicine_settings', 'insert into public.branch_medicine_settings (organization_id, branch_id, medicine_id, reorder_level) values (%1$L, %2$L, %3$L, 5) returning organization_id, branch_id'),
    ('suppliers', 'insert into public.suppliers (organization_id, name) values (%1$L, ''Sup '' || left(gen_random_uuid()::text, 8)) returning organization_id, null::uuid'),
    ('customers', 'insert into public.customers (organization_id, name) values (%1$L, ''Cust '' || left(gen_random_uuid()::text, 8)) returning organization_id, null::uuid'),
    ('loyalty_plans', 'insert into public.loyalty_plans (organization_id, name, duration_months) values (%1$L, ''Plan '' || left(gen_random_uuid()::text, 8), 12) returning organization_id, null::uuid')
  ) v(rel, sql)
 where r.rel = v.rel;
update tests.rls_rels r
   set ins_sql = 'with x(o, b) as (' || ins_sql || ') select tests.rls_set(array(select tests.rls_label(o, b) from x))'
 where exists (select 1 from tests.rls_write w where w.rel = r.rel and w.op = 'insert');

-- Label every seeded row (superuser, no RLS).
do $$
declare
  r record;
  v_from text;
  v_label text;
begin
  for r in select * from tests.rls_rels loop
    v_from := format('public.%I t', r.rel);
    v_label := case
      when r.rel = 'organizations' then 'tests.rls_label(t.id, null)'
      when r.rel = 'branches' then 'tests.rls_label(t.organization_id, t.id)'
      when r.rel = 'profiles' then 'coalesce((select u.key from tests.rls_users u where u.id = t.id), ''?'')'
      when r.rel = 'goods_receipt_items' then '(select tests.rls_label(p.organization_id, p.branch_id) from public.goods_receipts p where p.id = t.goods_receipt_id)'
      when r.rel = 'purchase_return_items' then '(select tests.rls_label(p.organization_id, p.branch_id) from public.purchase_returns p where p.id = t.purchase_return_id)'
      when r.rel = 'sale_item_batches' then '(select tests.rls_label(p.organization_id, p.branch_id) from public.sale_items p where p.id = t.sale_item_id)'
      when r.rel = 'sale_payments' then '(select tests.rls_label(p.organization_id, p.branch_id) from public.sales p where p.id = t.sale_id)'
      when r.rel = 'sale_return_items' then '(select tests.rls_label(p.organization_id, p.branch_id) from public.sale_returns p where p.id = t.sale_return_id)'
      when exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public' and c.table_name = r.rel and c.column_name = 'branch_id')
        then 'tests.rls_label(t.organization_id, t.branch_id)'
      else 'tests.rls_label(t.organization_id, null)'
    end;
    execute format('insert into tests.rls_rows (rel, pk, label) select %L, %s, %s from %s',
      r.rel, r.pk_expr, v_label, v_from);
  end loop;
end;
$$;

-- Hidden cost columns (probed per role in section 4).
insert into tests.rls_ids (key, val)
select 'cost:' || v, v from unnest(array[
  'batches.cost_paisa', 'inventory_movements.unit_cost_paisa', 'sales.cost_paisa', 'sale_items.cost_paisa',
  'sale_item_batches.unit_cost_paisa', 'sale_returns.cost_paisa', 'sale_return_items.cost_paisa',
  'daily_branch_sales.cost_paisa', 'daily_branch_sales.returns_cost_paisa', 'daily_branch_sales.voided_cost_paisa']) v;

-- =============================================================================
-- 1. Inventory of the API surface (fails when something new appears without coverage)
-- =============================================================================
select set_eq(
  $$ select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f') $$,
  $$ select rel from tests.rls_read $$,
  'every relation in schema public has a row in the reviewed read matrix (and nothing else is listed)');
select is(
  array(select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
         order by 1),
  array['batches', 'branch_assignments', 'branch_medicine_settings', 'branches', 'controlled_drug_register',
        'customer_balances', 'customer_ledger_entries', 'customers', 'daily_branch_sales', 'generics',
        'goods_receipt_items', 'goods_receipts', 'inventory_movements', 'invitations', 'loyalty_cards',
        'loyalty_memberships', 'loyalty_plans', 'loyalty_point_ledger', 'loyalty_usage_daily', 'manufacturers',
        'medicine_barcodes', 'medicine_packs', 'medicines', 'member_permissions', 'memberships', 'opening_stock_loads',
        'organization_settings', 'organizations', 'prescriptions', 'profiles', 'purchase_return_items',
        'purchase_returns', 'sale_item_batches', 'sale_items', 'sale_payments', 'sale_return_items', 'sale_returns',
        'sales', 'stock_adjustments', 'supplier_balances', 'supplier_ledger_entries', 'supplier_payments',
        'suppliers'],
  'schema public holds exactly the 40 tables and 3 views covered by this matrix');
select is(
  array(select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity order by 1),
  '{}'::text[], 'row level security is enabled on every public table');
select is(
  array(select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'v'
           and not coalesce('security_invoker=true' = any (c.reloptions), false) order by 1),
  '{}'::text[], 'every public view runs with the caller''s privileges (security_invoker), so RLS applies');
select is(
  array(select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
           and (has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
                or has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES'))
         order by 1),
  '{}'::text[], 'anon holds no privilege on any table, view or sequence in public (SEC-TC-03)');
select is(
  array(select c.relname || ':' || p.priv
          from pg_class c join pg_namespace n on n.oid = c.relnamespace
         cross join unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p(priv)
         where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
           and (has_table_privilege('authenticated', c.oid, p.priv)
                or (p.priv in ('INSERT', 'UPDATE') and has_any_column_privilege('authenticated', c.oid, p.priv)))
         order by 1),
  array(select rel || ':' || upper(op) from tests.rls_write order by 1),
  'authenticated can INSERT / UPDATE / DELETE exactly the cells of the reviewed write matrix (no ledger writes, SEC-TC-04)');
select is(
  array(select c.relname || '.' || a.attname from pg_attribute a
          join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'v') and a.attnum > 0 and not a.attisdropped
           and a.attname like '%cost%' and not has_column_privilege('authenticated', c.oid, a.attnum, 'SELECT')
         order by 1),
  array(select val from tests.rls_ids where key like 'cost:%' order by 1),
  'cost columns of stock, sales, returns and the daily summary are not granted to authenticated');
select is(
  array(select c.relname || '.' || a.attname from pg_attribute a
          join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'v') and a.attnum > 0 and not a.attisdropped
           and a.attname like '%cost%' and has_column_privilege('authenticated', c.oid, a.attnum, 'SELECT')
         order by 1),
  array['goods_receipt_items.unit_cost_paisa', 'purchase_return_items.unit_cost_paisa'],
  'the only selectable cost columns are supplier prices on purchase documents (gated by purchases.view, P-43/P-45)');
select is(
  array(select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' order by 1),
  array['accept_invitation(uuid)', 'add_member(uuid,text,org_role,uuid[])', 'add_opening_stock(uuid,jsonb,uuid)',
        'adjust_stock(uuid,integer,adjustment_reason,uuid,text)', 'cancel_loyalty_membership(uuid,text)',
        'create_branch(uuid,text,text,text,text)', 'create_organization(text,text,text,text)',
        'create_sale(uuid,jsonb,jsonb,uuid,uuid,text,bigint,jsonb,text)',
        'enroll_loyalty(uuid,uuid,uuid,uuid,payment_method,text)', 'leave_organization(uuid)',
        'list_members(uuid)', 'lookup_loyalty(uuid,text)', 'my_invitations()', 'my_permissions(uuid)', 'process_purchase_return(uuid,uuid,jsonb,text,uuid,text)',
        'process_sale_return(uuid,jsonb,text,uuid,payment_method)',
        'quote_sale(uuid,jsonb,uuid,text,bigint,jsonb)',
        'receive_goods(uuid,uuid,jsonb,uuid,text,date,bigint,bigint,payment_method,text)',
        'record_customer_payment(uuid,uuid,bigint,payment_method,uuid,text)',
        'record_supplier_payment(uuid,bigint,payment_method,uuid,uuid,text,text)',
        'replace_loyalty_card(uuid,text,text)', 'report_expiring_stock(uuid,integer)', 'report_low_stock(uuid)',
        'report_sales_summary(uuid,date,date,uuid)', 'report_stock_value(uuid)', 'revoke_invitation(uuid)',
        'save_medicine(uuid,text,dosage_form,uuid,text,text,text,text,drug_schedule,boolean,text,text[],text,boolean,uuid,text,integer)',
        'search_medicines(uuid,text,integer)',
        'set_batch_price(uuid,bigint,bigint)', 'set_customer_credit_limit(uuid,bigint)', 'set_member_permissions(uuid,jsonb)', 'update_member(uuid,org_role,boolean,uuid[])',
        'void_sale(uuid,text,payment_method)'],
  'schema public holds exactly the 33 RPC functions covered by this matrix');
select is(
  array(select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and (has_function_privilege('anon', p.oid, 'EXECUTE')
                or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
                            where x.grantee = 0 and x.privilege_type = 'EXECUTE'))
         order by 1),
  '{}'::text[], 'no public function is executable by anon or PUBLIC');
select is(
  array(select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'app' and has_function_privilege('authenticated', p.oid, 'EXECUTE') order by 1),
  array['app.allocate_proportionally(bigint,bigint[])', 'app.branch_org_id(uuid)',
        'app.business_date(uuid,timestamp with time zone)', 'app.can(uuid,text)', 'app.fail(text,text,text)',
        'app.fiscal_year_label(date,integer)', 'app.has_branch_access(uuid)', 'app.has_permission(uuid,text)',
        'app.luhn_check_digit(text)', 'app.normalize_bd_phone(text)',
        'app.percent_of(bigint,integer)', 'app.permitted_org_ids(text)', 'app.user_branch_ids()',
        'app.user_org_ids()', 'app.user_role(uuid)'],
  'authenticated may execute exactly the reviewed app.* helpers (section 6 checks each for cross-tenant reads)');
select is(
  array(select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('app', 'audit') and has_function_privilege('anon', p.oid, 'EXECUTE') order by 1),
  '{}'::text[], 'anon may execute no app.* or audit.* function');

-- Fixture coverage: every relation holds rows in every scope its owner can see, in BOTH organizations
-- (so an empty table can never make an isolation assertion pass vacuously). Rows of other tenants ('?',
-- e.g. data committed by 090_regressions_concurrency) are ignored here; in section 2 any '?' row a role
-- can see fails the matrix.
select is(
  tests.rls_set(array(select x.label from tests.rls_rows x where x.rel = r.rel and x.label <> '?')),
  case when r.rel = 'profiles'
       then tests.rls_set(array(select key from tests.rls_users))
       else tests.rls_set(string_to_array(trim(both '{}' from tests.rls_cell(r.owner, 'A')), ',')
                          || string_to_array(trim(both '{}' from tests.rls_cell(r.owner, 'B')), ',')) end,
  format('fixture: %s has seeded rows in every scope of both organizations', r.rel))
  from tests.rls_read r
 order by r.rel;

-- =============================================================================
-- 2. Read / write matrix: every relation, every role
-- =============================================================================
select tests.authenticate_as_anon();
select * from tests.rls_matrix('anon', 'anon', 'A', 'B', null);
select tests.authenticate_as(:'outsider');
select * from tests.rls_matrix('outsider (no membership)', 'outsider', 'A', 'B', 'outsider');

select tests.authenticate_as(:'owner_a');
select * from tests.rls_matrix('owner A (aal2)', 'owner', 'A', 'B', 'owner_a');
select tests.authenticate_as(:'owner_a', 'aal1');
select * from tests.rls_matrix('owner A without MFA (aal1)', 'owner_aal1', 'A', 'B', 'owner_a');
select tests.authenticate_as(:'manager_a');
select * from tests.rls_matrix('manager A (branch 1)', 'manager', 'A', 'B', 'manager_a');
select tests.authenticate_as(:'salesman_a', 'aal1');
select * from tests.rls_matrix('salesman A (branch 1, aal1)', 'salesman', 'A', 'B', 'salesman_a');
select tests.authenticate_as(:'accountant_a');
select * from tests.rls_matrix('accountant A', 'accountant', 'A', 'B', 'accountant_a');
select tests.authenticate_as(:'auditor_a');
select * from tests.rls_matrix('auditor A', 'auditor', 'A', 'B', 'auditor_a');

select tests.authenticate_as(:'owner_b');
select * from tests.rls_matrix('owner B (aal2)', 'owner', 'B', 'A', 'owner_b');
select tests.authenticate_as(:'owner_b', 'aal1');
select * from tests.rls_matrix('owner B without MFA (aal1)', 'owner_aal1', 'B', 'A', 'owner_b');
select tests.authenticate_as(:'manager_b');
select * from tests.rls_matrix('manager B (branch 1)', 'manager', 'B', 'A', 'manager_b');
select tests.authenticate_as(:'salesman_b', 'aal1');
select * from tests.rls_matrix('salesman B (branch 1, aal1)', 'salesman', 'B', 'A', 'salesman_b');
select tests.authenticate_as(:'accountant_b');
select * from tests.rls_matrix('accountant B', 'accountant', 'B', 'A', 'accountant_b');
select tests.authenticate_as(:'auditor_b');
select * from tests.rls_matrix('auditor B', 'auditor', 'B', 'A', 'auditor_b');

-- =============================================================================
-- 3. Row-level details the label sets cannot show
-- =============================================================================
select tests.authenticate_as(:'salesman_a', 'aal1');
select is(
  array(select created_by from public.prescriptions), array[:'salesman_a'::uuid],
  'salesman A reads only the prescription they captured, not the manager''s in the same branch (P-48)');
select tests.authenticate_as(:'manager_a');
select is(
  (select branches_count from public.loyalty_usage_daily where loyalty_card_id = tests.rid('a_card')), 1,
  'manager A: loyalty_usage_daily aggregates only branch-1 sales of a card used in both branches');
select is(
  tests.rls_try(format($$ with x as (insert into public.branch_medicine_settings
    (organization_id, branch_id, medicine_id, reorder_level) values (%L, %L, %L, 5) returning 1) select 'inserted' $$,
    :'org_a', :'a2', tests.rid('a_spare'))),
  'rls', 'manager A cannot insert branch settings for unassigned branch 2');
select tests.authenticate_as(:'owner_a');
select is(
  (select branches_count from public.loyalty_usage_daily where loyalty_card_id = tests.rid('a_card')), 2,
  'owner A: loyalty_usage_daily counts the card''s use in both branches');

-- Tenant-consistent foreign keys: an allowed direct write in A cannot point at B's rows (and the error
-- detail does not echo key values to the client).
select is(
  tests.rls_try(format($$ with x as (insert into public.medicines (organization_id, brand_name, dosage_form, generic_id)
    values (%L, 'Cross Generic', 'tablet', %L) returning 1) select 'inserted' $$, :'org_a', tests.rid('b_generic'))),
  '23503:Key is not present in table "generics".',
  'owner A cannot create a medicine pointing at B''s generic (composite foreign key)');
select is(
  tests.rls_try(format($$ with x as (update public.medicines set manufacturer_id = %L where id = %L returning 1)
    select 'updated' $$, tests.rid('b_manufacturer'), tests.rid('a_napa'))),
  '23503:Key is not present in table "manufacturers".',
  'owner A cannot re-point an A medicine at B''s manufacturer');
select is(
  tests.rls_try(format($$ with x as (insert into public.medicine_packs (organization_id, medicine_id, name, units_per_pack)
    values (%L, %L, 'Cross', 10) returning 1) select 'inserted' $$, :'org_a', tests.rid('b_napa'))),
  '23503:Key is not present in table "medicines".',
  'owner A cannot add a pack to B''s medicine');
select is(
  tests.rls_try(format($$ with x as (insert into public.medicine_barcodes (organization_id, medicine_id, barcode)
    values (%L, %L, 'CROSS-0001') returning 1) select 'inserted' $$, :'org_a', tests.rid('b_napa'))),
  '23503:Key is not present in table "medicines".',
  'owner A cannot add a barcode to B''s medicine');
select is(
  tests.rls_try(format($$ with x as (insert into public.branch_medicine_settings (organization_id, branch_id, medicine_id, reorder_level)
    values (%L, %L, %L, 5) returning 1) select 'inserted' $$, :'org_a', tests.rid('b_b1'), tests.rid('a_spare'))),
  'rls', 'owner A cannot write branch settings into B''s branch under A''s organization id');

-- =============================================================================
-- 4. Cost columns are not selectable by any role
-- =============================================================================
select tests.authenticate_as_anon();
select is(tests.rls_cost_probe(), '{}'::text[], 'anon: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'outsider');
select is(tests.rls_cost_probe(), '{}'::text[], 'outsider: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'owner_a');
select is(tests.rls_cost_probe(), '{}'::text[], 'owner A: every hidden cost column refuses SELECT (reports only)');
select tests.authenticate_as(:'owner_a', 'aal1');
select is(tests.rls_cost_probe(), '{}'::text[], 'owner A aal1: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'manager_a');
select is(tests.rls_cost_probe(), '{}'::text[], 'manager A: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'salesman_a', 'aal1');
select is(tests.rls_cost_probe(), '{}'::text[], 'salesman A: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'accountant_a');
select is(tests.rls_cost_probe(), '{}'::text[], 'accountant A: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'auditor_a');
select is(tests.rls_cost_probe(), '{}'::text[], 'auditor A: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'owner_b');
select is(tests.rls_cost_probe(), '{}'::text[], 'owner B: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'salesman_b', 'aal1');
select is(tests.rls_cost_probe(), '{}'::text[], 'salesman B: every hidden cost column refuses SELECT');
select tests.authenticate_as(:'salesman_a', 'aal1');
select throws_ok('select * from public.batches', '42501', null, 'salesman A: SELECT * on batches is refused (cost column)');
select throws_ok('select * from public.sales', '42501', null, 'salesman A: SELECT * on sales is refused (cost column)');

-- =============================================================================
-- 5. RPC functions: anon refused; another organization's ids refused and nothing changes
-- =============================================================================
select tests.authenticate_as_anon();
select * from tests.rls_anon_rpcs();
select tests.clear_authentication();

-- 'cross': run by owner B (full permissions in B, aal2) and by the outsider with organization A's ids.
insert into tests.rls_calls (who, fn, sql, expect, note) values
  ('cross', 'create_branch', $$ select public.create_branch(tests.rid('a_org'), 'XX', 'Intruder')::text $$, 'P0001:forbidden', 'in organization A'),
  ('cross', 'add_member', $$ select public.add_member(tests.rid('a_org'), 'spy@rls.test', 'owner')::text $$, 'P0001:forbidden', 'to organization A'),
  ('cross', 'my_invitations', $$ select count(*)::text from public.my_invitations() where organization_id = tests.rid('a_org') $$, 'ok:0', 'lists none of organization A''s invitations'),
  ('cross', 'accept_invitation', $$ select public.accept_invitation(tests.rid('a_invitation'))::text $$, 'P0001:invalid_invitation', 'addressed to someone else in A'),
  ('cross', 'update_member', $$ select public.update_member(tests.rid('a_manager_membership'), 'owner', true, '{}')::text $$, 'P0001:forbidden', 'of a member of A'),
  ('cross', 'my_permissions', $$ select public.my_permissions(tests.rid('a_org'))::text $$, 'ok:{}', 'holds nothing in organization A'),
  ('cross', 'list_members', $$ select count(*)::text from public.list_members(tests.rid('a_org')) $$, 'P0001:forbidden', 'of organization A'),
  ('cross', 'set_member_permissions', $$ select public.set_member_permissions(tests.rid('a_manager_membership'), '{"sales.void": true}')::text $$, 'P0001:forbidden', 'of a member of A'),
  ('cross', 'revoke_invitation', $$ select public.revoke_invitation(tests.rid('a_invitation'))::text $$, 'P0001:forbidden', 'of organization A'),
  ('cross', 'leave_organization', $$ select public.leave_organization(tests.rid('a_org'))::text $$, 'P0001:not_found', 'of organization A'),
  ('cross', 'add_opening_stock', $$ select public.add_opening_stock(tests.rid('a_b1'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'batch_no', 'X', 'expiry_date', '2099-01-01', 'quantity', 1, 'cost_paisa', 1, 'mrp_paisa', 2, 'sale_price_paisa', 2)), gen_random_uuid())::text $$, 'P0001:forbidden', 'into A branch 1'),
  ('cross', 'adjust_stock', $$ select public.adjust_stock(tests.rid('a_batch_b1'), -1, 'loss', gen_random_uuid())::text $$, 'P0001:forbidden', 'of an A batch'),
  ('cross', 'set_batch_price', $$ select public.set_batch_price(tests.rid('a_batch_b1'), 1)::text $$, 'P0001:forbidden', 'of an A batch'),
  ('cross', 'save_medicine', $$ select public.save_medicine(tests.rid('a_org'), 'Intruder', 'tablet')::text $$, 'P0001:forbidden', 'in organization A'),
  ('cross', 'search_medicines', $$ select count(*)::text from public.search_medicines(tests.rid('a_b1'), 'Napa') $$, 'P0001:forbidden', 'in A branch 1'),
  ('cross', 'quote_sale', $$ select public.quote_sale(tests.rid('a_b1'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'quantity', 1)))::text $$, 'P0001:forbidden', 'in A branch 1'),
  ('cross', 'set_customer_credit_limit', $$ select public.set_customer_credit_limit(tests.rid('a_customer'), 1)::text $$, 'P0001:forbidden', 'of an A customer'),
  ('cross', 'receive_goods', $$ select public.receive_goods(tests.rid('a_b1'), tests.rid('a_supplier'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'batch_no', 'X', 'expiry_date', '2099-01-01', 'quantity', 1, 'unit_cost_paisa', 1, 'mrp_paisa', 2, 'sale_price_paisa', 2)), gen_random_uuid())::text $$, 'P0001:forbidden', 'into A branch 1'),
  ('cross', 'record_supplier_payment', $$ select public.record_supplier_payment(tests.rid('a_supplier'), 100, 'cash', gen_random_uuid())::text $$, 'P0001:forbidden', 'to an A supplier'),
  ('cross', 'process_purchase_return', $$ select public.process_purchase_return(tests.rid('a_b1'), tests.rid('a_supplier'), jsonb_build_array(jsonb_build_object('batch_id', tests.rid('a_batch_b1'), 'quantity', 1)), 'Intruder', gen_random_uuid())::text $$, 'P0001:forbidden', 'from A branch 1'),
  ('cross', 'record_customer_payment', $$ select public.record_customer_payment(tests.rid('a_customer'), tests.rid('a_b1'), 1, 'cash', gen_random_uuid())::text $$, 'P0001:forbidden', 'of an A customer in A branch 1'),
  ('cross', 'enroll_loyalty', $$ select public.enroll_loyalty(tests.rid('a_customer'), tests.rid('a_plan'), tests.rid('a_b1'), gen_random_uuid())::text $$, 'P0001:forbidden', 'in A branch 1'),
  ('cross', 'cancel_loyalty_membership', $$ select public.cancel_loyalty_membership(tests.rid('a_membership_b1'), 'Intruder')::text $$, 'P0001:forbidden', 'of an A membership'),
  ('cross', 'replace_loyalty_card', $$ select public.replace_loyalty_card(tests.rid('a_card'), 'Intruder')::text $$, 'P0001:forbidden', 'of an A card'),
  ('cross', 'lookup_loyalty', $$ select count(*)::text from public.lookup_loyalty(tests.rid('a_org'), tests.rtxt('a_card_no')) $$, 'P0001:forbidden', 'in organization A'),
  ('cross', 'create_sale', $$ select public.create_sale(tests.rid('a_b1'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'quantity', 1)), '[{"method": "cash", "amount_paisa": 200}]', gen_random_uuid())::text $$, 'P0001:forbidden', 'in A branch 1'),
  ('cross', 'void_sale', $$ select public.void_sale(tests.rid('a_sale_b1'), 'Intruder')::text $$, 'P0001:forbidden', 'of an A sale'),
  ('cross', 'process_sale_return', $$ select public.process_sale_return(tests.rid('a_sale_b1'), jsonb_build_array(jsonb_build_object('sale_item_id', tests.rid('a_item_b1'), 'quantity', 1)), 'Intruder', gen_random_uuid())::text $$, 'P0001:forbidden', 'of an A sale'),
  ('cross', 'report_sales_summary', $$ select count(*)::text from public.report_sales_summary(tests.rid('a_org'), '2000-01-01', '2000-12-31') $$, 'P0001:forbidden', 'of organization A'),
  ('cross', 'report_expiring_stock', $$ select count(*)::text from public.report_expiring_stock(tests.rid('a_b1')) $$, 'P0001:forbidden', 'of A branch 1'),
  ('cross', 'report_low_stock', $$ select count(*)::text from public.report_low_stock(tests.rid('a_b1')) $$, 'P0001:forbidden', 'of A branch 1'),
  ('cross', 'report_stock_value', $$ select count(*)::text from public.report_stock_value(tests.rid('a_org')) $$, 'P0001:forbidden', 'of organization A'),
  -- Not tenant-scoped: it creates a separate organization and grants nothing in A.
  ('cross', 'create_organization', $$ select (public.create_organization('Intruder Pharmacy', 'Intruder', 'INT') <> tests.rid('a_org') and tests.rid('a_org') not in (select app.user_org_ids()))::text $$, 'ok:true', 'creates a separate organization only');

-- 'mixed': owner B combines its own ids with organization A's.
insert into tests.rls_calls (who, fn, sql, expect, note) values
  ('mixed', 'save_medicine', $$ select public.save_medicine(tests.rid('b_org'), 'Napa', 'tablet', p_medicine_id => tests.rid('a_napa'))::text $$, 'P0001:not_found', 'in B cannot rewrite an A medicine'),
  ('mixed', 'add_member', $$ select public.add_member(tests.rid('b_org'), 'new@rls.test', 'salesman', array[tests.rid('a_b1')])::text $$, 'P0001:invalid_branch', 'to B with an A branch assignment'),
  ('mixed', 'update_member', $$ select public.update_member(tests.rid('b_manager_membership'), 'manager', true, array[tests.rid('a_b1')])::text $$, 'P0001:invalid_branch', 'of a B member to an A branch'),
  ('mixed', 'add_opening_stock', $$ select public.add_opening_stock(tests.rid('b_b1'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'batch_no', 'X', 'expiry_date', '2099-01-01', 'quantity', 1, 'cost_paisa', 1, 'mrp_paisa', 2, 'sale_price_paisa', 2)), gen_random_uuid())::text $$, 'P0001:invalid_medicine', 'in B with an A medicine'),
  ('mixed', 'search_medicines', $$ select count(*)::text from public.search_medicines(tests.rid('b_b1'), 'Napa') where medicine_id = tests.rid('a_napa') $$, 'ok:0', 'in B never returns A medicines'),
  ('mixed', 'receive_goods', $$ select public.receive_goods(tests.rid('b_b1'), tests.rid('a_supplier'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('b_napa'), 'batch_no', 'X', 'expiry_date', '2099-01-01', 'quantity', 1, 'unit_cost_paisa', 1, 'mrp_paisa', 2, 'sale_price_paisa', 2)), gen_random_uuid())::text $$, 'P0001:invalid_supplier', 'in B from an A supplier'),
  ('mixed', 'receive_goods', $$ select public.receive_goods(tests.rid('b_b1'), tests.rid('b_supplier'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'batch_no', 'X', 'expiry_date', '2099-01-01', 'quantity', 1, 'unit_cost_paisa', 1, 'mrp_paisa', 2, 'sale_price_paisa', 2)), gen_random_uuid())::text $$, 'P0001:invalid_medicine', 'in B of an A medicine'),
  ('mixed', 'record_supplier_payment', $$ select public.record_supplier_payment(tests.rid('a_supplier'), 100, 'cash', gen_random_uuid(), tests.rid('b_b1'))::text $$, 'P0001:invalid_branch', 'to an A supplier from a B branch'),
  ('mixed', 'record_supplier_payment', $$ select public.record_supplier_payment(tests.rid('b_supplier'), 100, 'cash', gen_random_uuid(), tests.rid('a_b1'))::text $$, 'P0001:forbidden', 'to a B supplier from an A branch'),
  ('mixed', 'process_purchase_return', $$ select public.process_purchase_return(tests.rid('b_b1'), tests.rid('b_supplier'), jsonb_build_array(jsonb_build_object('batch_id', tests.rid('a_batch_b1'), 'quantity', 1)), 'Intruder', gen_random_uuid())::text $$, 'P0001:invalid_batch', 'in B of an A batch'),
  ('mixed', 'record_customer_payment', $$ select public.record_customer_payment(tests.rid('a_customer'), tests.rid('b_b1'), 1, 'cash', gen_random_uuid())::text $$, 'P0001:not_found', 'of an A customer in a B branch'),
  ('mixed', 'enroll_loyalty', $$ select public.enroll_loyalty(tests.rid('a_customer'), tests.rid('b_plan'), tests.rid('b_b1'), gen_random_uuid())::text $$, 'P0001:invalid_customer', 'of an A customer in B'),
  ('mixed', 'enroll_loyalty', $$ select public.enroll_loyalty(tests.rid('b_customer'), tests.rid('a_plan'), tests.rid('b_b1'), gen_random_uuid())::text $$, 'P0001:invalid_plan', 'on an A plan in B'),
  ('mixed', 'lookup_loyalty', $$ select count(*)::text from public.lookup_loyalty(tests.rid('b_org'), '01811000001') $$, 'ok:0', 'in B by an A customer''s phone finds nothing'),
  ('mixed', 'create_sale', $$ select public.create_sale(tests.rid('b_b1'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'quantity', 1)), '[{"method": "cash", "amount_paisa": 200}]', gen_random_uuid())::text $$, 'P0001:invalid_medicine', 'in B of an A medicine'),
  ('mixed', 'create_sale', $$ select public.create_sale(tests.rid('b_b1'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('b_napa'), 'quantity', 1)), '[{"method": "cash", "amount_paisa": 200}]', gen_random_uuid(), tests.rid('a_customer'))::text $$, 'P0001:invalid_customer', 'in B for an A customer'),
  ('mixed', 'process_sale_return', $$ select public.process_sale_return(tests.rid('b_sale_b1'), jsonb_build_array(jsonb_build_object('sale_item_id', tests.rid('a_item_b1'), 'quantity', 1)), 'Intruder', gen_random_uuid())::text $$, 'P0001:invalid_item', 'of a B sale with an A sale line'),
  ('mixed', 'report_sales_summary', $$ select count(*)::text from public.report_sales_summary(tests.rid('b_org'), app.business_date(tests.rid('b_org')) - 1, app.business_date(tests.rid('b_org')), tests.rid('a_b1')) $$, 'ok:0', 'of B filtered to an A branch returns nothing'),
  ('mixed', 'report_stock_value', $$ select count(*)::text from public.report_stock_value(tests.rid('b_org')) where branch_id in (tests.rid('a_b1'), tests.rid('a_b2')) $$, 'ok:0', 'of B lists no A branch');

-- 'unassigned': manager A (branch 1 only) with branch-2 ids of their own organization (SEC-TC-07).
insert into tests.rls_calls (who, fn, sql, expect, note) values
  ('unassigned', 'add_opening_stock', $$ select public.add_opening_stock(tests.rid('a_b2'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'batch_no', 'X', 'expiry_date', '2099-01-01', 'quantity', 1, 'cost_paisa', 1, 'mrp_paisa', 2, 'sale_price_paisa', 2)), gen_random_uuid())::text $$, 'P0001:forbidden', 'into branch 2'),
  ('unassigned', 'adjust_stock', $$ select public.adjust_stock(tests.rid('a_batch_b2'), -1, 'loss', gen_random_uuid())::text $$, 'P0001:forbidden', 'of a branch-2 batch'),
  ('unassigned', 'set_batch_price', $$ select public.set_batch_price(tests.rid('a_batch_b2'), 1)::text $$, 'P0001:forbidden', 'of a branch-2 batch'),
  ('unassigned', 'search_medicines', $$ select count(*)::text from public.search_medicines(tests.rid('a_b2'), 'Napa') $$, 'P0001:forbidden', 'in branch 2'),
  ('unassigned', 'receive_goods', $$ select public.receive_goods(tests.rid('a_b2'), tests.rid('a_supplier'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'batch_no', 'X', 'expiry_date', '2099-01-01', 'quantity', 1, 'unit_cost_paisa', 1, 'mrp_paisa', 2, 'sale_price_paisa', 2)), gen_random_uuid())::text $$, 'P0001:forbidden', 'into branch 2'),
  ('unassigned', 'process_purchase_return', $$ select public.process_purchase_return(tests.rid('a_b2'), tests.rid('a_supplier'), jsonb_build_array(jsonb_build_object('batch_id', tests.rid('a_batch_b2'), 'quantity', 1)), 'Wrong branch', gen_random_uuid())::text $$, 'P0001:forbidden', 'from branch 2'),
  ('unassigned', 'process_purchase_return', $$ select public.process_purchase_return(tests.rid('a_b1'), tests.rid('a_supplier'), jsonb_build_array(jsonb_build_object('batch_id', tests.rid('a_batch_b2'), 'quantity', 1)), 'Wrong branch', gen_random_uuid())::text $$, 'P0001:invalid_batch', 'from branch 1 of a branch-2 batch'),
  ('unassigned', 'record_supplier_payment', $$ select public.record_supplier_payment(tests.rid('a_supplier'), 100, 'cash', gen_random_uuid(), tests.rid('a_b2'))::text $$, 'P0001:forbidden', 'from branch 2'),
  ('unassigned', 'record_customer_payment', $$ select public.record_customer_payment(tests.rid('a_customer'), tests.rid('a_b2'), 1, 'cash', gen_random_uuid())::text $$, 'P0001:forbidden', 'in branch 2'),
  ('unassigned', 'enroll_loyalty', $$ select public.enroll_loyalty(tests.rid('a_customer'), tests.rid('a_plan'), tests.rid('a_b2'), gen_random_uuid())::text $$, 'P0001:forbidden', 'in branch 2'),
  ('unassigned', 'create_sale', $$ select public.create_sale(tests.rid('a_b2'), jsonb_build_array(jsonb_build_object('medicine_id', tests.rid('a_napa'), 'quantity', 1)), '[{"method": "cash", "amount_paisa": 200}]', gen_random_uuid())::text $$, 'P0001:forbidden', 'in branch 2'),
  ('unassigned', 'void_sale', $$ select public.void_sale(tests.rid('a_sale_b2'), 'Wrong branch')::text $$, 'P0001:forbidden', 'of a branch-2 sale'),
  ('unassigned', 'process_sale_return', $$ select public.process_sale_return(tests.rid('a_sale_b2'), jsonb_build_array(jsonb_build_object('sale_item_id', tests.rid('a_item_b2'), 'quantity', 1)), 'Wrong branch', gen_random_uuid())::text $$, 'P0001:forbidden', 'of a branch-2 sale'),
  ('unassigned', 'report_expiring_stock', $$ select count(*)::text from public.report_expiring_stock(tests.rid('a_b2')) $$, 'P0001:forbidden', 'of branch 2'),
  ('unassigned', 'report_low_stock', $$ select count(*)::text from public.report_low_stock(tests.rid('a_b2')) $$, 'P0001:forbidden', 'of branch 2'),
  ('unassigned', 'report_sales_summary', $$ select count(*)::text from public.report_sales_summary(tests.rid('a_org'), app.business_date(tests.rid('a_org')) - 1, app.business_date(tests.rid('a_org')), tests.rid('a_b2')) $$, 'ok:0', 'filtered to branch 2 returns nothing'),
  -- P-41 / P-37 ("B"): a Branch Manager pays suppliers only from an assigned branch (no organization-level
  -- payment) and cancels only memberships enrolled in an assigned branch.
  ('unassigned', 'record_supplier_payment', $$ select (public.record_supplier_payment(tests.rid('a_supplier'), 100, 'cash', gen_random_uuid()) is not null)::text $$, 'P0001:forbidden', 'without a branch (organization level)'),
  ('unassigned', 'cancel_loyalty_membership', $$ select public.cancel_loyalty_membership(tests.rid('a_membership_b2'), 'Customer request')::text $$, 'P0001:forbidden', 'enrolled in branch 2'),
  ('unassigned', 'report_stock_value', $$ select string_agg(branch_id::text, ',') from public.report_stock_value(tests.rid('a_org')) $$, 'ok:' || (select val from tests.rls_ids where key = 'a_b1'), 'lists branch 1 only');

select is(
  array(select distinct fn from tests.rls_calls where who = 'cross' order by 1),
  array(select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' order by 1),
  'every public RPC has a cross-tenant case');

select tests.rls_fingerprint(:'org_a') as fingerprint_before \gset
select tests.authenticate_as(:'owner_b');
select * from tests.rls_run_calls('cross', 'owner B with A''s ids');
select * from tests.rls_run_calls('mixed', 'owner B mixing B and A ids');
select tests.authenticate_as(:'outsider');
select * from tests.rls_run_calls('cross', 'outsider with A''s ids');
select tests.clear_authentication();
select is(tests.rls_fingerprint(:'org_a'), :'fingerprint_before',
  'organization A data, document counters and audit trail are unchanged by every refused cross-tenant call');

select tests.authenticate_as(:'manager_a');
select * from tests.rls_run_calls('unassigned', 'manager A (branch 1) with branch-2 ids');

-- =============================================================================
-- 6. app.* helpers granted to authenticated do not answer for another tenant
-- =============================================================================
select tests.clear_authentication();
select array_agg(distinct permission order by permission) as perms from app.role_permissions \gset

select tests.authenticate_as(:'owner_b');
select is((select count(*)::int from app.user_org_ids() x where x = :'org_a'), 0, 'owner B: app.user_org_ids() excludes A');
select is(app.user_role(:'org_a'), null, 'owner B: app.user_role(A) is null');
select is((select count(*)::int from app.user_branch_ids() x where x in (:'a1', :'a2')), 0, 'owner B: app.user_branch_ids() excludes A branches');
select ok(not app.has_branch_access(:'a1') and not app.has_branch_access(:'a2'), 'owner B: app.has_branch_access(A branches) is false');
select is(array(select p from unnest(:'perms'::text[]) p where app.has_permission(:'org_a', p)), '{}'::text[],
  'owner B: app.has_permission(A, p) is false for every permission');
select is(array(select p from unnest(:'perms'::text[]) p where :'org_a'::uuid in (select app.permitted_org_ids(p))), '{}'::text[],
  'owner B: app.permitted_org_ids(p) never contains A');
select is(array(select p from unnest(:'perms'::text[]) p where app.can(:'a1', p)), '{}'::text[],
  'owner B: app.can(A branch 1, p) is false for every permission');
select is(app.branch_org_id(:'a1'), null, 'owner B: app.branch_org_id(A branch) does not reveal the organization');
select is(app.business_date(:'org_a'), null, 'owner B: app.business_date(A) answers nothing');

select tests.authenticate_as(:'outsider');
-- (The outsider owns one organization by now: the create_organization case of section 5.)
select is((select count(*)::int from app.user_org_ids() x where x in (:'org_a', :'org_b')), 0,
  'outsider: app.user_org_ids() contains neither A nor B');
select is(app.user_role(:'org_a'), null, 'outsider: app.user_role(A) is null');
select is((select count(*)::int from app.user_branch_ids() x where x in (select b1 from tests.rls_orgs union all select b2 from tests.rls_orgs)), 0,
  'outsider: app.user_branch_ids() contains no branch of A or B');
select ok(not app.has_branch_access(:'a1') and not app.has_branch_access(:'a2'), 'outsider: app.has_branch_access(A branches) is false');
select is(array(select p from unnest(:'perms'::text[]) p where app.has_permission(:'org_a', p)), '{}'::text[],
  'outsider: app.has_permission(A, p) is false for every permission');
select is(array(select p from unnest(:'perms'::text[]) p where :'org_a'::uuid in (select app.permitted_org_ids(p))), '{}'::text[],
  'outsider: app.permitted_org_ids(p) never contains A');
select is(array(select p from unnest(:'perms'::text[]) p where app.can(:'a1', p)), '{}'::text[],
  'outsider: app.can(A branch 1, p) is false for every permission');
select is(app.branch_org_id(:'a1'), null, 'outsider: app.branch_org_id(A branch) does not reveal the organization');
select is(app.business_date(:'org_a'), null, 'outsider: app.business_date(A) answers nothing');

-- app.mfa_satisfied reads organization_settings.enforce_mfa as definer for any organization id, so a direct
-- call would tell whether a foreign organization enforces MFA. It is therefore not executable by
-- authenticated at all (only the SECURITY DEFINER membership helpers call it); a direct call is refused
-- whatever the caller's membership or A's setting.
select tests.clear_authentication();
update public.organization_settings set enforce_mfa = false where organization_id = :'org_a';
select tests.authenticate_as(:'outsider', 'aal1');
select throws_ok(format('select app.mfa_satisfied(%L, %L)', :'org_a', 'owner'), '42501', null,
  'outsider: app.mfa_satisfied(A, owner) is not executable, so it does not reveal A''s enforce_mfa setting');
select tests.authenticate_as(:'owner_b', 'aal1');
select throws_ok(format('select app.mfa_satisfied(%L, %L)', :'org_a', 'owner'), '42501', null,
  'owner B (aal1): app.mfa_satisfied(A, owner) is not executable, so it does not reveal A''s enforce_mfa setting');
select tests.clear_authentication();
update public.organization_settings set enforce_mfa = true where organization_id = :'org_a';

select tests.authenticate_as(:'manager_a');
select is(array(select x from app.user_branch_ids() x), array[:'a1'::uuid], 'manager A: app.user_branch_ids() is branch 1 only');
select ok(not app.has_branch_access(:'a2'), 'manager A: app.has_branch_access(branch 2) is false');
select is(array(select p from unnest(:'perms'::text[]) p where app.can(:'a2', p)), '{}'::text[],
  'manager A: app.can(branch 2, p) is false for every permission');

select * from finish();
rollback;
