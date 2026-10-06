-- Functional edge cases for create_sale / void_sale / process_sale_return.
--
-- One organization ("Edge Pharmacy", single branch) with an owner (aal2), a manager (aal2) and two
-- salesmen (aal1). Every section states its expected figures; all money is in paisa, all
-- percentages in basis points, all dates relative to app.business_date(org) (never current_date).
-- Assertions are made as the superuser (tests.clear_authentication) so they see every column; the
-- RPCs are always called as the role under test.
--
-- Time-based rules (void window, return window) are exercised by back-dating the sale row with
-- session_replication_role = replica (superuser fixture only; it bypasses the immutability trigger
-- for that one UPDATE). Everything is rolled back at the end.
begin;
select plan(153);

-- ---------------------------------------------------------------------------------------------
-- Test-local helpers (rolled back with the transaction)
-- ---------------------------------------------------------------------------------------------
-- Runs a statement and returns 'ok', or the app.fail() code (DETAIL) of the error it raised, or
-- 'SQLSTATE: message' for any other error. Runs in a subtransaction, so a failure leaves no trace.
create function tests.t120_err(p_sql text) returns text language plpgsql as $$
declare
  v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  return coalesce(nullif(v_detail, ''), sqlstate || ': ' || sqlerrm);
end;
$$;

-- Attempts a sale and returns 'ok' or the error code (see t120_err).
create function tests.t120_sale_err(
  p_branch uuid, p_items jsonb, p_payments jsonb, p_customer uuid default null, p_card text default null,
  p_invoice_discount bigint default 0, p_prescription jsonb default null, p_request uuid default gen_random_uuid()
) returns text language plpgsql as $$
begin
  return tests.t120_err(format(
    'select public.create_sale(%L, %L::jsonb, %L::jsonb, %L, %L, %L, %L, %L::jsonb)',
    p_branch, p_items, p_payments, p_request, p_customer, p_card, p_invoice_discount, p_prescription));
end;
$$;

create function tests.t120_line(p_medicine uuid, p_quantity integer, p_discount_bp integer default 0)
returns jsonb language sql immutable as $$
  select jsonb_build_object('medicine_id', p_medicine, 'quantity', p_quantity, 'discount_bp', p_discount_bp)
$$;

create function tests.t120_pay(p_method text, p_amount bigint)
returns jsonb language sql immutable as $$
  select jsonb_build_object('method', p_method, 'amount_paisa', p_amount)
$$;

create function tests.t120_rline(p_sale_item uuid, p_quantity integer)
returns jsonb language sql immutable as $$
  select jsonb_build_object('sale_item_id', p_sale_item, 'quantity', p_quantity)
$$;

create function tests.t120_rx(p_date date, p_reg_no text default 'BMDC-A-12345', p_doctor text default 'Dr. Karim')
returns jsonb language sql immutable as $$
  select jsonb_build_object('patient_name', 'Rahima Begum', 'patient_age', 45, 'doctor_name', p_doctor,
                            'doctor_reg_no', p_reg_no, 'prescription_date', p_date)
$$;

grant execute on function tests.t120_err(text),
  tests.t120_sale_err(uuid, jsonb, jsonb, uuid, text, bigint, jsonb, uuid),
  tests.t120_line(uuid, integer, integer), tests.t120_pay(text, bigint), tests.t120_rline(uuid, integer),
  tests.t120_rx(date, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Fixture: organization, people, catalog, stock, loyalty plans
-- ---------------------------------------------------------------------------------------------
select tests.create_user('owner@edge.test') as owner \gset
select tests.create_user('manager@edge.test') as manager \gset
select tests.create_user('sales1@edge.test') as sales1 \gset
select tests.create_user('sales2@edge.test') as sales2 \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Edge Pharmacy', 'Mohammadpur', 'EDG') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@edge.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales1@edge.test', 'salesman', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales2@edge.test', 'salesman', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Ace', 'tablet', '500 mg', 'tablet') returning id as ace \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Seclo', 'capsule', '20 mg', 'capsule') returning id as seclo \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label, loyalty_eligible)
  values (:'org', 'Insulin', 'injection', '100 IU', 'vial', false) returning id as insulin \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Fexo', 'tablet', '120 mg', 'tablet') returning id as fexo \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label, schedule)
  values (:'org', 'Azith', 'tablet', '500 mg', 'tablet', 'rx') returning id as azith \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label, schedule)
  values (:'org', 'Diazepam', 'tablet', '5 mg', 'tablet', 'controlled') returning id as diaz \gset

-- Loyalty plans (snapshotted at enrolment):
--   3-month: 10% discount on eligible items, capped at 100 paisa per invoice, no points.
--   6-month: no discount; 10 points per 100 taka; 1 point = 50 paisa; at least 10 points per redemption.
update public.loyalty_plans
   set is_active = true, fee_paisa = 0, discount_bp = 1000, max_discount_per_invoice_paisa = 100,
       points_per_100_taka = 0, point_value_paisa = 0, min_redeem_points = 0
 where organization_id = :'org' and duration_months = 3
 returning id as plan_cap \gset
update public.loyalty_plans
   set is_active = true, fee_paisa = 0, discount_bp = 0, max_discount_per_invoice_paisa = null,
       points_per_100_taka = 10, point_value_paisa = 50, min_redeem_points = 10
 where organization_id = :'org' and duration_months = 6
 returning id as plan_pts \gset

select tests.authenticate_as(:'manager');
select public.add_opening_stock(:'branch', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NP-1', 'expiry_date', :'today'::date + 400,
    'quantity', 5000, 'cost_paisa', 600, 'mrp_paisa', 1000, 'sale_price_paisa', 1000),
  jsonb_build_object('medicine_id', :'ace', 'batch_no', 'AC-1', 'expiry_date', :'today'::date + 400,
    'quantity', 1000, 'cost_paisa', 200, 'mrp_paisa', 333, 'sale_price_paisa', 333),
  jsonb_build_object('medicine_id', :'seclo', 'batch_no', 'SC-1', 'expiry_date', :'today'::date + 400,
    'quantity', 1000, 'cost_paisa', 500, 'mrp_paisa', 777, 'sale_price_paisa', 777),
  jsonb_build_object('medicine_id', :'insulin', 'batch_no', 'IN-1', 'expiry_date', :'today'::date + 400,
    'quantity', 100, 'cost_paisa', 400, 'mrp_paisa', 500, 'sale_price_paisa', 500),
  jsonb_build_object('medicine_id', :'azith', 'batch_no', 'AZ-1', 'expiry_date', :'today'::date + 400,
    'quantity', 100, 'cost_paisa', 1500, 'mrp_paisa', 2000, 'sale_price_paisa', 2000),
  jsonb_build_object('medicine_id', :'diaz', 'batch_no', 'DZ-1', 'expiry_date', :'today'::date + 400,
    'quantity', 100, 'cost_paisa', 1000, 'mrp_paisa', 1500, 'sale_price_paisa', 1500),
  -- Fexo lots, each at a different price. E0/E1 are back-dated to expired / expiring today below.
  jsonb_build_object('medicine_id', :'fexo', 'batch_no', 'FX-E0', 'expiry_date', :'today'::date + 5,
    'quantity', 50, 'cost_paisa', 50, 'mrp_paisa', 90, 'sale_price_paisa', 90),
  jsonb_build_object('medicine_id', :'fexo', 'batch_no', 'FX-E1', 'expiry_date', :'today'::date + 6,
    'quantity', 50, 'cost_paisa', 50, 'mrp_paisa', 95, 'sale_price_paisa', 95),
  jsonb_build_object('medicine_id', :'fexo', 'batch_no', 'FX-N', 'expiry_date', :'today'::date + 10,
    'quantity', 5, 'cost_paisa', 60, 'mrp_paisa', 100, 'sale_price_paisa', 100),
  jsonb_build_object('medicine_id', :'fexo', 'batch_no', 'FX-F', 'expiry_date', :'today'::date + 200,
    'quantity', 100, 'cost_paisa', 70, 'mrp_paisa', 120, 'sale_price_paisa', 120),
  jsonb_build_object('medicine_id', :'fexo', 'batch_no', 'FX-G', 'expiry_date', :'today'::date + 300,
    'quantity', 100, 'cost_paisa', 80, 'mrp_paisa', 130, 'sale_price_paisa', 130)
), gen_random_uuid());

select tests.clear_authentication();
select id as napa_b from public.batches where medicine_id = :'napa' \gset
select id as diaz_b from public.batches where medicine_id = :'diaz' \gset
select id as ace_b from public.batches where medicine_id = :'ace' \gset
select id as fx_e0 from public.batches where medicine_id = :'fexo' and batch_no = 'FX-E0' \gset
select id as fx_e1 from public.batches where medicine_id = :'fexo' and batch_no = 'FX-E1' \gset
select id as fx_n from public.batches where medicine_id = :'fexo' and batch_no = 'FX-N' \gset
select id as fx_f from public.batches where medicine_id = :'fexo' and batch_no = 'FX-F' \gset
select id as fx_g from public.batches where medicine_id = :'fexo' and batch_no = 'FX-G' \gset
-- Fixture: the lots age (expiry is not a guarded column). E0 expired yesterday, E1 expires today.
update public.batches set expiry_date = :'today'::date - 1 where id = :'fx_e0';
update public.batches set expiry_date = :'today'::date where id = :'fx_e1';

-- Customers (phones in E.164).
insert into public.customers (organization_id, name, phone) values (:'org', 'Cap Customer', '+8801711000001')
  returning id as cust_cap \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Points Customer', '+8801711000002')
  returning id as cust_pts \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Credit Customer', '+8801711000003')
  returning id as cust_credit \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Void Customer', '+8801711000004')
  returning id as cust_void \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Refund Customer', '+8801711000005')
  returning id as cust_refund \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Rounding Customer', '+8801711000006')
  returning id as cust_round \gset

select tests.authenticate_as(:'manager');
select public.set_customer_credit_limit(:'cust_void', 50000);
select public.set_customer_credit_limit(:'cust_refund', 50000);
select public.set_customer_credit_limit(:'cust_round', 10000);

select tests.authenticate_as(:'sales1', 'aal1');
select public.enroll_loyalty(:'cust_cap', :'plan_cap', :'branch', gen_random_uuid()) ->> 'card_no' as card_cap \gset
select r ->> 'card_no' as card_pts, r ->> 'membership_id' as ms_pts
  from (select public.enroll_loyalty(:'cust_pts', :'plan_pts', :'branch', gen_random_uuid()) r) q \gset
select public.enroll_loyalty(:'cust_void', :'plan_pts', :'branch', gen_random_uuid()) ->> 'card_no' as card_void \gset
select public.enroll_loyalty(:'cust_refund', :'plan_pts', :'branch', gen_random_uuid()) ->> 'card_no' as card_refund \gset

-- =============================================================================================
-- 1. FEFO, near_expiry_block_days and expired lots (14 assertions)
-- Fexo lots: E0 expired (90), E1 expires today (95), N today+10 (100, 5 units), F today+200 (120),
-- G today+300 (130).
-- =============================================================================================
select tests.clear_authentication();
update public.organization_settings set near_expiry_block_days = 10 where organization_id = :'org';

-- Block window 10 days: N (expires exactly today+10) is blocked as well; FEFO starts at F.
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'fexo', 3)),
  jsonb_build_array(tests.t120_pay('cash', 360)), gen_random_uuid()) ->> 'sale_id' as fx1 \gset
-- Sellable with the block: F 97 + G 100 = 197.
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'fexo', 198)), '[]'::jsonb),
  'insufficient_stock', 'near-expiry block: expired, expiring-today and blocked lots do not count as sellable stock');

select tests.clear_authentication();
select is((select string_agg(b.batch_no || ':' || sib.quantity || '@' || sib.unit_price_paisa, ',')
             from public.sale_item_batches sib join public.batches b on b.id = sib.batch_id
             join public.sale_items si on si.id = sib.sale_item_id where si.sale_id = :'fx1'),
  'FX-F:3@120', 'near-expiry block (10 days): a lot expiring exactly on today+10 is skipped; FEFO takes the next lot');
select is((select gross_paisa from public.sales where id = :'fx1'), 360::bigint,
  'near-expiry block: the line is priced from the lot actually sold (3 x 120)');

update public.organization_settings set near_expiry_block_days = 9 where organization_id = :'org';
select tests.authenticate_as(:'sales1', 'aal1');
-- Block window 9 days: N is sellable again. 8 units = N 5 x 100 + F 3 x 120 = 860.
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'fexo', 8)),
  jsonb_build_array(tests.t120_pay('cash', 1000)), gen_random_uuid()) as fx2_json \gset
select tests.clear_authentication();
select (:'fx2_json'::jsonb ->> 'sale_id') as fx2 \gset
select is((select string_agg(b.batch_no || ':' || sib.quantity || '@' || sib.unit_price_paisa, ',' order by b.expiry_date)
             from public.sale_item_batches sib join public.batches b on b.id = sib.batch_id
             join public.sale_items si on si.id = sib.sale_item_id where si.sale_id = :'fx2'),
  'FX-N:5@100,FX-F:3@120', 'multi-batch FEFO: earliest sellable lot first, then the next, each at its own price');
select is((select gross_paisa from public.sale_items where sale_id = :'fx2'), 860::bigint,
  'multi-batch FEFO: line gross = 5 x 100 + 3 x 120 = 860');
select is((:'fx2_json'::jsonb ->> 'change_paisa')::bigint, 140::bigint, 'multi-batch FEFO: change on 1000 paid = 140');

-- Spanning F and G: F has 94 left. 100 units = 94 x 120 + 6 x 130 = 11280 + 780 = 12060.
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'fexo', 100)),
  jsonb_build_array(tests.t120_pay('cash', 12060)), gen_random_uuid()) ->> 'sale_id' as fx3 \gset
select tests.clear_authentication();
select is((select string_agg(b.batch_no || ':' || sib.quantity || '@' || sib.unit_price_paisa, ',' order by b.expiry_date)
             from public.sale_item_batches sib join public.batches b on b.id = sib.batch_id
             join public.sale_items si on si.id = sib.sale_item_id where si.sale_id = :'fx3'),
  'FX-F:94@120,FX-G:6@130', 'multi-batch FEFO: a lot is drained completely before the next one is opened');
select is((select gross_paisa from public.sales where id = :'fx3'), 12060::bigint,
  'multi-batch FEFO: invoice gross = sum of quantity x unit price over the lots');
select is((select quantity_on_hand from public.batches where id = :'fx_f'), 0, 'lot F is depleted');
select is((select quantity_on_hand from public.batches where id = :'fx_g'), 94, 'lot G has 94 left');

-- Only G (94) is sellable now; E0 (expired) and E1 (expires today) hold 100 units that must never be sold.
update public.organization_settings set near_expiry_block_days = 0 where organization_id = :'org';
select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'fexo', 95)), '[]'::jsonb),
  'insufficient_stock', 'expired lots (yesterday) and lots expiring today are never sold, even with no block window');
select tests.clear_authentication();
select is((select quantity_on_hand from public.batches where id = :'fx_e0'), 50, 'expired lot E0 untouched');
select is((select quantity_on_hand from public.batches where id = :'fx_e1'), 50, 'lot E1 expiring today untouched');
select is((select count(*)::int from public.sale_item_batches where batch_id in (:'fx_e0', :'fx_e1')), 0,
  'no sale line was ever allocated to an expired lot');

-- =============================================================================================
-- 2. Line and invoice discount limits per role (salesman 5%, manager 15%, owner unlimited) (17)
-- Napa sells at 1000 paisa; 10 units = 10000 gross.
-- =============================================================================================
select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 500)), '[]'::jsonb),
  'customer_required', 'salesman: 5% line discount is within the limit (fails only later, on the unpaid amount)');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 500)),
  jsonb_build_array(tests.t120_pay('cash', 9500)), gen_random_uuid()) ->> 'sale_id' as d1 \gset
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 501)),
  jsonb_build_array(tests.t120_pay('cash', 9499))), 'discount_limit', 'salesman: 5.01% line discount is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10)),
  jsonb_build_array(tests.t120_pay('cash', 9499)), null, null, 501), 'discount_limit',
  'salesman: invoice discount of 5.01% of gross is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10)),
  jsonb_build_array(tests.t120_pay('cash', 9500)), null, null, 500), 'ok',
  'salesman: invoice discount of exactly 5% is accepted');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 300)),
  jsonb_build_array(tests.t120_pay('cash', 9499)), null, null, 201), 'discount_limit',
  'salesman: line 3% + invoice 2.01% (total 5.01%) is refused - the limit covers the combined discount');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 300)),
  jsonb_build_array(tests.t120_pay('cash', 9500)), null, null, 200), 'ok',
  'salesman: line 3% + invoice 2% (total 5%) is accepted');
-- Every line at exactly the salesman limit (5%), no invoice discount: Ace 333 -> 16.65 -> 17,
-- Seclo 777 -> 38.85 -> 39, Fexo (lot G) 130 -> 6.5 -> 7; lines total 63 while 5% of the gross 1240 is 62.0.
-- Each line is within the limit, so the sale must be accepted (per-line half-up rounding must not
-- turn a permitted discount into a limit breach).
select is(tests.t120_sale_err(:'branch',
  jsonb_build_array(tests.t120_line(:'ace', 1, 500), tests.t120_line(:'seclo', 1, 500), tests.t120_line(:'fexo', 1, 500)),
  jsonb_build_array(tests.t120_pay('cash', 1177))), 'ok',
  'salesman: several lines each at exactly 5% are accepted despite per-line rounding');

select tests.authenticate_as(:'manager');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 1500)),
  jsonb_build_array(tests.t120_pay('cash', 8500))), 'ok', 'manager: 15% line discount is accepted');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 1501)),
  jsonb_build_array(tests.t120_pay('cash', 8499))), 'discount_limit', 'manager: 15.01% line discount is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10)),
  jsonb_build_array(tests.t120_pay('cash', 8499)), null, null, 1501), 'discount_limit',
  'manager: invoice discount of 15.01% is refused');

select tests.authenticate_as(:'owner');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 10000)), '[]'::jsonb,
  gen_random_uuid()) as d_owner \gset
select is((:'d_owner'::jsonb ->> 'total_paisa')::bigint, 0::bigint, 'owner: a 100% line discount is accepted (total 0)');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 5000)), '[]'::jsonb,
  null, null, 5000), 'ok', 'owner: 50% line + invoice discount of the remaining 5000 is accepted');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 5000)), '[]'::jsonb,
  null, null, 5001), 'invalid_discount', 'owner: invoice discount larger than the amount after line discounts is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10)),
  jsonb_build_array(tests.t120_pay('cash', 10000)), null, null, -1), 'invalid_discount',
  'a negative invoice discount is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10, 10001)), '[]'::jsonb),
  'invalid_discount', 'a line discount above 100% is refused');

-- Invoice-level discount spread exactly (manager): Napa 1000 + Ace 333 + Seclo 777 = 2110, invoice
-- discount 101. Largest remainder: 47.87 / 15.94 / 37.19 -> 47+15+37 = 99, +1 to Ace, +1 to Napa.
select tests.authenticate_as(:'manager');
select public.create_sale(:'branch',
  jsonb_build_array(tests.t120_line(:'napa', 1), tests.t120_line(:'ace', 1), tests.t120_line(:'seclo', 1)),
  jsonb_build_array(tests.t120_pay('cash', 2009)), gen_random_uuid(), null, null, 101) ->> 'sale_id' as d_spread \gset
select tests.clear_authentication();
select is((select sum(invoice_discount_paisa)::bigint from public.sale_items where sale_id = :'d_spread'),
  (select invoice_discount_paisa from public.sales where id = :'d_spread'),
  'invoice discount: the line shares add up exactly to the header (101)');
select is((select string_agg(m.brand_name || '=' || si.invoice_discount_paisa, ',' order by m.brand_name)
             from public.sale_items si join public.medicines m on m.id = si.medicine_id where si.sale_id = :'d_spread'),
  'Ace=16,Napa=48,Seclo=37', 'invoice discount: proportional split with largest-remainder rounding');

-- =============================================================================================
-- 3. Loyalty discount cap per invoice (5 assertions)
-- Card on the capped plan: 10% on eligible items, max 100 paisa per invoice.
-- Napa 3 (3000) -> 300, Ace 1 (333) -> 33, Seclo 1 (777) -> 78, Insulin 1 (500, not eligible) -> 0.
-- Uncapped 411 > 100: 100 x (300, 33, 78)/411 = 72.99 / 8.03 / 18.98 -> 72+8+18 = 98, +1 Napa, +1 Seclo.
-- =============================================================================================
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch',
  jsonb_build_array(tests.t120_line(:'napa', 3), tests.t120_line(:'ace', 1), tests.t120_line(:'seclo', 1),
                    tests.t120_line(:'insulin', 1)),
  jsonb_build_array(tests.t120_pay('cash', 5000)), gen_random_uuid(), null, :'card_cap') as cap_json \gset
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'ace', 1)),
  jsonb_build_array(tests.t120_pay('cash', 300)), gen_random_uuid(), null, :'card_cap') ->> 'sale_id' as cap_small \gset
select tests.clear_authentication();
select (:'cap_json'::jsonb ->> 'sale_id') as cap_sale \gset
select is((select loyalty_discount_paisa from public.sales where id = :'cap_sale'), 100::bigint,
  'loyalty cap: the invoice loyalty discount is capped at max_discount_per_invoice_paisa');
select is((select sum(loyalty_discount_paisa)::bigint from public.sale_items where sale_id = :'cap_sale'), 100::bigint,
  'loyalty cap: the line loyalty discounts add up exactly to the cap');
select is((select string_agg(m.brand_name || '=' || si.loyalty_discount_paisa, ',' order by m.brand_name)
             from public.sale_items si join public.medicines m on m.id = si.medicine_id where si.sale_id = :'cap_sale'),
  'Ace=8,Insulin=0,Napa=73,Seclo=19', 'loyalty cap: proportional allocation; the excluded item gets no discount');
select is((:'cap_json'::jsonb ->> 'change_paisa')::bigint, 490::bigint,
  'loyalty cap: total 4610 - 100 = 4510, change on 5000 = 490');
select is((select loyalty_discount_paisa from public.sales where id = :'cap_small'), 33::bigint,
  'loyalty cap: an invoice below the cap gets the full 10% (33 on 333)');

-- =============================================================================================
-- 4. nearest_taka rounding, change, due, VAT-inclusive figure (12 assertions)
-- =============================================================================================
update public.organization_settings set cash_rounding = 'nearest_taka', vat_bp = 750 where organization_id = :'org';

-- Ace 333 + Seclo 777 = 1110 -> rounded to 1100 (-10). VAT inside 1100 at 7.5% = 1100 x 750/10750 = 76.74 -> 77.
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'ace', 1), tests.t120_line(:'seclo', 1)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), gen_random_uuid()) as r1_json \gset
select tests.clear_authentication();
select (:'r1_json'::jsonb ->> 'sale_id') as r1 \gset
select is((select row(net_paisa, rounding_paisa, total_paisa, paid_paisa, change_paisa, due_paisa)::text
             from public.sales where id = :'r1'),
  '(1110,-10,1100,2000,900,0)', 'nearest_taka: 1110 rounds down to 1100; change 900 on 2000');
select is((select vat_included_paisa from public.sales where id = :'r1'), 77::bigint,
  'VAT-inclusive: 7.5% VAT contained in 1100 is 77 (not added on top)');
select is((select string_agg(m.brand_name || '=' || si.rounding_paisa, ',' order by m.brand_name)
             from public.sale_items si join public.medicines m on m.id = si.medicine_id where si.sale_id = :'r1'),
  'Ace=-3,Seclo=-7', 'nearest_taka: the rounding is spread over the lines in proportion to their net');

-- Napa 1 with 5% line discount = 950 -> 9.5 taka rounds half up to 1000 (+50).
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 1, 500)),
  jsonb_build_array(tests.t120_pay('cash', 1000)), gen_random_uuid()) ->> 'sale_id' as r2 \gset
select tests.clear_authentication();
select is((select row(net_paisa, rounding_paisa, total_paisa, change_paisa)::text from public.sales where id = :'r2'),
  '(950,50,1000,0)', 'nearest_taka: exactly half a taka (950) rounds up to 1000');
select is((select vat_included_paisa from public.sales where id = :'r2'), 70::bigint,
  'VAT-inclusive: 1000 x 750 / 10750 = 69.77 -> 70');

-- Ace 2 + Seclo 1 = 666 + 777 = 1443 -> 1400 (-43); cash 1000 leaves a due of 400 on the customer.
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'ace', 2), tests.t120_line(:'seclo', 1)),
  jsonb_build_array(tests.t120_pay('cash', 1000)), gen_random_uuid(), :'cust_round') as r3_json \gset
select tests.clear_authentication();
select (:'r3_json'::jsonb ->> 'sale_id') as r3 \gset
select is((select row(net_paisa, rounding_paisa, total_paisa, paid_paisa, change_paisa, due_paisa)::text
             from public.sales where id = :'r3'),
  '(1443,-43,1400,1000,0,400)', 'nearest_taka with due: the due is computed on the rounded total (1400 - 1000)');
select is(app.customer_balance(:'cust_round'), 400::bigint, 'nearest_taka with due: the customer owes 400');
select is((select sum(net_paisa + rounding_paisa)::bigint from public.sale_items where sale_id = :'r3'), 1400::bigint,
  'nearest_taka: lines net + rounding share add up to the invoice total');
select is((select paid_paisa - change_paisa + due_paisa - total_paisa from public.sales where id = :'r3'), 0::bigint,
  'settlement identity: paid - change + due = total');

-- Full return of the rounded sale refunds exactly what was charged (1400), all against the due first.
select tests.authenticate_as(:'manager');
select public.process_sale_return(:'r3', (select jsonb_agg(tests.t120_rline(id, quantity)) from public.sale_items
  where sale_id = :'r3'), 'customer changed mind', gen_random_uuid()) as r3_ret \gset
select is((:'r3_ret'::jsonb ->> 'refund_paisa')::bigint, 1400::bigint,
  'nearest_taka: a full return refunds the rounded total, not the pre-rounding net');
select is(row((:'r3_ret'::jsonb ->> 'due_reduction_paisa')::bigint, (:'r3_ret'::jsonb ->> 'cash_refund_paisa')::bigint)::text,
  '(400,1000)', 'nearest_taka: return settles the 400 due first, then 1000 in cash');
select tests.clear_authentication();
select is(app.customer_balance(:'cust_round'), 0::bigint, 'nearest_taka: the customer owes nothing after the full return');

update public.organization_settings set cash_rounding = 'none', vat_bp = 0 where organization_id = :'org';

-- =============================================================================================
-- 5. Split payments; change only from cash (8 assertions)
-- Napa 5 = 5000.
-- =============================================================================================
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)),
  jsonb_build_array(tests.t120_pay('bkash', 3000), tests.t120_pay('cash', 2500)), gen_random_uuid()) as sp1_json \gset
select tests.clear_authentication();
select (:'sp1_json'::jsonb ->> 'sale_id') as sp1 \gset
select is((select row(total_paisa, paid_paisa, change_paisa, due_paisa)::text from public.sales where id = :'sp1'),
  '(5000,5500,500,0)', 'split cash + bKash: 500 change given back');
select is((select string_agg(method::text || '=' || amount_paisa, ',' order by method::text) from public.sale_payments
            where sale_id = :'sp1'), 'bkash=3000,cash=2500', 'split payment: both payment lines are recorded as tendered');
select ok((select change_paisa <= (select sum(amount_paisa) from public.sale_payments where sale_id = :'sp1' and method = 'cash')
             from public.sales where id = :'sp1'), 'split payment: change never exceeds the cash tendered');

select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)),
  jsonb_build_array(tests.t120_pay('bkash', 5500))), 'overpayment', 'bKash larger than the total is refused (no change from bKash)');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)),
  jsonb_build_array(tests.t120_pay('bkash', 4000), tests.t120_pay('nagad', 1500))), 'overpayment',
  'bKash + Nagad together larger than the total is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)),
  jsonb_build_array(tests.t120_pay('bkash', 5001), tests.t120_pay('cash', 100))), 'overpayment',
  'non-cash above the total is refused even when cash is also tendered');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)),
  jsonb_build_array(tests.t120_pay('bkash', 0))), 'invalid_payment', 'a zero payment line is refused');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)),
  jsonb_build_array(tests.t120_pay('card', 5000), tests.t120_pay('cash', 1000)), gen_random_uuid()) as sp2_json \gset
select is((:'sp2_json'::jsonb ->> 'change_paisa')::bigint, 1000::bigint,
  'card covers the total exactly; the whole cash tendered is returned as change');

-- =============================================================================================
-- 6. Loyalty points redemption (14 assertions)
-- Points plan: 10 points per 100 taka, 1 point = 50 paisa, minimum 10 points per redemption.
-- =============================================================================================
select tests.authenticate_as(:'sales1', 'aal1');
-- Earn: Napa 100 = 100000 paisa = 1000 taka -> 100 points.
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 100)),
  jsonb_build_array(tests.t120_pay('cash', 100000)), gen_random_uuid(), null, :'card_pts') as pe_json \gset
select is((:'pe_json'::jsonb ->> 'points_earned')::int, 100, 'points: 1000 taka on eligible items earns 100 points');
select is((select points_balance from public.lookup_loyalty(:'org', :'card_pts')), 100, 'points: balance is 100');

select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 30)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 775), tests.t120_pay('cash', 29225)), null, :'card_pts'),
  'invalid_payment', 'points: a points amount that is not a multiple of point_value_paisa (50) is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 30)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 450), tests.t120_pay('cash', 29550)), null, :'card_pts'),
  'invalid_payment', 'points: redeeming 9 points (below min_redeem_points = 10) is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 30)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 5050), tests.t120_pay('cash', 24950)), null, :'card_pts'),
  'insufficient_points', 'points: redeeming 101 points with a balance of 100 is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 30)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 1000), tests.t120_pay('cash', 29000))),
  'invalid_payment', 'points: paying with points without a loyalty card is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 1)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 1500)), null, :'card_pts'),
  'overpayment', 'points: points worth more than the total are refused (no change from points)');

-- Redeem 40 points (2000) on Napa 30 = 30000; points earned only on 30000 - 2000 = 28000 -> 280 taka -> 20 points.
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 30)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 2000), tests.t120_pay('cash', 28000)), gen_random_uuid(),
  null, :'card_pts') as pr_json \gset
select tests.clear_authentication();
select (:'pr_json'::jsonb ->> 'sale_id') as pr \gset
select is((select row(points_redeemed, points_redeemed_value_paisa, points_earned)::text from public.sales where id = :'pr'),
  '(40,2000,20)', 'points: 40 points redeemed (2000 paisa); 20 points earned on the money part only, not 30');
select is((select sum(points_earned)::int from public.sale_items where sale_id = :'pr'), 20,
  'points: earned points are allocated to the lines exactly');
select is((select string_agg(entry_type || ' ' || points, ', ' order by id) from public.loyalty_point_ledger where sale_id = :'pr'),
  'redeem -40, earn 20', 'points: ledger records the redemption and the earning');
select is(app.loyalty_points_balance((select id from public.loyalty_cards where card_no = :'card_pts')), 80,
  'points: balance 100 - 40 + 20 = 80');

-- Inactive membership: once cancelled, the card cannot be used, for discount or points.
select tests.authenticate_as(:'manager');
select public.cancel_loyalty_membership(:'ms_pts', 'customer asked to cancel');
select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 30)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 1000), tests.t120_pay('cash', 29000)), null, :'card_pts'),
  'loyalty_inactive', 'points: a card whose membership was cancelled cannot redeem points');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 1)),
  jsonb_build_array(tests.t120_pay('cash', 1000)), null, :'card_pts'),
  'loyalty_inactive', 'points: a card whose membership was cancelled cannot be used on a sale at all');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 1)),
  jsonb_build_array(tests.t120_pay('cash', 1000)), :'cust_cap', :'card_pts'),
  'loyalty_inactive', 'points: an inactive card is refused before any customer check');

-- =============================================================================================
-- 7. Credit (due) sales (8 assertions)
-- =============================================================================================
select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)),
  jsonb_build_array(tests.t120_pay('cash', 3000))), 'customer_required', 'credit: a due without a customer is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 1)), '[]'::jsonb, :'cust_credit'),
  'credit_limit', 'credit: a customer with credit limit 0 cannot buy on credit');

select tests.authenticate_as(:'manager');
select public.set_customer_credit_limit(:'cust_credit', 10000);
select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 6)), '[]'::jsonb, :'cust_credit'),
  'ok', 'credit: a due of 6000 within a limit of 10000 is accepted');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)), '[]'::jsonb, :'cust_credit'),
  'credit_limit', 'credit: existing due 6000 + new due 5000 > 10000 is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 5)),
  jsonb_build_array(tests.t120_pay('cash', 1000)), :'cust_credit'),
  'ok', 'credit: existing due 6000 + new due 4000 = exactly the limit is accepted');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 1)),
  jsonb_build_array(tests.t120_pay('cash', 999)), :'cust_credit'),
  'credit_limit', 'credit: one more paisa of due over the limit is refused');
select tests.clear_authentication();
select is(app.customer_balance(:'cust_credit'), 10000::bigint, 'credit: the customer owes exactly the limit');
select is((select count(*)::int from public.customer_ledger_entries where customer_id = :'cust_credit' and entry_type = 'credit_sale'),
  2, 'credit: one credit_sale ledger entry per accepted credit sale');

-- =============================================================================================
-- 8. Prescriptions: Rx with require_prescription_for_rx off / on; date window; controlled (12)
-- =============================================================================================
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'azith', 1)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), gen_random_uuid()) ->> 'sale_id' as rx_off \gset
select tests.clear_authentication();
select is((select prescription_id from public.sales where id = :'rx_off'), null,
  'Rx (require_prescription_for_rx off): sold without a prescription');
update public.organization_settings set require_prescription_for_rx = true where organization_id = :'org';

select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'azith', 1)),
  jsonb_build_array(tests.t120_pay('cash', 2000))), 'prescription_required',
  'Rx (require_prescription_for_rx on): refused without a prescription');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'azith', 1)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), null, null, 0, tests.t120_rx(:'today'::date, null, ' ')),
  'prescription_required', 'Rx (on): a prescription without a doctor name is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'azith', 1)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), null, null, 0, tests.t120_rx(:'today'::date - 181)),
  'invalid_prescription', 'Rx (on): a prescription dated 181 days ago is refused');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'azith', 1)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), null, null, 0, tests.t120_rx(:'today'::date + 1)),
  'invalid_prescription', 'Rx (on): a prescription dated tomorrow is refused');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'azith', 1)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), gen_random_uuid(), null, null, 0,
  tests.t120_rx(:'today'::date - 180, null)) ->> 'sale_id' as rx_on \gset
select tests.clear_authentication();
select is((select p.prescription_date from public.sales s join public.prescriptions p on p.id = s.prescription_id
            where s.id = :'rx_on'), :'today'::date - 180,
  'Rx (on): a prescription dated exactly 180 days ago is accepted and linked to the sale');
update public.organization_settings set require_prescription_for_rx = false where organization_id = :'org';

-- Controlled medicines always need a prescription with the doctor's registration number.
select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'diaz', 2)),
  jsonb_build_array(tests.t120_pay('cash', 3000))), 'prescription_required',
  'controlled: refused without a prescription even when the Rx setting is off');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'diaz', 2)),
  jsonb_build_array(tests.t120_pay('cash', 3000)), null, null, 0, tests.t120_rx(:'today'::date, null)),
  'prescription_required', 'controlled: refused without the doctor registration number');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'diaz', 2)),
  jsonb_build_array(tests.t120_pay('cash', 3000)), null, null, 0, tests.t120_rx(:'today'::date - 181)),
  'invalid_prescription', 'controlled: a prescription older than 180 days is refused');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'diaz', 2)),
  jsonb_build_array(tests.t120_pay('cash', 3000)), gen_random_uuid(), null, null, 0,
  tests.t120_rx(:'today'::date - 3)) ->> 'sale_id' as cd1 \gset
select tests.clear_authentication();
select is((select string_agg(entry_type || ' ' || quantity || ' ' || doctor_reg_no, ',') from public.controlled_drug_register
            where sale_id = :'cd1'), 'sale -2 BMDC-A-12345', 'controlled: the sale writes one register row (-2, with reg no)');
select is((select r.prescription_id from public.controlled_drug_register r where r.sale_id = :'cd1'),
  (select s.prescription_id from public.sales s where s.id = :'cd1'), 'controlled: the register row points at the prescription');
select is((select count(*)::int from public.controlled_drug_register r join public.sales s on s.id = r.sale_id
            where s.organization_id = :'org' and r.medicine_id <> :'diaz'), 0,
  'controlled: no register rows for non-controlled medicines');

-- =============================================================================================
-- 9. Idempotency: request id replay and reuse (5 assertions)
-- =============================================================================================
select gen_random_uuid() as req \gset
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 2)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), :'req') as idem1 \gset
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 9)),
  jsonb_build_array(tests.t120_pay('cash', 9000)), :'req') as idem2 \gset
select is(:'idem2'::jsonb ->> 'sale_id', :'idem1'::jsonb ->> 'sale_id', 'replay by the same user returns the original sale');
select is((:'idem2'::jsonb ->> 'replayed')::boolean, true, 'replay is flagged as replayed');
select tests.authenticate_as(:'sales2', 'aal1');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 2)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), null, null, 0, null, :'req'),
  'request_id_conflict', 'the same request id used by another salesman is refused (request_id_conflict)');
select tests.authenticate_as(:'manager');
select is(tests.t120_sale_err(:'branch', jsonb_build_array(tests.t120_line(:'napa', 2)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), null, null, 0, null, :'req'),
  'request_id_conflict', 'the same request id used by a manager is refused too (no cross-user replay leak)');
select tests.clear_authentication();
select is((select count(*)::int from public.sales where organization_id = :'org' and client_request_id = :'req'), 1,
  'only one sale exists for the request id');

-- =============================================================================================
-- 10. void_sale (23 assertions)
-- =============================================================================================
-- 10a. Void window. Sales are back-dated (fixture) because now() is constant inside this transaction.
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 1)),
  jsonb_build_array(tests.t120_pay('cash', 1000)), gen_random_uuid()) ->> 'sale_id' as w1 \gset
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 1)),
  jsonb_build_array(tests.t120_pay('cash', 1000)), gen_random_uuid()) ->> 'sale_id' as w2 \gset
select is(tests.t120_err(format('select public.void_sale(%L, %L)', :'w1', 'wrong item')), 'forbidden',
  'void: a salesman cannot void (sales.void is owner/manager only)');
select tests.clear_authentication();
set local session_replication_role = replica;
update public.sales set created_at = created_at - interval '2 hours' where id = :'w1';
update public.sales set created_at = created_at - interval '1 minute' where id = :'w2';
set local session_replication_role = origin;
update public.organization_settings set void_window_hours = 1 where organization_id = :'org';

select tests.authenticate_as(:'manager');
select is(tests.t120_err(format('select public.void_sale(%L, %L)', :'w1', 'wrong item')), 'void_window_passed',
  'void: a 2-hour-old sale cannot be voided with a 1-hour void window');
select tests.clear_authentication();
update public.organization_settings set void_window_hours = 3 where organization_id = :'org';
select tests.authenticate_as(:'manager');
select is(tests.t120_err(format('select public.void_sale(%L, %L)', :'w1', 'wrong item')), 'ok',
  'void: the same sale can be voided with a 3-hour void window');
select tests.clear_authentication();
update public.organization_settings set void_window_hours = 0 where organization_id = :'org';
select tests.authenticate_as(:'manager');
select is(tests.t120_err(format('select public.void_sale(%L, %L)', :'w2', 'wrong item')), 'void_window_passed',
  'void: void_window_hours = 0 disables voids (a 1-minute-old sale is refused)');
select tests.clear_authentication();
update public.organization_settings set void_window_hours = 24 where organization_id = :'org';

-- 10b. Full void of a sale with points, cash, due and a controlled item.
-- Void customer first earns 100 points (Napa 100).
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 100)),
  jsonb_build_array(tests.t120_pay('cash', 100000)), gen_random_uuid(), null, :'card_void') ->> 'sale_id' as void_earn \gset
select tests.clear_authentication();
select quantity_on_hand as napa_q0 from public.batches where id = :'napa_b' \gset
select quantity_on_hand as diaz_q0 from public.batches where id = :'diaz_b' \gset
select app.customer_balance(:'cust_void') as void_bal0 \gset
select app.loyalty_points_balance(id) as void_pts0 from public.loyalty_cards where card_no = :'card_void' \gset

-- Napa 20 (20000) + Diazepam 2 (3000) = 23000. Paid: 10 points (500) + cash 10000; due 12500.
-- Points earned: eligible net 20000 - 500 = 19500 -> 195 taka -> 1 x 10 = 10 points (controlled excluded).
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 20), tests.t120_line(:'diaz', 2)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 500), tests.t120_pay('cash', 10000)), gen_random_uuid(),
  null, :'card_void', 0, tests.t120_rx(:'today'::date)) as v_json \gset
select tests.clear_authentication();
select (:'v_json'::jsonb ->> 'sale_id') as vs \gset
select is((select row(total_paisa, paid_paisa, due_paisa, points_redeemed, points_earned)::text from public.sales where id = :'vs'),
  '(23000,10500,12500,10,10)', 'void setup: total 23000, paid 10500 (500 in points), due 12500, 10 points earned');
select gross_paisa as dg0, voids_count as dv0, voided_paisa as dvp0, credit_sales_paisa as dc0, sales_count as dsc0
  from public.daily_branch_sales where branch_id = :'branch' and business_date = :'today' \gset

select tests.authenticate_as(:'manager');
select public.void_sale(:'vs', 'wrong patient', 'cash') as void_res \gset
select is(row((:'void_res'::jsonb ->> 'refund_paisa')::bigint, (:'void_res'::jsonb ->> 'due_reduction_paisa')::bigint,
              :'void_res'::jsonb ->> 'refund_method')::text,
  '(10000,12500,cash)', 'void: refunds the 10000 cash paid and writes off the 12500 due');
select is(row((:'void_res'::jsonb ->> 'points_returned')::int, (:'void_res'::jsonb ->> 'points_reversed')::int)::text,
  '(10,10)', 'void: 10 redeemed points returned, 10 earned points reversed');
select is(tests.t120_err(format('select public.void_sale(%L, %L)', :'vs', 'again')), 'already_voided',
  'void: a voided sale cannot be voided again');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'vs',
  (select jsonb_agg(tests.t120_rline(id, 1)) from public.sale_items where sale_id = :'vs')::text, 'return after void',
  gen_random_uuid())), 'sale_voided', 'void: a voided sale cannot be returned');
select tests.clear_authentication();
select is((select status::text from public.sales where id = :'vs'), 'voided', 'void: sale status is voided');
select is((select quantity_on_hand from public.batches where id = :'napa_b'), :'napa_q0'::int,
  'void: Napa stock is restored to its pre-sale level');
select is((select quantity_on_hand from public.batches where id = :'diaz_b'), :'diaz_q0'::int,
  'void: controlled stock is restored to its pre-sale level');
select is((select count(*)::int from public.inventory_movements where reference_id = :'vs' and movement_type = 'sale_void'), 2,
  'void: one sale_void movement per allocation');
select is(app.customer_balance(:'cust_void'), :'void_bal0'::bigint, 'void: the customer due is back to its pre-sale balance');
select is(app.loyalty_points_balance((select id from public.loyalty_cards where card_no = :'card_void')), :'void_pts0'::int,
  'void: the points balance is back to its pre-sale value');
select is((select coalesce(sum(points), 0)::int from public.loyalty_point_ledger where sale_id = :'vs'), 0,
  'void: the points ledger of the sale nets to zero');
select is((select string_agg(entry_type || ' ' || quantity, ',' order by id) from public.controlled_drug_register
            where sale_id = :'vs'), 'sale -2,void 2', 'void: the controlled register gets a +2 void row');
select is((select row(doctor_name, doctor_reg_no, prescription_id is not null)::text from public.controlled_drug_register
            where sale_id = :'vs' and entry_type = 'void'), '("Dr. Karim",BMDC-A-12345,t)',
  'void: the void register row carries the original prescription details');
select is((select gross_paisa from public.daily_branch_sales where branch_id = :'branch' and business_date = :'today'),
  :'dg0'::bigint - 23000, 'void: daily summary gross no longer includes the voided invoice');
select is((select credit_sales_paisa from public.daily_branch_sales where branch_id = :'branch' and business_date = :'today'),
  :'dc0'::bigint - 12500, 'void: daily summary credit sales drop by the voided due');
select is((select row(voids_count - :'dv0'::int, voided_paisa - :'dvp0'::bigint)::text from public.daily_branch_sales
            where branch_id = :'branch' and business_date = :'today'), '(1,23000)',
  'void: daily summary counts one void of 23000');
select is((select row(void_refund_paisa, void_refund_method::text, voided_by = :'manager'::uuid)::text from public.sales
            where id = :'vs'), '(10000,cash,t)', 'void: refund and voiding manager are recorded on the sale');
select is((select count(*)::int from audit.log where table_name = 'public.sales' and record_id = :'vs' and action = 'UPDATE'), 1,
  'void: the status change is audited');

-- =============================================================================================
-- 11. process_sale_return (29 assertions)
-- =============================================================================================
-- 11a. Multiple partial returns of one line add up exactly to the line amount.
-- Ace 7 x 333 = 2331, 2.5% line discount = 58.275 -> 58, net 2273 (2273/7 = 324.71...).
-- Returns 3, 2, 2: round(2273x3/7)=974; round(2273x5/7)=1624 -> 650; 2273 - 1624 = 649.
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'ace', 7, 250)),
  jsonb_build_array(tests.t120_pay('cash', 2273)), gen_random_uuid()) ->> 'sale_id' as pr7 \gset
select tests.clear_authentication();
select id as pr7_line from public.sale_items where sale_id = :'pr7' \gset
select quantity_on_hand as ace_q0 from public.batches where id = :'ace_b' \gset
select is((select net_paisa from public.sale_items where id = :'pr7_line'), 2273::bigint, 'partial returns setup: line net 2273');

select tests.authenticate_as(:'sales1', 'aal1');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'pr7',
  jsonb_build_array(tests.t120_rline(:'pr7_line', 1)), 'damaged strip', gen_random_uuid())), 'forbidden',
  'return: a salesman cannot process returns (sales.return is owner/manager only)');
select tests.authenticate_as(:'manager');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'pr7',
  jsonb_build_array(tests.t120_rline(:'pr7_line', 8)), 'too many', gen_random_uuid())), 'invalid_quantity',
  'return bounds: returning more than was sold is refused');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'pr7',
  jsonb_build_array(tests.t120_rline(:'pr7_line', 4), tests.t120_rline(:'pr7_line', 4)), 'split request',
  gen_random_uuid())), 'invalid_quantity', 'return bounds: duplicate entries for one line are summed (4 + 4 > 7)');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'pr7',
  jsonb_build_array(tests.t120_rline(:'pr7_line', 0)), 'zero qty', gen_random_uuid())), 'invalid_quantity',
  'return bounds: a zero quantity is refused');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'pr7',
  jsonb_build_array(tests.t120_rline(:'pr7_line', -1)), 'negative qty', gen_random_uuid())), 'invalid_quantity',
  'return bounds: a negative quantity is refused');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'pr7',
  jsonb_build_array(tests.t120_rline((select id from public.sale_items where sale_id = :'fx2'), 1)), 'other sale',
  gen_random_uuid())), 'invalid_item', 'return bounds: a line from another sale is refused');

select gen_random_uuid() as ret_req1 \gset
select public.process_sale_return(:'pr7', jsonb_build_array(tests.t120_rline(:'pr7_line', 3)), 'damaged strips',
  :'ret_req1') as ret1 \gset
select public.process_sale_return(:'pr7', jsonb_build_array(tests.t120_rline(:'pr7_line', 2)), 'damaged strips',
  gen_random_uuid()) as ret2 \gset
-- Idempotent replay of the first return (same request id, different payload): nothing new happens.
select public.process_sale_return(:'pr7', jsonb_build_array(tests.t120_rline(:'pr7_line', 2)), 'damaged strips',
  :'ret_req1') as ret1_replay \gset
select public.process_sale_return(:'pr7', jsonb_build_array(tests.t120_rline(:'pr7_line', 2)), 'damaged strips',
  gen_random_uuid()) as ret3 \gset
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'pr7',
  jsonb_build_array(tests.t120_rline(:'pr7_line', 1)), 'one more', gen_random_uuid())), 'invalid_quantity',
  'return bounds: nothing more can be returned once the whole line has been returned');
-- The first return's request id reused for a DIFFERENT sale must not silently replay the other
-- sale's return (the till would pay out that refund again while nothing is returned).
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'fx2',
  jsonb_build_array(tests.t120_rline((select id from public.sale_items where sale_id = :'fx2'), 1)), 'other sale',
  :'ret_req1')), 'request_id_conflict',
  'return idempotency: a request id already used for another sale''s return is refused (request_id_conflict)');
select tests.clear_authentication();
select is(row((:'ret1'::jsonb ->> 'refund_paisa')::bigint, (:'ret2'::jsonb ->> 'refund_paisa')::bigint,
              (:'ret3'::jsonb ->> 'refund_paisa')::bigint)::text, '(974,650,649)',
  'partial returns: cumulative proportional refunds 974 / 650 / 649');
select is((select sum(refund_paisa)::bigint from public.sale_returns where sale_id = :'pr7'), 2273::bigint,
  'partial returns: the refunds of all partial returns add up exactly to the line net');
select is((select row(refunded_paisa, total_paisa)::text from public.sales where id = :'pr7'), '(2273,2273)',
  'partial returns: the sale is fully refunded, never above what was charged');
select is((select returned_quantity from public.sale_items where id = :'pr7_line'), 7, 'partial returns: returned quantity = 7');
select is((select quantity_on_hand from public.batches where id = :'ace_b'), :'ace_q0'::int + 7,
  'partial returns: all 7 units are back in their lot (the replay restocked nothing)');
select is(:'ret1_replay'::jsonb ->> 'sale_return_id', :'ret1'::jsonb ->> 'sale_return_id',
  'return replay: the same request id returns the original return');
select is((:'ret1_replay'::jsonb ->> 'replayed')::boolean, true, 'return replay: flagged as replayed');
select is((select count(*)::int from public.sale_returns where sale_id = :'pr7'), 3,
  'return replay: no extra return row was written');

-- 11b. Return window. A sale back-dated 3 days (fixture).
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 2)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), gen_random_uuid()) ->> 'sale_id' as rw \gset
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 2)),
  jsonb_build_array(tests.t120_pay('cash', 2000)), gen_random_uuid()) ->> 'sale_id' as rw_today \gset
select tests.clear_authentication();
select id as rw_line from public.sale_items where sale_id = :'rw' \gset
select id as rw_today_line from public.sale_items where sale_id = :'rw_today' \gset
set local session_replication_role = replica;
update public.sales set business_date = business_date - 3 where id = :'rw';
set local session_replication_role = origin;
update public.organization_settings set return_window_days = 2 where organization_id = :'org';
select tests.authenticate_as(:'manager');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'rw',
  jsonb_build_array(tests.t120_rline(:'rw_line', 1)), 'late return', gen_random_uuid())), 'return_window_passed',
  'return window: a 3-day-old sale cannot be returned with a 2-day window');
select tests.clear_authentication();
update public.organization_settings set return_window_days = 0 where organization_id = :'org';
select tests.authenticate_as(:'manager');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'rw_today',
  jsonb_build_array(tests.t120_rline(:'rw_today_line', 1)), 'same day return', gen_random_uuid())), 'ok',
  'return window 0: a same-day sale can still be returned');
select tests.clear_authentication();
update public.organization_settings set return_window_days = 3 where organization_id = :'org';
select tests.authenticate_as(:'manager');
select is(tests.t120_err(format('select public.process_sale_return(%L, %L::jsonb, %L, %L)', :'rw',
  jsonb_build_array(tests.t120_rline(:'rw_line', 1)), 'late return', gen_random_uuid())), 'ok',
  'return window: a 3-day-old sale can be returned with a 3-day window (boundary inclusive)');
select tests.clear_authentication();
update public.organization_settings set return_window_days = 7 where organization_id = :'org';

-- 11c. Refund order: points paid -> due -> cash.
-- Refund customer earns 20 points (Napa 20 = 200 taka), then buys Napa 10 = 10000 paying 20 points (1000),
-- cash 4000 and leaving 5000 due. Points earned: 9000 eligible -> 90 taka -> 0 points.
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 20)),
  jsonb_build_array(tests.t120_pay('cash', 20000)), gen_random_uuid(), null, :'card_refund') ->> 'sale_id' as refund_earn \gset
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'napa', 10)),
  jsonb_build_array(tests.t120_pay('loyalty_points', 1000), tests.t120_pay('cash', 4000)), gen_random_uuid(),
  null, :'card_refund') ->> 'sale_id' as rf \gset
select tests.clear_authentication();
select id as rf_line from public.sale_items where sale_id = :'rf' \gset
select is((select row(points_redeemed, points_earned, paid_paisa, due_paisa)::text from public.sales where id = :'rf'),
  '(20,0,5000,5000)', 'refund order setup: 20 points + 4000 cash paid, 5000 due, no points earned');

-- First half (5 units = 5000): 10 points (500) back, then 4500 off the due, no cash.
select tests.authenticate_as(:'manager');
select public.process_sale_return(:'rf', jsonb_build_array(tests.t120_rline(:'rf_line', 5)), 'half returned',
  gen_random_uuid()) ->> 'sale_return_id' as rf1 \gset
-- Second half: 10 points back, the last 500 of due, then 4000 cash.
select public.process_sale_return(:'rf', jsonb_build_array(tests.t120_rline(:'rf_line', 5)), 'rest returned',
  gen_random_uuid()) ->> 'sale_return_id' as rf2 \gset
select tests.clear_authentication();
select is((select row(refund_paisa, points_returned, points_refund_value_paisa, due_reduction_paisa, cash_refund_paisa,
                      refund_method::text)::text from public.sale_returns where id = :'rf1'),
  '(5000,10,500,4500,0,)', 'refund order: points first (500), then the due (4500), no cash, no refund method');
select is((select row(refund_paisa, points_returned, points_refund_value_paisa, due_reduction_paisa, cash_refund_paisa,
                      refund_method::text)::text from public.sale_returns where id = :'rf2'),
  '(5000,10,500,500,4000,cash)', 'refund order: points (500), the remaining due (500), then cash (4000)');
select is((select row(sum(points_refund_value_paisa), sum(due_reduction_paisa), sum(cash_refund_paisa))::text
             from public.sale_returns where sale_id = :'rf'), '(1000,5000,4000)',
  'refund order: in total exactly the points, due and cash that were charged come back');
select is(app.customer_balance(:'cust_refund'), 0::bigint, 'refund order: the customer owes nothing');
select is(app.loyalty_points_balance((select id from public.loyalty_cards where card_no = :'card_refund')), 20,
  'refund order: the 20 redeemed points are back on the card');

-- 11d. Return of a controlled item writes a register row.
select tests.authenticate_as(:'sales1', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(tests.t120_line(:'diaz', 3)),
  jsonb_build_array(tests.t120_pay('cash', 4500)), gen_random_uuid(), null, null, 0,
  tests.t120_rx(:'today'::date - 1)) ->> 'sale_id' as cd2 \gset
select tests.clear_authentication();
select id as cd2_line from public.sale_items where sale_id = :'cd2' \gset
select tests.authenticate_as(:'manager');
select public.process_sale_return(:'cd2', jsonb_build_array(tests.t120_rline(:'cd2_line', 1)), 'patient stopped',
  gen_random_uuid()) ->> 'refund_paisa' as cd2_refund \gset
select tests.clear_authentication();
select is(:'cd2_refund'::bigint, 1500::bigint, 'controlled return: one unit refunded at 1500');
select is((select string_agg(entry_type || ' ' || quantity, ',' order by id) from public.controlled_drug_register
            where sale_id = :'cd2'), 'sale -3,return 1', 'controlled return: the register gets a +1 return row');
select is((select row(doctor_reg_no, prescription_id = (select prescription_id from public.sales where id = :'cd2'))::text
             from public.controlled_drug_register where sale_id = :'cd2' and entry_type = 'return'),
  '(BMDC-A-12345,t)', 'controlled return: the return row keeps the prescription and prescriber');

-- =============================================================================================
-- 12. Global invariants over every sale of this organization (6 assertions)
-- =============================================================================================
select is((select count(*)::int from public.sales s
            where s.organization_id = :'org'
              and s.net_paisa <> (select coalesce(sum(si.net_paisa), 0) from public.sale_items si where si.sale_id = s.id)),
  0, 'invariant: sum(sale_items.net_paisa) = sales.net_paisa for every sale');
select is((select count(*)::int from public.sales s
            where s.organization_id = :'org'
              and row(s.invoice_discount_paisa, s.loyalty_discount_paisa, s.line_discount_paisa, s.gross_paisa,
                      s.rounding_paisa)
                  is distinct from (select row(sum(si.invoice_discount_paisa)::bigint, sum(si.loyalty_discount_paisa)::bigint,
                                               sum(si.line_discount_paisa)::bigint, sum(si.gross_paisa)::bigint,
                                               sum(si.rounding_paisa)::bigint)
                                      from public.sale_items si where si.sale_id = s.id)),
  0, 'invariant: every header discount, gross and rounding equals the sum over its lines');
select is((select count(*)::int from public.sale_items si join public.sales s on s.id = si.sale_id
            where s.organization_id = :'org'
              and si.gross_paisa <> (select sum(sib.quantity::bigint * sib.unit_price_paisa) from public.sale_item_batches sib
                                      where sib.sale_item_id = si.id)),
  0, 'invariant: every line gross = sum of its lot allocations (quantity x unit price)');
select is((select count(*)::int from public.sale_items si join public.sales s on s.id = si.sale_id
            where s.organization_id = :'org'
              and si.quantity <> (select sum(sib.quantity) from public.sale_item_batches sib where sib.sale_item_id = si.id)),
  0, 'invariant: every line quantity is fully allocated to lots');
select is((select count(*)::int from public.sales s
            where s.organization_id = :'org' and s.points_earned <> (select coalesce(sum(si.points_earned), 0)
                                                                        from public.sale_items si where si.sale_id = s.id)),
  0, 'invariant: line points add up to the invoice points earned');
select is((select count(*)::int from public.batches b
            where b.organization_id = :'org'
              and b.quantity_on_hand <> (select coalesce(sum(m.quantity), 0) from public.inventory_movements m where m.batch_id = b.id)),
  0, 'invariant: every lot on-hand quantity equals the sum of its ledger movements');

select * from finish();
rollback;
