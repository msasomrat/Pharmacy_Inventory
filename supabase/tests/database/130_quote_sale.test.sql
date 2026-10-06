-- quote_sale returns create_sale's exact figures and leaves no trace.
begin;
select plan(7);

select tests.create_user('owner@quote.test') as owner \gset
select tests.authenticate_as(:'owner');
select public.create_organization('Quote Pharmacy', 'Main', 'QTE') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
insert into public.medicines (organization_id, brand_name, dosage_form, base_unit_label)
  values (:'org', 'Napa', 'tablet', 'tablet') returning id as napa \gset
select public.add_opening_stock(:'branch', jsonb_build_array(
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'A', 'expiry_date', app.business_date(:'org') + 30,
    'quantity', 5, 'cost_paisa', 80, 'mrp_paisa', 115, 'sale_price_paisa', 110),
  jsonb_build_object('medicine_id', :'napa', 'batch_no', 'B', 'expiry_date', app.business_date(:'org') + 300,
    'quantity', 100, 'cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid());

select public.quote_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 10, 'discount_bp', 500))) as q \gset

select is((:'q'::jsonb ->> 'gross_paisa')::bigint, (5 * 110 + 5 * 120)::bigint, 'quote uses FEFO batch prices');
select is((:'q'::jsonb ->> 'total_paisa')::bigint, (1150 - 58)::bigint, 'quote applies the 5% line discount');
select is(jsonb_array_length(:'q'::jsonb -> 'lines'), 1, 'quote returns line breakdown');
select is((select count(*)::int from public.sales where organization_id = :'org'), 0, 'quote does not create a sale');
select is((select sum(quantity_on_hand)::int from public.batches where branch_id = :'branch'), 105, 'quote does not move stock');

select public.create_sale(:'branch', jsonb_build_array(jsonb_build_object('medicine_id', :'napa', 'quantity', 10, 'discount_bp', 500)),
  '[{"method": "cash", "amount_paisa": 2000}]'::jsonb, gen_random_uuid()) as s \gset
select is((:'s'::jsonb ->> 'total_paisa')::bigint, (:'q'::jsonb ->> 'total_paisa')::bigint, 'real sale total equals the quote');
select ok(:'s'::jsonb ->> 'invoice_no' like '%-000001', 'quote did not consume an invoice number');

select * from finish();
rollback;
