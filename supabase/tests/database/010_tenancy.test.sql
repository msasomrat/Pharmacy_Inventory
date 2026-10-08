-- Tenancy, branch access, permission matrix and MFA enforcement.
begin;
select plan(18);

select tests.create_user('owner.a@test.local') as owner_a \gset
select tests.create_user('owner.b@test.local') as owner_b \gset
select tests.create_user('sales.a@test.local') as sales_a \gset
select tests.create_user('manager.a@test.local') as manager_a \gset

-- Owner A creates org A with branch MPR; owner B creates org B.
select tests.authenticate_as(:'owner_a');
select public.create_organization('Pharmacy A', 'Mohammadpur', 'mpr') as org_a \gset
select id as branch_mpr from public.branches where organization_id = :'org_a' \gset
select public.create_branch(:'org_a', 'DHN', 'Dhanmondi') as branch_dhn \gset
select tests.add_member(:'org_a', 'sales.a@test.local', 'salesman', array[:'branch_mpr']::uuid[]) as m_sales \gset
select tests.add_member(:'org_a', 'manager.a@test.local', 'manager', array[:'branch_dhn']::uuid[]) as m_mgr \gset

select tests.authenticate_as(:'owner_b');
select public.create_organization('Pharmacy B', 'Mirpur', 'MIR') as org_b \gset

-- Isolation between organizations
select tests.authenticate_as(:'owner_a');
select is((select count(*)::int from public.organizations), 1, 'owner A sees only their organization');
select is((select count(*)::int from public.branches), 2, 'owner A sees both of their branches');
select is((select code from public.branches where id = :'branch_mpr'), 'MPR', 'branch code is upper-cased');
select is((select count(*)::int from public.branches where organization_id = :'org_b'), 0,
  'owner A cannot see organization B branches');

select tests.authenticate_as(:'owner_b');
select is((select count(*)::int from public.memberships where organization_id = :'org_a'), 0,
  'owner B cannot see organization A members');

-- Branch access by role
select tests.authenticate_as(:'sales_a', 'aal1');
select results_eq('select app.user_branch_ids()', array[:'branch_mpr'::uuid],
  'salesman only has access to the assigned branch');
select ok(app.can(:'branch_mpr', 'sales.create'), 'salesman may sell in the assigned branch');
select ok(not app.can(:'branch_dhn', 'sales.create'), 'salesman may not sell in another branch');
select ok(not app.has_permission(:'org_a', 'sales.void'), 'salesman may not void sales');
select throws_ok(
  $$ select public.create_branch((select organization_id from public.branches limit 1), 'XYZ', 'Rogue') $$,
  'P0001', 'Permission denied: branches.manage', 'salesman cannot create branches');

-- MFA is enforced for owners only; staff sign in with a password
select tests.authenticate_as(:'manager_a', 'aal1');
select ok(app.has_permission(:'org_a', 'stock.adjust'), 'manager without MFA has manager permissions');
select tests.authenticate_as(:'owner_a', 'aal1');
select ok(not app.has_permission(:'org_a', 'stock.adjust'), 'owner without MFA has no permissions');
select ok(not app.has_permission(:'org_a', 'users.manage'), 'manager cannot manage users');

-- Last owner protection
select tests.authenticate_as(:'owner_a');
select id as m_owner from public.memberships where organization_id = :'org_a' and role = 'owner' \gset
select throws_ok(
  format($$ select public.update_member(%L, 'manager', true, '{}') $$, :'m_owner'),
  'P0001', 'An organization must keep at least one active owner',
  'the last owner cannot be demoted');

-- Column-level grants: the organization timezone is not editable through the API
select throws_ok(
  format($$ update public.organizations set timezone = 'UTC' where id = %L $$, :'org_a'),
  '42501', null, 'timezone cannot be changed directly');

-- Settings: owner may update, salesman may not (RLS silently filters the row)
update public.organization_settings set salesman_max_discount_bp = 300 where organization_id = :'org_a';
select tests.authenticate_as(:'sales_a', 'aal1');
update public.organization_settings set salesman_max_discount_bp = 10000 where organization_id = :'org_a';
select is((select salesman_max_discount_bp from public.organization_settings where organization_id = :'org_a'),
  300, 'salesman cannot raise their own discount limit');

-- Anonymous users see nothing
select tests.authenticate_as_anon();
select throws_ok('select count(*) from public.organizations', '42501', null,
  'anon has no privilege on organizations');

-- Audit trail captured the settings change with the actor
select tests.clear_authentication();
select ok(exists (
  select 1 from audit.log
   where table_name = 'public.organization_settings'
     and action = 'UPDATE'
     and 'salesman_max_discount_bp' = any (changed_fields)
     and actor_id = :'owner_a'
), 'audit log records the settings change and who made it');

select * from finish();
rollback;
