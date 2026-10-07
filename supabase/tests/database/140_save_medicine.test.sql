-- save_medicine: atomic create/update with generic/manufacturer lookup, barcodes and permission checks.
begin;
select plan(19);

-- Runs a statement and returns the app.fail code (DETAIL) it raised, or null if it succeeded.
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

select tests.create_user('owner@catalog.test') as owner \gset
select tests.create_user('sales@catalog.test') as salesman \gset
select tests.create_user('stranger@catalog.test') as stranger \gset
select tests.authenticate_as(:'owner');
select public.create_organization('Catalog Pharmacy', 'Main', 'CAT') as org \gset
select id as branch from public.branches where organization_id = :'org' \gset
select tests.add_member(:'org', 'sales@catalog.test', 'salesman', array[:'branch']::uuid[]);

-- Create
select public.save_medicine(:'org', '  Napa ', 'tablet', p_generic_name => 'Paracetamol',
  p_manufacturer_name => 'Beximco', p_strength => '500 mg', p_base_unit_label => 'tablet',
  p_barcodes => array['8941100500012', ' 8941100500012 ', '']) as napa \gset
select is((select brand_name from public.medicines where id = :'napa'), 'Napa', 'brand name is trimmed');
select is((select g.name from public.medicines m join public.generics g on g.id = m.generic_id where m.id = :'napa'),
  'Paracetamol', 'generic is created and linked');
select is((select count(*)::int from public.medicine_barcodes where medicine_id = :'napa'), 1,
  'duplicate and blank barcodes are collapsed');

-- Same generic in different case is reused, not duplicated
select public.save_medicine(:'org', 'Ace', 'tablet', p_generic_name => 'PARACETAMOL',
  p_manufacturer_name => 'square', p_strength => '500 mg') as ace \gset
select is((select count(*)::int from public.generics where organization_id = :'org'), 1,
  'generic lookup is case-insensitive');
select is((select count(*)::int from public.manufacturers where organization_id = :'org'), 2,
  'a new manufacturer is created once');

-- Search finds it by barcode and by generic
select is((select count(*)::int from public.search_medicines(:'branch', '8941100500012')), 1, 'searchable by barcode');
select is((select count(*)::int from public.search_medicines(:'branch', 'paracet')), 2, 'searchable by generic');

-- Duplicates map to stable error codes
select is(tests.error_code(format($$ select public.save_medicine(%L, 'napa', 'tablet', p_manufacturer_name => 'BEXIMCO', p_strength => '500 mg') $$, :'org')),
  'duplicate_medicine', 'same brand/form/strength/manufacturer is rejected');
select is((select tests.error_code(format($$ select public.save_medicine(%L, 'Ace', 'tablet', p_medicine_id => %L, p_generic_name => 'Paracetamol', p_manufacturer_name => 'Square', p_strength => '500 mg', p_barcodes => array['8941100500012']) $$, :'org', :'ace'))),
  'duplicate_barcode', 'a barcode cannot belong to two medicines');
select is((select tests.error_code(format($$ select public.save_medicine(%L, 'X', 'tablet', p_barcodes => array['ab']) $$, :'org'))),
  'invalid_barcode', 'malformed barcode is rejected');

-- Update replaces barcodes and keeps the id
select public.save_medicine(:'org', 'Napa', 'tablet', p_medicine_id => :'napa', p_generic_name => 'Paracetamol',
  p_manufacturer_name => 'Beximco', p_strength => '500 mg', p_base_unit_label => 'tablet', p_schedule => 'otc',
  p_barcodes => array['NAPA-500']) as napa2 \gset
select is(:'napa2'::uuid, :'napa'::uuid, 'update returns the same id');
select results_eq(format($$ select barcode from public.medicine_barcodes where medicine_id = %L $$, :'napa'),
  $$ values ('NAPA-500') $$, 'update replaces the barcodes');
select is((select tests.error_code(format($$ select public.save_medicine(%L, 'Ghost', 'tablet', p_medicine_id => gen_random_uuid()) $$, :'org'))),
  'not_found', 'updating an unknown medicine fails');

-- Branch rack location and reorder level are stored per branch and shown by the POS search
select public.save_medicine(:'org', 'Napa', 'tablet', p_medicine_id => :'napa', p_generic_name => 'Paracetamol',
  p_manufacturer_name => 'Beximco', p_strength => '500 mg', p_base_unit_label => 'tablet',
  p_branch_id => :'branch', p_rack_location => ' a-3 ', p_reorder_level => 50);
select results_eq(format($$ select rack_location, reorder_level from public.branch_medicine_settings where medicine_id = %L $$, :'napa'),
  $$ values ('A-3'::text, 50) $$, 'rack location (normalised) and reorder level are saved for the branch');
select is((select rack_location from public.search_medicines(:'branch', 'Napa') where medicine_id = :'napa'), 'A-3',
  'POS search shows the rack location');
select public.create_branch(:'org', 'TWO', 'Second') as branch2 \gset
select is((select rack_location from public.search_medicines(:'branch2', 'Napa') where medicine_id = :'napa'), null,
  'rack location is per branch');

-- Permissions: salesman cannot edit the catalog; outsiders cannot either; MFA is required
select tests.authenticate_as(:'salesman');
select is((select tests.error_code(format($$ select public.save_medicine(%L, 'Fexo', 'tablet') $$, :'org'))),
  'forbidden', 'salesman cannot add medicines');
select tests.authenticate_as(:'stranger');
select is((select tests.error_code(format($$ select public.save_medicine(%L, 'Fexo', 'tablet') $$, :'org'))),
  'forbidden', 'a non-member cannot add medicines');
select tests.authenticate_as(:'owner', 'aal1');
select isnt((select tests.error_code(format($$ select public.save_medicine(%L, 'Fexo', 'tablet') $$, :'org'))),
  null, 'owner without MFA cannot add medicines');

select * from finish();
rollback;
