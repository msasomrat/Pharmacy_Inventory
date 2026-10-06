-- Regression tests for performance, integrity and privilege defects found in the M1 database review.
-- Each section reproduces one confirmed finding (the section header names it) and asserts the fixed
-- behaviour. Sections are independent: each creates its own organization and users.
begin;
select plan(30);

-- =============================================================================================
-- A. rls-per-row-has-permission (4 assertions)
-- Regression: RLS policies must not evaluate app.has_permission() once per row. The permission check
-- has to be hoisted into a once-per-query subplan (e.g. organization_id in (select ...)), otherwise
-- customer dues lists / count=exact on large ledgers run into statement_timeout.
-- =============================================================================================
-- Function call counting needs track_functions = 'all' (superuser-only setting); skip the counts otherwise.
do $$ begin perform set_config('track_functions', 'all', true); exception when insufficient_privilege then null; end $$;

select tests.create_user('owner@rls-perf.test') as owner \gset
select tests.authenticate_as(:'owner');
select public.create_organization('RLS Perf Pharmacy', 'Dhanmondi', 'RLP') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select tests.clear_authentication();

-- 2,000 ledger rows per table (written directly as superuser; the RPCs are not under test here).
insert into public.customers (organization_id, name) select :'org', 'Customer ' || g from generate_series(1, 200) g;
insert into public.customer_ledger_entries (organization_id, customer_id, branch_id, entry_type, amount_paisa)
select :'org', c.id, :'branch', 'credit_sale', 100
  from public.customers c cross join generate_series(1, 10) g where c.organization_id = :'org';
insert into public.suppliers (organization_id, name) select :'org', 'Supplier ' || g from generate_series(1, 200) g;
insert into public.supplier_ledger_entries (organization_id, supplier_id, branch_id, entry_type, amount_paisa)
select :'org', s.id, :'branch', 'opening_balance', 100
  from public.suppliers s cross join generate_series(1, 10) g where s.organization_id = :'org';

create temp table fn_calls (label text, calls bigint);
grant all on fn_calls to authenticated;
create or replace function pg_temp.has_permission_calls() returns bigint language sql as $$
  select coalesce(sum(calls), 0)::bigint from pg_stat_xact_user_functions
   where schemaname = 'app' and funcname = 'has_permission'
$$;

-- customer_ledger_entries
insert into fn_calls select 'before', pg_temp.has_permission_calls();
select tests.authenticate_as(:'owner');
select is((select count(*) from public.customer_ledger_entries), 2000::bigint, 'owner sees all 2,000 customer ledger rows');
select tests.clear_authentication();
select case when current_setting('track_functions') = 'all'
  then cmp_ok(pg_temp.has_permission_calls() - (select calls from fn_calls where label = 'before'), '<', 20::bigint,
         'customer_ledger_select does not call app.has_permission once per row')
  else skip('track_functions cannot be enabled by this role', 1) end;

-- supplier_ledger_entries
delete from fn_calls;
insert into fn_calls select 'before', pg_temp.has_permission_calls();
select tests.authenticate_as(:'owner');
select is((select count(*) from public.supplier_ledger_entries), 2000::bigint, 'owner sees all 2,000 supplier ledger rows');
select tests.clear_authentication();
select case when current_setting('track_functions') = 'all'
  then cmp_ok(pg_temp.has_permission_calls() - (select calls from fn_calls where label = 'before'), '<', 20::bigint,
         'supplier_ledger_select does not call app.has_permission once per row')
  else skip('track_functions cannot be enabled by this role', 1) end;

-- =============================================================================================
-- B. search-medicines-full-scan (4 assertions)
-- Regression: POS search (search_medicines) must stay index-driven and tenant-scoped. An exact barcode
-- scan in tenant A must not sequentially read tenant B's catalog (cost would grow with platform size).
-- =============================================================================================
select tests.create_user('owner-a@search.test') as owner_a \gset
select tests.create_user('sales-a@search.test') as sales_a \gset
select tests.create_user('owner-b@search.test') as owner_b \gset
select tests.authenticate_as(:'owner_a');
select public.create_organization('Search A', 'Dhanmondi', 'SRA') as org_a \gset
select id as branch_a from public.branches where organization_id = :'org_a' \gset
select tests.add_member(:'org_a', 'sales-a@search.test', 'salesman', array[:'branch_a']::uuid[]) as m \gset
select tests.authenticate_as(:'owner_b');
select public.create_organization('Search B', 'Gulshan', 'SRB') as org_b \gset
select tests.clear_authentication();

-- Tenant A: 500 medicines with barcodes. Tenant B: 20,000 medicines with barcodes.
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
select :'org_a', 'A' || substr(md5('a' || g), 1, 9), 'tablet', 'tablet' from generate_series(1, 500) g;
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
select :'org_b', 'B' || substr(md5('b' || g), 1, 9), 'tablet', 'tablet' from generate_series(1, 20000) g;
insert into public.medicine_barcodes (organization_id, medicine_id, barcode)
select organization_id, id, left(organization_id::text, 4) || lpad((row_number() over (partition by organization_id order by id))::text, 10, '0')
  from public.medicines where organization_id in (:'org_a', :'org_b');
analyze public.medicines;
analyze public.medicine_barcodes;
analyze public.generics;

select barcode as bc, medicine_id as bc_med from public.medicine_barcodes
 where organization_id = :'org_a' order by barcode offset 123 limit 1 \gset

create temp table scan_before as
select relname, coalesce(seq_tup_read, 0) as seq_tup_read from pg_stat_xact_user_tables
 where schemaname = 'public' and relname in ('medicines', 'medicine_barcodes');

select tests.authenticate_as(:'sales_a', 'aal1');
select results_eq(
  format($$ select medicine_id from public.search_medicines(%L, %L, 20) $$, :'branch_a', :'bc'),
  format($$ values (%L::uuid) $$, :'bc_med'),
  'exact barcode scan finds the medicine');
select tests.clear_authentication();

select cmp_ok(
  (select s.seq_tup_read - b.seq_tup_read from pg_stat_xact_user_tables s join scan_before b using (relname)
    where s.schemaname = 'public' and s.relname = 'medicine_barcodes'),
  '<', 500::bigint,
  'barcode lookup does not sequentially scan other tenants'' medicine_barcodes');
select cmp_ok(
  (select s.seq_tup_read - b.seq_tup_read from pg_stat_xact_user_tables s join scan_before b using (relname)
    where s.schemaname = 'public' and s.relname = 'medicines'),
  '<', 1000::bigint,
  'barcode lookup does not sequentially scan other tenants'' medicines');

select tests.authenticate_as(:'sales_a', 'aal1');
select results_eq(
  format($$ select medicine_id from public.search_medicines(%L, (select brand_name from public.medicines where id = %L), 1) $$,
    :'branch_a', :'bc_med'),
  format($$ values (%L::uuid) $$, :'bc_med'),
  'a brand name search ranks the exact brand first');
select tests.clear_authentication();

-- Name search must not read the other tenant's catalog either.
delete from scan_before;
insert into scan_before
select relname, coalesce(seq_tup_read, 0) from pg_stat_xact_user_tables
 where schemaname = 'public' and relname in ('medicines', 'medicine_barcodes');
select tests.authenticate_as(:'sales_a', 'aal1');
select count(*) as nothing from public.search_medicines(:'branch_a', 'zzzz', 20) \gset
select tests.clear_authentication();
select cmp_ok(
  (select sum(s.seq_tup_read - b.seq_tup_read) from pg_stat_xact_user_tables s join scan_before b using (relname)
    where s.schemaname = 'public')::bigint,
  '<', 2000::bigint,
  'a no-match name search does not sequentially scan other tenants'' catalog rows');

-- =============================================================================================
-- C. batches-updates-never-hot (2 assertions)
-- Regression: stock changes (app.post_movement updating batches.quantity_on_hand) should be able to use
-- HOT updates. Using quantity_on_hand in a partial-index predicate makes every stock change a non-HOT
-- update that inserts into every batches index.
-- =============================================================================================
select tests.create_user('owner@hot.test') as owner \gset
select tests.authenticate_as(:'owner');
select public.create_organization('HOT Pharmacy', 'Dhanmondi', 'HOT') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
  values (:'org', 'Napa', 'tablet', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Depot') returning id as supplier \gset
select public.receive_goods(:'branch', :'supplier', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'N1', 'expiry_date', :'today'::date + 400,
    'quantity', 1000, 'unit_cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120)
), gen_random_uuid(), 'INV-HOT', :'today'::date, 0, 0, 'cash') as receipt \gset
select id as batch from public.batches where branch_id = :'branch' and batch_no = 'N1' \gset
select tests.clear_authentication();

create temp table upd_before as
select coalesce(n_tup_upd, 0) as upd, coalesce(n_tup_hot_upd, 0) as hot
  from pg_stat_xact_user_tables where schemaname = 'public' and relname = 'batches';

-- 50 stock changes (stock stays above zero, so no batch leaves the partial indexes).
select tests.authenticate_as(:'owner');
select count(public.adjust_stock(:'batch', -1, 'damage', gen_random_uuid(), 'broken strip')) as adjustments from generate_series(1, 50) \gset
select tests.clear_authentication();

select cmp_ok((select s.n_tup_upd - b.upd from pg_stat_xact_user_tables s cross join upd_before b
                where s.schemaname = 'public' and s.relname = 'batches'), '>=', 50::bigint,
  '50 stock changes updated the batch row');
select cmp_ok((select s.n_tup_hot_upd - b.hot from pg_stat_xact_user_tables s cross join upd_before b
                where s.schemaname = 'public' and s.relname = 'batches'), '>', 0::bigint,
  'stock changes that do not touch indexed columns are HOT updates');

-- =============================================================================================
-- D. report-low-stock-cross-tenant-scan (3 assertions)
-- Regression: report_low_stock (SECURITY DEFINER, so no RLS) must filter medicines by the caller's
-- organization; otherwise it sequentially reads every tenant's catalog and gets slower as the platform grows.
-- =============================================================================================
select tests.create_user('owner-a@lowstock.test') as owner_a \gset
select tests.create_user('owner-b@lowstock.test') as owner_b \gset
select tests.authenticate_as(:'owner_a');
select public.create_organization('Low Stock A', 'Dhanmondi', 'LSA') as org_a \gset
select id as branch_a from public.branches where organization_id = :'org_a' \gset
select app.business_date(:'org_a') as today \gset
select tests.authenticate_as(:'owner_b');
select public.create_organization('Low Stock B', 'Gulshan', 'LSB') as org_b \gset
select tests.clear_authentication();

-- Tenant A: 3,000 medicines with reorder levels, half of them below the level. Tenant B: 30,000 medicines.
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
select :'org_a', 'A' || lpad(g::text, 6, '0'), 'tablet', 'tablet' from generate_series(1, 3000) g;
-- Stock enters lots only through the stock ledger (app.post_movement), as in production.
insert into public.batches (organization_id, branch_id, medicine_id, batch_no, expiry_date, cost_paisa, mrp_paisa,
  sale_price_paisa)
select :'org_a', :'branch_a', id, 'B1', :'today'::date + 400, 50, 100, 100
  from public.medicines where organization_id = :'org_a';
select count(app.post_movement(b.id, 'opening_balance', case when m.brand_name < 'A001501' then 5 else 50 end,
         'opening_stock', null))
  from public.batches b join public.medicines m on m.id = b.medicine_id
 where b.branch_id = :'branch_a';
insert into public.branch_medicine_settings (organization_id, branch_id, medicine_id, reorder_level)
select :'org_a', :'branch_a', id, 10 from public.medicines where organization_id = :'org_a';
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
select :'org_b', 'B' || lpad(g::text, 6, '0'), 'tablet', 'tablet' from generate_series(1, 30000) g;
analyze public.medicines;
analyze public.batches;
analyze public.branch_medicine_settings;

drop table if exists scan_before;
create temp table scan_before as
select relname, coalesce(seq_tup_read, 0) as seq_tup_read from pg_stat_xact_user_tables where schemaname = 'public';

select tests.authenticate_as(:'owner_a');
select is((select count(*) from public.report_low_stock(:'branch_a')), 1500::bigint,
  'report lists the 1,500 medicines at or below their reorder level');
select is((select sellable_quantity from public.report_low_stock(:'branch_a') order by brand_name limit 1), 5::bigint,
  'report shows sellable stock');
select tests.clear_authentication();

select cmp_ok(
  (select (s.seq_tup_read - b.seq_tup_read) from pg_stat_xact_user_tables s join scan_before b using (relname)
    where s.schemaname = 'public' and s.relname = 'medicines'),
  '<', 30000::bigint,
  'report_low_stock does not sequentially read the other tenant''s medicines');

-- =============================================================================================
-- E. controlled-register-missing-indexes (4 assertions)
-- Regression: void_sale / process_sale_return look up controlled_drug_register by sale_id / sale_item_id.
-- The register is append-only and platform-wide, so these lookups need indexes (no sequential scans while
-- the sale and its batches are locked).
-- =============================================================================================
select ok(exists (
  select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
   where i.indrelid = 'public.controlled_drug_register'::regclass and a.attname = 'sale_id'),
  'controlled_drug_register has an index leading with sale_id');
select ok(exists (
  select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
   where i.indrelid = 'public.controlled_drug_register'::regclass and a.attname = 'sale_item_id'),
  'controlled_drug_register has an index leading with sale_item_id');

-- Behaviour: voiding a controlled sale must not read the whole register.
select tests.create_user('owner@cdr.test') as owner \gset
select tests.authenticate_as(:'owner');
select public.create_organization('CDR Pharmacy', 'Dhanmondi', 'CDR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, schedule, base_unit_label)
  values (:'org', 'Sedil', 'tablet', '5 mg', 'controlled', 'tablet') returning id as sedil \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Depot') returning id as supplier \gset
select public.receive_goods(:'branch', :'supplier', jsonb_build_array(
  jsonb_build_object('medicine_id', :'sedil', 'batch_no', 'SD-1', 'expiry_date', :'today'::date + 400,
    'quantity', 100, 'unit_cost_paisa', 200, 'mrp_paisa', 300, 'sale_price_paisa', 300)
), gen_random_uuid(), 'INV-CDR', :'today'::date, 0, 0, 'cash') as receipt \gset
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'sedil', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 300}]'::jsonb, gen_random_uuid(), null, null, 0,
  jsonb_build_object('patient_name', 'Rahim', 'doctor_name', 'Dr. Karim', 'doctor_reg_no', 'A-12345',
    'prescription_date', :'today')) ->> 'sale_id' as old_sale \gset
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'sedil', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 300}]'::jsonb, gen_random_uuid(), null, null, 0,
  jsonb_build_object('patient_name', 'Rahim', 'doctor_name', 'Dr. Karim', 'doctor_reg_no', 'A-12345',
    'prescription_date', :'today')) ->> 'sale_id' as sale_to_void \gset
select tests.clear_authentication();

-- Simulate years of register history (copies of the first sale's entry).
insert into public.controlled_drug_register (organization_id, branch_id, medicine_id, sale_id, sale_item_id,
  prescription_id, entry_type, quantity, patient_name, doctor_name, doctor_reg_no, created_by)
select r.organization_id, r.branch_id, r.medicine_id, r.sale_id, r.sale_item_id, r.prescription_id, r.entry_type,
       r.quantity, r.patient_name, r.doctor_name, r.doctor_reg_no, r.created_by
  from public.controlled_drug_register r cross join generate_series(1, 5000)
 where r.sale_id = :'old_sale';
analyze public.controlled_drug_register;

drop table if exists scan_before;
create temp table scan_before as
select coalesce(seq_tup_read, 0) as seq_tup_read from pg_stat_xact_user_tables
 where schemaname = 'public' and relname = 'controlled_drug_register';
select tests.authenticate_as(:'owner');
select lives_ok(format($$ select public.void_sale(%L, 'wrong patient') $$, :'sale_to_void'), 'controlled sale is voided');
select tests.clear_authentication();
select cmp_ok(
  (select s.seq_tup_read - b.seq_tup_read from pg_stat_xact_user_tables s cross join scan_before b
    where s.schemaname = 'public' and s.relname = 'controlled_drug_register'),
  '<', 1000::bigint,
  'void_sale does not sequentially scan the controlled drug register');

-- =============================================================================================
-- F. truncate-and-projection-unguarded (7 assertions)
-- Regression: truncate-and-projection-unguarded.
-- Append-only is enforced by BEFORE UPDATE/DELETE row triggers only. TRUNCATE skips row triggers, and
-- app.harden_privileges() revokes nothing from service_role, which keeps the platform default ALL
-- (including TRUNCATE) on every public table. The design (3.5, 16) says TRUNCATE is revoked on ledgers.
-- Nothing stops privileged code from editing the batches.quantity_on_hand projection directly either
-- (design delta D-23).
-- =============================================================================================
select format('owner-%s@truncate.test', gen_random_uuid()) as owner_email \gset
select tests.create_user(:'owner_email') as owner \gset
select tests.authenticate_as(:'owner');
select public.create_organization('Truncate Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa',
  'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300, 'quantity', 100, 'cost_paisa', 50,
  'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid());
select id as batch from public.batches where organization_id = :'org' and batch_no = 'NA-1' \gset
select tests.clear_authentication();

select ok(not has_table_privilege('service_role', 'public.inventory_movements', 'TRUNCATE'),
  'service_role cannot TRUNCATE the stock ledger');
select ok(not has_table_privilege('service_role', 'public.customer_ledger_entries', 'TRUNCATE'),
  'service_role cannot TRUNCATE the customer ledger');
select ok(not has_table_privilege('service_role', 'public.loyalty_point_ledger', 'TRUNCATE'),
  'service_role cannot TRUNCATE the points ledger');
select ok(not has_table_privilege('service_role', 'public.controlled_drug_register', 'TRUNCATE'),
  'service_role cannot TRUNCATE the controlled drug register');

set local role service_role;
select throws_ok(format('update public.batches set quantity_on_hand = quantity_on_hand + 500 where id = %L', :'batch'),
  null, null, 'a direct edit of the on-hand projection (without a ledger row) is rejected');
reset role;
select is((select quantity_on_hand from public.batches where id = :'batch'),
          (select sum(quantity)::int from public.inventory_movements where batch_id = :'batch'),
  'on-hand quantity still equals the sum of the stock ledger');

-- last, because a successful TRUNCATE empties the ledger for the rest of the transaction
set local role service_role;
select throws_ok('truncate public.inventory_movements', null, null,
  'TRUNCATE of the stock ledger is rejected (privilege or trigger)');
reset role;

-- =============================================================================================
-- G. missing-fks-register-and-ledgers (5 assertions)
-- Regression: missing-fks-register-and-ledgers.
-- Design DP-03 promises composite (organization_id, parent_id) foreign keys so that no row can point at a
-- missing or foreign parent "even from privileged code". These reference columns have no foreign key:
-- controlled_drug_register.sale_item_id / prescription_id, loyalty_point_ledger.sale_id,
-- inventory_movements.medicine_id, and sale_items.branch_id (which drives the sale_items RLS policy) is
-- not tied to the parent sale's branch. Inserts below run as the table owner (as SECURITY DEFINER code
-- does) and should be rejected with 23503.
-- =============================================================================================
select format('owner-%s@fks.test', gen_random_uuid()) as owner_email \gset
select format('sales-%s@fks.test', gen_random_uuid()) as sales_email \gset
select tests.create_user(:'owner_email') as owner \gset
select tests.create_user(:'sales_email') as sales \gset
select tests.authenticate_as(:'owner');
select public.create_organization('FK Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select public.create_branch(:'org', 'DHN', 'Dhanmondi') as branch2 \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', :'sales_email', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, schedule, base_unit_label)
  values (:'org', 'Sedil', 'tablet', '5 mg', 'controlled', 'tablet') returning id as sedil \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim', '01811223344') returning id as customer \gset
update public.loyalty_plans set is_active = true, discount_bp = 500
 where organization_id = :'org' and duration_months = 3 returning id as plan3 \gset
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'sedil',
  'batch_no', 'SD-1', 'expiry_date', :'today'::date + 300, 'quantity', 100, 'cost_paisa', 200,
  'mrp_paisa', 300, 'sale_price_paisa', 300)), gen_random_uuid());

select tests.authenticate_as(:'sales', 'aal1');
select public.enroll_loyalty(:'customer', :'plan3', :'branch', gen_random_uuid()) ->> 'card_no' as card_no \gset
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'sedil', 'quantity', 2)),
  '[{"method": "cash", "amount_paisa": 600}]'::jsonb, gen_random_uuid(), null, null, 0,
  jsonb_build_object('patient_name', 'Rahim', 'doctor_name', 'Dr. Karim', 'doctor_reg_no', 'A-12345',
    'prescription_date', :'today')) ->> 'sale_id' as sale \gset
select tests.clear_authentication();
select id as batch from public.batches where organization_id = :'org' and batch_no = 'SD-1' \gset
select id as card from public.loyalty_cards where organization_id = :'org' and card_no = :'card_no' \gset
select id as sale_item from public.sale_items where sale_id = :'sale' \gset

select throws_ok(format($$ insert into public.controlled_drug_register (organization_id, branch_id, medicine_id,
    sale_id, sale_item_id, entry_type, quantity) values (%L, %L, %L, %L, gen_random_uuid(), 'sale', -1) $$,
    :'org', :'branch', :'sedil', :'sale'),
  '23503', null, 'controlled register: sale_item_id must reference a sale line');
select throws_ok(format($$ insert into public.controlled_drug_register (organization_id, branch_id, medicine_id,
    sale_id, sale_item_id, prescription_id, entry_type, quantity) values (%L, %L, %L, %L, %L, gen_random_uuid(), 'sale', -1) $$,
    :'org', :'branch', :'sedil', :'sale', :'sale_item'),
  '23503', null, 'controlled register: prescription_id must reference a prescription');
select throws_ok(format($$ insert into public.loyalty_point_ledger (organization_id, card_id, branch_id, entry_type,
    points, sale_id) values (%L, %L, %L, 'earn', 5, gen_random_uuid()) $$, :'org', :'card', :'branch'),
  '23503', null, 'points ledger: sale_id must reference a sale');
select throws_ok(format($$ insert into public.inventory_movements (organization_id, branch_id, batch_id, medicine_id,
    movement_type, quantity, unit_cost_paisa, reference_type) values (%L, %L, %L, gen_random_uuid(), 'adjustment', 1, 0, 'test') $$,
    :'org', :'branch', :'batch'),
  '23503', null, 'stock ledger: medicine_id must reference a medicine');
select throws_ok(format($$ insert into public.sale_items (organization_id, sale_id, branch_id, line_no, medicine_id,
    quantity, gross_paisa, line_discount_paisa, invoice_discount_paisa, loyalty_discount_paisa, net_paisa, cost_paisa)
    values (%L, %L, %L, 99, %L, 1, 100, 0, 0, 0, 100, 50) $$, :'org', :'sale', :'branch2', :'napa'),
  '23503', null, 'sale line: branch_id must be the branch of its sale');

select * from finish();
rollback;
