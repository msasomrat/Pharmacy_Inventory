-- Functional tests for inventory, purchasing, customer dues and loyalty RPCs:
--   add_opening_stock, adjust_stock, set_batch_price, search_medicines, receive_goods,
--   record_supplier_payment, process_purchase_return, record_customer_payment, enroll_loyalty,
--   cancel_loyalty_membership, replace_loyalty_card, lookup_loyalty,
-- followed by ledger / projection invariants over everything the file posted.
-- Business dates come from app.business_date(org) (Asia/Dhaka), never current_date.
begin;
select plan(216);

-- =============================================================================================
-- Setup: two organizations, staff with different roles and branches, catalog, suppliers
-- =============================================================================================
select tests.create_user('owner@t110.test') as owner \gset
select tests.create_user('manager@t110.test') as manager \gset
select tests.create_user('sales@t110.test') as sales \gset
select tests.create_user('managerb@t110.test') as managerb \gset
select tests.create_user('acct@t110.test') as acct \gset
select tests.create_user('outsider@t110.test') as outsider \gset

select tests.authenticate_as(:'owner');
select public.create_organization('Domain Pharmacy', 'Mohammadpur', 'MPR') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select public.create_branch(:'org', 'DHN', 'Dhanmondi') as branch_b \gset
select app.business_date(:'org') as today \gset
select tests.add_member(:'org', 'manager@t110.test', 'manager', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'sales@t110.test', 'salesman', array[:'branch']::uuid[]);
select tests.add_member(:'org', 'managerb@t110.test', 'manager', array[:'branch_b']::uuid[]);
select tests.add_member(:'org', 'acct@t110.test', 'accountant');

insert into public.manufacturers (organization_id, name) values (:'org', 'Beximco') returning id as mfr \gset
insert into public.generics (organization_id, name) values (:'org', 'Paracetamol') returning id as g_para \gset
insert into public.generics (organization_id, name) values (:'org', 'Omeprazole') returning id as g_omep \gset
insert into public.medicines (organization_id, brand_name, generic_id, manufacturer_id, dosage_form, strength, base_unit_label)
  values (:'org', 'Napa', :'g_para', :'mfr', 'tablet', '500 mg', 'tablet') returning id as napa \gset
insert into public.medicines (organization_id, brand_name, generic_id, dosage_form, strength, base_unit_label)
  values (:'org', 'Ace', :'g_para', 'tablet', '500 mg', 'tablet') returning id as ace \gset
insert into public.medicines (organization_id, brand_name, generic_id, dosage_form, strength, base_unit_label)
  values (:'org', 'Napadol', :'g_para', 'tablet', '665 mg', 'tablet') returning id as napadol \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Panapa', 'syrup', '120 mg', 'bottle') returning id as panapa \gset
insert into public.medicines (organization_id, brand_name, generic_id, dosage_form, strength, base_unit_label)
  values (:'org', 'Seclo', :'g_omep', 'capsule', '20 mg', 'capsule') returning id as seclo \gset
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'org', 'Zinc 50%', 'tablet', '20 mg', 'tablet') returning id as zinc \gset
insert into public.medicine_barcodes (organization_id, medicine_id, barcode) values (:'org', :'seclo', '8941100500012');
insert into public.medicine_barcodes (organization_id, medicine_id, barcode) values (:'org', :'napadol', '8941100500029');
update public.medicines set is_active = false where id = :'napadol';

insert into public.suppliers (organization_id, name, phone) values (:'org', 'Square Depot', '01711000000')
  returning id as supplier \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Renata Depot') returning id as supplier2 \gset
insert into public.suppliers (organization_id, name) values (:'org', 'Closed Depot') returning id as supplier_off \gset
update public.suppliers set is_active = false where id = :'supplier_off';

-- Second, unrelated tenant.
select tests.authenticate_as(:'outsider');
select public.create_organization('Other Pharmacy', 'Uttara', 'UTR') as org2 \gset
select id as branch2 from public.branches where organization_id = :'org2' \gset
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
  values (:'org2', 'Napa', 'tablet', 'tablet') returning id as napa2 \gset
insert into public.suppliers (organization_id, name) values (:'org2', 'Other Depot') returning id as supplier_o \gset
insert into public.customers (organization_id, name, phone) values (:'org2', 'Other Customer', '01911000009')
  returning id as cust_o \gset
select id as plan_o from public.loyalty_plans where organization_id = :'org2' and duration_months = 3 \gset

-- =============================================================================================
-- A. add_opening_stock
-- =============================================================================================
select jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', ' OB-NAPA ', 'expiry_date', :'today'::date + 200,
    'quantity', 100, 'cost_paisa', 70, 'mrp_paisa', 120, 'sale_price_paisa', 115),
  jsonb_build_object('medicine_id', :'ace', 'batch_no', 'OB-ACE', 'expiry_date', :'today'::date + 200,
    'quantity', 40, 'cost_paisa', 60, 'mrp_paisa', 100, 'sale_price_paisa', 100)
)::text as ob_items \gset
select gen_random_uuid() as ob_req \gset

select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.add_opening_stock(%L, %L::jsonb, gen_random_uuid()) $$, :'branch', :'ob_items'),
  'P0001', 'Permission denied: stock.adjust', 'add_opening_stock: a salesman cannot load opening stock');

select tests.authenticate_as(:'manager', 'aal1');
select throws_ok(format($$ select public.add_opening_stock(%L, %L::jsonb, gen_random_uuid()) $$, :'branch', :'ob_items'),
  'P0001', 'Two-factor authentication is required',
  'add_opening_stock: a manager without a TOTP-verified (aal2) session is refused while the org enforces MFA');

select tests.authenticate_as(:'manager');
select is(public.add_opening_stock(:'branch', :'ob_items'::jsonb, :'ob_req'), 2,
  'add_opening_stock: returns the number of lines posted');
select id as ob_napa from public.batches where branch_id = :'branch' and batch_no = 'OB-NAPA' \gset
select id as ob_ace from public.batches where branch_id = :'branch' and batch_no = 'OB-ACE' \gset
select is((select quantity_on_hand from public.batches where id = :'ob_napa'), 100,
  'add_opening_stock: the opening quantity lands on the batch (batch number trimmed)');
select is((select format('%s/%s/%s', movement_type, quantity, reference_type)
             from public.inventory_movements where batch_id = :'ob_napa'),
  'opening_balance/100/opening_stock', 'add_opening_stock: one opening_balance movement of +100 is written');
select is(public.add_opening_stock(:'branch', :'ob_items'::jsonb, :'ob_req'), 2,
  'add_opening_stock: replaying the same request returns the original line count');
select is((select count(*)::int from public.batches where branch_id = :'branch' and batch_no like 'OB-%'), 2,
  'add_opening_stock: a replayed request creates no extra batches');
select is((select line_count from public.opening_stock_loads where client_request_id = :'ob_req'), 2,
  'add_opening_stock: the load is recorded once with its line count');

select throws_ok(format($$ select public.add_opening_stock(%L, '[{"medicine_id": "%s", "batch_no": "X1", "expiry_date": "%s",
    "quantity": 0, "cost_paisa": 1, "mrp_paisa": 10, "sale_price_paisa": 10}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'napa', :'today'::date + 10),
  'P0001', 'Quantity must be greater than zero', 'add_opening_stock: a zero quantity is rejected');
select throws_ok(format($$ select public.add_opening_stock(%L, '[{"medicine_id": "%s", "batch_no": "X1", "expiry_date": "%s",
    "quantity": 5, "cost_paisa": 1, "mrp_paisa": 10, "sale_price_paisa": 10}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'napa', :'today'),
  'P0001', 'Expiry date must be in the future', 'add_opening_stock: a lot expiring on the business date is rejected');
select throws_ok(format($$ select public.add_opening_stock(%L, '[{"medicine_id": "%s", "batch_no": "X1", "expiry_date": "%s",
    "quantity": 5, "cost_paisa": 1, "mrp_paisa": 10, "sale_price_paisa": 11}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'napa', :'today'::date + 10),
  'P0001', 'Sale price must be greater than zero and not above MRP', 'add_opening_stock: a sale price above MRP is rejected');
select throws_ok(format($$ select public.add_opening_stock(%L, '[{"medicine_id": "%s", "batch_no": "X1", "expiry_date": "%s",
    "quantity": 5, "cost_paisa": -1, "mrp_paisa": 10, "sale_price_paisa": 10}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'napa', :'today'::date + 10),
  'P0001', 'Cost cannot be negative', 'add_opening_stock: a negative cost is rejected');
select throws_ok(format($$ select public.add_opening_stock(%L, '[{"medicine_id": "%s", "batch_no": "X1", "expiry_date": "%s",
    "quantity": 5, "cost_paisa": 1, "mrp_paisa": 10, "sale_price_paisa": 10}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'napadol', :'today'::date + 10),
  'P0001', 'Medicine not found or inactive', 'add_opening_stock: an inactive medicine is rejected');
select throws_ok(format($$ select public.add_opening_stock(%L, '[{"medicine_id": "%s", "batch_no": "X1", "expiry_date": "%s",
    "quantity": 5, "cost_paisa": 1, "mrp_paisa": 10, "sale_price_paisa": 10}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'napa2', :'today'::date + 10),
  'P0001', 'Medicine not found or inactive', 'add_opening_stock: a medicine of another organization is rejected');
select throws_ok(format($$ select public.add_opening_stock(%L, '[]'::jsonb, gen_random_uuid()) $$, :'branch'),
  'P0001', 'Provide between 1 and 1000 items', 'add_opening_stock: an empty item list is rejected');
select throws_ok(format($$ select public.add_opening_stock(%L, %L::jsonb, gen_random_uuid()) $$, :'branch_b', :'ob_items'),
  'P0001', 'You do not have access to this branch', 'add_opening_stock: a manager cannot load stock into an unassigned branch');

select tests.authenticate_as(:'owner');
select throws_ok(format($$ select public.add_opening_stock(%L, %L::jsonb, %L) $$, :'branch_b', :'ob_items', :'ob_req'),
  'P0001', 'This request id was already used for another operation',
  'add_opening_stock: a request id already used for another branch is refused');

select tests.clear_authentication();
select is((select cost_paisa from public.batches where id = :'ob_napa'), 70::bigint,
  'add_opening_stock: the batch cost is taken from cost_paisa');

-- =============================================================================================
-- B. adjust_stock (OB-NAPA starts at 100)
-- =============================================================================================
select gen_random_uuid() as adj_req \gset
select tests.authenticate_as(:'manager');
select public.adjust_stock(:'ob_napa', -5, 'damage', :'adj_req', 'Crushed strip') as adj_damage \gset
select is((select quantity_on_hand from public.batches where id = :'ob_napa'), 95, 'adjust_stock: damage -5 reduces stock to 95');
select is((select format('%s/%s/%s/%s', movement_type, quantity, reference_type, note) from public.inventory_movements
            where reference_id = :'adj_damage'),
  'adjustment/-5/stock_adjustment/Crushed strip', 'adjust_stock: damage posts an adjustment movement carrying the note');
select is((select format('%s/%s/%s', reason, quantity_delta, created_by = :'manager'::uuid) from public.stock_adjustments
            where id = :'adj_damage'),
  'damage/-5/t', 'adjust_stock: the adjustment row records reason, delta and the acting user');

select public.adjust_stock(:'ob_napa', -2, 'loss', gen_random_uuid());
select public.adjust_stock(:'ob_napa', -1, 'theft', gen_random_uuid());
select is((select quantity_on_hand from public.batches where id = :'ob_napa'), 92, 'adjust_stock: loss -2 and theft -1 reduce stock to 92');
select is((select count(*)::int from public.inventory_movements where batch_id = :'ob_napa' and movement_type = 'adjustment'), 3,
  'adjust_stock: damage, loss and theft all post adjustment movements');

select public.adjust_stock(:'ob_napa', 3, 'count_correction', gen_random_uuid()) as adj_cc \gset
select is((select quantity_on_hand from public.batches where id = :'ob_napa'), 95, 'adjust_stock: a count correction can add stock (+3)');
select is((select movement_type::text from public.inventory_movements where reference_id = :'adj_cc'), 'count_correction',
  'adjust_stock: count_correction posts a count_correction movement');
select public.adjust_stock(:'ob_napa', -4, 'count_correction', gen_random_uuid());
select is((select quantity_on_hand from public.batches where id = :'ob_napa'), 91, 'adjust_stock: a count correction can remove stock (-4)');

select public.adjust_stock(:'ob_napa', -1, 'expired_writeoff', gen_random_uuid()) as adj_exp \gset
select is((select quantity_on_hand from public.batches where id = :'ob_napa'), 90, 'adjust_stock: an expiry write-off of -1 reduces stock');
select is((select format('%s/%s', movement_type, quantity) from public.inventory_movements where reference_id = :'adj_exp'),
  'expiry_writeoff/-1', 'adjust_stock: expired_writeoff posts a negative expiry_writeoff movement');
select throws_ok(format($$ select public.adjust_stock(%L, 1, 'expired_writeoff', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'An expiry write-off must reduce stock', 'adjust_stock: a positive expiry write-off is rejected');

select throws_ok(format($$ select public.adjust_stock(%L, 1, 'other', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'Explain an adjustment with reason "other" (at least 3 characters)', 'adjust_stock: reason "other" without a note is rejected');
select throws_ok(format($$ select public.adjust_stock(%L, 1, 'other', gen_random_uuid(), '  ab  ') $$, :'ob_napa'),
  'P0001', 'Explain an adjustment with reason "other" (at least 3 characters)',
  'adjust_stock: reason "other" with a note shorter than 3 characters after trimming is rejected');
select public.adjust_stock(:'ob_napa', 2, 'other', gen_random_uuid(), '  Found behind shelf  ') as adj_other \gset
select is((select quantity_on_hand from public.batches where id = :'ob_napa'), 92, 'adjust_stock: reason "other" with a note is accepted (+2)');
select is((select note from public.stock_adjustments where id = :'adj_other'), 'Found behind shelf',
  'adjust_stock: the note is stored trimmed');

select throws_ok(format($$ select public.adjust_stock(%L, 5, 'opening_balance', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'Use add_opening_stock for opening balances', 'adjust_stock: reason opening_balance is refused');
select throws_ok(format($$ select public.adjust_stock(%L, 0, 'damage', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'Adjustment quantity cannot be zero', 'adjust_stock: a zero delta is rejected');
select throws_ok(format($$ select public.adjust_stock(%L, -1000, 'loss', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'Not enough stock in this batch', 'adjust_stock: an adjustment cannot drive stock negative');
select ok(public.adjust_stock(:'ob_napa', -5, 'damage', :'adj_req', 'Crushed strip') = :'adj_damage'::uuid
          and (select quantity_on_hand from public.batches where id = :'ob_napa') = 92,
  'adjust_stock: replaying a request returns the original adjustment and changes no stock');
select throws_ok(format($$ select public.adjust_stock(%L, -1, 'damage', %L) $$, :'ob_ace', :'adj_req'),
  'P0001', 'This request id was already used for another operation', 'adjust_stock: a request id reused for another batch is refused');
select throws_ok($$ select public.adjust_stock(gen_random_uuid(), -1, 'damage', gen_random_uuid()) $$,
  'P0001', 'Batch not found', 'adjust_stock: an unknown batch is reported');

select tests.authenticate_as(:'manager', 'aal1');
select throws_ok(format($$ select public.adjust_stock(%L, -1, 'damage', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'Two-factor authentication is required', 'adjust_stock: a manager needs an aal2 session');
select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.adjust_stock(%L, -1, 'damage', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'Permission denied: stock.adjust', 'adjust_stock: a salesman cannot adjust stock');
select is((select count(*)::int from public.stock_adjustments), 0, 'adjust_stock: a salesman cannot list stock adjustments');
select tests.authenticate_as(:'managerb');
select throws_ok(format($$ select public.adjust_stock(%L, -1, 'damage', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'You do not have access to this branch', 'adjust_stock: a manager of another branch cannot adjust this batch');
select tests.authenticate_as(:'outsider');
select throws_ok(format($$ select public.adjust_stock(%L, -1, 'damage', gen_random_uuid()) $$, :'ob_napa'),
  'P0001', 'You do not have access to this branch', 'adjust_stock: an owner of another organization cannot adjust this batch');

-- =============================================================================================
-- C. set_batch_price (OB-ACE: MRP 100, price 100)
-- =============================================================================================
select tests.authenticate_as(:'manager');
select throws_ok(format($$ select public.set_batch_price(%L, 101) $$, :'ob_ace'),
  'P0001', 'Sale price must be greater than zero and not above MRP', 'set_batch_price: a price above the current MRP is rejected');
select throws_ok(format($$ select public.set_batch_price(%L, 0) $$, :'ob_ace'),
  'P0001', 'Sale price must be greater than zero and not above MRP', 'set_batch_price: a zero price is rejected');
select throws_ok(format($$ select public.set_batch_price(%L, 90, 80) $$, :'ob_ace'),
  'P0001', 'Sale price must be greater than zero and not above MRP', 'set_batch_price: a new MRP below the new price is rejected');
select throws_ok(format($$ select public.set_batch_price(%L, 90, 0) $$, :'ob_ace'),
  'P0001', 'Sale price must be greater than zero and not above MRP', 'set_batch_price: a zero MRP is rejected');
select lives_ok(format($$ select public.set_batch_price(%L, 95) $$, :'ob_ace'), 'set_batch_price: a price cut within MRP is accepted');
select is((select format('%s/%s', sale_price_paisa, mrp_paisa) from public.batches where id = :'ob_ace'), '95/100',
  'set_batch_price: the MRP is kept when not given');
select lives_ok(format($$ select public.set_batch_price(%L, 110, 110) $$, :'ob_ace'),
  'set_batch_price: raising MRP and price together is accepted');
select is((select format('%s/%s', sale_price_paisa, mrp_paisa) from public.batches where id = :'ob_ace'), '110/110',
  'set_batch_price: new MRP and price are stored');
select throws_ok($$ select public.set_batch_price(gen_random_uuid(), 10) $$, 'P0001', 'Batch not found',
  'set_batch_price: an unknown batch is reported');
select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.set_batch_price(%L, 50) $$, :'ob_ace'),
  'P0001', 'Permission denied: pricing.manage', 'set_batch_price: a salesman cannot change prices');
select tests.authenticate_as(:'managerb');
select throws_ok(format($$ select public.set_batch_price(%L, 50) $$, :'ob_ace'),
  'P0001', 'You do not have access to this branch', 'set_batch_price: a manager of another branch cannot change this price');

select tests.clear_authentication();
select is((select count(*)::int from audit.log where table_name = 'public.batches' and record_id = :'ob_ace' and action = 'UPDATE'), 2,
  'set_batch_price: each price change writes one audit entry');
select ok((select old_data ->> 'sale_price_paisa' = '95' and new_data ->> 'sale_price_paisa' = '110'
                  and old_data ->> 'mrp_paisa' = '100' and new_data ->> 'mrp_paisa' = '110'
                  and changed_fields @> array['mrp_paisa', 'sale_price_paisa']
                  and actor_id = :'manager'::uuid and organization_id = :'org'::uuid and branch_id = :'branch'::uuid
             from audit.log where table_name = 'public.batches' and record_id = :'ob_ace' order by id desc limit 1),
  'set_batch_price: the audit entry holds before/after prices, the actor, the organization and the branch');

-- =============================================================================================
-- D. search_medicines
-- Branch A Napa lots: OB-NAPA 92 @115 (+200d), NA-SOON 30 @110 (+20d), NA-EXP 10 @100 (expired),
-- NA-TODAY 7 @105 (expires today). Branch B: OB-B-NAPA 500 @118.
-- =============================================================================================
select tests.authenticate_as(:'owner');
select public.add_opening_stock(:'branch', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-SOON', 'expiry_date', :'today'::date + 20,
    'quantity', 30, 'cost_paisa', 70, 'mrp_paisa', 120, 'sale_price_paisa', 110),
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-EXP', 'expiry_date', :'today'::date + 10,
    'quantity', 10, 'cost_paisa', 70, 'mrp_paisa', 120, 'sale_price_paisa', 100),
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-TODAY', 'expiry_date', :'today'::date + 5,
    'quantity', 7, 'cost_paisa', 70, 'mrp_paisa', 120, 'sale_price_paisa', 105),
  jsonb_build_object('medicine_id', :'seclo', 'batch_no', 'SE-OB', 'expiry_date', :'today'::date + 300,
    'quantity', 25, 'cost_paisa', 500, 'mrp_paisa', 700, 'sale_price_paisa', 700)
), gen_random_uuid());
select public.add_opening_stock(:'branch_b', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'OB-B-NAPA', 'expiry_date', :'today'::date + 200,
    'quantity', 500, 'cost_paisa', 70, 'mrp_paisa', 120, 'sale_price_paisa', 118)
), gen_random_uuid());
-- Time passes: one lot has expired, another expires today (lots cannot be received already expired).
select tests.clear_authentication();
update public.batches set expiry_date = :'today'::date - 1 where branch_id = :'branch' and batch_no = 'NA-EXP';
update public.batches set expiry_date = :'today'::date where branch_id = :'branch' and batch_no = 'NA-TODAY';
select id as ob_b_napa from public.batches where batch_no = 'OB-B-NAPA' \gset

select tests.authenticate_as(:'sales', 'aal1');
select is(array(select brand_name from public.search_medicines(:'branch', 'nap')), array['Napa', 'Panapa'],
  'search_medicines: brand search is case-insensitive and ranks a prefix match above a substring match');
select is((select count(*)::int from public.search_medicines(:'branch', 'Napadol')), 0,
  'search_medicines: an inactive medicine is not found by name');
select is(array(select brand_name from public.search_medicines(:'branch', 'paracet')), array['Ace', 'Napa'],
  'search_medicines: a generic name finds every active brand of that generic');
select is((select format('%s/%s', generic_name, schedule) from public.search_medicines(:'branch', 'Seclo')), 'Omeprazole/otc',
  'search_medicines: the generic name and schedule are returned');
select is(array(select brand_name from public.search_medicines(:'branch', '8941100500012')), array['Seclo'],
  'search_medicines: an exact barcode finds its medicine');
select is((select count(*)::int from public.search_medicines(:'branch', '89411005000')), 0,
  'search_medicines: a partial barcode does not match');
select is((select count(*)::int from public.search_medicines(:'branch', '8941100500029')), 0,
  'search_medicines: the barcode of an inactive medicine does not match');
select is((select count(*)::int from public.search_medicines(:'branch', 'N_pa')), 0,
  'search_medicines: "_" in the query is matched literally, not as a LIKE wildcard');
select is((select count(*)::int from public.search_medicines(:'branch', '%%')), 0,
  'search_medicines: "%%" in the query is matched literally and does not list the whole catalog');
select is(array(select brand_name from public.search_medicines(:'branch', '50%')), array['Zinc 50%'],
  'search_medicines: a literal "%" in a brand name can be searched');
select is((select format('%s/%s', stock_quantity, coalesce(sale_price_paisa::text, 'none'))
             from public.search_medicines(:'branch', 'Zinc')), '0/none',
  'search_medicines: a medicine without stock shows zero stock and no price');
select is((select count(*)::int from public.search_medicines(:'branch', 'N')), 0,
  'search_medicines: a one-character query returns nothing');
select is((select stock_quantity from public.search_medicines(:'branch', 'Napa') where brand_name = 'Napa'), 122::bigint,
  'search_medicines: stock excludes expired lots, lots expiring on the business date and other branches (92 + 30)');
select is((select format('%s/%s', sale_price_paisa, nearest_expiry) from public.search_medicines(:'branch', 'Napa')
            where brand_name = 'Napa'),
  format('%s/%s', 110, :'today'::date + 20),
  'search_medicines: FEFO price and nearest expiry come from the earliest sellable lot, not the expired one');

select tests.authenticate_as(:'owner');
update public.organization_settings set near_expiry_block_days = 30 where organization_id = :'org';
select tests.authenticate_as(:'sales', 'aal1');
select is((select format('%s/%s/%s', stock_quantity, sale_price_paisa, nearest_expiry)
             from public.search_medicines(:'branch', 'Napa') where brand_name = 'Napa'),
  format('%s/%s/%s', 92, 115, :'today'::date + 200),
  'search_medicines: lots inside the near-expiry sale block are excluded from stock and price');
select is((public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 1)),
             '[{"method": "cash", "amount_paisa": 115}]'::jsonb, gen_random_uuid()) ->> 'total_paisa')::bigint, 115::bigint,
  'search_medicines: the sale charges the same FEFO price the search shows');
select tests.authenticate_as(:'owner');
update public.organization_settings set near_expiry_block_days = 0 where organization_id = :'org';

select tests.authenticate_as(:'managerb');
select is((select format('%s/%s', stock_quantity, sale_price_paisa) from public.search_medicines(:'branch_b', 'Napa')
            where brand_name = 'Napa'), '500/118',
  'search_medicines: each branch sees only its own stock and price');
select throws_ok(format($$ select * from public.search_medicines(%L, 'Napa') $$, :'branch'),
  'P0001', 'You do not have access to this branch', 'search_medicines: a manager cannot search an unassigned branch');
select tests.authenticate_as(:'outsider');
select is(array(select medicine_id from public.search_medicines(:'branch2', 'Napa')), array[:'napa2'::uuid],
  'search_medicines: another organization sees only its own catalog');
select tests.authenticate_as_anon();
select throws_ok(format($$ select * from public.search_medicines(%L, 'Napa') $$, :'branch'),
  '42501', null, 'search_medicines: anon cannot call the search');
select tests.clear_authentication();

-- =============================================================================================
-- E. receive_goods
-- Lines: Ace 3 x 333 = 999; Seclo 7 x 143 = 1001 (+2 bonus); Napa 6 x 5 = 30 (+2 bonus).
-- Subtotal 2030, discount 100 -> largest remainder shares 49 / 49 / 2; total 1930; paid 500.
-- Costs: 950/3 = 316.67 -> 317; 952/9 = 105.78 -> 106; 28/8 = 3.5 -> 4 (half up).
-- =============================================================================================
select gen_random_uuid() as grn_req \gset
select jsonb_build_array(
  jsonb_build_object('medicine_id', :'ace', 'batch_no', 'AC-G1', 'expiry_date', :'today'::date + 365,
    'quantity', 3, 'unit_cost_paisa', 333, 'mrp_paisa', 500, 'sale_price_paisa', 450),
  jsonb_build_object('medicine_id', :'seclo', 'batch_no', 'SE-G1', 'expiry_date', :'today'::date + 365,
    'quantity', 7, 'bonus_quantity', 2, 'unit_cost_paisa', 143, 'mrp_paisa', 300, 'sale_price_paisa', 300),
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'NA-G1', 'expiry_date', :'today'::date + 365,
    'quantity', 6, 'bonus_quantity', 2, 'unit_cost_paisa', 5, 'mrp_paisa', 120, 'sale_price_paisa', 120)
)::text as grn_items \gset

select tests.authenticate_as(:'manager');
select public.receive_goods(:'branch', :'supplier', :'grn_items'::jsonb, :'grn_req', 'SQ-1001', :'today'::date,
  100, 500, 'bkash', '  first delivery  ') as grn \gset
select (:'grn'::jsonb ->> 'goods_receipt_id') as grn_id \gset

select is((:'grn'::jsonb ->> 'total_paisa')::bigint, 1930::bigint, 'receive_goods: total = subtotal 2030 - invoice discount 100');
select is((select format('%s/%s/%s/%s/%s', subtotal_paisa, discount_paisa, total_paisa, paid_paisa, note)
             from public.goods_receipts where id = :'grn_id'),
  '2030/100/1930/500/first delivery', 'receive_goods: the receipt header stores subtotal, discount, total, paid and trimmed note');
select is(array(select discount_paisa from public.goods_receipt_items where goods_receipt_id = :'grn_id' order by line_total_paisa),
  array[2, 49, 49]::bigint[], 'receive_goods: the invoice discount is allocated proportionally (largest remainder) and sums to 100');
select is(array(select quantity_on_hand from public.batches where branch_id = :'branch' and batch_no in ('AC-G1', 'NA-G1', 'SE-G1')
                 order by batch_no),
  array[3, 8, 9], 'receive_goods: paid plus bonus units are stocked');
select is((select sum(quantity)::int from public.inventory_movements
            where reference_type = 'goods_receipt' and reference_id = :'grn_id' and movement_type = 'purchase_receipt'), 20,
  'receive_goods: purchase_receipt movements cover paid and bonus units');
select is(array(select amount_paisa from public.supplier_ledger_entries where reference_id = :'grn_id' order by id),
  array[1930, -500]::bigint[], 'receive_goods: the supplier ledger is credited with the total and debited with the payment');
select is((select format('%s/%s/%s', amount_paisa, method, goods_receipt_id = :'grn_id'::uuid) from public.supplier_payments
            where goods_receipt_id = :'grn_id'),
  '500/bkash/t', 'receive_goods: the payment made with the receipt is recorded against it');
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier'), 1430::bigint,
  'receive_goods: supplier due = 1930 - 500');

select public.receive_goods(:'branch', :'supplier', :'grn_items'::jsonb, :'grn_req', 'SQ-1001', :'today'::date,
  100, 500, 'bkash') as grn_replay \gset
select ok((:'grn_replay'::jsonb ->> 'replayed')::boolean and :'grn_replay'::jsonb ->> 'goods_receipt_id' = :'grn_id',
  'receive_goods: replaying the request returns the original receipt');
select ok((select count(*) from public.batches where branch_id = :'branch' and batch_no in ('AC-G1', 'NA-G1', 'SE-G1')) = 3
          and (select balance_paisa from public.supplier_balances where supplier_id = :'supplier') = 1430,
  'receive_goods: a replay creates no batches and posts nothing to the supplier ledger');

select tests.clear_authentication();
select is(array(select cost_paisa from public.batches where branch_id = :'branch' and batch_no in ('AC-G1', 'NA-G1', 'SE-G1')
                 order by batch_no),
  array[317, 4, 106]::bigint[],
  'receive_goods: batch cost = net line amount / (paid + bonus units), rounded half up (950/3, 28/8, 952/9)');

select tests.authenticate_as(:'manager');
select lives_ok(format($$ select public.receive_goods(%L, %L, '[
    {"medicine_id": "%s", "batch_no": "SHARED-1", "expiry_date": "%s", "quantity": 1, "unit_cost_paisa": 10, "mrp_paisa": 20, "sale_price_paisa": 20},
    {"medicine_id": "%s", "batch_no": "SHARED-1", "expiry_date": "%s", "quantity": 1, "unit_cost_paisa": 10, "mrp_paisa": 20, "sale_price_paisa": 20}
  ]'::jsonb, gen_random_uuid(), null, null, 0, 20) $$, :'branch', :'supplier', :'ace', :'today'::date + 100, :'seclo', :'today'::date + 100),
  'receive_goods: the same batch number may be received for two different medicines');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[
    {"medicine_id": "%s", "batch_no": "DUP-1", "expiry_date": "%s", "quantity": 1, "unit_cost_paisa": 10, "mrp_paisa": 20, "sale_price_paisa": 20},
    {"medicine_id": "%s", "batch_no": " dup-1 ", "expiry_date": "%s", "quantity": 2, "unit_cost_paisa": 10, "mrp_paisa": 20, "sale_price_paisa": 20}
  ]'::jsonb, gen_random_uuid()) $$, :'branch', :'supplier', :'ace', :'today'::date + 100, :'ace', :'today'::date + 100),
  'P0001', 'Each medicine batch may appear only once',
  'receive_goods: duplicate medicine + batch lines (case and space insensitive) are rejected');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid(), null, null, 0, 1001) $$,
    :'branch', :'supplier', :'ace', :'today'::date + 100),
  'P0001', 'Paid amount must be between zero and the total', 'receive_goods: paying more than the invoice total is rejected');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid(), null, null, 600, 500) $$,
    :'branch', :'supplier', :'ace', :'today'::date + 100),
  'P0001', 'Paid amount must be between zero and the total', 'receive_goods: paid is checked against the total after discount');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid(), null, null, 1001) $$,
    :'branch', :'supplier', :'ace', :'today'::date + 100),
  'P0001', 'Discount must be between zero and the subtotal', 'receive_goods: a discount above the subtotal is rejected');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid(), null, null, 0, 100, 'loyalty_points') $$,
    :'branch', :'supplier', :'ace', :'today'::date + 100),
  'P0001', 'Loyalty points cannot pay suppliers', 'receive_goods: loyalty points cannot pay a supplier');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "bonus_quantity": -1, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'supplier', :'ace', :'today'::date + 100),
  'P0001', 'Quantity must be greater than zero and bonus cannot be negative', 'receive_goods: a negative bonus quantity is rejected');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "  ", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'supplier', :'ace', :'today'::date + 100),
  'P0001', 'Batch number is required', 'receive_goods: a blank batch number is rejected');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid(), 'F-1', %L) $$,
    :'branch', :'supplier', :'ace', :'today'::date + 100, :'today'::date + 1),
  'P0001', 'Supplier invoice date cannot be in the future', 'receive_goods: a future supplier invoice date is rejected');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid(), 'sq-1001') $$,
    :'branch', :'supplier', :'ace', :'today'::date + 100),
  '23505', null, 'receive_goods: the same supplier invoice number (any case) cannot be received twice');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'supplier_off', :'ace', :'today'::date + 100),
  'P0001', 'Supplier not found or inactive', 'receive_goods: an inactive supplier is rejected');
select throws_ok(format($$ select public.receive_goods(%L, %L, '[{"medicine_id": "%s", "batch_no": "P1", "expiry_date": "%s",
    "quantity": 10, "unit_cost_paisa": 100, "mrp_paisa": 200, "sale_price_paisa": 200}]'::jsonb, gen_random_uuid()) $$,
    :'branch', :'supplier_o', :'ace', :'today'::date + 100),
  'P0001', 'Supplier not found or inactive', 'receive_goods: a supplier of another organization is rejected');
select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.receive_goods(%L, %L, %L::jsonb, gen_random_uuid()) $$, :'branch', :'supplier', :'grn_items'),
  'P0001', 'Permission denied: purchases.receive', 'receive_goods: a salesman cannot receive goods');
select tests.authenticate_as(:'acct');
select throws_ok(format($$ select public.receive_goods(%L, %L, %L::jsonb, gen_random_uuid()) $$, :'branch', :'supplier', :'grn_items'),
  'P0001', 'Permission denied: purchases.receive', 'receive_goods: an accountant cannot receive goods');

-- =============================================================================================
-- F. record_supplier_payment (Square Depot due 1430)
-- =============================================================================================
select gen_random_uuid() as pay_req \gset
select tests.authenticate_as(:'manager');
select public.record_supplier_payment(:'supplier', 400, 'cash', :'pay_req', :'branch', ' CHQ-1 ', ' part payment ') as pay1 \gset
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier'), 1030::bigint,
  'record_supplier_payment: a payment of 400 reduces the due to 1030');
select is((select format('%s/%s/%s/%s', entry_type, amount_paisa, reference_type, branch_id = :'branch'::uuid)
             from public.supplier_ledger_entries where reference_id = :'pay1'),
  'payment/-400/supplier_payment/t', 'record_supplier_payment: one negative payment ledger entry is posted');
select is((select format('%s/%s/%s/%s', amount_paisa, method, reference, note) from public.supplier_payments where id = :'pay1'),
  '400/cash/CHQ-1/part payment', 'record_supplier_payment: the payment stores method and trimmed reference and note');
select ok(public.record_supplier_payment(:'supplier', 400, 'cash', :'pay_req', :'branch') = :'pay1'::uuid
          and (select balance_paisa from public.supplier_balances where supplier_id = :'supplier') = 1030,
  'record_supplier_payment: replaying the request returns the original payment and pays nothing twice');
select throws_ok(format($$ select public.record_supplier_payment(%L, 401, 'cash', %L, %L) $$, :'supplier', :'pay_req', :'branch'),
  'P0001', 'This request id was already used for another payment', 'record_supplier_payment: a request id reused with another amount is refused');
select throws_ok(format($$ select public.record_supplier_payment(%L, 0, 'cash', gen_random_uuid(), %L) $$, :'supplier', :'branch'),
  'P0001', 'Amount must be greater than zero', 'record_supplier_payment: a zero amount is rejected');
select throws_ok(format($$ select public.record_supplier_payment(%L, 10, 'loyalty_points', gen_random_uuid(), %L) $$, :'supplier', :'branch'),
  'P0001', 'Loyalty points cannot pay suppliers', 'record_supplier_payment: loyalty points cannot pay a supplier');
select throws_ok($$ select public.record_supplier_payment(gen_random_uuid(), 10, 'cash', gen_random_uuid()) $$,
  'P0001', 'Supplier not found', 'record_supplier_payment: an unknown supplier is reported');
select tests.authenticate_as(:'managerb');
select throws_ok(format($$ select public.record_supplier_payment(%L, 10, 'cash', gen_random_uuid(), %L) $$, :'supplier', :'branch'),
  'P0001', 'You do not have access to this branch', 'record_supplier_payment: a manager cannot pay from an unassigned branch');
select throws_ok(format($$ select public.record_supplier_payment(%L, 10, 'cash', gen_random_uuid()) $$, :'supplier'),
  'P0001', 'Choose the branch this payment is made from',
  'record_supplier_payment: a Branch Manager cannot record an organization-level payment without a branch (P-41)');
select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.record_supplier_payment(%L, 10, 'cash', gen_random_uuid(), %L) $$, :'supplier', :'branch'),
  'P0001', 'Permission denied: suppliers.pay', 'record_supplier_payment: a salesman cannot pay suppliers (branch payment)');
select throws_ok(format($$ select public.record_supplier_payment(%L, 10, 'cash', gen_random_uuid()) $$, :'supplier'),
  'P0001', 'Permission denied: suppliers.pay', 'record_supplier_payment: a salesman cannot pay suppliers (head-office payment)');
select tests.authenticate_as(:'acct');
select public.record_supplier_payment(:'supplier', 100, 'bank_transfer', gen_random_uuid(), null, 'BT-77');
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier'), 930::bigint,
  'record_supplier_payment: an accountant can record a head-office payment (no branch)');
select tests.authenticate_as(:'outsider');
select throws_ok(format($$ select public.record_supplier_payment(%L, 10, 'cash', gen_random_uuid()) $$, :'supplier'),
  'P0001', 'Permission denied: suppliers.pay', 'record_supplier_payment: another organization cannot pay this supplier');
select throws_ok(format($$ select public.record_supplier_payment(%L, 10, 'cash', gen_random_uuid(), %L) $$, :'supplier', :'branch2'),
  'P0001', 'Branch belongs to another organization', 'record_supplier_payment: a branch of another organization is refused');

-- =============================================================================================
-- G. process_purchase_return
-- SE-G1: 9 units received for a net 952. NA-G1: 8 units for a net 28. AC-G1: 3 units for 950.
-- =============================================================================================
select tests.authenticate_as(:'manager');
select id as se_g1 from public.batches where branch_id = :'branch' and batch_no = 'SE-G1' \gset
select id as na_g1 from public.batches where branch_id = :'branch' and batch_no = 'NA-G1' \gset
select id as ac_g1 from public.batches where branch_id = :'branch' and batch_no = 'AC-G1' \gset
select gen_random_uuid() as ret_req \gset

select public.process_purchase_return(:'branch', :'supplier', jsonb_build_array(jsonb_build_object('batch_id', :'se_g1', 'quantity', 3)),
  ' near expiry ', :'ret_req', 'call depot') as ret1 \gset
select (:'ret1'::jsonb ->> 'purchase_return_id') as ret1_id \gset
select is((:'ret1'::jsonb ->> 'total_paisa')::bigint, 317::bigint,
  'process_purchase_return: 3 of 9 units are valued at round(952 x 3 / 9) = 317');
select is((select quantity_on_hand from public.batches where id = :'se_g1'), 6, 'process_purchase_return: returned units leave the batch');
select is((select format('%s/%s', movement_type, quantity) from public.inventory_movements
            where reference_type = 'purchase_return' and reference_id = :'ret1_id'),
  'purchase_return/-3', 'process_purchase_return: a negative purchase_return movement is posted');
select is((select format('%s/%s', entry_type, amount_paisa) from public.supplier_ledger_entries where reference_id = :'ret1_id'),
  'purchase_return/-317', 'process_purchase_return: the supplier ledger is debited with the returned value');
select ok((select pri.quantity = 3 and pri.unit_cost_paisa = 106 and pri.line_total_paisa = 317
                  and pri.goods_receipt_item_id = (select gri.id from public.goods_receipt_items gri where gri.batch_id = :'se_g1')
             from public.purchase_return_items pri where pri.purchase_return_id = :'ret1_id'),
  'process_purchase_return: the return line links the originating receipt line, lot cost and value');
select is((select format('%s/%s', reason, note) from public.purchase_returns where id = :'ret1_id'), 'near expiry/call depot',
  'process_purchase_return: reason and note are stored trimmed');
select ok((public.process_purchase_return(:'branch', :'supplier', jsonb_build_array(jsonb_build_object('batch_id', :'se_g1', 'quantity', 3)),
             'near expiry', :'ret_req') ->> 'purchase_return_id') = :'ret1_id'
          and (select quantity_on_hand from public.batches where id = :'se_g1') = 6,
  'process_purchase_return: replaying the request returns the original return and moves no stock');

select is((public.process_purchase_return(:'branch', :'supplier', jsonb_build_array(jsonb_build_object('batch_id', :'se_g1', 'quantity', 6)),
             'near expiry', gen_random_uuid()) ->> 'total_paisa')::bigint, 635::bigint,
  'process_purchase_return: returning the rest is valued 952 - 317 = 635, clearing exactly the invoiced net amount');
select is((select format('%s/%s', quantity_on_hand, is_depleted) from public.batches where id = :'se_g1'), '0/t',
  'process_purchase_return: the fully returned lot is depleted');

select public.process_purchase_return(:'branch', :'supplier', jsonb_build_array(
  jsonb_build_object('batch_id', :'na_g1', 'quantity', 1), jsonb_build_object('batch_id', :'na_g1', 'quantity', 2)),
  'damaged cartons', gen_random_uuid()) as ret3 \gset
select is((select format('%s/%s/%s', count(*), sum(quantity), sum(line_total_paisa)) from public.purchase_return_items
            where purchase_return_id = (:'ret3'::jsonb ->> 'purchase_return_id')::uuid),
  '1/3/11', 'process_purchase_return: repeated lines for one lot are merged (3 units, round(28 x 3 / 8) = 10.5 -> 11)');

select public.adjust_stock(:'ac_g1', -2, 'damage', gen_random_uuid());
select throws_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 2}]'::jsonb, 'expired', gen_random_uuid()) $$,
    :'branch', :'supplier', :'ac_g1'),
  'P0001', 'Not enough stock in this batch', 'process_purchase_return: cannot return more than is on hand');
select throws_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 1}]'::jsonb, 'expired', gen_random_uuid()) $$,
    :'branch', :'supplier', :'ob_ace'),
  'P0001', 'Only stock received from a supplier can be returned to a supplier', 'process_purchase_return: opening stock cannot be returned');
select throws_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 1}]'::jsonb, 'expired', gen_random_uuid()) $$,
    :'branch', :'supplier2', :'na_g1'),
  'P0001', 'This batch was received from a different supplier', 'process_purchase_return: a lot cannot be returned to another supplier');
select throws_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 1}]'::jsonb, 'ab', gen_random_uuid()) $$,
    :'branch', :'supplier', :'na_g1'),
  'P0001', 'A reason is required', 'process_purchase_return: a reason of at least 3 characters is required');
select throws_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 0}]'::jsonb, 'expired', gen_random_uuid()) $$,
    :'branch', :'supplier', :'na_g1'),
  'P0001', 'Quantity must be greater than zero', 'process_purchase_return: a zero quantity is rejected');
select throws_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 1}]'::jsonb, 'expired', gen_random_uuid()) $$,
    :'branch', :'supplier', :'ob_b_napa'),
  'P0001', 'Batch not found in this branch', 'process_purchase_return: a lot of another branch cannot be returned from this branch');
select throws_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 1}]'::jsonb, 'expired', gen_random_uuid()) $$,
    :'branch', :'supplier', gen_random_uuid()),
  'P0001', 'Batch not found in this branch', 'process_purchase_return: an unknown lot is rejected');
select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.process_purchase_return(%L, %L, '[{"batch_id": "%s", "quantity": 1}]'::jsonb, 'expired', gen_random_uuid()) $$,
    :'branch', :'supplier', :'na_g1'),
  'P0001', 'Permission denied: purchases.return', 'process_purchase_return: a salesman cannot return goods');

select tests.authenticate_as(:'manager');
select is((select balance_paisa from public.supplier_balances where supplier_id = :'supplier'), (930 - 317 - 635 - 11)::bigint,
  'process_purchase_return: supplier balance reflects all three returns (may go below zero: supplier owes us)');

-- =============================================================================================
-- H. record_customer_payment (Karim owes 1000 from an opening balance)
-- =============================================================================================
select tests.authenticate_as(:'owner');
insert into public.customers (organization_id, name, phone) values (:'org', 'Karim Uddin', '01811-223344') returning id as cust_due \gset
select tests.clear_authentication();
insert into public.customer_ledger_entries (organization_id, customer_id, branch_id, entry_type, amount_paisa, note)
  values (:'org', :'cust_due', :'branch', 'opening_balance', 1000, 'Imported due');

select gen_random_uuid() as cpay_req \gset
select tests.authenticate_as(:'sales', 'aal1');
select is(public.record_customer_payment(:'cust_due', :'branch', 300, 'bkash', :'cpay_req', ' TRX1 '), 700::bigint,
  'record_customer_payment: collecting 300 of a 1000 due returns the new balance 700');
select is((select format('%s/%s/%s/%s/%s', entry_type, amount_paisa, method, note, created_by = :'sales'::uuid)
             from public.customer_ledger_entries where client_request_id = :'cpay_req'),
  'payment/-300/bkash/TRX1/t', 'record_customer_payment: a negative payment entry with method, reference and collector is posted');
select ok(public.record_customer_payment(:'cust_due', :'branch', 300, 'bkash', :'cpay_req') = 700
          and (select count(*) from public.customer_ledger_entries where customer_id = :'cust_due' and entry_type = 'payment') = 1,
  'record_customer_payment: replaying the request returns the balance and records nothing twice');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 301, 'bkash', %L) $$, :'cust_due', :'branch', :'cpay_req'),
  'P0001', 'This request id was already used for another payment', 'record_customer_payment: a request id reused with another amount is refused');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 701, 'cash', gen_random_uuid()) $$, :'cust_due', :'branch'),
  'P0001', 'Payment is larger than the outstanding due', 'record_customer_payment: paying more than the due is refused');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 0, 'cash', gen_random_uuid()) $$, :'cust_due', :'branch'),
  'P0001', 'Amount must be greater than zero', 'record_customer_payment: a zero amount is rejected');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 10, 'loyalty_points', gen_random_uuid()) $$, :'cust_due', :'branch'),
  'P0001', 'Loyalty points cannot settle dues', 'record_customer_payment: loyalty points cannot settle a due');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 10, 'cash', gen_random_uuid()) $$, :'cust_o', :'branch'),
  'P0001', 'Customer not found', 'record_customer_payment: a customer of another organization is not found');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 10, 'cash', gen_random_uuid()) $$, :'cust_due', :'branch_b'),
  'P0001', 'You do not have access to this branch', 'record_customer_payment: a salesman cannot collect at an unassigned branch');
select tests.authenticate_as(:'acct');
select is(public.record_customer_payment(:'cust_due', :'branch', 100, 'cash', gen_random_uuid()), 600::bigint,
  'record_customer_payment: an accountant can collect dues');
select tests.authenticate_as(:'sales', 'aal1');
select is(public.record_customer_payment(:'cust_due', :'branch', 600, 'nagad', gen_random_uuid()), 0::bigint,
  'record_customer_payment: the full remaining due can be collected');
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 1, 'cash', gen_random_uuid()) $$, :'cust_due', :'branch'),
  'P0001', 'Payment is larger than the outstanding due', 'record_customer_payment: a customer without a due cannot pay');
select tests.authenticate_as_anon();
select throws_ok(format($$ select public.record_customer_payment(%L, %L, 1, 'cash', gen_random_uuid()) $$, :'cust_due', :'branch'),
  '42501', null, 'record_customer_payment: anon cannot call the function');
select tests.clear_authentication();

-- =============================================================================================
-- I. enroll_loyalty
-- 6-Month Card: free, 3% discount. 3-Month Card: 200 taka, 5% discount, points.
-- =============================================================================================
select tests.authenticate_as(:'owner');
update public.loyalty_plans set is_active = true, fee_paisa = 0, discount_bp = 300
 where organization_id = :'org' and duration_months = 6 returning id as plan_free \gset
update public.loyalty_plans set is_active = true, fee_paisa = 20000, discount_bp = 500, points_per_100_taka = 1, point_value_paisa = 100
 where organization_id = :'org' and duration_months = 3 returning id as plan_paid \gset
insert into public.loyalty_plans (organization_id, name, duration_months, discount_bp, is_active)
  values (:'org', 'Retired Plan', 12, 1000, false) returning id as plan_off \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Rahima Begum', '01711000001') returning id as c_free \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Jamal Hossain', '01711000002') returning id as c_paid \gset
insert into public.customers (organization_id, name) values (:'org', 'No Phone') returning id as c_nophone \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Gone Away', '01711000003') returning id as c_inactive \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Pre Printed', '01711000004') returning id as c_pre \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Late Comer', '01711000005') returning id as c_late \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Dup Card', '01711000006') returning id as c_dup \gset
insert into public.customers (organization_id, name, phone) values (:'org', 'Lapsed Member', '01711000007') returning id as c_lapsed \gset
update public.customers set is_active = false where id = :'c_inactive';
select tests.clear_authentication();
select '400001234' || app.luhn_check_digit('400001234') as good_card,
       '400001234' || ((app.luhn_check_digit('400001234') + 1) % 10) as bad_card,
       '400005678' || app.luhn_check_digit('400005678') as good_card2 \gset
-- A membership that ended yesterday (written directly: the RPCs only create current or future periods).
insert into public.loyalty_cards (organization_id, customer_id, card_no) values (:'org', :'c_lapsed', '7000000005')
  returning id as card_lapsed \gset
insert into public.loyalty_memberships (organization_id, card_id, customer_id, plan_id, branch_id, starts_on, ends_on,
  fee_paid_paisa, discount_bp, points_per_100_taka, point_value_paisa, min_redeem_points, client_request_id, created_by)
values (:'org', :'card_lapsed', :'c_lapsed', :'plan_free', :'branch', :'today'::date - 100, :'today'::date - 1,
  0, 300, 0, 0, 0, gen_random_uuid(), :'owner');

select gen_random_uuid() as enrol_req \gset
select tests.authenticate_as(:'sales', 'aal1');
select public.enroll_loyalty(:'c_free', :'plan_free', :'branch', :'enrol_req', null) as enrol_free \gset
select (:'enrol_free'::jsonb ->> 'membership_id') as m_free \gset
select (:'enrol_free'::jsonb ->> 'card_no') as card_free_no \gset
select is((:'enrol_free'::jsonb ->> 'starts_on')::date, :'today'::date, 'enroll_loyalty: a new membership starts on the business date');
select is((:'enrol_free'::jsonb ->> 'ends_on')::date,
  case when extract(day from :'today'::date + interval '6 months') < extract(day from :'today'::date)
       then (:'today'::date + interval '6 months')::date
       else (:'today'::date + interval '6 months')::date - 1 end,
  'enroll_loyalty: a 6-month membership ends the day before the same date six months later');
select is((select format('%s/%s/%s', fee_paid_paisa, coalesce(payment_method::text, 'none'), discount_bp)
             from public.loyalty_memberships where id = :'m_free'),
  '0/none/300', 'enroll_loyalty: a free plan collects no fee and needs no payment method; plan terms are snapshotted');
select ok(:'card_free_no' ~ '^[0-9]+$' and app.luhn_check_digit(left(:'card_free_no', -1)) = right(:'card_free_no', 1)::int,
  'enroll_loyalty: the generated card number carries a valid Luhn check digit');
select is(length(:'card_free_no'), 10, 'enroll_loyalty: generated card numbers have 10 digits including the check digit (CFG-25)');
select ok((public.enroll_loyalty(:'c_free', :'plan_free', :'branch', :'enrol_req', null) ->> 'membership_id') = :'m_free'
          and (select count(*) from public.loyalty_memberships where customer_id = :'c_free') = 1,
  'enroll_loyalty: replaying the request returns the original membership');

select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid(), null) $$, :'c_paid', :'plan_paid', :'branch'),
  'P0001', 'Choose how the membership fee is paid', 'enroll_loyalty: a paid plan needs a payment method');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid(), 'loyalty_points') $$, :'c_paid', :'plan_paid', :'branch'),
  'P0001', 'Choose how the membership fee is paid', 'enroll_loyalty: a membership fee cannot be paid with loyalty points');
select public.enroll_loyalty(:'c_paid', :'plan_paid', :'branch', gen_random_uuid(), 'bkash') as enrol_paid \gset
select (:'enrol_paid'::jsonb ->> 'membership_id') as m_paid \gset
select is((select format('%s/%s/%s', fee_paid_paisa, payment_method, discount_bp) from public.loyalty_memberships where id = :'m_paid'),
  '20000/bkash/500', 'enroll_loyalty: a paid plan records the fee and how it was paid');

select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'c_late', :'plan_off', :'branch'),
  'P0001', 'Loyalty plan not found or not active', 'enroll_loyalty: an inactive plan cannot be sold');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'c_late', :'plan_o', :'branch'),
  'P0001', 'Loyalty plan not found or not active', 'enroll_loyalty: a plan of another organization cannot be used');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'c_nophone', :'plan_free', :'branch'),
  'P0001', 'A mobile number is required for a loyalty card', 'enroll_loyalty: a customer without a phone number cannot enrol');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'c_inactive', :'plan_free', :'branch'),
  'P0001', 'Customer not found or inactive', 'enroll_loyalty: an inactive customer cannot enrol');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'cust_o', :'plan_free', :'branch'),
  'P0001', 'Customer not found or inactive', 'enroll_loyalty: a customer of another organization cannot enrol');

select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid(), 'cash', %L) $$, :'c_pre', :'plan_free', :'branch', :'bad_card'),
  'P0001', 'Card number is not valid', 'enroll_loyalty: a pre-printed card number with a bad Luhn digit is rejected');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid(), 'cash', 'CARD-1234') $$, :'c_pre', :'plan_free', :'branch'),
  'P0001', 'Card number is not valid', 'enroll_loyalty: a non-numeric card number is rejected');
select is(public.enroll_loyalty(:'c_pre', :'plan_free', :'branch', gen_random_uuid(), 'cash', ' ' || :'good_card' || ' ') ->> 'card_no',
  :'good_card', 'enroll_loyalty: a valid pre-printed card number is issued as given (trimmed)');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid(), 'cash', %L) $$, :'c_dup', :'plan_free', :'branch', :'good_card'),
  '23505', null, 'enroll_loyalty: a card number already issued in the organization cannot be issued again');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid(), 'cash', %L) $$, :'c_free', :'plan_free', :'branch', :'good_card2'),
  'P0001', 'This customer already has a different active card', 'enroll_loyalty: a second card cannot be issued to a member');

-- Renewal while the current period is running: starts the day after it ends, same card.
select public.enroll_loyalty(:'c_free', :'plan_paid', :'branch', gen_random_uuid(), 'cash') as renew_free \gset
select (:'renew_free'::jsonb ->> 'membership_id') as m_free_renewal \gset
select is((:'renew_free'::jsonb ->> 'starts_on')::date, (:'enrol_free'::jsonb ->> 'ends_on')::date + 1,
  'enroll_loyalty: a renewal starts the day after the current membership ends');
select (:'renew_free'::jsonb ->> 'starts_on')::date as renew_start \gset
select ok((:'renew_free'::jsonb ->> 'ends_on')::date =
            case when extract(day from :'renew_start'::date + interval '3 months') < extract(day from :'renew_start'::date)
                 then (:'renew_start'::date + interval '3 months')::date
                 else (:'renew_start'::date + interval '3 months')::date - 1 end
          and :'renew_free'::jsonb ->> 'card_no' = :'card_free_no'
          and (select renewed_from_id from public.loyalty_memberships where id = :'m_free_renewal') = :'m_free'::uuid,
  'enroll_loyalty: the renewal runs for the new plan''s duration on the same card and links the period it follows');
-- Renewal after the previous period has ended: starts today, same card.
select public.enroll_loyalty(:'c_lapsed', :'plan_free', :'branch', gen_random_uuid()) as renew_lapsed \gset
select ok((:'renew_lapsed'::jsonb ->> 'starts_on')::date = :'today'::date and :'renew_lapsed'::jsonb ->> 'card_no' = '7000000005'
          and (select renewed_from_id from public.loyalty_memberships where id = (:'renew_lapsed'::jsonb ->> 'membership_id')::uuid) is null,
  'enroll_loyalty: renewing after the membership ended starts on the business date with the same card');
-- FR-LOY-018: only one future (not yet started) period may exist per card.
select public.enroll_loyalty(:'c_paid', :'plan_free', :'branch', gen_random_uuid()) as renew_paid \gset
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'c_paid', :'plan_free', :'branch'),
  'P0001', null, 'enroll_loyalty: a second early renewal is rejected while a future period exists (FR-LOY-018)');

select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'c_late', :'plan_free', :'branch_b'),
  'P0001', 'You do not have access to this branch', 'enroll_loyalty: a salesman cannot enrol at an unassigned branch');
select tests.authenticate_as(:'acct');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'c_late', :'plan_free', :'branch'),
  'P0001', 'Permission denied: loyalty.enroll', 'enroll_loyalty: an accountant cannot enrol members');
select tests.authenticate_as(:'owner');
update public.organization_settings set loyalty_enabled = false where organization_id = :'org';
select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.enroll_loyalty(%L, %L, %L, gen_random_uuid()) $$, :'c_late', :'plan_free', :'branch'),
  'P0001', 'The loyalty programme is turned off', 'enroll_loyalty: nobody can enrol while loyalty is disabled');
select tests.authenticate_as(:'owner');
update public.organization_settings set loyalty_enabled = true where organization_id = :'org';

-- =============================================================================================
-- L. lookup_loyalty
-- =============================================================================================
-- The other organization issues its first card; its number collides with ours (per-org sequence).
select tests.authenticate_as(:'outsider');
update public.loyalty_plans set is_active = true where id = :'plan_o';
select public.enroll_loyalty(:'cust_o', :'plan_o', :'branch2', gen_random_uuid()) ->> 'card_no' as card_o_no \gset

select tests.authenticate_as(:'sales', 'aal1');
select is((select format('%s/%s/%s/%s/%s', customer_name, plan_name, discount_bp, points_balance, membership_id = :'m_free'::uuid)
             from public.lookup_loyalty(:'org', :'card_free_no')),
  'Rahima Begum/6-Month Card/300/0/t', 'lookup_loyalty: a card number finds the member, current plan, discount and points');
select is((select card_no from public.lookup_loyalty(:'org', '01711-000001')), :'card_free_no',
  'lookup_loyalty: a local-format phone number finds the card');
select is((select card_no from public.lookup_loyalty(:'org', '+880 1711 000001')), :'card_free_no',
  'lookup_loyalty: an E.164 phone number with spaces finds the card');
select is((select count(*)::int from public.lookup_loyalty(:'org', '0000000000')), 0,
  'lookup_loyalty: an unknown card number finds nothing');
select is((select customer_id from public.lookup_loyalty(:'org', :'card_o_no')), :'c_free'::uuid,
  'lookup_loyalty: a card number also used by another organization resolves to this organization''s member only');
select tests.authenticate_as(:'owner');
update public.customers set is_active = false where id = :'c_pre';
select is((select count(*)::int from public.lookup_loyalty(:'org', :'good_card')), 0,
  'lookup_loyalty: the card of a deactivated customer is not found');
update public.customers set is_active = true where id = :'c_pre';
select tests.authenticate_as(:'outsider');
select throws_ok(format($$ select * from public.lookup_loyalty(%L, %L) $$, :'org', :'card_free_no'),
  'P0001', 'You do not have access to this organization', 'lookup_loyalty: another organization cannot look up our cards');
select is((select count(*)::int from public.lookup_loyalty(:'org2', '01711000001')), 0,
  'lookup_loyalty: our member''s phone is not found in another organization');
select tests.authenticate_as_anon();
select throws_ok(format($$ select * from public.lookup_loyalty(%L, %L) $$, :'org', :'card_free_no'),
  '42501', null, 'lookup_loyalty: anon cannot call the lookup');
select tests.clear_authentication();

-- =============================================================================================
-- J. cancel_loyalty_membership
-- =============================================================================================
select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.cancel_loyalty_membership(%L, 'Customer request') $$, :'m_paid'),
  'P0001', 'Permission denied: loyalty.cancel', 'cancel_loyalty_membership: a salesman cannot cancel');
select tests.authenticate_as(:'outsider');
select throws_ok(format($$ select public.cancel_loyalty_membership(%L, 'Customer request') $$, :'m_paid'),
  'P0001', 'Permission denied: loyalty.cancel', 'cancel_loyalty_membership: another organization cannot cancel');
select tests.authenticate_as(:'managerb');
select throws_ok(format($$ select public.cancel_loyalty_membership(%L, 'Customer request') $$, :'m_paid'),
  'P0001', 'You do not have access to this branch',
  'cancel_loyalty_membership: a Branch Manager cannot cancel a membership enrolled in an unassigned branch (P-37)');
select tests.authenticate_as(:'manager');
select throws_ok(format($$ select public.cancel_loyalty_membership(%L, ' no ') $$, :'m_paid'),
  'P0001', 'A reason is required', 'cancel_loyalty_membership: a reason of at least 3 characters is required');
select throws_ok($$ select public.cancel_loyalty_membership(gen_random_uuid(), 'Customer request') $$,
  'P0001', 'Membership not found', 'cancel_loyalty_membership: an unknown membership is reported');
select lives_ok(format($$ select public.cancel_loyalty_membership(%L, '  Customer request  ') $$, :'m_paid'),
  'cancel_loyalty_membership: a manager can cancel a membership');
select is((select format('%s/%s/%s/%s', status, cancelled_by = :'manager'::uuid, cancel_reason, cancelled_at is not null)
             from public.loyalty_memberships where id = :'m_paid'),
  'cancelled/t/Customer request/t', 'cancel_loyalty_membership: status, actor, trimmed reason and time are recorded');
select ok((select membership_id is null from public.lookup_loyalty(:'org', '01711000002')),
  'cancel_loyalty_membership: benefits stop immediately (lookup shows no current membership)');
select throws_ok(format($$ select public.cancel_loyalty_membership(%L, 'Customer request') $$, :'m_paid'),
  'P0001', 'Membership is already cancelled', 'cancel_loyalty_membership: a cancelled membership cannot be cancelled again');
select tests.clear_authentication();
select ok(exists (select 1 from audit.log where table_name = 'public.loyalty_memberships' and record_id = :'m_paid'
                     and action = 'UPDATE' and 'status' = any (changed_fields) and actor_id = :'manager'::uuid),
  'cancel_loyalty_membership: the cancellation is audited');

-- =============================================================================================
-- K. replace_loyalty_card (Rahima: current free period + paid renewal; 30 points)
-- =============================================================================================
select id as card_free from public.loyalty_cards where card_no = :'card_free_no' and organization_id = :'org' \gset
insert into public.loyalty_point_ledger (organization_id, card_id, branch_id, entry_type, points, note)
  values (:'org', :'card_free', :'branch', 'earn', 40, 'test earn'), (:'org', :'card_free', :'branch', 'redeem', -10, 'test redeem');

select tests.authenticate_as(:'sales', 'aal1');
select throws_ok(format($$ select public.replace_loyalty_card(%L, 'Lost wallet') $$, :'card_free'),
  'P0001', 'Permission denied: loyalty.cancel', 'replace_loyalty_card: a salesman cannot replace a card');
select tests.authenticate_as(:'outsider');
select throws_ok(format($$ select public.replace_loyalty_card(%L, 'Lost wallet') $$, :'card_free'),
  'P0001', 'Permission denied: loyalty.cancel', 'replace_loyalty_card: another organization cannot replace our card');
select tests.authenticate_as(:'manager');
select throws_ok(format($$ select public.replace_loyalty_card(%L, '') $$, :'card_free'),
  'P0001', 'A reason is required', 'replace_loyalty_card: a reason is required');
select throws_ok(format($$ select public.replace_loyalty_card(%L, 'Lost wallet', %L) $$, :'card_free', :'bad_card'),
  'P0001', 'Card number is not valid', 'replace_loyalty_card: a replacement number with a bad Luhn digit is rejected');
select public.replace_loyalty_card(:'card_free', 'Lost wallet') as new_card_no \gset
select ok(:'new_card_no' <> :'card_free_no'
          and app.luhn_check_digit(left(:'new_card_no', -1)) = right(:'new_card_no', 1)::int,
  'replace_loyalty_card: a new Luhn-valid card number is issued');
select id as new_card from public.loyalty_cards where card_no = :'new_card_no' and organization_id = :'org' \gset
select is((select format('%s/%s/%s', is_active, deactivation_reason, deactivated_at is not null) from public.loyalty_cards
            where id = :'card_free'),
  'f/Lost wallet/t', 'replace_loyalty_card: the old card is blocked with the reason');
select is((select format('%s/%s', coalesce(sum(points) filter (where card_id = :'card_free'), 0),
                                  coalesce(sum(points) filter (where card_id = :'new_card'), 0))
             from public.loyalty_point_ledger), '0/30',
  'replace_loyalty_card: the 30-point balance moves to the new card');
select is((select format('%s/%s', count(*) filter (where card_id = :'new_card'), count(*) filter (where card_id = :'card_free'))
             from public.loyalty_memberships where customer_id = :'c_free'),
  '2/0', 'replace_loyalty_card: the current and the future membership move to the new card');
select is((select count(*)::int from public.lookup_loyalty(:'org', :'card_free_no')), 0,
  'replace_loyalty_card: the old card number no longer finds the member');
select is((select format('%s/%s', membership_id = :'m_free'::uuid, points_balance) from public.lookup_loyalty(:'org', :'new_card_no')),
  't/30', 'replace_loyalty_card: the new card finds the current membership and the points');
select throws_ok(format($$ select public.replace_loyalty_card(%L, 'Lost again') $$, :'card_free'),
  'P0001', 'Active card not found', 'replace_loyalty_card: a blocked card cannot be replaced again');
select id as card_pre from public.loyalty_cards where card_no = :'good_card' and organization_id = :'org' \gset
select is(public.replace_loyalty_card(:'card_pre', 'Damaged card', :'good_card2'), :'good_card2',
  'replace_loyalty_card: a valid pre-printed replacement number is used as given');

-- =============================================================================================
-- M. Ledger / projection invariants over everything posted above
-- =============================================================================================
select tests.clear_authentication();
select is((select count(*)::int from public.batches b
            where b.quantity_on_hand <> coalesce((select sum(m.quantity) from public.inventory_movements m where m.batch_id = b.id), 0)),
  0, 'invariant: for every batch, quantity_on_hand = sum(inventory_movements.quantity)');
select is((select count(*)::int from public.batches b
            where not exists (select 1 from public.inventory_movements m where m.batch_id = b.id)),
  0, 'invariant: every batch received its stock through the ledger (at least one movement)');
select is((select count(*)::int from public.inventory_movements m join public.batches b on b.id = m.batch_id
            where m.unit_cost_paisa <> b.cost_paisa or m.medicine_id <> b.medicine_id or m.branch_id <> b.branch_id
               or m.organization_id <> b.organization_id),
  0, 'invariant: movements carry their batch''s organization, branch, medicine and cost');
select is((select count(*)::int from public.stock_adjustments sa
            where (select count(*) from public.inventory_movements m
                    where m.reference_type = 'stock_adjustment' and m.reference_id = sa.id
                      and m.batch_id = sa.batch_id and m.quantity = sa.quantity_delta) <> 1),
  0, 'invariant: every stock adjustment has exactly one matching movement');
select is((select count(*)::int from public.goods_receipt_items gri
            where gri.quantity + gri.bonus_quantity <> (select coalesce(sum(m.quantity), 0) from public.inventory_movements m
                                                         where m.batch_id = gri.batch_id and m.movement_type = 'purchase_receipt')),
  0, 'invariant: every receipt line posted paid + bonus units to its lot');
select is((select count(*)::int from public.goods_receipts gr
            where gr.subtotal_paisa <> (select sum(i.line_total_paisa) from public.goods_receipt_items i where i.goods_receipt_id = gr.id)
               or gr.discount_paisa <> (select sum(i.discount_paisa) from public.goods_receipt_items i where i.goods_receipt_id = gr.id)),
  0, 'invariant: receipt subtotal and discount equal the sums of their lines');
select is((select count(*)::int from public.purchase_returns pr
            where pr.total_paisa <> (select sum(i.line_total_paisa) from public.purchase_return_items i where i.purchase_return_id = pr.id)
               or (select sum(i.quantity) from public.purchase_return_items i where i.purchase_return_id = pr.id)
                  <> -(select sum(m.quantity) from public.inventory_movements m
                        where m.reference_type = 'purchase_return' and m.reference_id = pr.id)),
  0, 'invariant: purchase return totals and movements equal the sums of their lines');
select is((select count(*)::int from public.suppliers s
            where (select coalesce(sum(l.amount_paisa), 0) from public.supplier_ledger_entries l where l.supplier_id = s.id)
               <> (select coalesce(sum(gr.total_paisa), 0) from public.goods_receipts gr where gr.supplier_id = s.id)
                - (select coalesce(sum(p.amount_paisa), 0) from public.supplier_payments p where p.supplier_id = s.id)
                - (select coalesce(sum(r.total_paisa), 0) from public.purchase_returns r where r.supplier_id = s.id)),
  0, 'invariant: supplier balance = receipts - payments - returns');
select is((select count(*)::int from public.opening_stock_loads l
            where l.line_count <> (select count(*) from public.inventory_movements m
                                    where m.reference_type = 'opening_stock' and m.reference_id = l.id)),
  0, 'invariant: every opening stock load posted one movement per line');
select is((select count(*)::int from public.loyalty_cards c where app.loyalty_points_balance(c.id) < 0),
  0, 'invariant: no loyalty card has a negative points balance');

select * from finish();
rollback;
