-- Regression tests for access-control defects found in the M1 database review:
--   A. mfa-not-enforced-on-reads             E. prescriptions-readable-by-all-roles
--   B. add-member-no-consent-cross-tenant     F. validated-branch-ids-noop
--   C. sale-return-items-cost-leak            G. app-helpers-cross-tenant-lookup
--   D. manager-reads-purchase-cost (policy: Branch Managers hold reports.view_cost, P-45)
begin;
select plan(60);

-- Runs SQL and returns 'ok' or 'SQLSTATE: message' (rolled back with the test).
create function tests.try_sql(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate || ': ' || sqlerrm;
end;
$$;
grant execute on function tests.try_sql(text) to authenticated;

-- =============================================================================
-- A. MFA on the read path (FR-IAM-005, NFR-SEC-004): an Owner / Manager / Accountant / Auditor with an
--    aal1 session reads no business data while the organization enforces MFA.
-- =============================================================================
select tests.create_user('owner@mfa.test') as owner \gset
select tests.create_user('manager@mfa.test') as manager \gset
select tests.create_user('acct@mfa.test') as acct \gset
select tests.create_user('sales@mfa.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('MFA Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@mfa.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'acct@mfa.test', 'accountant');
select tests.add_member(:'org', 'sales@mfa.test', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, schedule, base_unit_label)
  values (:'org', 'Sedil', 'tablet', '5 mg', 'controlled', 'tablet') returning id as sedil \gset
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'sedil', 'batch_no', 'SD-1', 'expiry_date', :'today'::date + 400,
  'quantity', 20, 'cost_paisa', 83, 'mrp_paisa', 300, 'sale_price_paisa', 300)), gen_random_uuid());
insert into public.customers (organization_id, name, phone, address)
  values (:'org', 'Karim Uddin', '01811223344', 'House 1, Road 2, Mohammadpur') returning id as customer \gset
select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'sedil', 'quantity', 2)),
  '[{"method": "cash", "amount_paisa": 600}]'::jsonb, gen_random_uuid(), :'customer', null, 0,
  jsonb_build_object('patient_name', 'Rahim', 'patient_age', 42, 'doctor_name', 'Dr. Karim',
    'doctor_reg_no', 'A-12345', 'prescription_date', :'today'::date)) as sale \gset

select tests.clear_authentication();
select is((select enforce_mfa from public.organization_settings where organization_id = :'org'), true,
  'A: precondition: the organization enforces MFA (default)');

select tests.authenticate_as(:'owner', 'aal2');
select is((select count(*)::int from public.sales), 1, 'A: control: aal2 owner sees the sale');

select tests.authenticate_as(:'owner', 'aal1');
select ok(not app.has_permission(:'org', 'reports.view'), 'A: precondition: aal1 owner holds no permissions');
select is((select count(*)::int from public.sales), 0, 'A: aal1 owner reads no sales');
select is((select count(*)::int from public.sale_items), 0, 'A: aal1 owner reads no sale lines');
select is((select count(*)::int from public.sale_payments), 0, 'A: aal1 owner reads no payments');
select is((select count(*)::int from public.customers), 0, 'A: aal1 owner reads no customers (names, phones, addresses)');
select is((select count(*)::int from public.prescriptions), 0, 'A: aal1 owner reads no prescriptions (patient data)');
select is((select count(*)::int from public.batches), 0, 'A: aal1 owner reads no stock');
select is((select count(*)::int from public.inventory_movements), 0, 'A: aal1 owner reads no stock ledger');
select is((select count(*)::int from public.profiles where id <> :'owner'), 0, 'A: aal1 owner reads no staff profiles');
select is((select count(*)::int from public.profiles where id = :'owner'), 1, 'A: aal1 owner still reads their own profile');

select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 1}]'::jsonb,
    '[{"method": "cash", "amount_paisa": 300}]'::jsonb, gen_random_uuid()) $$, :'branch', :'sedil'),
  'P0001', 'Two-factor authentication is required', 'A: an aal1 owner is told to complete two-factor sign-in');

-- Owner decision (20261010120000_owner_only_mfa): staff sign in with a password only.
select tests.authenticate_as(:'manager', 'aal1');
select ok(app.has_permission(:'org', 'sales.create'), 'A: aal1 manager holds the manager permissions');
select is((select count(*)::int from public.sales), 1, 'A: aal1 manager reads sales');
select is((select count(*)::int from public.medicines), 1, 'A: aal1 manager reads the catalog');
select is((select count(*)::int from public.profiles where id = :'owner'), 1, 'A: aal1 manager reads colleague profiles');
select ok(not app.has_permission(:'org', 'users.manage'), 'A: aal1 manager still cannot manage staff');
select tests.authenticate_as(:'acct', 'aal1');
select is((select count(*)::int from public.customers), 1, 'A: aal1 accountant reads customers');
select tests.authenticate_as(:'sales', 'aal1');
select is((select count(*)::int from public.customers), 1, 'A: salesmen are not MFA-gated');

-- =============================================================================
-- B. Membership needs the invitee's consent; no account enumeration; org cap not consumable by others.
-- =============================================================================
select tests.create_user('attacker@x.test', 'Attacker') as attacker \gset
select tests.create_user('victim@x.test', 'Victim Person') as victim \gset
select tests.create_user('bystander@x.test') as bystander \gset

select tests.authenticate_as(:'victim', 'aal1');
update public.profiles set phone = '+8801711000001' where id = :'victim';

select tests.authenticate_as(:'attacker');
select public.create_organization('Evil 1', 'Evil', 'EV1') as evil1 \gset
select public.create_organization('Evil 2', 'Evil', 'EV2') as evil2 \gset
select public.create_organization('Evil 3', 'Evil', 'EV3') as evil3 \gset
select public.create_organization('Evil 4', 'Evil', 'EV4') as evil4 \gset
select public.create_organization('Evil 5', 'Evil', 'EV5') as evil5 \gset
select public.add_member(:'evil1', 'victim@x.test', 'owner') as invitation1 \gset
select public.add_member(:'evil2', 'victim@x.test', 'owner');
select public.add_member(:'evil3', 'victim@x.test', 'owner');
select public.add_member(:'evil4', 'victim@x.test', 'owner');
select public.add_member(:'evil5', 'victim@x.test', 'owner');

select is((select count(*)::int from public.profiles where id = :'victim' and phone is not null), 0,
  'B: attacker cannot read the phone of a stranger who never accepted a membership');
select is(
  regexp_replace(tests.try_sql(format($$ select public.add_member(%L, 'nobody@x.test', 'salesman') $$, :'evil1')),
    '[0-9a-f-]{36}', '<id>'),
  regexp_replace(tests.try_sql(format($$ select public.add_member(%L, 'bystander@x.test', 'salesman') $$, :'evil1')),
    '[0-9a-f-]{36}', '<id>'),
  'B: add_member gives the same response for an unknown email and for an existing account (no enumeration)');
select is((select count(*)::int from public.invitations where organization_id = :'evil1'), 3,
  'B: the inviting owner sees their organization''s pending invitations');

select tests.authenticate_as(:'victim', 'aal1');
select is((select count(*)::int from public.organizations), 0,
  'B: victim is not placed in organizations they never accepted');
select is((select count(*)::int from public.memberships where user_id = :'victim'), 0,
  'B: no active membership exists for the victim without acceptance');
select is((select count(*)::int from public.invitations), 0, 'B: invitations are not readable by invitees directly');
select is((select count(*)::int from public.my_invitations()), 5, 'B: the invitee lists the invitations addressed to them');
select lives_ok($$ select public.create_organization('My Pharmacy', 'Mirpur', 'MIR') $$,
  'B: victim can still create their own organization (cap not consumed by invitations)');

-- The bystander cannot accept an invitation addressed to someone else.
select tests.authenticate_as(:'bystander', 'aal1');
select throws_ok(format($$ select public.accept_invitation(%L) $$, :'invitation1'),
  'P0001', 'This invitation is not valid or has expired', 'B: only the invitee can accept an invitation');

-- The victim accepts one invitation; only then is the membership created.
select tests.authenticate_as(:'victim', 'aal1');
select lives_ok(format($$ select public.accept_invitation(%L) $$, :'invitation1'), 'B: the invitee accepts');
select tests.authenticate_as(:'victim', 'aal2');
select is((select count(*)::int from public.organizations where id = :'evil1'), 1,
  'B: after accepting (and MFA) the member sees the organization');
select lives_ok(format($$ select public.leave_organization(%L) $$, :'evil1'),
  'B: a member can leave an organization');
select is((select count(*)::int from public.organizations where id = :'evil1'), 0,
  'B: after leaving, the organization is no longer visible');
select tests.authenticate_as(:'attacker');
select throws_ok(format($$ select public.leave_organization(%L) $$, :'evil2'),
  'P0001', 'An organization must keep at least one active owner', 'B: the last active owner cannot leave');

-- =============================================================================
-- C. sale_return_items.cost_paisa is purchase cost: hidden from roles without reports.view_cost.
-- =============================================================================
select tests.create_user('owner@srcost.test') as owner \gset
select tests.create_user('manager@srcost.test') as manager \gset
select tests.create_user('sales@srcost.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Cost Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@srcost.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@srcost.test', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset

select tests.authenticate_as(:'manager');
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
  'quantity', 100, 'cost_paisa', 83, 'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid());

select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 3)),
  '[{"method": "cash", "amount_paisa": 360}]'::jsonb, gen_random_uuid()) as sale \gset

select tests.authenticate_as(:'manager');
select id as line from public.sale_items where sale_id = (:'sale'::jsonb ->> 'sale_id')::uuid \gset
select public.process_sale_return((:'sale'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'line', 'quantity', 3)), 'customer returned', gen_random_uuid());

select tests.authenticate_as(:'sales', 'aal1');
select ok(not app.has_permission(:'org', 'reports.view_cost'), 'C: precondition: salesman lacks reports.view_cost');
select throws_ok('select cost_paisa from public.batches', '42501', null, 'C: control: batch cost is hidden');
select throws_ok('select cost_paisa from public.sale_returns', '42501', null, 'C: control: return header cost is hidden');
select lives_ok('select id, sale_return_id, sale_item_id, quantity, refund_paisa from public.sale_return_items',
  'C: salesman can still read non-cost return line columns');
select throws_ok('select cost_paisa from public.sale_return_items', '42501', null,
  'C: salesman cannot read purchase cost through sale_return_items.cost_paisa');

-- =============================================================================
-- D. Purchase cost policy is consistent: every role that can read purchase tables (purchases.view)
--    holds reports.view_cost, including Branch Managers (security model P-43, P-45, SEC-GAP-02).
-- =============================================================================
select tests.clear_authentication();
select is_empty(
  $$ select role::text from app.role_permissions where permission = 'purchases.view'
     except
     select role::text from app.role_permissions where permission = 'reports.view_cost' $$,
  'D: every holder of purchases.view also holds reports.view_cost');

select tests.create_user('owner@pcost.test') as owner \gset
select tests.create_user('manager@pcost.test') as manager \gset
select tests.create_user('sales@pcost.test') as sales \gset
select tests.authenticate_as(:'owner');
select public.create_organization('PCost Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@pcost.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@pcost.test', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Depot') returning id as supplier \gset
select public.receive_goods(:'branch', :'supplier', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
  'quantity', 100, 'bonus_quantity', 20, 'unit_cost_paisa', 100, 'mrp_paisa', 120, 'sale_price_paisa', 120)),
  gen_random_uuid());

select tests.authenticate_as(:'manager');
select ok(app.has_permission(:'org', 'reports.view_cost'), 'D: a branch manager holds reports.view_cost');
select ok((select bool_and(value_cost_paisa is not null) from public.report_stock_value(:'org')),
  'D: reports show stock value at cost to the manager');
select throws_ok('select cost_paisa from public.batches', '42501', null,
  'D: batch cost is still served only through reports, never by direct reads');
select tests.authenticate_as(:'sales', 'aal1');
select is((select count(*)::int from public.goods_receipt_items), 0,
  'D: a salesman (no purchases.view) reads no supplier prices');

-- =============================================================================
-- E. Patient data: prescriptions and the controlled-drug register need controlled.register.view
--    (owner, manager, auditor); counter staff see only the prescriptions they captured.
-- =============================================================================
select tests.create_user('owner@rx.test') as owner \gset
select tests.create_user('acct@rx.test') as acct \gset
select tests.create_user('sales1@rx.test') as sales1 \gset
select tests.create_user('sales2@rx.test') as sales2 \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Rx Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'acct@rx.test', 'accountant');
select tests.add_member(:'org', 'sales1@rx.test', 'salesman', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales2@rx.test', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, schedule, base_unit_label)
  values (:'org', 'Sedil', 'tablet', '5 mg', 'controlled', 'tablet') returning id as sedil \gset
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'sedil', 'batch_no', 'SD-1', 'expiry_date', :'today'::date + 400,
  'quantity', 20, 'cost_paisa', 200, 'mrp_paisa', 300, 'sale_price_paisa', 300)), gen_random_uuid());
select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'sedil', 'quantity', 2)),
  '[{"method": "cash", "amount_paisa": 600}]'::jsonb, gen_random_uuid(), null, null, 0,
  jsonb_build_object('patient_name', 'Rahim', 'patient_age', 42, 'doctor_name', 'Dr. Karim',
    'doctor_reg_no', 'A-12345', 'prescription_date', :'today'::date, 'notes', 'chronic anxiety'));

select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'sedil', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 300}]'::jsonb, gen_random_uuid(), null, null, 0,
  jsonb_build_object('patient_name', 'Salma', 'doctor_name', 'Dr. Karim', 'doctor_reg_no', 'A-12345',
    'prescription_date', :'today'::date));

-- The accountant signs in with MFA, so the result reflects the role, not the MFA gate.
select tests.authenticate_as(:'acct', 'aal2');
select ok(not app.has_permission(:'org', 'sales.create'), 'E: precondition: accountant has no sales permission');
select ok(not app.has_permission(:'org', 'audit.view'), 'E: precondition: accountant has no audit.view');
select is((select count(*)::int from public.prescriptions where patient_name = 'Rahim'), 0,
  'E: accountant cannot read patient prescriptions');
select is((select count(*)::int from public.controlled_drug_register), 0,
  'E: accountant cannot read patient names through the controlled-drug register');

select tests.authenticate_as(:'sales1', 'aal1');
select is((select array_agg(patient_name order by patient_name) from public.prescriptions), array['Salma'],
  'E: a salesman reads only the prescriptions they captured');
select tests.authenticate_as(:'sales2', 'aal1');
select is((select count(*)::int from public.prescriptions), 0, 'E: another salesman reads none of them');
select tests.authenticate_as(:'owner');
select is((select count(*)::int from public.prescriptions), 2, 'E: control: the owner reads all prescriptions');

-- =============================================================================
-- F. app.validated_branch_ids rejects foreign, unknown and NULL branch ids with invalid_branch.
-- =============================================================================
select tests.create_user('owner.a@vb.test') as owner_a \gset
select tests.create_user('owner.b@vb.test') as owner_b \gset
select tests.create_user('staff@vb.test') as staff \gset

select tests.authenticate_as(:'owner_b');
select public.create_organization('Org B', 'Mirpur', 'MIR') as org_b \gset
select id as branch_b from public.branches where organization_id = :'org_b' \gset

select tests.authenticate_as(:'owner_a');
select public.create_organization('Org A', 'Mohammadpur', 'MPR') as org_a \gset
select id as branch_a from public.branches where organization_id = :'org_a' \gset

select tests.clear_authentication();
select throws_ok(format($$ select app.validated_branch_ids(%L, array[%L]::uuid[]) $$, :'org_a', :'branch_b'),
  'P0001', 'One or more branches do not belong to this organization',
  'F: validated_branch_ids rejects a branch of another organization');
select throws_ok(format($$ select app.validated_branch_ids(%L, array[%L, null]::uuid[]) $$, :'org_a', :'branch_a'),
  'P0001', 'One or more branches do not belong to this organization',
  'F: validated_branch_ids rejects a NULL element');
select throws_ok(format($$ select app.validated_branch_ids(%L, array[gen_random_uuid()]) $$, :'org_a'),
  'P0001', 'One or more branches do not belong to this organization',
  'F: validated_branch_ids rejects a non-existent branch id');

select tests.authenticate_as(:'owner_a');
select throws_ok(format($$ select public.add_member(%L, 'staff@vb.test', 'salesman', array[%L]::uuid[]) $$, :'org_a', :'branch_b'),
  'P0001', 'One or more branches do not belong to this organization',
  'F: add_member refuses a foreign branch with invalid_branch');
select throws_ok(format($$ select public.add_member(%L, 'staff@vb.test', 'salesman', array[null]::uuid[]) $$, :'org_a'),
  'P0001', 'One or more branches do not belong to this organization',
  'F: add_member refuses a NULL branch id with invalid_branch');

-- =============================================================================
-- G. Helpers granted to authenticated answer only for the caller's own organizations.
-- =============================================================================
select tests.authenticate_as(:'owner_b');
select is((select count(*)::int from public.branches where id = :'branch_a'), 0,
  'G: control: RLS hides org A branch from owner B');
select ok(has_function_privilege('authenticated', 'app.branch_org_id(uuid)', 'execute'),
  'G: precondition: authenticated may execute app.branch_org_id');
select is(app.branch_org_id(:'branch_a'), null::uuid,
  'G: app.branch_org_id does not reveal the organization of another tenant''s branch');
select is(app.business_date(:'org_a'), null::date,
  'G: app.business_date does not answer for an organization the caller does not belong to');

select * from finish();
rollback;
