-- =============================================================================
-- Migration: save_medicine
-- Creates or updates a catalog medicine in one transaction: finds or creates its generic and
-- manufacturer by name (case-insensitive) and replaces its unit-level barcodes. Doing this server-side
-- keeps the catalog consistent (no medicine left without the barcode the user typed, no duplicate
-- generic spellings) and returns stable error codes the app translates.
-- Also: search_medicines now returns the branch rack (shelf) location.
-- =============================================================================

create or replace function app.find_or_create_generic(p_organization_id uuid, p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := nullif(btrim(p_name), '');
  v_id uuid;
begin
  if v_name is null then
    return null;
  end if;
  insert into public.generics (organization_id, name, created_by, updated_by)
  values (p_organization_id, v_name, auth.uid(), auth.uid())
  on conflict (organization_id, lower(name)) do nothing
  returning id into v_id;
  if v_id is null then
    select g.id into v_id from public.generics g
     where g.organization_id = p_organization_id and lower(g.name) = lower(v_name);
  end if;
  return v_id;
end;
$$;

create or replace function app.find_or_create_manufacturer(p_organization_id uuid, p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := nullif(btrim(p_name), '');
  v_id uuid;
begin
  if v_name is null then
    return null;
  end if;
  insert into public.manufacturers (organization_id, name, created_by, updated_by)
  values (p_organization_id, v_name, auth.uid(), auth.uid())
  on conflict (organization_id, lower(name)) do nothing
  returning id into v_id;
  if v_id is null then
    select m.id into v_id from public.manufacturers m
     where m.organization_id = p_organization_id and lower(m.name) = lower(v_name);
  end if;
  return v_id;
end;
$$;

-- p_medicine_id null creates a medicine; otherwise updates it.
-- p_barcodes null leaves barcodes unchanged; an array (possibly empty) replaces the unit-level barcodes.
-- p_branch_id set also stores the branch shelf (rack) location and reorder level for that branch.
create or replace function public.save_medicine(
  p_organization_id uuid,
  p_brand_name text,
  p_dosage_form public.dosage_form,
  p_medicine_id uuid default null,
  p_generic_name text default null,
  p_manufacturer_name text default null,
  p_strength text default null,
  p_base_unit_label text default 'piece',
  p_schedule public.drug_schedule default 'otc',
  p_loyalty_eligible boolean default true,
  p_sku text default null,
  p_barcodes text[] default null,
  p_notes text default null,
  p_is_active boolean default true,
  p_branch_id uuid default null,
  p_rack_location text default null,
  p_reorder_level integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := p_medicine_id;
  v_generic uuid;
  v_manufacturer uuid;
  v_barcodes text[];
  v_constraint text;
begin
  perform app.require_permission(p_organization_id, 'catalog.manage');

  if coalesce(btrim(p_brand_name), '') = '' then
    perform app.fail('invalid_name', 'Brand name is required');
  end if;
  if p_dosage_form is null then
    perform app.fail('invalid_dosage_form', 'Dosage form is required');
  end if;

  if p_branch_id is not null then
    if not app.can(p_branch_id, 'catalog.manage')
       or app.branch_org_id(p_branch_id) is distinct from p_organization_id then
      perform app.fail('forbidden', 'You cannot manage medicines in this branch');
    end if;
    if p_reorder_level is not null and p_reorder_level < 0 then
      perform app.fail('invalid_quantity', 'Reorder level cannot be negative');
    end if;
  end if;

  if p_barcodes is not null then
    select coalesce(array_agg(distinct b), '{}') into v_barcodes
      from (select btrim(x) as b from unnest(p_barcodes) x) s
     where b <> '';
    if exists (select 1 from unnest(v_barcodes) b where b !~ '^[0-9A-Za-z-]{4,64}$') then
      perform app.fail('invalid_barcode', 'Barcodes are 4 to 64 letters, digits or dashes');
    end if;
    if cardinality(v_barcodes) > 20 then
      perform app.fail('invalid_barcode', 'At most 20 barcodes per medicine');
    end if;
  end if;

  begin
    v_generic := app.find_or_create_generic(p_organization_id, p_generic_name);
    v_manufacturer := app.find_or_create_manufacturer(p_organization_id, p_manufacturer_name);

    if v_id is null then
      insert into public.medicines (
        organization_id, brand_name, generic_id, manufacturer_id, dosage_form, strength, base_unit_label,
        schedule, loyalty_eligible, sku, notes, is_active, created_by, updated_by
      ) values (
        p_organization_id, btrim(p_brand_name), v_generic, v_manufacturer, p_dosage_form,
        nullif(btrim(p_strength), ''), coalesce(nullif(btrim(p_base_unit_label), ''), 'piece'),
        coalesce(p_schedule, 'otc'), coalesce(p_loyalty_eligible, true), nullif(btrim(p_sku), ''),
        nullif(btrim(p_notes), ''), coalesce(p_is_active, true), auth.uid(), auth.uid()
      ) returning id into v_id;
    else
      update public.medicines
         set brand_name = btrim(p_brand_name),
             generic_id = v_generic,
             manufacturer_id = v_manufacturer,
             dosage_form = p_dosage_form,
             strength = nullif(btrim(p_strength), ''),
             base_unit_label = coalesce(nullif(btrim(p_base_unit_label), ''), 'piece'),
             schedule = coalesce(p_schedule, 'otc'),
             loyalty_eligible = coalesce(p_loyalty_eligible, true),
             sku = nullif(btrim(p_sku), ''),
             notes = nullif(btrim(p_notes), ''),
             is_active = coalesce(p_is_active, true)
       where id = v_id and organization_id = p_organization_id;
      if not found then
        perform app.fail('not_found', 'Medicine not found');
      end if;
    end if;

    if v_barcodes is not null then
      delete from public.medicine_barcodes
       where medicine_id = v_id and pack_id is null and barcode <> all (v_barcodes);
      insert into public.medicine_barcodes (organization_id, medicine_id, barcode, created_by)
      select p_organization_id, v_id, b, auth.uid()
        from unnest(v_barcodes) b
       where not exists (
         select 1 from public.medicine_barcodes mb
          where mb.organization_id = p_organization_id and mb.medicine_id = v_id and mb.barcode = b);
    end if;

    if p_branch_id is not null then
      insert into public.branch_medicine_settings (
        organization_id, branch_id, medicine_id, reorder_level, rack_location, updated_by
      ) values (
        p_organization_id, p_branch_id, v_id, coalesce(p_reorder_level, 0),
        nullif(upper(btrim(p_rack_location)), ''), auth.uid()
      )
      on conflict (branch_id, medicine_id) do update
         set reorder_level = coalesce(p_reorder_level, public.branch_medicine_settings.reorder_level),
             rack_location = excluded.rack_location;
    end if;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint = 'medicines_identity_key' then
        perform app.fail('duplicate_medicine',
          'A medicine with this brand, form, strength and manufacturer already exists');
      elsif v_constraint = 'medicines_org_sku_key' then
        perform app.fail('duplicate_sku', 'Another medicine already uses this SKU');
      elsif v_constraint = 'medicine_barcodes_organization_id_barcode_key' then
        perform app.fail('duplicate_barcode', 'This barcode already belongs to another medicine');
      end if;
      raise;
    when check_violation then
      perform app.fail('invalid_medicine_field', 'One of the fields is too long or invalid');
  end;

  return v_id;
end;
$$;

-- search_medicines also returns the branch shelf (rack) location so the counter knows where to pick.
-- The return type changes, so the function is dropped and recreated with the same arguments.
drop function public.search_medicines(uuid, text, integer);

create or replace function public.search_medicines(
  p_branch_id uuid,
  p_query text,
  p_limit integer default 20
)
returns table (
  medicine_id uuid,
  brand_name text,
  generic_name text,
  manufacturer_name text,
  dosage_form public.dosage_form,
  strength text,
  schedule public.drug_schedule,
  base_unit_label text,
  stock_quantity bigint,
  sale_price_paisa bigint,
  nearest_expiry date,
  rack_location text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_query text := btrim(coalesce(p_query, ''));
  v_org uuid;
  v_escaped text;
  v_today date;
  v_block integer;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
begin
  if not app.has_branch_access(p_branch_id) then
    perform app.fail('forbidden', 'You do not have access to this branch');
  end if;
  if length(v_query) < 2 then
    return;
  end if;
  select b.organization_id into v_org from public.branches b where b.id = p_branch_id;
  select app.business_date(v_org), s.near_expiry_block_days into v_today, v_block
    from public.organization_settings s where s.organization_id = v_org;
  v_escaped := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');

  return query
  with candidates as (
    select m.id, m.brand_name, 3.0::real as score
      from public.medicine_barcodes mb
      join public.medicines m on m.id = mb.medicine_id
     where mb.organization_id = v_org
       and mb.barcode = v_query
       and m.is_active
    union all
    select m.id, m.brand_name,
           case when m.brand_name ilike v_escaped || '%'
                then 2.0::real + extensions.similarity(m.brand_name, v_query)
                else extensions.similarity(m.brand_name, v_query) end
      from public.medicines m
     where m.organization_id = v_org
       and m.is_active
       and m.brand_name ilike '%' || v_escaped || '%'
    union all
    select m.id, m.brand_name, extensions.similarity(g.name, v_query)
      from public.generics g
      join public.medicines m on m.generic_id = g.id
     where g.organization_id = v_org
       and m.organization_id = v_org
       and m.is_active
       and g.name ilike '%' || v_escaped || '%'
  ),
  top_matches as (
    select c.id, max(c.score) as score, c.brand_name
      from candidates c
     group by c.id, c.brand_name
     order by max(c.score) desc, c.brand_name
     limit v_limit
  )
  select m.id, m.brand_name, g.name, mf.name, m.dosage_form, m.strength, m.schedule, m.base_unit_label,
         coalesce(stock.qty, 0)::bigint,
         fefo.sale_price_paisa,
         fefo.expiry_date,
         bms.rack_location
    from top_matches x
    join public.medicines m on m.id = x.id
    left join public.generics g on g.id = m.generic_id
    left join public.manufacturers mf on mf.id = m.manufacturer_id
    left join public.branch_medicine_settings bms on bms.branch_id = p_branch_id and bms.medicine_id = m.id
    left join lateral (
      select sum(b.quantity_on_hand) as qty
        from public.batches b
       where b.branch_id = p_branch_id and b.medicine_id = m.id
         and not b.is_depleted and b.expiry_date > v_today + v_block
    ) stock on true
    left join lateral (
      select b.sale_price_paisa, b.expiry_date
        from public.batches b
       where b.branch_id = p_branch_id and b.medicine_id = m.id
         and not b.is_depleted and b.expiry_date > v_today + v_block
       order by b.expiry_date, b.received_at, b.id
       limit 1
    ) fefo on true
   order by x.score desc, m.brand_name;
end;
$$;

grant execute on function public.search_medicines(uuid, text, integer) to authenticated;

grant execute on function public.save_medicine(uuid, text, public.dosage_form, uuid, text, text, text, text,
  public.drug_schedule, boolean, text, text[], text, boolean, uuid, text, integer) to authenticated;

call app.harden_privileges();
