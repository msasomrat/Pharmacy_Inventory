-- Regression tests for purchasing and inventory defects found in the M1 database review.
-- Each section reproduces one confirmed finding (the section header names it) and asserts the fixed
-- behaviour. Sections are independent: each creates its own organization and users.
begin;
select plan(46);

-- =============================================================================================
-- A. process-purchase-return-always-fails (3 assertions)
-- Regression (found while verifying manager-reads-purchase-cost): process_purchase_return can never
-- complete. Pass 2 groups items with sum((e ->> 'quantity')::integer), which is bigint, and then calls
-- app.post_movement(uuid, movement_type, integer, ...) with -v_item.quantity (bigint) => 42883.
-- =============================================================================================
select tests.create_user('owner@pret.test') as owner \gset
select tests.create_user('manager@pret.test') as manager \gset

select tests.authenticate_as(:'owner');
select public.create_organization('PRet Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@pret.test', 'manager', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Depot') returning id as supplier \gset
select public.receive_goods(:'branch', :'supplier', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
  'quantity', 100, 'unit_cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid());
select id as batch from public.batches where batch_no = 'NA-1' \gset

select tests.authenticate_as(:'manager');
select lives_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 10}]'::jsonb,
  'near expiry', gen_random_uuid()) $$, :'branch', :'supplier', :'batch'),
  'a manager can return 10 units to the supplier');
select is((select quantity_on_hand from public.batches where id = :'batch'), 90, 'returned units leave the batch');
select tests.clear_authentication();
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier'), (100 * 80 - 10 * 80)::bigint,
  'supplier due is reduced by the returned value');

-- =============================================================================================
-- B. purchase-return-always-fails (stock, return line, ledgers) (5 assertions)
-- Regression: process_purchase_return must be able to record a return to the supplier.
-- Defect: sum(integer) is bigint, and app.post_movement(uuid, movement_type, integer, ...) has no
-- implicit bigint -> integer cast, so every call failed with 42883 (function does not exist).
-- =============================================================================================
select tests.create_user('owner@pr1.test') as owner \gset
select tests.create_user('manager@pr1.test') as manager \gset

select tests.authenticate_as(:'owner');
select public.create_organization('PR1 Pharmacy', 'Mohammadpur', 'PRA') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@pr1.test', 'manager', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'E1', 'expiry_date', :'today'::date + 60,
    'quantity', 1000, 'unit_cost_paisa', 50, 'mrp_paisa', 100, 'sale_price_paisa', 100)
), gen_random_uuid()) as grn \gset
select id as e1 from public.batches where batch_no = 'E1' and branch_id = :'branch' \gset

select lives_ok(
  format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 100}]'::jsonb,
    'near expiry', gen_random_uuid()) $$, :'branch', :'supa', :'e1'),
  'a near-expiry purchase return can be recorded');
select is((select quantity_on_hand from public.batches where id = :'e1'), 900,
  'returned units leave the batch');
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supa'),
  (1000 * 50 - 100 * 50)::bigint, 'supplier payable is reduced by the returned value at batch cost');
select is((select count(*)::int from public.purchase_return_items pri
            join public.purchase_returns pr on pr.id = pri.purchase_return_id
           where pr.branch_id = :'branch'), 1, 'one purchase return line is written');
select is((select sum(quantity)::int from public.inventory_movements
            where batch_id = :'e1' and movement_type = 'purchase_return'), -100,
  'the stock ledger records the purchase return');

-- =============================================================================================
-- C. purchase-return-any-supplier (4 assertions)
-- Regression: purchase-return-any-supplier.
-- process_purchase_return only checks that the supplier belongs to the organization. Lots carry no
-- supplier provenance, so stock from opening balances, or bought from supplier A, can be "returned" to
-- supplier B, and B's payable is reduced by the lot cost.
-- =============================================================================================

select format('owner-%s@anysupplier.test', gen_random_uuid()) as owner_email \gset
select format('manager-%s@anysupplier.test', gen_random_uuid()) as manager_email \gset
select tests.create_user(:'owner_email') as owner \gset
select tests.create_user(:'manager_email') as manager \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Any Supplier Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', :'manager_email', 'manager', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supplier_a \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier B') returning id as supplier_b \gset

select tests.authenticate_as(:'manager');
-- Lot 1: opening stock (no supplier). Lot 2: bought from supplier A. Supplier B never supplied anything.
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa',
  'batch_no', 'OPEN-1', 'expiry_date', :'today'::date + 60, 'quantity', 1000, 'cost_paisa', 50,
  'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid());
select public.receive_goods(:'branch', :'supplier_a', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'A-1', 'expiry_date', :'today'::date + 60,
  'quantity', 1000, 'unit_cost_paisa', 50, 'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid()) is not null;
select id as lot_open from public.batches where organization_id = :'org' and batch_no = 'OPEN-1' \gset
select id as lot_a from public.batches where organization_id = :'org' and batch_no = 'A-1' \gset

-- Control: returning supplier A's stock to supplier A works.
select lives_ok(
  format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 100}]'::jsonb,
    'near expiry', gen_random_uuid()) $$, :'branch', :'supplier_a', :'lot_a'),
  'stock bought from supplier A can be returned to supplier A');

select throws_ok(
  format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 500}]'::jsonb,
    'near expiry', gen_random_uuid()) $$, :'branch', :'supplier_b', :'lot_open'),
  'P0001', null, 'opening stock (no supplier) cannot be returned to supplier B');
select throws_ok(
  format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 500}]'::jsonb,
    'near expiry', gen_random_uuid()) $$, :'branch', :'supplier_b', :'lot_a'),
  'P0001', null, 'stock bought from supplier A cannot be returned to supplier B');

select tests.clear_authentication();
select diag(format('supplier B balance: %s', (select balance_paisa from public.supplier_balances where supplier_id = :'supplier_b')));
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier_b'), 0::bigint,
  'supplier B, who supplied nothing, has no balance');

-- =============================================================================================
-- D. purchase-return-wrong-supplier (4 assertions)
-- Regression: a purchase return must be credited to the supplier the batch was received from.
-- Defect: process_purchase_return checks only that the supplier exists and the batch is in the
-- branch, so a batch received from Supplier A (or opening stock) can be returned against Supplier B.
-- =============================================================================================
select tests.create_user('owner@pr5.test') as owner \gset
select tests.create_user('manager@pr5.test') as manager \gset

select tests.authenticate_as(:'owner');
select public.create_organization('PR5 Pharmacy', 'Mohammadpur', 'PRE') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@pr5.test', 'manager', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier B') returning id as supb \gset

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'E1', 'expiry_date', :'today'::date + 60,
    'quantity', 1000, 'unit_cost_paisa', 50, 'mrp_paisa', 100, 'sale_price_paisa', 100)
), gen_random_uuid()) as grn \gset
select id as e1 from public.batches where batch_no = 'E1' and branch_id = :'branch' \gset

-- Supplier B never supplied batch E1: the return must be refused.
select throws_ok(
  format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 100}]'::jsonb,
    'near expiry', gen_random_uuid()) $$, :'branch', :'supb', :'e1'),
  'P0001', null, 'a batch cannot be returned to a supplier it was not received from');
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supb'), 0::bigint,
  'Supplier B balance is untouched');
select is((select quantity_on_hand from public.batches where id = :'e1'), 1000, 'stock is untouched');

-- Returning to the right supplier still works.
select lives_ok(
  format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 100}]'::jsonb,
    'near expiry', gen_random_uuid()) $$, :'branch', :'supa', :'e1'),
  'the batch can be returned to the supplier it came from');

-- =============================================================================================
-- E. grn-unit-cost-rounding-drift (4 assertions)
-- Regression: returning a whole goods-receipt lot to the supplier must credit exactly what the lot
-- was invoiced at. Defect: batch cost = round(net line / (qty + bonus)) drops the remainder, and
-- purchase returns are valued at that rounded batch cost (47 x 90 = 4230 with 7 bonus -> cost 78 ->
-- 54 x 78 = 4212, an 18-paisa mismatch per line).
-- =============================================================================================
select tests.create_user('owner@pr14.test') as owner \gset
select tests.create_user('manager@pr14.test') as manager \gset

select tests.authenticate_as(:'owner');
select public.create_organization('PR14 Pharmacy', 'Mohammadpur', 'PRN') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@pr14.test', 'manager', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'L1', 'expiry_date', :'today'::date + 60,
    'quantity', 47, 'bonus_quantity', 7, 'unit_cost_paisa', 90, 'mrp_paisa', 120, 'sale_price_paisa', 120)
), gen_random_uuid()) as grn \gset
select id as l1 from public.batches where batch_no = 'L1' and branch_id = :'branch' \gset

select is((select balance_paisa from public.supplier_balances where supplier_id = :'supa'), 4230::bigint,
  'supplier is owed the invoiced 47 x 90');

-- Return the entire lot (paid + bonus units).
select lives_ok(
  format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 54}]'::jsonb,
    'whole lot recalled', gen_random_uuid()) $$, :'branch', :'supa', :'l1'),
  'the whole lot can be returned');
select is((select quantity_on_hand from public.batches where id = :'l1'), 0, 'nothing is left in stock');
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supa'), 0::bigint,
  'returning the whole lot clears exactly what was invoiced for it');

-- =============================================================================================
-- F. adjustment-other-null-note (6 assertions)
-- Regression: a stock adjustment with reason 'other' must carry an explanation (>= 3 characters).
-- The CHECK (reason <> 'other' or length(btrim(note)) >= 3) passes when note IS NULL.
-- =============================================================================================
select tests.create_user('owner@adj.test') as owner \gset
select tests.create_user('manager@adj.test') as manager \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Adj Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@adj.test', 'manager', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset

select tests.authenticate_as(:'manager');
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
  'quantity', 100, 'cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid());
select id as batch from public.batches where batch_no = 'NA-1' \gset

select throws_ok(format($$ select public.adjust_stock(%L, -5, 'other', gen_random_uuid(), 'ab') $$, :'batch'),
  'P0001', 'Explain an adjustment with reason "other" (at least 3 characters)',
  'control: a 2-character note is rejected');
select throws_ok(format($$ select public.adjust_stock(%L, -5, 'other', gen_random_uuid()) $$, :'batch'),
  'P0001', 'Explain an adjustment with reason "other" (at least 3 characters)',
  'reason other without a note (NULL) is rejected');
select throws_ok(format($$ select public.adjust_stock(%L, -5, 'other', gen_random_uuid(), '   ') $$, :'batch'),
  'P0001', 'Explain an adjustment with reason "other" (at least 3 characters)',
  'reason other with a blank note (normalised to NULL) is rejected');
select is((select quantity_on_hand from public.batches where id = :'batch'), 100,
  'no stock left the batch without an explanation');
select lives_ok(format($$ select public.adjust_stock(%L, -5, 'other', gen_random_uuid(), 'spilled syrup') $$, :'batch'),
  'reason other with an explanation is accepted');
-- The table constraint itself rejects a NULL note (privileged code paths included).
select tests.clear_authentication();
select throws_ok(format($$ insert into public.stock_adjustments (organization_id, branch_id, batch_id, quantity_delta,
    reason, client_request_id, created_by) values (%L, %L, %L, -1, 'other', gen_random_uuid(), %L) $$,
    :'org', :'branch', :'batch', :'manager'),
  '23514', null, 'stock_adjustments_note_required rejects reason other with a NULL note');

-- =============================================================================================
-- G. low-stock-ignores-near-expiry-block (4 assertions)
-- Regression: report_low_stock must count only stock the POS can actually sell.
-- Defect: report_low_stock counts every unexpired batch (expiry_date > today), but create_sale and
-- search_medicines only sell batches with expiry_date > today + near_expiry_block_days.
-- =============================================================================================
select tests.create_user('owner@v15.test') as owner \gset
select tests.create_user('manager@v15.test') as manager \gset
select tests.create_user('sales@v15.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('V15 Pharmacy', 'Mohammadpur', 'VFF') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@v15.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@v15.test', 'salesman', array[:'branch']::uuid[]);
update public.organization_settings set near_expiry_block_days = 30 where organization_id = :'org';

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
insert into public.branch_medicine_settings (organization_id, branch_id, medicine_id, reorder_level)
  values (:'org', :'branch', :'napa', 50);

select tests.authenticate_as(:'manager');
-- Only batch expires in 20 days: inside the 30-day sales block.
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'N1', 'expiry_date', :'today'::date + 20,
    'quantity', 95, 'unit_cost_paisa', 80, 'mrp_paisa', 105, 'sale_price_paisa', 105)
), gen_random_uuid()) as grn \gset

select tests.authenticate_as(:'sales', 'aal1');
select is((select stock_quantity from public.search_medicines(:'branch', 'Napa')), 0::bigint,
  'the POS shows no sellable stock');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 1}]'::jsonb,
    '[{"method": "cash", "amount_paisa": 105}]'::jsonb, gen_random_uuid()) $$, :'branch', :'napa'),
  'P0001', null, 'and the POS refuses to sell it');

select tests.authenticate_as(:'manager');
select ok(exists (select 1 from public.report_low_stock(:'branch') where medicine_id = :'napa'),
  'the medicine is flagged for reorder (nothing sellable, reorder level 50)');
select is((select sellable_quantity from public.report_low_stock(:'branch') where medicine_id = :'napa'), 0::bigint,
  'low-stock report shows the same sellable quantity as the POS');


-- =============================================================================================
-- H. no-idempotency-on-payments-and-adjustments (14 assertions)
-- record_customer_payment, record_supplier_payment, adjust_stock and add_opening_stock take a
-- client_request_id (NFR-REL-006): a retry after a lost response returns the original result
-- instead of booking the operation twice.
-- =============================================================================================
select ok(exists (select 1 from pg_proc p where p.oid = to_regproc('public.record_customer_payment')
                    and 'p_client_request_id' = any (p.proargnames)),
  'record_customer_payment takes a client_request_id');
select ok(exists (select 1 from pg_proc p where p.oid = to_regproc('public.record_supplier_payment')
                    and 'p_client_request_id' = any (p.proargnames)),
  'record_supplier_payment takes a client_request_id');
select ok(exists (select 1 from pg_proc p where p.oid = to_regproc('public.adjust_stock')
                    and 'p_client_request_id' = any (p.proargnames)),
  'adjust_stock takes a client_request_id');
select ok(exists (select 1 from pg_proc p where p.oid = to_regproc('public.add_opening_stock')
                    and 'p_client_request_id' = any (p.proargnames)),
  'add_opening_stock takes a client_request_id');

select tests.create_user('owner@retry.test') as owner \gset
select tests.create_user('manager@retry.test') as manager \gset
select tests.create_user('sales@retry.test') as sales \gset
select tests.authenticate_as(:'owner');
select public.create_organization('Retry Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@retry.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@retry.test', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Depot') returning id as supplier \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim', '01811223344') returning id as customer \gset
select public.set_customer_credit_limit(:'customer', 100000);

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supplier', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
  'quantity', 100, 'unit_cost_paisa', 400, 'mrp_paisa', 1000, 'sale_price_paisa', 1000)), gen_random_uuid()) is not null;
select id as batch from public.batches where organization_id = :'org' and batch_no = 'NA-1' \gset
select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 10)),
  '[]'::jsonb, gen_random_uuid(), :'customer') is not null;   -- due 10000

-- Customer pays 4000 by bKash; the response is lost and the app retries the identical call.
select gen_random_uuid() as pay_req \gset
select public.record_customer_payment(:'customer', :'branch', 4000, 'bkash', :'pay_req', 'TRX-1') as pay1 \gset
select is(public.record_customer_payment(:'customer', :'branch', 4000, 'bkash', :'pay_req', 'TRX-1'), 6000::bigint,
  'a retried customer payment returns the balance without paying again');
select is((select balance_paisa from public.customer_balances where customer_id = :'customer'), 6000::bigint,
  'customer due after a 4000 payment sent twice is 10000 - 4000');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 1000, 'bkash', %L) $$,
    :'customer', :'branch', :'pay_req'),
  'P0001', 'This request id was already used for another payment', 'a request id cannot be reused for a different payment');

-- Supplier paid 40000 (the full payable); retried.
select tests.authenticate_as(:'manager');
select gen_random_uuid() as spay_req \gset
select public.record_supplier_payment(:'supplier', 40000, 'bank_transfer', :'spay_req', :'branch', 'CHQ-1') as spay1 \gset
select is(public.record_supplier_payment(:'supplier', 40000, 'bank_transfer', :'spay_req', :'branch', 'CHQ-1'), :'spay1'::uuid,
  'a retried supplier payment returns the original payment');
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier'), 0::bigint,
  'supplier payable after a 40000 payment sent twice is 0');

-- Damage write-off of 5 units; retried.
select gen_random_uuid() as adj_req \gset
select public.adjust_stock(:'batch', -5, 'damage', :'adj_req', 'broken strip') as adj1 \gset
select is(public.adjust_stock(:'batch', -5, 'damage', :'adj_req', 'broken strip'), :'adj1'::uuid,
  'a retried adjustment returns the original adjustment');
select is((select quantity_on_hand from public.batches where id = :'batch'), 85,
  'lot after a 5-unit write-off sent twice: 100 - 10 sold - 5');

-- Opening stock line; retried.
select gen_random_uuid() as open_req \gset
select format($$select public.add_opening_stock(%L, jsonb_build_array(jsonb_build_object('medicine_id', %L,
  'batch_no', 'OPEN-1', 'expiry_date', %L, 'quantity', 50, 'cost_paisa', 400,
  'mrp_paisa', 1000, 'sale_price_paisa', 1000)), %L)$$, :'branch', :'napa', :'today'::date + 300, :'open_req') as open_sql \gset
select results_eq(:'open_sql', 'values (1)', 'opening stock loads one line');
select results_eq(:'open_sql', 'values (1)', 'a retried opening-stock load returns the original line count');
select is((select row(count(*), sum(quantity_on_hand))::text from public.batches
            where organization_id = :'org' and batch_no = 'OPEN-1'), '(1,50)',
  'opening stock sent twice creates one lot of 50 units');

-- =============================================================================================
-- I. Purchase returns are valued from the receipt line net (invoice discount and bonus included),
--    and never exceed what the receipt line brought in (grn-unit-cost-rounding-drift follow-up).
-- =============================================================================================
select tests.create_user('owner@prdisc.test') as owner \gset
select tests.authenticate_as(:'owner');
select public.create_organization('PR Discount Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
  values (:'org', 'Napa', 'tablet', 'tablet') returning id as napa \gset
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
  values (:'org', 'Fexo', 'tablet', 'tablet') returning id as fexo \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Depot') returning id as supplier \gset
-- 30 x 70 + 3 bonus and 11 x 130, invoice discount 101: payable 2100 + 1430 - 101 = 3429.
select public.receive_goods(:'branch', :'supplier', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NP-1', 'expiry_date', :'today'::date + 300,
    'quantity', 30, 'bonus_quantity', 3, 'unit_cost_paisa', 70, 'mrp_paisa', 120, 'sale_price_paisa', 120),
  jsonb_build_object('medicine_id', :'fexo', 'batch_no', 'FX-1', 'expiry_date', :'today'::date + 300,
    'quantity', 11, 'unit_cost_paisa', 130, 'mrp_paisa', 200, 'sale_price_paisa', 200)),
  gen_random_uuid(), null, null, 101) is not null;
select id as lot_np from public.batches where organization_id = :'org' and batch_no = 'NP-1' \gset
select id as lot_fx from public.batches where organization_id = :'org' and batch_no = 'FX-1' \gset
select public.process_purchase_return(:'branch', :'supplier',
  jsonb_build_array(jsonb_build_object('batch_id', :'lot_np', 'quantity', 10)), 'near expiry', gen_random_uuid()) is not null;
select public.process_purchase_return(:'branch', :'supplier',
  jsonb_build_array(jsonb_build_object('batch_id', :'lot_np', 'quantity', 23),
                    jsonb_build_object('batch_id', :'lot_fx', 'quantity', 11)), 'recall', gen_random_uuid()) is not null;
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier'), 0::bigint,
  'returning every unit of a discounted receipt (in parts) clears exactly the invoiced amount');
-- Stock found in a count cannot be "returned" beyond what the supplier delivered.
select public.adjust_stock(:'lot_fx', 5, 'count_correction', gen_random_uuid(), 'found in back store') is not null;
select throws_ok(format($$ select public.process_purchase_return(%L, %L,
    '[{"batch_id": "%s", "quantity": 5}]'::jsonb, 'recall', gen_random_uuid()) $$, :'branch', :'supplier', :'lot_fx'),
  'P0001', 'Cannot return more than was received on the goods receipt',
  'a lot cannot be returned beyond the quantity its receipt line delivered');

select * from finish();
rollback;
