-- End-to-end business flow: goods receipt -> FEFO sale -> idempotency -> limits -> credit ->
-- controlled drugs -> loyalty -> return -> void -> reports, with role and column security checks.
begin;
select plan(48);

-- ---------------------------------------------------------------------------
-- Setup: organization, staff, catalog, supplier
-- ---------------------------------------------------------------------------
select tests.create_user('owner@flow.test') as owner \gset
select tests.create_user('manager@flow.test') as manager \gset
select tests.create_user('sales@flow.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Flow Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
-- Business dates are in Asia/Dhaka, which can differ from the server's UTC date.
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@flow.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@flow.test', 'salesman', array[:'branch']::uuid[]);

insert into public.manufacturers (organization_id, name) values (:'org', 'Beximco') returning id as mfr \gset
insert into public.generics (organization_id, name) values (:'org', 'Paracetamol') returning id as gen \gset
insert into public.medicines (organization_id, brand_name, generic_id, manufacturer_id, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', :'gen', :'mfr', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, schedule, base_unit_label)
  values (:'org', 'Seclo', 'capsule', '20 mg', 'rx', 'capsule') returning id as seclo \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, schedule, base_unit_label)
  values (:'org', 'Sedil', 'tablet', '5 mg', 'controlled', 'tablet') returning id as sedil \gset
insert into public.suppliers (organization_id, name, phone) values (:'org', 'Beximco Depot', '01711000000')
  returning id as supplier \gset

select is((select phone from public.suppliers where id = :'supplier'), '+8801711000000', 'supplier phone is normalised to E.164');

-- ---------------------------------------------------------------------------
-- Goods receipt
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supplier', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-LATE', 'expiry_date', current_date + 300,
    'quantity', 100, 'unit_cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120),
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-EARLY', 'expiry_date', current_date + 60,
    'quantity', 40, 'bonus_quantity', 10, 'unit_cost_paisa', 90, 'mrp_paisa', 120, 'sale_price_paisa', 115),
  jsonb_build_object('medicine_id', :'seclo', 'batch_no', 'SE-1', 'expiry_date', current_date + 400,
    'quantity', 100, 'unit_cost_paisa', 500, 'mrp_paisa', 700, 'sale_price_paisa', 700),
  jsonb_build_object('medicine_id', :'sedil', 'batch_no', 'SD-1', 'expiry_date', current_date + 400,
    'quantity', 20, 'unit_cost_paisa', 200, 'mrp_paisa', 300, 'sale_price_paisa', 300)
), gen_random_uuid(), 'INV-9001', current_date, 0, 10000, 'cash') as receipt \gset

select is(:'receipt'::jsonb ->> 'receipt_no', 'MPR-G' || app.fiscal_year_label(:'today') || '-000001',
  'goods receipt gets a gapless branch number');
select is((select quantity_on_hand from public.batches where batch_no = 'NA-EARLY'), 50,
  'bonus units are added to stock');
select tests.clear_authentication();
select is((select cost_paisa from public.batches where batch_no = 'NA-EARLY'), 72::bigint,
  'batch cost spreads the paid amount over bonus units (40 x 90 / 50 = 72)');
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier'),
  (100 * 80 + 40 * 90 + 100 * 500 + 20 * 200 - 10000)::bigint, 'supplier due = purchase total - amount paid');

select tests.authenticate_as(:'manager');
select throws_ok(
  format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "X", "expiry_date": "%s",
    "quantity": 1, "unit_cost_paisa": 1, "mrp_paisa": 10, "sale_price_paisa": 10}]'::jsonb, gen_random_uuid(), 'INV-9001') $$,
    :'branch', :'supplier', :'napa', current_date + 10),
  '23505', null, 'the same supplier invoice number cannot be received twice');
select throws_ok(
  format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "X", "expiry_date": "%s",
    "quantity": 1, "unit_cost_paisa": 1, "mrp_paisa": 10, "sale_price_paisa": 10}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'supplier', :'napa', current_date),
  'P0001', 'Expiry date must be in the future', 'expired stock cannot be received');
select throws_ok(
  format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "X", "expiry_date": "%s",
    "quantity": 1, "unit_cost_paisa": 1, "mrp_paisa": 10, "sale_price_paisa": 11}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'supplier', :'napa', current_date + 10),
  'P0001', 'Sale price must be greater than zero and not above MRP', 'selling price above MRP is rejected');

-- ---------------------------------------------------------------------------
-- FEFO sale, change, idempotency
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'sales', 'aal1');
select gen_random_uuid() as req1 \gset
select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 60)),
  '[{"method": "cash", "amount_paisa": 7000}]'::jsonb, :'req1') as sale1 \gset

select is(:'sale1'::jsonb ->> 'invoice_no', 'MPR-' || app.fiscal_year_label(:'today') || '-000001',
  'first invoice number of the fiscal year');
select is((:'sale1'::jsonb ->> 'total_paisa')::bigint, (50 * 115 + 10 * 120)::bigint,
  'FEFO: 50 from the early-expiry batch at 1.15 + 10 from the later batch at 1.20');
select is((:'sale1'::jsonb ->> 'change_paisa')::bigint, 50::bigint, 'change is returned from cash');
select is((select quantity_on_hand from public.batches where batch_no = 'NA-EARLY'), 0, 'early batch emptied first');
select is((select quantity_on_hand from public.batches where batch_no = 'NA-LATE'), 90, 'later batch used for the rest');

select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 60)),
  '[{"method": "cash", "amount_paisa": 7000}]'::jsonb, :'req1') as replay \gset
select ok((:'replay'::jsonb ->> 'replayed')::boolean and :'replay'::jsonb ->> 'sale_id' = :'sale1'::jsonb ->> 'sale_id',
  'retrying the same request returns the original sale');
select is((select quantity_on_hand from public.batches where batch_no = 'NA-LATE'), 90, 'a retried request does not sell twice');

select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 1000}]'::jsonb, '[]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'napa'),
  'P0001', null, 'cannot sell more than sellable stock');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 1, "discount_bp": 600}]'::jsonb,
    '[{"method": "cash", "amount_paisa": 200}]'::jsonb, gen_random_uuid()) $$, :'branch', :'napa'),
  'P0001', 'Discount exceeds your limit', 'salesman discount is capped at 5% by default');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 1}]'::jsonb,
    '[{"method": "bkash", "amount_paisa": 500}]'::jsonb, gen_random_uuid()) $$, :'branch', :'napa'),
  'P0001', 'Card, mobile banking and points payments cannot exceed the total', 'no change is given on mobile payments');

-- Column privileges: cost is hidden from direct queries
select throws_ok('select cost_paisa from public.batches', '42501', null, 'staff cannot read batch cost directly');
select throws_ok('select cost_paisa from public.sales', '42501', null, 'staff cannot read sale cost directly');
select lives_ok('select id, sale_price_paisa, quantity_on_hand from public.batches', 'staff can read prices and stock');

-- Ledger immutability
select tests.clear_authentication();
select throws_ok('update public.inventory_movements set quantity = 1', 'P0001', null, 'stock ledger rows cannot be edited');
select throws_ok('delete from public.sale_payments', 'P0001', null, 'payments cannot be deleted');
select throws_ok(format($$ update public.sales set total_paisa = 1 where id = %L $$, :'sale1'::jsonb ->> 'sale_id'),
  'P0001', 'A completed sale cannot be edited; void or return it instead', 'sale totals cannot be edited');

-- ---------------------------------------------------------------------------
-- Controlled medicines need a prescription; register entry is written
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 2}]'::jsonb,
    '[{"method": "cash", "amount_paisa": 600}]'::jsonb, gen_random_uuid()) $$, :'branch', :'sedil'),
  'P0001', 'Prescription details are required for this sale', 'controlled medicine without prescription is refused');
select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'sedil', 'quantity', 2)),
  '[{"method": "cash", "amount_paisa": 600}]'::jsonb, gen_random_uuid(), null, null, 0,
  jsonb_build_object('patient_name', 'Rahim', 'doctor_name', 'Dr. Karim', 'doctor_reg_no', 'A-12345',
    'prescription_date', current_date)) as sale_ctrl \gset
select tests.clear_authentication();
select is((select quantity from public.controlled_drug_register where sale_id = (:'sale_ctrl'::jsonb ->> 'sale_id')::uuid),
  -2, 'controlled drug register records the sale');

-- ---------------------------------------------------------------------------
-- Customer credit (due / বাকি)
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'sales', 'aal1');
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim Uddin', '01811-223344')
  returning id as customer \gset
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 10}]'::jsonb,
    '[{"method": "cash", "amount_paisa": 200}]'::jsonb, gen_random_uuid(), %L) $$, :'branch', :'napa', :'customer'),
  'P0001', 'This sale would exceed the customer''s credit limit', 'credit sale refused when the limit is zero');
select throws_ok(format($$ select public.set_customer_credit_limit(%L, 5000) $$, :'customer'),
  'P0001', 'Only an owner or manager can change credit limits', 'salesman cannot change credit limits');

select tests.authenticate_as(:'owner');
select public.set_customer_credit_limit(:'customer', 5000);
select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 10)),
  '[{"method": "cash", "amount_paisa": 200}]'::jsonb, gen_random_uuid(), :'customer') as sale_credit \gset
select is((:'sale_credit'::jsonb ->> 'due_paisa')::bigint, 1000::bigint, 'unpaid amount becomes customer due');
select is((select balance_paisa from public.customer_balances where customer_id = :'customer'), 1000::bigint,
  'customer balance reflects the due');
select is(public.record_customer_payment(:'customer', :'branch', 400, 'bkash', gen_random_uuid(), 'TRX123'), 600::bigint,
  'collecting part of the due reduces the balance');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 999999, 'cash', gen_random_uuid()) $$, :'customer', :'branch'),
  'P0001', 'Payment is larger than the outstanding due', 'overpayment of dues is refused');

-- ---------------------------------------------------------------------------
-- Loyalty: owner configures the 3-month plan, salesman enrols, discount and points apply
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'owner');
update public.loyalty_plans
   set is_active = true, fee_paisa = 20000, discount_bp = 500, points_per_100_taka = 1, point_value_paisa = 100
 where organization_id = :'org' and duration_months = 3
 returning id as plan3 \gset

select tests.authenticate_as(:'sales', 'aal1');
select public.enroll_loyalty(:'customer', :'plan3', :'branch', gen_random_uuid(), 'cash') as enrol \gset
-- Ends the day before the same day-of-month three months later; when that month is shorter (start on
-- the 31st), it ends on that month's last day instead.
select is((:'enrol'::jsonb ->> 'ends_on')::date,
  case when extract(day from :'today'::date + interval '3 months') < extract(day from :'today'::date)
       then (:'today'::date + interval '3 months')::date
       else (:'today'::date + interval '3 months')::date - 1 end,
  '3-month membership ends the day before the same date three months later');
select ok(app.luhn_check_digit(left(:'enrol'::jsonb ->> 'card_no', -1)) = right(:'enrol'::jsonb ->> 'card_no', 1)::int,
  'generated card number carries a valid Luhn check digit');

select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'seclo', 'quantity', 30),
                    jsonb_build_object('medicine_id', :'sedil', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 21000}]'::jsonb, gen_random_uuid(), null, :'enrol'::jsonb ->> 'card_no', 0,
  jsonb_build_object('patient_name', 'Karim Uddin', 'doctor_name', 'Dr. Karim', 'doctor_reg_no', 'A-12345',
    'prescription_date', current_date)) as sale_loyal \gset
select is((:'sale_loyal'::jsonb ->> 'loyalty_discount_paisa')::bigint, 1050::bigint,
  '5% loyalty discount on eligible items only (controlled medicine excluded)');
select is((:'sale_loyal'::jsonb ->> 'total_paisa')::bigint, (21000 - 1050 + 300)::bigint, 'total after loyalty discount');
select is((:'sale_loyal'::jsonb ->> 'points_earned')::int, 1, 'one point per 100 taka of eligible spend');
select is((select customer_id from public.sales where id = (:'sale_loyal'::jsonb ->> 'sale_id')::uuid), :'customer'::uuid,
  'loyalty sale is linked to the card holder');

-- ---------------------------------------------------------------------------
-- Returns (manager) and voids
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$ select public.void_sale(%L, 'mistake') $$, :'sale1'::jsonb ->> 'sale_id'),
  'P0001', 'Permission denied: sales.void', 'salesman cannot void');

select tests.authenticate_as(:'manager');
select id as seclo_line from public.sale_items
 where sale_id = (:'sale_loyal'::jsonb ->> 'sale_id')::uuid and medicine_id = :'seclo' \gset
select public.process_sale_return((:'sale_loyal'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'seclo_line', 'quantity', 10)),
  'customer changed prescription', gen_random_uuid()) as ret \gset
select is((:'ret'::jsonb ->> 'refund_paisa')::bigint, 6650::bigint, 'refund is the proportional net amount (19950 x 10/30)');
select is((select quantity_on_hand from public.batches where batch_no = 'SE-1'), 80, 'returned units go back to their batch');
select throws_ok(
  format($$ select public.process_sale_return(%L, '[{"sale_item_id": "%s", "quantity": 21}]'::jsonb, 'again', gen_random_uuid()) $$,
    :'sale_loyal'::jsonb ->> 'sale_id', :'seclo_line'),
  'P0001', 'Return quantity exceeds the quantity still returnable', 'cannot return more than was sold');
select throws_ok(
  format($$ select public.void_sale(%L, 'mistake') $$, :'sale_loyal'::jsonb ->> 'sale_id'),
  'P0001', 'A sale with returns cannot be voided', 'a sale with returns cannot be voided');

select public.void_sale((:'sale1'::jsonb ->> 'sale_id')::uuid, 'wrong customer');
select is((select quantity_on_hand from public.batches where batch_no = 'NA-EARLY'), 50, 'void restores the early batch');
select is((select quantity_on_hand from public.batches where batch_no = 'NA-LATE'), 90,
  'void restores the later batch (80 after the credit sale + 10 restored)');

-- ---------------------------------------------------------------------------
-- Reports: cost and profit only for permitted roles
-- ---------------------------------------------------------------------------
select is((select sum(sales_count)::int from public.report_sales_summary(:'org', :'today', :'today')), 3,
  'report counts completed sales (voided sale excluded)');
select ok((select bool_and(cost_paisa is not null) from public.report_sales_summary(:'org', :'today', :'today')),
  'branch managers see cost for their branches (security model P-45)');
select tests.authenticate_as(:'owner');
select ok((select bool_and(gross_profit_paisa is not null) from public.report_sales_summary(:'org', :'today', :'today')),
  'owners see gross profit');

select * from finish();
rollback;
