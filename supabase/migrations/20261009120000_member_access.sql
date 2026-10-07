-- =============================================================================
-- Migration: per-member access control
-- A member's role is the starting template; the owner can switch individual permissions on or off
-- for one member (member_permissions). Every permission check (app.has_permission,
-- app.permitted_org_ids and therefore every RLS policy and RPC) applies these overrides.
--
-- Safety rules:
--   * Owners always hold every permission; overrides cannot be stored for an owner.
--   * Owner-only governance permissions (users, branches, organization settings) cannot be granted.
--   * purchases.view implies reports.view_cost (purchase tables carry supplier prices, P-45).
--   * A member with any granted permission needs a TOTP (aal2) session, like a manager.
--   * Changing a member's role clears their overrides (the new role is a fresh template).
-- =============================================================================

-- Permission catalogue: every permission that exists, and whether it may be granted to a non-owner.
create table app.permissions (
  permission text primary key,
  grantable boolean not null default true
);
insert into app.permissions (permission, grantable)
select distinct rp.permission, rp.permission not in ('users.manage', 'branches.manage', 'org.settings.manage')
  from app.role_permissions rp;
alter table app.permissions enable row level security;

alter table public.memberships add constraint memberships_organization_id_id_key unique (organization_id, id);

create table public.member_permissions (
  organization_id uuid not null,
  membership_id uuid not null,
  permission text not null references app.permissions (permission),
  allowed boolean not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  primary key (membership_id, permission),
  foreign key (organization_id, membership_id) references public.memberships (organization_id, id)
);
create index member_permissions_org_idx on public.member_permissions (organization_id);

comment on table public.member_permissions is
  'Per-member override of the role template: allowed = true grants, false revokes. Written only by set_member_permissions.';

call app.enable_audit('public.member_permissions');

alter table public.member_permissions enable row level security;
create policy member_permissions_select on public.member_permissions for select to authenticated
  using (organization_id in (select app.permitted_org_ids('users.manage')));
grant select on public.member_permissions to authenticated;

-- Owners hold everything: no override row may point at an owner membership.
create or replace function app.member_permissions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from public.memberships m where m.id = new.membership_id and m.role = 'owner') then
    perform app.fail('owner_has_all', 'Owners always have full access');
  end if;
  return new;
end;
$$;
create trigger member_permissions_guard before insert or update on public.member_permissions
  for each row execute function app.member_permissions_guard();

-- A role change (or promotion to owner) starts from the new role's template.
create or replace function app.memberships_reset_overrides()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role then
    delete from public.member_permissions where membership_id = new.id;
  end if;
  return new;
end;
$$;
create trigger memberships_reset_overrides after update of role on public.memberships
  for each row execute function app.memberships_reset_overrides();

-- -----------------------------------------------------------------------------
-- Permission resolution (replaces the role-only versions)
-- -----------------------------------------------------------------------------

-- Effective grant for one membership: an override wins, otherwise the role template.
create or replace function app.membership_has(p_membership_id uuid, p_role public.org_role, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_role = 'owner' then exists (select 1 from app.permissions p where p.permission = p_permission)
    else coalesce(
      (select mp.allowed from public.member_permissions mp
        where mp.membership_id = p_membership_id and mp.permission = p_permission),
      exists (select 1 from app.role_permissions rp where rp.role = p_role and rp.permission = p_permission)
    )
  end
$$;

-- Salesmen are exempt from MFA unless the owner granted them anything beyond the salesman template.
create or replace function app.mfa_satisfied(p_organization_id uuid, p_role public.org_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (
      p_role = 'salesman'
      and not exists (
        select 1
          from public.member_permissions mp
          join public.memberships m on m.id = mp.membership_id
         where m.organization_id = p_organization_id
           and m.user_id = auth.uid()
           and mp.allowed
      )
    )
    or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    or not coalesce((
         select s.enforce_mfa from public.organization_settings s
          where s.organization_id = p_organization_id
       ), true)
$$;

create or replace function app.permitted_org_ids(p_permission text)
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
     and app.mfa_satisfied(m.organization_id, m.role)
     and app.membership_has(m.id, m.role, p_permission)
$$;

create or replace function app.has_permission(p_organization_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from app.permitted_org_ids(p_permission) o where o = p_organization_id)
$$;

-- -----------------------------------------------------------------------------
-- RPC
-- -----------------------------------------------------------------------------

-- The signed-in user's effective permissions in an organization (drives which screens the app shows).
create or replace function public.my_permissions(p_organization_id uuid)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_permissions text[];
begin
  if auth.uid() is null then
    perform app.fail('not_authenticated', 'You must be signed in');
  end if;
  select coalesce(array_agg(p.permission order by p.permission), '{}') into v_permissions
    from app.permissions p
   where app.has_permission(p_organization_id, p.permission);
  return v_permissions;
end;
$$;

-- Members of an organization with email, name, branches and overrides (users.manage).
create or replace function public.list_members(p_organization_id uuid)
returns table (
  membership_id uuid,
  user_id uuid,
  email text,
  full_name text,
  role public.org_role,
  is_active boolean,
  branch_ids uuid[],
  overrides jsonb,
  last_sign_in_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_permission(p_organization_id, 'users.manage');
  return query
  select m.id, m.user_id, u.email::text, p.full_name, m.role, m.is_active,
         coalesce((select array_agg(ba.branch_id order by ba.created_at) from public.branch_assignments ba
                    where ba.organization_id = m.organization_id and ba.user_id = m.user_id), '{}'),
         coalesce((select jsonb_object_agg(mp.permission, mp.allowed) from public.member_permissions mp
                    where mp.membership_id = m.id), '{}'::jsonb),
         u.last_sign_in_at, m.created_at
    from public.memberships m
    join auth.users u on u.id = m.user_id
    left join public.profiles p on p.id = m.user_id
   where m.organization_id = p_organization_id
   order by m.is_active desc, m.role, coalesce(p.full_name, u.email);
end;
$$;

-- Replaces a member's overrides. p_overrides is {"permission": true|false}; permissions left out
-- follow the role template. Returns the member's effective permissions.
create or replace function public.set_member_permissions(p_membership_id uuid, p_overrides jsonb)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.memberships;
  v_key text;
  v_value jsonb;
  v_effective text[];
begin
  select * into v_member from public.memberships where id = p_membership_id;
  if v_member.id is null then
    perform app.fail('not_found', 'Membership not found');
  end if;
  perform app.require_permission(v_member.organization_id, 'users.manage');
  if v_member.role = 'owner' then
    perform app.fail('owner_has_all', 'Owners always have full access');
  end if;
  if jsonb_typeof(p_overrides) is distinct from 'object' then
    perform app.fail('invalid_permissions', 'Overrides must be an object of permission: true/false');
  end if;

  for v_key, v_value in select * from jsonb_each(p_overrides) loop
    if not exists (select 1 from app.permissions p where p.permission = v_key) then
      perform app.fail('invalid_permissions', format('Unknown permission: %s', v_key));
    end if;
    if jsonb_typeof(v_value) is distinct from 'boolean' then
      perform app.fail('invalid_permissions', format('Value for %s must be true or false', v_key));
    end if;
    if v_value = 'true'::jsonb and not (select p.grantable from app.permissions p where p.permission = v_key) then
      perform app.fail('not_grantable', format('%s is reserved for owners', v_key));
    end if;
  end loop;

  delete from public.member_permissions where membership_id = p_membership_id;
  -- Store only real differences from the role template, so the template stays the source of truth.
  insert into public.member_permissions (organization_id, membership_id, permission, allowed, updated_by)
  select v_member.organization_id, p_membership_id, e.key, (e.value)::boolean, auth.uid()
    from jsonb_each(p_overrides) e
   where (e.value)::boolean is distinct from exists (
           select 1 from app.role_permissions rp where rp.role = v_member.role and rp.permission = e.key);

  if app.membership_has(p_membership_id, v_member.role, 'purchases.view')
     and not app.membership_has(p_membership_id, v_member.role, 'reports.view_cost') then
    perform app.fail('permission_dependency', 'Viewing purchases also shows purchase cost: allow cost and profit too');
  end if;

  select coalesce(array_agg(p.permission order by p.permission), '{}') into v_effective
    from app.permissions p
   where app.membership_has(p_membership_id, v_member.role, p.permission);
  return v_effective;
end;
$$;

-- Withdraws a pending invitation (users.manage).
create or replace function public.revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
begin
  select i.organization_id into v_org from public.invitations i
   where i.id = p_invitation_id and i.accepted_at is null and i.revoked_at is null;
  if v_org is null then
    perform app.fail('not_found', 'Pending invitation not found');
  end if;
  perform app.require_permission(v_org, 'users.manage');
  update public.invitations set revoked_at = now() where id = p_invitation_id;
end;
$$;

grant execute on function
  public.my_permissions(uuid),
  public.list_members(uuid),
  public.set_member_permissions(uuid, jsonb),
  public.revoke_invitation(uuid)
to authenticated;

call app.harden_privileges();
