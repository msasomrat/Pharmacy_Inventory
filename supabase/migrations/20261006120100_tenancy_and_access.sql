-- =============================================================================
-- Migration: tenancy and access control
-- organizations -> branches; users (profiles), memberships with roles, branch assignments,
-- the role/permission matrix and the helper functions every RLS policy relies on.
-- Canonical permission matrix: docs/security/security-model.md
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 2 and 120),
  timezone text not null default 'Asia/Dhaka',
  currency text not null default 'BDT' check (currency = 'BDT'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id)
);

comment on table public.organizations is 'Tenant: one pharmacy business. All business data is scoped to an organization.';

create table public.organization_settings (
  organization_id uuid primary key references public.organizations (id),
  vat_bp integer not null default 0 check (vat_bp between 0 and 5000),
  salesman_max_discount_bp integer not null default 500 check (salesman_max_discount_bp between 0 and 10000),
  manager_max_discount_bp integer not null default 1500 check (manager_max_discount_bp between 0 and 10000),
  cash_rounding public.cash_rounding not null default 'none',
  fiscal_year_start_month integer not null default 7 check (fiscal_year_start_month between 1 and 12),
  return_window_days integer not null default 7 check (return_window_days between 0 and 90),
  void_window_hours integer not null default 24 check (void_window_hours between 0 and 168),
  near_expiry_block_days integer not null default 0 check (near_expiry_block_days between 0 and 365),
  expiry_alert_days integer not null default 90 check (expiry_alert_days between 1 and 730),
  require_prescription_for_rx boolean not null default false,
  enforce_mfa boolean not null default true,
  loyalty_enabled boolean not null default true,
  ai_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id)
);

comment on column public.organization_settings.enforce_mfa is
  'When true, owner and manager permissions require an aal2 (TOTP-verified) session.';
comment on column public.organization_settings.near_expiry_block_days is
  'Batches expiring within this many days are not sold (0 = only expired batches are blocked).';

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  code text not null check (code ~ '^[A-Z0-9]{2,6}$'),
  name text not null check (length(btrim(name)) between 2 and 120),
  address text check (length(address) <= 500),
  phone text check (phone is null or phone ~ '^\+8801[3-9][0-9]{8}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (organization_id, code),
  unique (organization_id, id)
);

comment on table public.branches is 'A physical shop. Branches are deactivated, never deleted.';

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text check (length(full_name) <= 120),
  phone text check (phone is null or phone ~ '^\+8801[3-9][0-9]{8}$'),
  preferred_language text not null default 'en' check (preferred_language in ('en', 'bn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  user_id uuid not null references auth.users (id),
  role public.org_role not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (organization_id, user_id)
);

create index memberships_user_idx on public.memberships (user_id) where is_active;

create table public.branch_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  user_id uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  unique (branch_id, user_id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id)
);

create index branch_assignments_user_idx on public.branch_assignments (user_id);

-- Static role -> permission matrix (see docs/security/security-model.md).
create table app.role_permissions (
  role public.org_role not null,
  permission text not null,
  primary key (role, permission)
);

insert into app.role_permissions (role, permission)
select r::public.org_role, p
  from (values
    ('org.settings.manage',  array['owner']),
    ('branches.manage',      array['owner']),
    ('users.manage',         array['owner']),
    ('catalog.manage',       array['owner', 'manager']),
    ('pricing.manage',       array['owner', 'manager']),
    ('purchases.view',       array['owner', 'manager', 'accountant', 'auditor']),
    ('purchases.receive',    array['owner', 'manager']),
    ('purchases.return',     array['owner', 'manager']),
    ('suppliers.manage',     array['owner', 'manager']),
    ('suppliers.pay',        array['owner', 'manager', 'accountant']),
    ('stock.adjust',         array['owner', 'manager']),
    ('sales.create',         array['owner', 'manager', 'salesman']),
    ('sales.credit',         array['owner', 'manager', 'salesman']),
    ('sales.void',           array['owner', 'manager']),
    ('sales.return',         array['owner', 'manager']),
    ('customers.manage',     array['owner', 'manager', 'salesman']),
    ('customers.collect',    array['owner', 'manager', 'salesman', 'accountant']),
    ('loyalty.manage_plans', array['owner']),
    ('loyalty.enroll',       array['owner', 'manager', 'salesman']),
    ('loyalty.cancel',       array['owner', 'manager']),
    ('reports.view',         array['owner', 'manager', 'accountant', 'auditor']),
    ('reports.view_cost',    array['owner', 'accountant', 'auditor']),
    ('audit.view',           array['owner', 'auditor']),
    ('data.export',          array['owner', 'accountant'])
  ) as m(p, roles)
  cross join lateral unnest(m.roles) as r;

-- Gapless document counters (invoice numbers, receipt numbers, card numbers). The row lock taken
-- by the upsert is held until commit, so numbers are never skipped or duplicated.
create table app.document_sequences (
  scope_id uuid not null,
  doc_type text not null,
  period text not null default '',
  last_value bigint not null default 0,
  primary key (scope_id, doc_type, period)
);

-- -----------------------------------------------------------------------------
-- Access helper functions (SECURITY DEFINER so policies can read memberships without recursion)
-- -----------------------------------------------------------------------------
create or replace function app.user_org_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.organization_id
    from public.memberships m
    join public.organizations o on o.id = m.organization_id
   where m.user_id = auth.uid()
     and m.is_active
     and o.is_active
$$;

create or replace function app.user_role(p_organization_id uuid)
returns public.org_role
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
    from public.memberships m
    join public.organizations o on o.id = m.organization_id
   where m.organization_id = p_organization_id
     and m.user_id = auth.uid()
     and m.is_active
     and o.is_active
$$;

-- Branches the current user may access: every active branch for owner/accountant/auditor,
-- assigned active branches for manager/salesman.
create or replace function app.user_branch_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b.id
    from public.branches b
    join public.memberships m on m.organization_id = b.organization_id
    join public.organizations o on o.id = b.organization_id
   where m.user_id = auth.uid()
     and m.is_active
     and o.is_active
     and b.is_active
     and (
       m.role in ('owner', 'accountant', 'auditor')
       or exists (
         select 1
           from public.branch_assignments ba
          where ba.branch_id = b.id
            and ba.user_id = m.user_id
       )
     )
$$;

create or replace function app.has_branch_access(p_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from app.user_branch_ids() id where id = p_branch_id)
$$;

-- True when the current user's role grants p_permission in the organization. Owner and manager
-- permissions additionally require an MFA-verified (aal2) session when the org enforces MFA.
create or replace function app.has_permission(p_organization_id uuid, p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role public.org_role := app.user_role(p_organization_id);
begin
  if v_role is null then
    return false;
  end if;
  if not exists (
    select 1 from app.role_permissions rp where rp.role = v_role and rp.permission = p_permission
  ) then
    return false;
  end if;
  if v_role in ('owner', 'manager')
     and coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2'
     and coalesce((
       select s.enforce_mfa from public.organization_settings s
        where s.organization_id = p_organization_id
     ), true) then
    return false;
  end if;
  return true;
end;
$$;

create or replace function app.branch_org_id(p_branch_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b.organization_id from public.branches b where b.id = p_branch_id
$$;

create or replace function app.can(p_branch_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.has_branch_access(p_branch_id)
     and app.has_permission(app.branch_org_id(p_branch_id), p_permission)
$$;

create or replace function app.require_permission(p_organization_id uuid, p_permission text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    perform app.fail('not_authenticated', 'You must be signed in');
  end if;
  if not app.has_permission(p_organization_id, p_permission) then
    perform app.fail('forbidden', format('Permission denied: %s', p_permission),
      'Ask the owner for access, or sign in with two-factor authentication');
  end if;
end;
$$;

-- Checks branch access + permission and returns the branch's organization id.
create or replace function app.require_branch_permission(p_branch_id uuid, p_permission text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := app.branch_org_id(p_branch_id);
begin
  if auth.uid() is null then
    perform app.fail('not_authenticated', 'You must be signed in');
  end if;
  if v_org is null or not app.has_branch_access(p_branch_id) then
    perform app.fail('forbidden', 'You do not have access to this branch');
  end if;
  perform app.require_permission(v_org, p_permission);
  return v_org;
end;
$$;

create or replace function app.max_discount_bp(p_organization_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case app.user_role(p_organization_id)
    when 'owner' then 10000
    when 'manager' then s.manager_max_discount_bp
    when 'salesman' then s.salesman_max_discount_bp
    else 0
  end
  from public.organization_settings s
  where s.organization_id = p_organization_id
$$;

create or replace function app.business_date(p_organization_id uuid, p_at timestamptz default now())
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (p_at at time zone o.timezone)::date from public.organizations o where o.id = p_organization_id
$$;

create or replace function app.next_number(p_scope_id uuid, p_doc_type text, p_period text default '')
returns bigint
language sql
volatile
security definer
set search_path = ''
as $$
  insert into app.document_sequences as s (scope_id, doc_type, period, last_value)
  values (p_scope_id, p_doc_type, p_period, 1)
  on conflict (scope_id, doc_type, period)
  do update set last_value = s.last_value + 1
  returning s.last_value
$$;

-- Branch document number, e.g. MPR-2627-000123 (sale) or MPR-G2627-000007 (goods receipt).
create or replace function app.next_branch_document_no(p_branch_id uuid, p_doc_type text, p_prefix text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_org uuid;
  v_fy text;
  v_seq bigint;
begin
  select b.code, b.organization_id into v_code, v_org from public.branches b where b.id = p_branch_id;
  select app.fiscal_year_label(app.business_date(v_org), s.fiscal_year_start_month)
    into v_fy
    from public.organization_settings s
   where s.organization_id = v_org;
  v_seq := app.next_number(p_branch_id, p_doc_type, v_fy);
  return format('%s-%s%s-%s', v_code, p_prefix, v_fy, lpad(v_seq::text, 6, '0'));
end;
$$;

grant execute on function
  app.user_org_ids(),
  app.user_role(uuid),
  app.user_branch_ids(),
  app.has_branch_access(uuid),
  app.has_permission(uuid, text),
  app.can(uuid, text)
to authenticated;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------
create trigger organizations_touch before update on public.organizations
  for each row execute function app.touch_updated();
create trigger organization_settings_touch before update on public.organization_settings
  for each row execute function app.touch_updated();
create trigger branches_touch before update on public.branches
  for each row execute function app.touch_updated();
create trigger profiles_touch before update on public.profiles
  for each row execute function app.touch_updated();
create trigger memberships_touch before update on public.memberships
  for each row execute function app.touch_updated();

-- A branch code and organization never change once issued (they are embedded in invoice numbers).
create or replace function app.branches_guard_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.organization_id <> old.organization_id or new.code <> old.code then
    perform app.fail('immutable_field', 'Branch code and organization cannot be changed');
  end if;
  return new;
end;
$$;

create trigger branches_guard_immutable before update on public.branches
  for each row execute function app.branches_guard_immutable();

-- Profile row for every auth user.
create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, nullif(left(new.raw_user_meta_data ->> 'full_name', 120), ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();

call app.enable_audit('public.organizations');
call app.enable_audit('public.organization_settings');
call app.enable_audit('public.branches');
call app.enable_audit('public.memberships');
call app.enable_audit('public.branch_assignments');

-- -----------------------------------------------------------------------------
-- Row level security
-- -----------------------------------------------------------------------------
alter table public.organizations enable row level security;
alter table public.organization_settings enable row level security;
alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.branch_assignments enable row level security;
alter table app.role_permissions enable row level security;
alter table app.document_sequences enable row level security;

create policy organizations_select on public.organizations for select to authenticated
  using (id in (select app.user_org_ids()));
create policy organizations_update on public.organizations for update to authenticated
  using (app.has_permission(id, 'org.settings.manage'))
  with check (app.has_permission(id, 'org.settings.manage'));

create policy organization_settings_select on public.organization_settings for select to authenticated
  using (organization_id in (select app.user_org_ids()));
create policy organization_settings_update on public.organization_settings for update to authenticated
  using (app.has_permission(organization_id, 'org.settings.manage'))
  with check (app.has_permission(organization_id, 'org.settings.manage'));

create policy branches_select on public.branches for select to authenticated
  using (organization_id in (select app.user_org_ids()));
create policy branches_update on public.branches for update to authenticated
  using (app.has_permission(organization_id, 'branches.manage'))
  with check (app.has_permission(organization_id, 'branches.manage'));

create policy profiles_select on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.memberships m
       where m.user_id = profiles.id
         and m.organization_id in (select app.user_org_ids())
    )
  );
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy memberships_select on public.memberships for select to authenticated
  using (organization_id in (select app.user_org_ids()));

create policy branch_assignments_select on public.branch_assignments for select to authenticated
  using (organization_id in (select app.user_org_ids()));

-- -----------------------------------------------------------------------------
-- Grants (deny by default; column-level update grants restrict what can be edited)
-- -----------------------------------------------------------------------------
grant select on public.organizations, public.organization_settings, public.branches,
  public.profiles, public.memberships, public.branch_assignments to authenticated;
grant update (name) on public.organizations to authenticated;
grant update (vat_bp, salesman_max_discount_bp, manager_max_discount_bp, cash_rounding,
  fiscal_year_start_month, return_window_days, void_window_hours, near_expiry_block_days,
  expiry_alert_days, require_prescription_for_rx, enforce_mfa, loyalty_enabled, ai_enabled)
  on public.organization_settings to authenticated;
grant update (name, address, phone, is_active) on public.branches to authenticated;
grant update (full_name, phone, preferred_language) on public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- RPC: organization bootstrap and membership management
-- -----------------------------------------------------------------------------

-- Creates an organization with the caller as owner and its first branch.
create or replace function public.create_organization(
  p_name text,
  p_branch_name text,
  p_branch_code text,
  p_timezone text default 'Asia/Dhaka'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
begin
  if v_user is null then
    perform app.fail('not_authenticated', 'You must be signed in');
  end if;
  if (select count(*) from public.memberships m where m.user_id = v_user and m.role = 'owner') >= 5 then
    perform app.fail('limit_reached', 'A user can own at most 5 organizations');
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names tz where tz.name = p_timezone) then
    perform app.fail('invalid_timezone', format('Unknown time zone: %s', p_timezone));
  end if;

  insert into public.organizations (name, timezone, created_by, updated_by)
  values (btrim(p_name), p_timezone, v_user, v_user)
  returning id into v_org;

  insert into public.organization_settings (organization_id, updated_by) values (v_org, v_user);

  insert into public.memberships (organization_id, user_id, role, created_by, updated_by)
  values (v_org, v_user, 'owner', v_user, v_user);

  insert into public.branches (organization_id, code, name, created_by, updated_by)
  values (v_org, upper(btrim(p_branch_code)), btrim(p_branch_name), v_user, v_user);

  return v_org;
end;
$$;

create or replace function public.create_branch(
  p_organization_id uuid,
  p_code text,
  p_name text,
  p_address text default null,
  p_phone text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch uuid;
begin
  perform app.require_permission(p_organization_id, 'branches.manage');
  insert into public.branches (organization_id, code, name, address, phone, created_by, updated_by)
  values (p_organization_id, upper(btrim(p_code)), btrim(p_name), p_address,
          app.normalize_bd_phone(p_phone), auth.uid(), auth.uid())
  returning id into v_branch;
  return v_branch;
end;
$$;

-- Validates that every branch belongs to the organization; returns the de-duplicated list.
create or replace function app.validated_branch_ids(p_organization_id uuid, p_branch_ids uuid[])
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_branch_ids, '{}')));
begin
  if exists (
    select 1 from unnest(v_ids) id
     where not exists (
       select 1 from public.branches b where b.id = id and b.organization_id = p_organization_id
     )
  ) then
    perform app.fail('invalid_branch', 'One or more branches do not belong to this organization');
  end if;
  return v_ids;
end;
$$;

create or replace function app.assert_not_last_owner(p_membership_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.memberships;
begin
  select * into v_member from public.memberships where id = p_membership_id;
  if v_member.role = 'owner' and v_member.is_active and not exists (
    select 1 from public.memberships m
     where m.organization_id = v_member.organization_id
       and m.role = 'owner'
       and m.is_active
       and m.id <> v_member.id
  ) then
    perform app.fail('last_owner', 'An organization must keep at least one active owner');
  end if;
end;
$$;

-- Adds an existing auth user (invited through Supabase Auth) to the organization.
create or replace function public.add_member(
  p_organization_id uuid,
  p_email text,
  p_role public.org_role,
  p_branch_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_membership uuid;
  v_branches uuid[];
  v_branch uuid;
begin
  perform app.require_permission(p_organization_id, 'users.manage');

  select u.id into v_user from auth.users u where lower(u.email) = lower(btrim(p_email));
  if v_user is null then
    perform app.fail('user_not_found', 'No account exists for this email. Send an invitation first.');
  end if;

  v_branches := app.validated_branch_ids(p_organization_id, p_branch_ids);

  insert into public.memberships (organization_id, user_id, role, created_by, updated_by)
  values (p_organization_id, v_user, p_role, auth.uid(), auth.uid())
  on conflict (organization_id, user_id) do nothing
  returning id into v_membership;
  if v_membership is null then
    perform app.fail('already_member', 'This user is already a member of the organization');
  end if;

  foreach v_branch in array v_branches loop
    insert into public.branch_assignments (organization_id, branch_id, user_id, created_by)
    values (p_organization_id, v_branch, v_user, auth.uid());
  end loop;

  return v_membership;
end;
$$;

create or replace function public.update_member(
  p_membership_id uuid,
  p_role public.org_role,
  p_is_active boolean,
  p_branch_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.memberships;
  v_branches uuid[];
begin
  select * into v_member from public.memberships where id = p_membership_id for update;
  if v_member.id is null then
    perform app.fail('not_found', 'Membership not found');
  end if;
  perform app.require_permission(v_member.organization_id, 'users.manage');

  if v_member.role = 'owner' and (p_role <> 'owner' or not p_is_active) then
    perform app.assert_not_last_owner(p_membership_id);
  end if;

  v_branches := app.validated_branch_ids(v_member.organization_id, p_branch_ids);

  update public.memberships
     set role = p_role, is_active = p_is_active, updated_by = auth.uid()
   where id = p_membership_id;

  delete from public.branch_assignments ba
   where ba.organization_id = v_member.organization_id
     and ba.user_id = v_member.user_id
     and not (ba.branch_id = any (v_branches));

  insert into public.branch_assignments (organization_id, branch_id, user_id, created_by)
  select v_member.organization_id, b, v_member.user_id, auth.uid()
    from unnest(v_branches) b
  on conflict (branch_id, user_id) do nothing;
end;
$$;

grant execute on function
  public.create_organization(text, text, text, text),
  public.create_branch(uuid, text, text, text, text),
  public.add_member(uuid, text, public.org_role, uuid[]),
  public.update_member(uuid, public.org_role, boolean, uuid[])
to authenticated;

call app.harden_privileges();
