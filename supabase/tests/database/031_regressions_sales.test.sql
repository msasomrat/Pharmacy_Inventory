-- Regression tests for sales, returns, voids and loyalty defects found in the M1 database review.
-- Each section reproduces one confirmed finding (the section header names it) and asserts the fixed
-- behaviour. Sections are independent: each creates its own organization and users.
begin;
select plan(73);

-- =============================================================================================
-- A. spent-points-not-clawed-back (return and void paths) (6 assertions)
-- Regression: returning or voiding a sale whose earned points were already spent must not leave the
-- customer with the value of those points. Either the refund keeps back the shortfall, or the
-- return/void is refused. Fails while the reversal is silently capped at the current balance.
-- =============================================================================================
create function tests.try_sql(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate || ': ' || sqlerrm;
end;
$$;
grant execute on function tests.try_sql(text) to authenticated;

select tests.create_user('owner@pts.test') as owner \gset
select tests.create_user('manager@pts.test') as manager \gset
select tests.create_user('sales@pts.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Points Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@pts.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@pts.test', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
-- 10 points per 100 taka, 1 point = 1 taka (100 paisa), no discount.
update public.loyalty_plans
   set is_active = true, fee_paisa = 0, discount_bp = 0, points_per_100_taka = 10, point_value_paisa = 100
 where organization_id = :'org' and duration_months = 3
 returning id as plan3 \gset

select tests.authenticate_as(:'manager');
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
  'quantity', 5000, 'cost_paisa', 100, 'mrp_paisa', 150, 'sale_price_paisa', 149)), gen_random_uuid());

select tests.authenticate_as(:'sales', 'aal1');
insert into public.customers (organization_id, name, phone) values (:'org', 'Loyal Customer', '01811223344')
  returning id as customer \gset
select public.enroll_loyalty(:'customer', :'plan3', :'branch', gen_random_uuid(), 'cash') ->> 'card_no' as card \gset

-- ---------------------------------------------------------------------------
-- Return path
-- ---------------------------------------------------------------------------
-- Sale A: 1000 tablets for 1490 taka cash -> earns 140 points.
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 1000)),
  '[{"method": "cash", "amount_paisa": 149000}]'::jsonb, gen_random_uuid(), null, :'card') as sale_a \gset
select is((:'sale_a'::jsonb ->> 'points_earned')::int, 140, 'precondition: sale A earns 140 points');
-- Sale B: spend all 140 points (140 taka) on the next purchase.
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 100)),
  '[{"method": "loyalty_points", "amount_paisa": 14000}, {"method": "cash", "amount_paisa": 900}]'::jsonb,
  gen_random_uuid(), null, :'card') as sale_b \gset
select is((select coalesce(sum(l.points), 0)::int from public.loyalty_point_ledger l
             join public.loyalty_cards c on c.id = l.card_id where c.card_no = :'card'),
  0, 'precondition: the earned points have been spent');

-- Manager returns sale A in full.
select tests.authenticate_as(:'manager');
select id as line_a from public.sale_items where sale_id = (:'sale_a'::jsonb ->> 'sale_id')::uuid \gset
select tests.try_sql(format($$ select public.process_sale_return(%L, '[{"sale_item_id": "%s", "quantity": 1000}]'::jsonb,
  'customer returned everything', %L) $$, :'sale_a'::jsonb ->> 'sale_id', :'line_a', gen_random_uuid())) as ret_a \gset
select diag('return of sale A: ' || :'ret_a');
select diag('sale_return row: ' || coalesce((select row(cash_refund_paisa, due_reduction_paisa, points_reversed)::text
  from public.sale_returns where sale_id = (:'sale_a'::jsonb ->> 'sale_id')::uuid), '(none)'));
select ok(
  not exists (select 1 from public.sale_returns where sale_id = (:'sale_a'::jsonb ->> 'sale_id')::uuid)
  or (select r.cash_refund_paisa + r.due_reduction_paisa + (140 - r.points_reversed)::bigint * 100
        from public.sale_returns r where r.sale_id = (:'sale_a'::jsonb ->> 'sale_id')::uuid) <= 149000,
  'return: money refunded + value of spent-but-unreversed points does not exceed what the customer paid');
select ok(
  not exists (select 1 from public.sale_returns where sale_id = (:'sale_a'::jsonb ->> 'sale_id')::uuid)
  or (select r.cash_refund_paisa from public.sale_returns r where r.sale_id = (:'sale_a'::jsonb ->> 'sale_id')::uuid)
     <= 149000 - 14000,
  'return: the 140 taka of already-spent points is kept back from the cash refund');
select is((select row(r.cash_refund_paisa, r.points_shortfall_value_paisa, r.points_reversed)::text
             from public.sale_returns r where r.sale_id = (:'sale_a'::jsonb ->> 'sale_id')::uuid),
  '(135000,14000,0)', 'return: the shortfall (140 points x 100 paisa) is recorded on the return');

-- ---------------------------------------------------------------------------
-- Void path
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'sales', 'aal1');
-- Sale C earns 140 points, sale D spends them.
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 1000)),
  '[{"method": "cash", "amount_paisa": 149000}]'::jsonb, gen_random_uuid(), null, :'card') as sale_c \gset
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 100)),
  '[{"method": "loyalty_points", "amount_paisa": 14000}, {"method": "cash", "amount_paisa": 900}]'::jsonb,
  gen_random_uuid(), null, :'card') as sale_d \gset
select is((:'sale_c'::jsonb ->> 'points_earned')::int, 140, 'precondition: sale C earns 140 points');

select tests.authenticate_as(:'manager');
select tests.try_sql(format($$ select public.void_sale(%L, 'wrong customer') $$, :'sale_c'::jsonb ->> 'sale_id')) as void_c \gset
select diag('void of sale C: ' || :'void_c');
select diag('points ledger for sale C: ' || coalesce((select string_agg(entry_type || ' ' || points, ', ' order by id)
  from public.loyalty_point_ledger where sale_id = (:'sale_c'::jsonb ->> 'sale_id')::uuid), '(none)'));
select ok(
  :'void_c' <> 'ok'
  or (select coalesce(sum(points), 0) from public.loyalty_point_ledger
       where sale_id = (:'sale_c'::jsonb ->> 'sale_id')::uuid) = 0,
  'void: either refused, or the points earned by the voided sale are fully reversed');
select is(:'void_c'::text, 'P0001: Points earned on this sale have already been spent; process a return instead',
  'void: refused once the points it earned are spent (a return keeps their value back instead)');

-- =============================================================================================
-- B. spent-points-never-clawed-back (customer pays the price of goods kept) (5 assertions)
-- Regression: returning a sale whose earned points were already spent must not refund the full
-- money amount while the customer keeps the value of those points.
-- Defect: process_sale_return caps the reverse_earn at the card balance and never deducts the
-- unreversible points' value from the money refund.
-- =============================================================================================
select tests.create_user('owner@l2.test') as owner \gset
select tests.create_user('manager@l2.test') as manager \gset
select tests.create_user('sales@l2.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('L2 Pharmacy', 'Mohammadpur', 'LTB') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@l2.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@l2.test', 'salesman', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Seclo', 'capsule', '20 mg', 'capsule') returning id as seclo \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
-- 10 points per 100 taka, 1 point = 1 taka (100 paisa), no discount, free card.
update public.loyalty_plans
   set is_active = true, fee_paisa = 0, discount_bp = 0, points_per_100_taka = 10, point_value_paisa = 100
 where organization_id = :'org' and duration_months = 3
 returning id as plan3 \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Rahim', '01811-000001')
  returning id as cust \gset

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'seclo', 'batch_no', 'S1', 'expiry_date', :'today'::date + 300,
    'quantity', 500, 'unit_cost_paisa', 500, 'mrp_paisa', 700, 'sale_price_paisa', 700)
), gen_random_uuid()) as grn \gset

select tests.authenticate_as(:'sales', 'aal1');
select public.enroll_loyalty(:'cust', :'plan3', :'branch', gen_random_uuid()) ->> 'card_no' as card_no \gset

-- Sale A: 30 x 7 taka = 210 taka cash, earns 20 points.
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'seclo', 'quantity', 30)),
  '[{"method": "cash", "amount_paisa": 21000}]'::jsonb, gen_random_uuid(), null, :'card_no') as sale_a \gset
select is((:'sale_a'::jsonb ->> 'points_earned')::int, 20, 'sale A earns 20 points');

-- Sale B: spends those 20 points (20 taka) + 1 taka cash.
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'seclo', 'quantity', 3)),
  '[{"method": "loyalty_points", "amount_paisa": 2000}, {"method": "cash", "amount_paisa": 100}]'::jsonb,
  gen_random_uuid(), null, :'card_no') as sale_b \gset
select is((select points_balance from public.lookup_loyalty(:'org', :'card_no')), 0, 'the points were spent on sale B');

-- Full return of sale A.
select tests.authenticate_as(:'manager');
select id as line_a from public.sale_items where sale_id = (:'sale_a'::jsonb ->> 'sale_id')::uuid \gset
select public.process_sale_return((:'sale_a'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'line_a', 'quantity', 30)),
  'customer returned everything', gen_random_uuid()) as ret \gset

select is((:'ret'::jsonb ->> 'refund_paisa')::bigint, 21000::bigint, 'the return is valued at the full net amount');
-- Whatever points could not be taken back from the card must be withheld from the money refund.
select is((:'ret'::jsonb ->> 'cash_refund_paisa')::bigint,
  21000 - (20 - (:'ret'::jsonb ->> 'points_reversed')::int) * 100::bigint,
  'money refund is reduced by the value of earned points that could not be reversed');
-- Net effect for the customer: paid 211 taka in money, got the money refund back, and any point
-- balance left on the card is value still held (a negative balance is value still owed).
-- They kept 3 capsules worth 21 taka, so money paid - points value held must equal 21 taka.
select is(21100 - (:'ret'::jsonb ->> 'cash_refund_paisa')::bigint
          - (select points_balance from public.lookup_loyalty(:'org', :'card_no'))::bigint * 100,
  2100::bigint,
  'customer has paid exactly the price of the goods kept (no free value from spent points)');

-- =============================================================================================
-- C. rounding-over-refund (4 assertions)
-- Regression: with cash rounding to the nearest taka, a full return must not refund more than the
-- customer actually paid (total_paisa = net + rounding). Fails while refunds use pre-rounding net.
-- =============================================================================================
select tests.create_user('owner@round.test') as owner \gset
select tests.create_user('manager@round.test') as manager \gset
select tests.create_user('sales@round.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Round Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@round.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@round.test', 'salesman', array[:'branch']::uuid[]);
update public.organization_settings set cash_rounding = 'nearest_taka' where organization_id = :'org';
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset

select tests.authenticate_as(:'manager');
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
  'quantity', 100, 'cost_paisa', 100, 'mrp_paisa', 150, 'sale_price_paisa', 149)), gen_random_uuid());

select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 100}]'::jsonb, gen_random_uuid()) as sale \gset
select is((:'sale'::jsonb ->> 'total_paisa')::bigint, 100::bigint, 'precondition: 1.49 taka rounds down to 1 taka');
select is((:'sale'::jsonb ->> 'change_paisa')::bigint, 0::bigint, 'precondition: customer paid exactly 1 taka');

select tests.authenticate_as(:'manager');
select id as line from public.sale_items where sale_id = (:'sale'::jsonb ->> 'sale_id')::uuid \gset
select public.process_sale_return((:'sale'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'line', 'quantity', 1)), 'customer returned', gen_random_uuid()) as ret \gset
select diag('return result: ' || :'ret');
select ok((:'ret'::jsonb ->> 'cash_refund_paisa')::bigint <= 100,
  'full return refunds at most what the customer paid (100 paisa)');
select ok((select refunded_paisa <= total_paisa from public.sales where id = (:'sale'::jsonb ->> 'sale_id')::uuid),
  'cumulative refunded amount never exceeds the sale total actually collected');

-- =============================================================================================
-- D. refund-ignores-cash-rounding (3 assertions)
-- Regression: refund-ignores-cash-rounding.
-- With cash_rounding = 'nearest_taka' the customer pays total_paisa = net_paisa + rounding_paisa, but
-- process_sale_return prorates refunds over the line net amounts. A full return of a sale rounded down
-- refunds more than the customer paid, and the daily summary's net sales go negative.
-- =============================================================================================
select format('owner-%s@rounding.test', gen_random_uuid()) as owner_email \gset
select format('manager-%s@rounding.test', gen_random_uuid()) as manager_email \gset
select format('sales-%s@rounding.test', gen_random_uuid()) as sales_email \gset
select tests.create_user(:'owner_email') as owner \gset
select tests.create_user(:'manager_email') as manager \gset
select tests.create_user(:'sales_email') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Rounding Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', :'manager_email', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', :'sales_email', 'salesman', array[:'branch']::uuid[]);
update public.organization_settings set cash_rounding = 'nearest_taka' where organization_id = :'org';
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Seclo', 'capsule', '20 mg', 'capsule') returning id as seclo \gset
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'seclo',
  'batch_no', 'SE-1', 'expiry_date', :'today'::date + 300, 'quantity', 100, 'cost_paisa', 500,
  'mrp_paisa', 1049, 'sale_price_paisa', 1049)), gen_random_uuid());

-- Net 10.49 taka, rounded down to 10.00; the customer pays 10.00.
select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'seclo', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 1000}]'::jsonb, gen_random_uuid()) as sale \gset
select is((:'sale'::jsonb ->> 'total_paisa')::bigint, 1000::bigint, 'setup: net 1049 is rounded to a total of 1000');

select tests.clear_authentication();
select id as line from public.sale_items where sale_id = (:'sale'::jsonb ->> 'sale_id')::uuid \gset
select tests.authenticate_as(:'manager');
select public.process_sale_return((:'sale'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'line', 'quantity', 1)), 'customer returned', gen_random_uuid()) as ret \gset
select diag('full return: ' || :'ret');
select cmp_ok((:'ret'::jsonb ->> 'cash_refund_paisa')::bigint, '<=', 1000::bigint,
  'a full return never refunds more cash than the customer paid');

select tests.clear_authentication();
select cmp_ok((select net_paisa - returns_paisa from public.daily_branch_sales
                where branch_id = :'branch' and business_date = :'today'::date), '>=', 0::bigint,
  'net sales of a fully returned sale are not negative');

-- =============================================================================================
-- E. nearest-taka-rounding-vs-returns (7 assertions)
-- Regression: with cash_rounding = 'nearest_taka', a full return must settle exactly what the
-- customer was charged (total_paisa = net + rounding), not the unrounded net.
-- Defect: refunds are based on line net_paisa only, so a fully returned credit sale either leaves a
-- residual due (rounded up) or pays cash to a customer who paid nothing (rounded down), and daily
-- net sales (bumped with total) minus returns (bumped with net) leave a residue.
-- =============================================================================================
select tests.create_user('owner@v9.test') as owner \gset
select tests.create_user('manager@v9.test') as manager \gset
select tests.create_user('sales@v9.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('V9 Pharmacy', 'Mohammadpur', 'VNI') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@v9.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@v9.test', 'salesman', array[:'branch']::uuid[]);
update public.organization_settings set cash_rounding = 'nearest_taka' where organization_id = :'org';

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Fexo', 'tablet', '120 mg', 'tablet') returning id as fexo \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Up', '01811-000091')
  returning id as cust_up \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Down', '01811-000092')
  returning id as cust_down \gset
select public.set_customer_credit_limit(:'cust_up', 1000000);
select public.set_customer_credit_limit(:'cust_down', 1000000);

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'N1', 'expiry_date', :'today'::date + 300,
    'quantity', 1000, 'unit_cost_paisa', 80, 'mrp_paisa', 105, 'sale_price_paisa', 105),
  jsonb_build_object('medicine_id', :'fexo', 'batch_no', 'F1', 'expiry_date', :'today'::date + 300,
    'quantity', 100, 'unit_cost_paisa', 800, 'mrp_paisa', 1049, 'sale_price_paisa', 1049)
), gen_random_uuid()) as grn \gset

select tests.authenticate_as(:'sales', 'aal1');
-- (a) net 10.50 taka rounds up to 11 taka, all on due.
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 10)),
  '[]'::jsonb, gen_random_uuid(), :'cust_up') as s_up \gset
-- (b) net 10.49 taka rounds down to 10 taka, all on due.
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'fexo', 'quantity', 1)),
  '[]'::jsonb, gen_random_uuid(), :'cust_down') as s_down \gset
select is((:'s_up'::jsonb ->> 'total_paisa') || '/' || (:'s_down'::jsonb ->> 'total_paisa'),
  '1100/1000', 'totals are rounded to the nearest taka (11 and 10 taka)');

select tests.authenticate_as(:'manager');
select id as up_line from public.sale_items where sale_id = (:'s_up'::jsonb ->> 'sale_id')::uuid \gset
select id as down_line from public.sale_items where sale_id = (:'s_down'::jsonb ->> 'sale_id')::uuid \gset
select public.process_sale_return((:'s_up'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'up_line', 'quantity', 10)), 'returned all', gen_random_uuid()) as r_up \gset
select public.process_sale_return((:'s_down'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'down_line', 'quantity', 1)), 'returned all', gen_random_uuid()) as r_down \gset

select is((select balance_paisa from public.customer_balances where customer_id = :'cust_up'), 0::bigint,
  '(a) after returning everything the customer owes nothing');
select is((:'r_up'::jsonb ->> 'cash_refund_paisa')::bigint, 0::bigint, '(a) a customer who paid nothing gets no cash');
select is((select balance_paisa from public.customer_balances where customer_id = :'cust_down'), 0::bigint,
  '(b) after returning everything the customer owes nothing');
select is((:'r_down'::jsonb ->> 'cash_refund_paisa')::bigint, 0::bigint,
  '(b) a customer who paid nothing gets no cash');
select is((:'r_up'::jsonb ->> 'refund_paisa')::bigint + (:'r_down'::jsonb ->> 'refund_paisa')::bigint, 2100::bigint,
  'total refunded equals total charged when every sale is fully returned');

select tests.authenticate_as(:'owner');
select is((select sum(net_sales_paisa)::bigint from public.report_sales_summary(:'org', :'today', :'today')), 0::bigint,
  'net sales are zero when every sale was fully returned');

-- =============================================================================================
-- F. loyalty-card-bypasses-inactive-customer (5 assertions)
-- Regression: a deactivated customer must not be charged (credit/due) through their loyalty card.
-- create_sale rejects an inactive p_customer_id, but reloads the card holder without is_active.
-- =============================================================================================
select tests.create_user('owner@inact.test') as owner \gset
select tests.create_user('sales@inact.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Inactive Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'sales@inact.test', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
select public.add_opening_stock(:'branch', jsonb_build_array(jsonb_build_object(
  'medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
  'quantity', 100, 'cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid());
update public.loyalty_plans set is_active = true, fee_paisa = 0, discount_bp = 0
 where organization_id = :'org' and duration_months = 3 returning id as plan3 \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Bad Debtor', '01811223344')
  returning id as customer \gset
select public.set_customer_credit_limit(:'customer', 5000);
select public.enroll_loyalty(:'customer', :'plan3', :'branch', gen_random_uuid(), 'cash') ->> 'card_no' as card \gset

-- The owner deactivates the customer (e.g. unpaid dues); the loyalty membership stays active.
update public.customers set is_active = false where id = :'customer';
select is((select is_active from public.customers where id = :'customer'), false, 'precondition: customer is inactive');

select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 10}]'::jsonb,
    '[{"method": "cash", "amount_paisa": 200}]'::jsonb, gen_random_uuid(), %L) $$, :'branch', :'napa', :'customer'),
  'P0001', 'Customer not found or inactive', 'control: inactive customer is refused by id');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 10}]'::jsonb,
    '[{"method": "cash", "amount_paisa": 200}]'::jsonb, gen_random_uuid(), null, %L) $$, :'branch', :'napa', :'card'),
  'P0001', null, 'inactive customer is refused when identified by loyalty card');

select tests.clear_authentication();
select is((select count(*)::int from public.sales where customer_id = :'customer'), 0,
  'no sale was recorded against the inactive customer');
select is((select coalesce(sum(amount_paisa), 0)::bigint from public.customer_ledger_entries where customer_id = :'customer'),
  0::bigint, 'no due was posted to the inactive customer');

-- =============================================================================================
-- G. inactive-customer-credit-via-card (4 assertions)
-- Regression: a deactivated customer must not be able to buy on credit or use loyalty benefits by
-- presenting their loyalty card.
-- Defect: create_sale reloads v_customer from the card holder without checking is_active
-- (p_customer_id is checked, the card path is not).
-- =============================================================================================
select tests.create_user('owner@v11.test') as owner \gset
select tests.create_user('manager@v11.test') as manager \gset
select tests.create_user('sales@v11.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('V11 Pharmacy', 'Mohammadpur', 'VEL') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@v11.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@v11.test', 'salesman', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
update public.loyalty_plans
   set is_active = true, fee_paisa = 0, discount_bp = 500, points_per_100_taka = 10, point_value_paisa = 100
 where organization_id = :'org' and duration_months = 3
 returning id as plan3 \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim', '01811-000111')
  returning id as cust \gset
select public.set_customer_credit_limit(:'cust', 10000000);

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'N1', 'expiry_date', :'today'::date + 300,
    'quantity', 1000, 'unit_cost_paisa', 80, 'mrp_paisa', 105, 'sale_price_paisa', 105)
), gen_random_uuid()) as grn \gset
select public.enroll_loyalty(:'cust', :'plan3', :'branch', gen_random_uuid()) ->> 'card_no' as card_no \gset

-- The owner deactivates the customer (e.g. bad debt).
select tests.authenticate_as(:'owner');
update public.customers set is_active = false where id = :'cust';

select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 10}]'::jsonb, '[]'::jsonb,
    gen_random_uuid(), %L) $$, :'branch', :'napa', :'cust'),
  'P0001', 'Customer not found or inactive', 'an inactive customer is refused when selected directly');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 10}]'::jsonb, '[]'::jsonb,
    gen_random_uuid(), null, %L) $$, :'branch', :'napa', :'card_no'),
  'P0001', null, 'an inactive customer is refused when their loyalty card is presented for a credit sale');
select throws_ok(
  format($$ select public.create_sale(%L, '[{"medicine_id": "%s", "quantity": 10}]'::jsonb,
    '[{"method": "cash", "amount_paisa": 2000}]'::jsonb, gen_random_uuid(), null, %L) $$, :'branch', :'napa', :'card_no'),
  'P0001', null, 'an inactive customer gets no loyalty discount or points through their card');

select tests.authenticate_as(:'owner');
select is((select balance_paisa from public.customer_balances where customer_id = :'cust'), 0::bigint,
  'no due was posted to the inactive customer');

-- =============================================================================================
-- H. points-posted-to-replaced-card (4 assertions)
-- Regression: points-posted-to-replaced-card.
-- void_sale (and process_sale_return) post point reversals to sales.loyalty_card_id, the card used at
-- sale time, and clamp them to that card's balance. replace_loyalty_card moves the balance to a new
-- card, so after a replacement the reversal of earned points is clamped to the dead card's balance and
-- the points earned on a voided sale stay spendable on the new card.
-- =============================================================================================
select format('owner-%s@cardswap.test', gen_random_uuid()) as owner_email \gset
select format('manager-%s@cardswap.test', gen_random_uuid()) as manager_email \gset
select format('sales-%s@cardswap.test', gen_random_uuid()) as sales_email \gset
select tests.create_user(:'owner_email') as owner \gset
select tests.create_user(:'manager_email') as manager \gset
select tests.create_user(:'sales_email') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Card Swap Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', :'manager_email', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', :'sales_email', 'salesman', array[:'branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim', '01811223344') returning id as customer \gset
-- 1 point per 100 taka, 1 point = 1 taka
update public.loyalty_plans set is_active = true, points_per_100_taka = 1, point_value_paisa = 100
 where organization_id = :'org' and duration_months = 3 returning id as plan3 \gset
select public.add_opening_stock(:'branch', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-1', 'expiry_date', :'today'::date + 300,
    'quantity', 1000, 'cost_paisa', 500, 'mrp_paisa', 1000, 'sale_price_paisa', 1000)), gen_random_uuid());

select tests.authenticate_as(:'sales', 'aal1');
select public.enroll_loyalty(:'customer', :'plan3', :'branch', gen_random_uuid()) ->> 'card_no' as card_no \gset
-- Sale A: 2000 taka -> earns 20 points
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 200)),
  '[{"method": "cash", "amount_paisa": 200000}]'::jsonb, gen_random_uuid(), null, :'card_no') as sale_a \gset
-- Sale B: 10 taka, 9 paid with points (earns nothing)
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 1)),
  '[{"method": "loyalty_points", "amount_paisa": 900}, {"method": "cash", "amount_paisa": 100}]'::jsonb,
  gen_random_uuid(), null, :'card_no') as sale_b \gset
select tests.clear_authentication();
select id as old_card from public.loyalty_cards where organization_id = :'org' and card_no = :'card_no' \gset

select is((:'sale_a'::jsonb ->> 'points_earned')::int, 20, 'setup: sale A earned 20 points');
select is(app.loyalty_points_balance(:'old_card'), 11, 'setup: 20 earned - 9 redeemed = 11 points');

-- Card lost: replace it (balance moves to the new card), then void both sales (B first, then A).
select tests.authenticate_as(:'manager');
select public.replace_loyalty_card(:'old_card', 'card lost') as new_card_no \gset
select public.void_sale((:'sale_b'::jsonb ->> 'sale_id')::uuid, 'entered by mistake');
select public.void_sale((:'sale_a'::jsonb ->> 'sale_id')::uuid, 'entered by mistake');
select tests.clear_authentication();
select id as new_card from public.loyalty_cards where organization_id = :'org' and card_no = :'new_card_no' \gset

select diag(format('after voids: old card %s points, new card %s points',
  app.loyalty_points_balance(:'old_card'), app.loyalty_points_balance(:'new_card')));
select is(app.loyalty_points_balance(:'new_card'), 0,
  'points earned and redeemed on voided sales are fully reversed on the customer''s active card');
select is((select sum(app.loyalty_points_balance(c.id))::int from public.loyalty_cards c where c.customer_id = :'customer'), 0,
  'the customer keeps no points from voided sales across all cards');

-- =============================================================================================
-- I. card-replacement-strands-reversals (6 assertions)
-- Regression: point reversals on void/return must follow the customer to the replacement card.
-- Defect: replace_loyalty_card moves the whole balance to the new card, but void_sale and
-- process_sale_return keep posting to sales.loyalty_card_id (the old, deactivated card):
--   * reverse_earn is capped at the old card's balance (0), so earned points are never clawed back;
--   * reverse_redeem credits the dead card, so the customer loses refunded points.
-- =============================================================================================
select tests.create_user('owner@l3.test') as owner \gset
select tests.create_user('manager@l3.test') as manager \gset
select tests.create_user('sales@l3.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('L3 Pharmacy', 'Mohammadpur', 'LTC') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@l3.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@l3.test', 'salesman', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Seclo', 'capsule', '20 mg', 'capsule') returning id as seclo \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
update public.loyalty_plans
   set is_active = true, fee_paisa = 0, discount_bp = 0, points_per_100_taka = 10, point_value_paisa = 100
 where organization_id = :'org' and duration_months = 3
 returning id as plan3 \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Customer X', '01811-000011')
  returning id as cust_x \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Customer Y', '01811-000012')
  returning id as cust_y \gset

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'seclo', 'batch_no', 'S1', 'expiry_date', :'today'::date + 300,
    'quantity', 500, 'unit_cost_paisa', 500, 'mrp_paisa', 700, 'sale_price_paisa', 700)
), gen_random_uuid()) as grn \gset

select tests.authenticate_as(:'sales', 'aal1');
select public.enroll_loyalty(:'cust_x', :'plan3', :'branch', gen_random_uuid()) ->> 'card_no' as card_x \gset
select public.enroll_loyalty(:'cust_y', :'plan3', :'branch', gen_random_uuid()) ->> 'card_no' as card_y \gset

-- ---------------------------------------------------------------------------
-- Case 1: earned points move to the new card, then the earning sale is voided.
-- ---------------------------------------------------------------------------
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'seclo', 'quantity', 30)),
  '[{"method": "cash", "amount_paisa": 21000}]'::jsonb, gen_random_uuid(), null, :'card_x') as sale_x \gset
select is((:'sale_x'::jsonb ->> 'points_earned')::int, 20, 'sale earns 20 points on card X1');

select tests.authenticate_as(:'manager');
select id as card_x_id from public.loyalty_cards where card_no = :'card_x' and organization_id = :'org' \gset
select public.replace_loyalty_card(:'card_x_id', 'card lost') as card_x2 \gset
select is((select points_balance from public.lookup_loyalty(:'org', :'card_x2')), 20,
  'replacement card X2 carries the 20 points');
select public.void_sale((:'sale_x'::jsonb ->> 'sale_id')::uuid, 'wrong customer');
select is((select points_balance from public.lookup_loyalty(:'org', :'card_x2')), 0,
  'voiding the sale takes back the 20 earned points from the customer''s current card');
select is((select coalesce(sum(p.points), 0)::int from public.loyalty_point_ledger p
            join public.loyalty_cards c on c.id = p.card_id where c.customer_id = :'cust_x'), 0,
  'customer X holds no points from a voided sale across all cards');

-- ---------------------------------------------------------------------------
-- Case 2: points redeemed on a sale, card replaced, then that sale is voided.
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'seclo', 'quantity', 30)),
  '[{"method": "cash", "amount_paisa": 21000}]'::jsonb, gen_random_uuid(), null, :'card_y') as sale_y1 \gset
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'seclo', 'quantity', 3)),
  '[{"method": "loyalty_points", "amount_paisa": 2000}, {"method": "cash", "amount_paisa": 100}]'::jsonb,
  gen_random_uuid(), null, :'card_y') as sale_y2 \gset

select tests.authenticate_as(:'manager');
select id as card_y_id from public.loyalty_cards where card_no = :'card_y' and organization_id = :'org' \gset
select public.replace_loyalty_card(:'card_y_id', 'card damaged') as card_y2 \gset
select public.void_sale((:'sale_y2'::jsonb ->> 'sale_id')::uuid, 'customer cancelled');
select is((select points_balance from public.lookup_loyalty(:'org', :'card_y2')), 20,
  'redeemed points refunded by the void land on the customer''s usable card');
select is((select coalesce(sum(p.points), 0)::int from public.loyalty_point_ledger p
            where p.card_id = :'card_y_id'), 0,
  'nothing is credited to the deactivated card');

-- =============================================================================================
-- J. points-reversal-ignores-eligibility (6 assertions)
-- Regression: points reversed on a return must follow the lines that earned them.
-- Defect: process_sale_return reverses points_earned x refund / whole-sale net, but points are earned
-- only on loyalty-eligible lines. Returning the eligible line reverses a fraction of the points;
-- returning an ineligible line takes away points it never earned.
-- =============================================================================================
select tests.create_user('owner@l4.test') as owner \gset
select tests.create_user('manager@l4.test') as manager \gset
select tests.create_user('sales@l4.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('L4 Pharmacy', 'Mohammadpur', 'LTD') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@l4.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@l4.test', 'salesman', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Elig', 'tablet', '500 mg', 'tablet') returning id as elig \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label, loyalty_eligible)
  values (:'org', 'Inel', 'injection', '1 g', 'vial', false) returning id as inel \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
update public.loyalty_plans
   set is_active = true, fee_paisa = 0, discount_bp = 0, points_per_100_taka = 10, point_value_paisa = 100
 where organization_id = :'org' and duration_months = 3
 returning id as plan3 \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Rahim', '01811-000021')
  returning id as cust \gset

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'elig', 'batch_no', 'EL1', 'expiry_date', :'today'::date + 300,
    'quantity', 1000, 'unit_cost_paisa', 80, 'mrp_paisa', 105, 'sale_price_paisa', 105),
  jsonb_build_object('medicine_id', :'inel', 'batch_no', 'IN1', 'expiry_date', :'today'::date + 300,
    'quantity', 10, 'unit_cost_paisa', 80000, 'mrp_paisa', 90000, 'sale_price_paisa', 90000)
), gen_random_uuid()) as grn \gset

select tests.authenticate_as(:'sales', 'aal1');
select public.enroll_loyalty(:'cust', :'plan3', :'branch', gen_random_uuid()) ->> 'card_no' as card_no \gset

-- Two identical sales: Elig 100 x 1.05 taka (eligible, 105 taka) + Inel 1 x 900 taka (not eligible).
select public.create_sale(:'branch', jsonb_build_array(
    jsonb_build_object('medicine_id', :'elig', 'quantity', 100),
    jsonb_build_object('medicine_id', :'inel', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 100500}]'::jsonb, gen_random_uuid(), null, :'card_no') as s1 \gset
select public.create_sale(:'branch', jsonb_build_array(
    jsonb_build_object('medicine_id', :'elig', 'quantity', 100),
    jsonb_build_object('medicine_id', :'inel', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 100500}]'::jsonb, gen_random_uuid(), null, :'card_no') as s2 \gset
select is((:'s1'::jsonb ->> 'points_earned')::int, 10, 'all 10 points come from the eligible line (105 taka)');
select is((select points_balance from public.lookup_loyalty(:'org', :'card_no')), 20, 'card holds 20 points');

select tests.authenticate_as(:'manager');
select id as s1_elig from public.sale_items where sale_id = (:'s1'::jsonb ->> 'sale_id')::uuid and medicine_id = :'elig' \gset
select id as s2_inel from public.sale_items where sale_id = (:'s2'::jsonb ->> 'sale_id')::uuid and medicine_id = :'inel' \gset

-- Return the whole eligible line of sale 1: all 10 points it earned must go.
select public.process_sale_return((:'s1'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'s1_elig', 'quantity', 100)),
  'returned eligible goods', gen_random_uuid()) as r1 \gset
select is((:'r1'::jsonb ->> 'refund_paisa')::bigint, 10500::bigint, 'refund is the eligible line net');
select is((:'r1'::jsonb ->> 'points_reversed')::int, 10,
  'returning the line that earned all the points reverses all of them');

-- Return only the ineligible line of sale 2: it earned no points, so none are reversed.
select public.process_sale_return((:'s2'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'s2_inel', 'quantity', 1)),
  'returned ineligible goods', gen_random_uuid()) as r2 \gset
select is((:'r2'::jsonb ->> 'refund_paisa')::bigint, 90000::bigint, 'refund is the ineligible line net');
select is((:'r2'::jsonb ->> 'points_reversed')::int, 0,
  'returning a line that earned no points reverses no points');

-- =============================================================================================
-- K. void-negative-customer-balance (6 assertions)
-- Regression: voiding a credit sale whose due was already collected must not leave the customer
-- with an unexplained negative balance.
-- Defect: void_sale posts sale_void -due_paisa for the full original due, ignoring collections.
-- process_sale_return caps the due reduction at the customer's balance and refunds the rest as
-- money; void_sale does not, and record_customer_payment cannot pay out a negative balance.
-- =============================================================================================
select tests.create_user('owner@v6.test') as owner \gset
select tests.create_user('manager@v6.test') as manager \gset
select tests.create_user('sales@v6.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('V6 Pharmacy', 'Mohammadpur', 'VSF') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@v6.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@v6.test', 'salesman', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim', '01811-000061')
  returning id as cust \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim Two', '01811-000062')
  returning id as cust2 \gset
select public.set_customer_credit_limit(:'cust', 1000000);
select public.set_customer_credit_limit(:'cust2', 1000000);

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'N1', 'expiry_date', :'today'::date + 300,
    'quantity', 1000, 'unit_cost_paisa', 80, 'mrp_paisa', 105, 'sale_price_paisa', 105)
), gen_random_uuid()) as grn \gset

-- Credit sale of 10.50 taka fully on due, collected in cash later the same day.
select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 10)),
  '[]'::jsonb, gen_random_uuid(), :'cust') as sale \gset
select is((:'sale'::jsonb ->> 'due_paisa')::bigint, 1050::bigint, 'whole sale is on due');
select is(public.record_customer_payment(:'cust', :'branch', 1050, 'cash', gen_random_uuid()), 0::bigint, 'due collected in cash');

select tests.authenticate_as(:'manager');
select public.void_sale((:'sale'::jsonb ->> 'sale_id')::uuid, 'entered by mistake');
select is((select balance_paisa from public.customer_balances where customer_id = :'cust'), 0::bigint,
  'after the void the customer neither owes nor is silently owed money (the collected cash is refunded explicitly)');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 1, 'cash', gen_random_uuid()) $$, :'cust', :'branch'),
  'P0001', null, 'there is no due left to collect');

-- Same situation handled through a full return instead: balance stays at zero and the money is refunded.
select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 10)),
  '[]'::jsonb, gen_random_uuid(), :'cust2') as sale2 \gset
select public.record_customer_payment(:'cust2', :'branch', 1050, 'cash', gen_random_uuid());
select tests.authenticate_as(:'manager');
select id as line2 from public.sale_items where sale_id = (:'sale2'::jsonb ->> 'sale_id')::uuid \gset
select public.process_sale_return((:'sale2'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'line2', 'quantity', 10)), 'returned', gen_random_uuid()) as ret2 \gset
select is((:'ret2'::jsonb ->> 'cash_refund_paisa')::bigint, 1050::bigint,
  'a full return of a collected credit sale refunds the money');
select is((select balance_paisa from public.customer_balances where customer_id = :'cust2'), 0::bigint,
  'a full return keeps the customer balance at zero');

-- =============================================================================================
-- L. return-cost-not-batch-cost (5 assertions)
-- Regression: the cost of returned goods must equal the cost of the batch units actually restocked.
-- Defect: process_sale_return books cost as a proportional share of the line's mixed-batch cost,
-- but the units go back into specific batches (latest expiry first), whose movements are valued at
-- that batch's cost. Cost of sales and inventory value then diverge.
-- =============================================================================================
select tests.create_user('owner@v8.test') as owner \gset
select tests.create_user('manager@v8.test') as manager \gset
select tests.create_user('sales@v8.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('V8 Pharmacy', 'Mohammadpur', 'VEI') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@v8.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@v8.test', 'salesman', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-LATE', 'expiry_date', :'today'::date + 300,
    'quantity', 100, 'unit_cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120),
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-EARLY', 'expiry_date', :'today'::date + 60,
    'quantity', 40, 'bonus_quantity', 10, 'unit_cost_paisa', 90, 'mrp_paisa', 120, 'sale_price_paisa', 115)
), gen_random_uuid()) as grn \gset

-- FEFO: 50 from NA-EARLY (cost 72) + 10 from NA-LATE (cost 80) = line cost 4400.
select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 60)),
  '[{"method": "cash", "amount_paisa": 7000}]'::jsonb, gen_random_uuid()) as sale \gset

select tests.authenticate_as(:'manager');
select id as line from public.sale_items where sale_id = (:'sale'::jsonb ->> 'sale_id')::uuid \gset
select public.process_sale_return((:'sale'::jsonb ->> 'sale_id')::uuid,
  jsonb_build_array(jsonb_build_object('sale_item_id', :'line', 'quantity', 10)), 'returned', gen_random_uuid()) as ret \gset
select is((select quantity_on_hand from public.batches where batch_no = 'NA-LATE' and branch_id = :'branch'), 100,
  'the 10 returned units went back into NA-LATE (cost 80)');

select tests.clear_authentication();
select is((select cost_paisa from public.sales where id = (:'sale'::jsonb ->> 'sale_id')::uuid), 4400::bigint,
  'sale cost = 50 x 72 + 10 x 80');
select is((select sum(quantity * unit_cost_paisa)::bigint from public.inventory_movements
            where reference_type = 'sale_return' and reference_id = (:'ret'::jsonb ->> 'sale_return_id')::uuid),
  800::bigint, 'inventory gains 10 x 80 = 800 at cost');
select is((select cost_paisa from public.sale_returns where id = (:'ret'::jsonb ->> 'sale_return_id')::uuid),
  800::bigint, 'the return''s cost equals the cost of the units restocked');
select is((select returns_cost_paisa from public.daily_branch_sales where branch_id = :'branch' and business_date = :'today'),
  800::bigint, 'daily returns cost equals the cost of the units restocked');

-- =============================================================================================
-- M. report-not-net-of-voids (6 assertions)
-- Regression: report_sales_summary must exclude voided sales from every column, not only from
-- sales_count / net / cost.
-- Defect: void_sale bumps only voids_count, voided_paisa and voided_cost_paisa, so gross, discount,
-- loyalty discount and credit sales still include the voided invoice.
-- =============================================================================================
select tests.create_user('owner@v10.test') as owner \gset
select tests.create_user('manager@v10.test') as manager \gset
select tests.create_user('sales@v10.test') as sales \gset

select tests.authenticate_as(:'owner');
select public.create_organization('V10 Pharmacy', 'Mohammadpur', 'VTN') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@v10.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@v10.test', 'salesman', array[:'branch']::uuid[]);

insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Supplier A') returning id as supa \gset
update public.loyalty_plans
   set is_active = true, fee_paisa = 0, discount_bp = 500
 where organization_id = :'org' and duration_months = 3
 returning id as plan3 \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim', '01811-000101')
  returning id as cust \gset
select public.set_customer_credit_limit(:'cust', 1000000);

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supa', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'N1', 'expiry_date', :'today'::date + 300,
    'quantity', 1000, 'unit_cost_paisa', 80, 'mrp_paisa', 105, 'sale_price_paisa', 105)
), gen_random_uuid()) as grn \gset
select public.enroll_loyalty(:'cust', :'plan3', :'branch', gen_random_uuid()) ->> 'card_no' as card_no \gset

-- Voided invoice: 100 x 1.05 taka, 10% line discount, 5% loyalty discount, fully on credit.
select public.create_sale(:'branch',
  jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 100, 'discount_bp', 1000)),
  '[]'::jsonb, gen_random_uuid(), null, :'card_no') as s_void \gset
select public.void_sale((:'s_void'::jsonb ->> 'sale_id')::uuid, 'entered by mistake');

-- Kept invoice: 10 x 1.05 taka cash, no discount, no card.
select tests.authenticate_as(:'sales', 'aal1');
select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 10)),
  '[{"method": "cash", "amount_paisa": 1050}]'::jsonb, gen_random_uuid()) as s_keep \gset

select tests.authenticate_as(:'owner');
select is((select sales_count from public.report_sales_summary(:'org', :'today', :'today')), 1,
  'only the kept invoice is counted');
select is((select net_sales_paisa from public.report_sales_summary(:'org', :'today', :'today')), 1050::bigint,
  'net sales exclude the voided invoice');
select is((select gross_paisa from public.report_sales_summary(:'org', :'today', :'today')), 1050::bigint,
  'gross excludes the voided invoice');
select is((select discount_paisa from public.report_sales_summary(:'org', :'today', :'today')), 0::bigint,
  'discount given excludes the voided invoice');
select is((select loyalty_discount_paisa from public.report_sales_summary(:'org', :'today', :'today')), 0::bigint,
  'loyalty discount given excludes the voided invoice');
select is((select credit_sales_paisa from public.report_sales_summary(:'org', :'today', :'today')), 0::bigint,
  'credit sales exclude the voided invoice');

-- =============================================================================================
-- N. membership-month-end-off-by-one (4 assertions)
-- Regression: a membership that starts on a day the end month does not have (29th-31st) must not
-- lose a day. Defect: ends_on = (starts_on + n months)::date - 1; when the month is clamped
-- (Oct 31 + 1 month = Nov 30) the code subtracts another day (Nov 29), and the renewal anchor then
-- drifts to the 30th/29th/... permanently.
-- The dates are derived from app.business_date: S is the first 31st after today whose following
-- month is shorter. A current membership ending on S - 1 is created directly, then renewed.
-- =============================================================================================
select tests.create_user('owner@v12.test') as owner \gset
select tests.create_user('manager@v12.test') as manager \gset

select tests.authenticate_as(:'owner');
select public.create_organization('V12 Pharmacy', 'Mohammadpur', 'VTW') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@v12.test', 'manager', array[:'branch']::uuid[]);
insert into public.loyalty_plans (organization_id, name, duration_months, fee_paisa, discount_bp, is_active)
  values (:'org', '1-Month Card', 1, 0, 500, true) returning id as plan1 \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim', '01811-000121')
  returning id as cust \gset

select min(d)::date as s from generate_series(:'today'::date + 1, :'today'::date + 400, interval '1 day') d
 where extract(day from d) = 31 and extract(day from d + interval '1 month') < 31 \gset

-- Issue the card (membership starting today), then replace that membership by one ending S - 1.
select tests.authenticate_as(:'manager');
select public.enroll_loyalty(:'cust', :'plan1', :'branch', gen_random_uuid()) as first \gset
select public.cancel_loyalty_membership((:'first'::jsonb ->> 'membership_id')::uuid, 'test setup');
select tests.clear_authentication();
insert into public.loyalty_memberships (
  organization_id, card_id, customer_id, plan_id, branch_id, starts_on, ends_on, fee_paid_paisa,
  discount_bp, points_per_100_taka, point_value_paisa, min_redeem_points, client_request_id, created_by)
select :'org', c.id, :'cust', :'plan1', :'branch', :'today'::date, :'s'::date - 1, 0, 500, 0, 0, 0,
       gen_random_uuid(), :'manager'
  from public.loyalty_cards c where c.customer_id = :'cust' and c.is_active;

-- Renew: the new membership starts on S (a 31st) and lasts one month.
select tests.authenticate_as(:'manager');
select public.enroll_loyalty(:'cust', :'plan1', :'branch', gen_random_uuid()) as renewal \gset
select is((:'renewal'::jsonb ->> 'starts_on')::date, :'s'::date, 'renewal starts the day after the current membership');
select is((:'renewal'::jsonb ->> 'ends_on')::date, (:'s'::date + interval '1 month')::date,
  'a 1-month membership starting on the 31st runs to the last day of the next (shorter) month');
select is((select ends_on from public.loyalty_memberships where id = (:'renewal'::jsonb ->> 'membership_id')::uuid),
  (:'s'::date + interval '1 month')::date, 'stored end date matches');

-- The following renewal must return to the month-end anchor rather than drifting earlier. Only one future
-- period may exist per card (FR-LOY-018), so first let the renewal period become the current one: cancel
-- the period running to S - 1 and start the renewal today (its end date, S + 1 month, is unchanged).
select tests.clear_authentication();
update public.loyalty_memberships set status = 'cancelled', cancelled_at = now(), cancel_reason = 'test setup'
 where customer_id = :'cust' and status = 'active' and ends_on = :'s'::date - 1;
update public.loyalty_memberships set starts_on = :'today'::date
 where id = (:'renewal'::jsonb ->> 'membership_id')::uuid;
select tests.authenticate_as(:'manager');
select public.enroll_loyalty(:'cust', :'plan1', :'branch', gen_random_uuid()) as renewal2 \gset
-- (S = Oct 31 -> Nov 30, then Dec 1 -> Dec 31; with the defect Nov 29, then Nov 30 -> Dec 29.)
select is((:'renewal2'::jsonb ->> 'ends_on')::date,
  (date_trunc('month', :'s'::date + interval '2 months') + interval '1 month' - interval '1 day')::date,
  'the second renewal ends at the month end two months after S (no permanent drift)');

select * from finish();
rollback;
