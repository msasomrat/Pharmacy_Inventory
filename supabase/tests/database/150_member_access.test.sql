-- Per-member access control: overrides on top of the role template, enforced by every permission check.
begin;
select plan(24);

create function tests.error_code(p_sql text)
returns text
language plpgsql
as $$
declare
  v_detail text;
begin
  execute p_sql;
  return null;
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  return coalesce(nullif(v_detail, ''), sqlstate);
end;
$$;
grant execute on function tests.error_code(text) to authenticated;

select tests.create_user('owner@access.test', 'Owner') as owner \gset
select tests.create_user('sales@access.test', 'Sales Person') as salesman \gset
select tests.create_user('manager@access.test') as manager \gset
select tests.authenticate_as(:'owner');
select public.create_organization('Access Pharmacy', 'Main', 'ACC') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select tests.add_member(:'org', 'sales@access.test', 'salesman', array[:'branch']::uuid[]) as sales_m \gset
select tests.add_member(:'org', 'manager@access.test', 'manager', array[:'branch']::uuid[]) as manager_m \gset
select id as owner_m from public.memberships where user_id = :'owner' \gset

-- Role template
select tests.authenticate_as(:'salesman', 'aal1');
select ok('sales.create' = any (public.my_permissions(:'org')), 'salesman template: can sell');
select ok(not ('purchases.view' = any (public.my_permissions(:'org'))), 'salesman template: no purchases');

-- Owner customises the salesman
select tests.authenticate_as(:'owner');
select is(public.set_member_permissions(:'sales_m', '{"sales.void": true, "customers.manage": false, "sales.create": true}'),
  (select array_agg(p order by p) from unnest(array['customers.collect', 'loyalty.enroll', 'sales.create', 'sales.credit', 'sales.void']) p),
  'returns the effective permissions');
select is((select count(*)::int from public.member_permissions where membership_id = :'sales_m'), 2,
  'only differences from the role template are stored');
select results_eq($$ select email, (overrides ->> 'sales.void')::boolean from public.list_members('$$ || :'org' || $$') where role = 'salesman' $$,
  $$ values ('sales@access.test'::text, true) $$, 'list_members shows email and overrides');

-- A granted salesman still signs in with a password only (two-factor is for owners)
select tests.authenticate_as(:'salesman', 'aal1');
select ok('sales.void' = any (public.my_permissions(:'org')), 'granted permission applies without MFA');
select is((select count(*)::int from public.branches where organization_id = :'org'), 1, 'and reads their branch');
select ok(not ('customers.manage' = any (public.my_permissions(:'org'))), 'revoked permission is gone');
select ok(not ('users.manage' = any (public.my_permissions(:'org'))), 'owner-only permissions are never held');
select is(tests.error_code(format($$ insert into public.customers (organization_id, name) values (%L, 'X') $$, :'org')),
  '42501', 'RLS enforces the revocation (customers insert refused)');

-- Revoking from a manager
select tests.authenticate_as(:'owner');
select public.set_member_permissions(:'manager_m', '{"purchases.receive": false}');
select tests.authenticate_as(:'manager', 'aal2');
select ok('purchases.view' = any (public.my_permissions(:'org')), 'manager keeps the rest of the template');
select is(tests.error_code(format($$ select public.receive_goods(%L, gen_random_uuid(), '[]'::jsonb, gen_random_uuid()) $$, :'branch')),
  'forbidden', 'revoked manager cannot receive goods');
select is(tests.error_code(format($$ select public.list_members(%L) $$, :'org')), 'forbidden', 'manager cannot list members');

-- Validation
select tests.authenticate_as(:'owner');
select is(tests.error_code(format($$ select public.set_member_permissions(%L, '{"users.manage": true}') $$, :'sales_m')),
  'not_grantable', 'owner-only permissions cannot be granted');
select is(tests.error_code(format($$ select public.set_member_permissions(%L, '{"purchases.view": true}') $$, :'sales_m')),
  'permission_dependency', 'purchases.view requires cost visibility');
select isnt(tests.error_code(format($$ select public.set_member_permissions(%L, '{"purchases.view": true, "reports.view_cost": true}') $$, :'sales_m')),
  'permission_dependency', 'purchases.view with cost visibility is accepted');
select is(tests.error_code(format($$ select public.set_member_permissions(%L, '{"nope": true}') $$, :'sales_m')),
  'invalid_permissions', 'unknown permission is rejected');
select is(tests.error_code(format($$ select public.set_member_permissions(%L, '{"sales.void": "yes"}') $$, :'sales_m')),
  'invalid_permissions', 'non-boolean value is rejected');
select is(tests.error_code(format($$ select public.set_member_permissions(%L, '{}') $$, :'owner_m')),
  'owner_has_all', 'owners cannot be restricted');

-- Role change starts from the new template
select public.update_member(:'sales_m', 'manager', true, array[:'branch']::uuid[]);
select is((select count(*)::int from public.member_permissions where membership_id = :'sales_m'), 0,
  'changing the role clears overrides');

-- Owner membership can never carry overrides (also for privileged code)
reset role;
select is(tests.error_code(format($$ insert into public.member_permissions (organization_id, membership_id, permission, allowed) values (%L, %L, 'sales.void', false) $$, :'org', :'owner_m')),
  'owner_has_all', 'trigger blocks overrides on an owner');

-- Invitations can be withdrawn
select tests.authenticate_as(:'owner');
select public.add_member(:'org', 'late@access.test', 'salesman', array[:'branch']::uuid[]) as invitation \gset
select tests.authenticate_as(:'manager', 'aal2');
select is(tests.error_code(format($$ select public.revoke_invitation(%L) $$, :'invitation')), 'forbidden',
  'only users.manage can revoke');
select tests.authenticate_as(:'owner');
select lives_ok(format($$ select public.revoke_invitation(%L) $$, :'invitation'), 'owner revokes a pending invitation');
select is(tests.error_code(format($$ select public.revoke_invitation(%L) $$, :'invitation')), 'not_found',
  'a revoked invitation cannot be revoked again');

select * from finish();
rollback;
