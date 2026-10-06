-- =============================================================================
-- Migration: catalog and inventory
-- Shared (organization-wide) medicine catalog; branch-level batch stock with an append-only
-- inventory ledger (inventory_movements) as the source of truth.
-- Tenant integrity: composite foreign keys (organization_id, id) make cross-tenant references
-- impossible even for privileged code paths.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Catalog
-- -----------------------------------------------------------------------------
create table public.manufacturers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  name text not null check (length(btrim(name)) between 2 and 120),
  country text not null default 'Bangladesh' check (length(country) <= 60),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (organization_id, id)
);
create unique index manufacturers_org_name_key on public.manufacturers (organization_id, lower(name));

create table public.generics (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  name text not null check (length(btrim(name)) between 2 and 200),
  therapeutic_class text check (length(therapeutic_class) <= 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (organization_id, id)
);
create unique index generics_org_name_key on public.generics (organization_id, lower(name));
create index generics_name_trgm_idx on public.generics using gin (name extensions.gin_trgm_ops);

create table public.medicines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  brand_name text not null check (length(btrim(brand_name)) between 1 and 160),
  generic_id uuid,
  manufacturer_id uuid,
  dosage_form public.dosage_form not null,
  strength text check (length(strength) <= 60),
  base_unit_label text not null default 'piece' check (length(base_unit_label) between 1 and 30),
  schedule public.drug_schedule not null default 'otc',
  loyalty_eligible boolean not null default true,
  sku text check (length(sku) <= 60),
  notes text check (length(notes) <= 1000),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (organization_id, id),
  foreign key (organization_id, generic_id) references public.generics (organization_id, id),
  foreign key (organization_id, manufacturer_id) references public.manufacturers (organization_id, id)
);

comment on column public.medicines.base_unit_label is
  'Smallest sellable unit (tablet, capsule, bottle, tube...). All stock quantities use this unit.';
comment on column public.medicines.loyalty_eligible is
  'False excludes the medicine from loyalty discounts and points (e.g. controlled or low-margin items).';

create unique index medicines_org_sku_key on public.medicines (organization_id, sku) where sku is not null;
create unique index medicines_identity_key on public.medicines (
  organization_id, lower(brand_name), dosage_form, coalesce(lower(strength), ''),
  coalesce(manufacturer_id, '00000000-0000-0000-0000-000000000000'::uuid)
);
create index medicines_brand_trgm_idx on public.medicines using gin (brand_name extensions.gin_trgm_ops);
create index medicines_generic_idx on public.medicines (generic_id);
create index medicines_manufacturer_idx on public.medicines (manufacturer_id);

-- Pack levels, e.g. strip = 10 tablets, box = 100 tablets.
create table public.medicine_packs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  medicine_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 30),
  units_per_pack integer not null check (units_per_pack between 1 and 100000),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  foreign key (organization_id, medicine_id) references public.medicines (organization_id, id),
  unique (organization_id, id)
);
create unique index medicine_packs_name_key on public.medicine_packs (medicine_id, lower(name));
create unique index medicine_packs_one_default on public.medicine_packs (medicine_id) where is_default;

create table public.medicine_barcodes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  medicine_id uuid not null,
  pack_id uuid,
  barcode text not null check (barcode ~ '^[0-9A-Za-z-]{4,64}$'),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  unique (organization_id, barcode),
  foreign key (organization_id, medicine_id) references public.medicines (organization_id, id),
  foreign key (organization_id, pack_id) references public.medicine_packs (organization_id, id)
);
create index medicine_barcodes_medicine_idx on public.medicine_barcodes (medicine_id);

create table public.branch_medicine_settings (
  organization_id uuid not null,
  branch_id uuid not null,
  medicine_id uuid not null,
  reorder_level integer not null default 0 check (reorder_level >= 0),
  max_stock_level integer check (max_stock_level is null or max_stock_level >= reorder_level),
  rack_location text check (length(rack_location) <= 40),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  primary key (branch_id, medicine_id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  foreign key (organization_id, medicine_id) references public.medicines (organization_id, id)
);

-- -----------------------------------------------------------------------------
-- Inventory
-- -----------------------------------------------------------------------------

-- A batch row is one stock lot of a medicine in one branch. The same manufacturer batch number can
-- appear in several lots (e.g. received twice at different costs).
create table public.batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  medicine_id uuid not null,
  batch_no text not null check (length(btrim(batch_no)) between 1 and 60),
  expiry_date date not null,
  cost_paisa bigint not null check (cost_paisa >= 0),
  mrp_paisa bigint not null check (mrp_paisa > 0),
  sale_price_paisa bigint not null check (sale_price_paisa > 0),
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  constraint batches_price_within_mrp check (sale_price_paisa <= mrp_paisa),
  unique (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  foreign key (organization_id, medicine_id) references public.medicines (organization_id, id)
);

comment on table public.batches is
  'Stock lot per branch. quantity_on_hand is a projection of inventory_movements, maintained in the same transaction.';
comment on column public.batches.cost_paisa is 'Purchase cost per base unit (net of bonus units and discounts).';
comment on column public.batches.mrp_paisa is 'Maximum retail price per base unit printed on the pack. Selling above MRP is not allowed.';

create index batches_fefo_idx on public.batches (branch_id, medicine_id, expiry_date, received_at, id)
  where quantity_on_hand > 0;
create index batches_org_expiry_idx on public.batches (organization_id, expiry_date) where quantity_on_hand > 0;
create index batches_medicine_idx on public.batches (medicine_id);

create table public.inventory_movements (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  branch_id uuid not null,
  batch_id uuid not null,
  medicine_id uuid not null,
  movement_type public.movement_type not null,
  quantity integer not null check (quantity <> 0),
  unit_cost_paisa bigint not null check (unit_cost_paisa >= 0),
  reference_type text not null check (length(reference_type) <= 40),
  reference_id uuid,
  note text check (length(note) <= 500),
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  foreign key (organization_id, batch_id) references public.batches (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  constraint inventory_movements_direction check (
    case
      when movement_type in ('purchase_receipt', 'sale_void', 'sale_return', 'transfer_in', 'opening_balance')
        then quantity > 0
      when movement_type in ('sale', 'purchase_return', 'transfer_out', 'expiry_writeoff')
        then quantity < 0
      else true
    end
  )
);

comment on table public.inventory_movements is 'Append-only stock ledger. Every change to batches.quantity_on_hand has exactly one row here.';

create index inventory_movements_branch_time_idx on public.inventory_movements (branch_id, created_at desc);
create index inventory_movements_batch_idx on public.inventory_movements (batch_id, id);
create index inventory_movements_reference_idx on public.inventory_movements (reference_type, reference_id);
create index inventory_movements_medicine_idx on public.inventory_movements (medicine_id, created_at desc);

create trigger inventory_movements_append_only
  before update or delete on public.inventory_movements
  for each row execute function app.forbid_mutation();

create table public.stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  batch_id uuid not null,
  quantity_delta integer not null check (quantity_delta <> 0),
  reason public.adjustment_reason not null,
  note text check (length(note) <= 500),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  foreign key (organization_id, batch_id) references public.batches (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  constraint stock_adjustments_note_required check (reason <> 'other' or length(btrim(note)) >= 3)
);
create index stock_adjustments_branch_time_idx on public.stock_adjustments (branch_id, created_at desc);

create trigger stock_adjustments_append_only
  before update or delete on public.stock_adjustments
  for each row execute function app.forbid_mutation();

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------
create trigger manufacturers_touch before update on public.manufacturers
  for each row execute function app.touch_updated();
create trigger generics_touch before update on public.generics
  for each row execute function app.touch_updated();
create trigger medicines_touch before update on public.medicines
  for each row execute function app.touch_updated();
create trigger branch_medicine_settings_touch before update on public.branch_medicine_settings
  for each row execute function app.touch_updated();
create trigger batches_touch before update on public.batches
  for each row execute function app.touch_updated();

-- Tenant columns of catalog rows are immutable.
create or replace function app.guard_organization_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.organization_id is distinct from old.organization_id then
    perform app.fail('immutable_field', 'organization_id cannot be changed');
  end if;
  return new;
end;
$$;

create trigger manufacturers_guard_org before update on public.manufacturers
  for each row execute function app.guard_organization_id();
create trigger generics_guard_org before update on public.generics
  for each row execute function app.guard_organization_id();
create trigger medicines_guard_org before update on public.medicines
  for each row execute function app.guard_organization_id();

call app.enable_audit('public.medicines');
call app.enable_audit('public.medicine_packs');
call app.enable_audit('public.medicine_barcodes');

-- Batches change on every sale; only price changes are audited.
create trigger audit_price_change
  after update on public.batches
  for each row
  when (old.sale_price_paisa is distinct from new.sale_price_paisa
        or old.mrp_paisa is distinct from new.mrp_paisa
        or old.cost_paisa is distinct from new.cost_paisa)
  execute function app.audit_row();

-- -----------------------------------------------------------------------------
-- Row level security and grants
-- -----------------------------------------------------------------------------
alter table public.manufacturers enable row level security;
alter table public.generics enable row level security;
alter table public.medicines enable row level security;
alter table public.medicine_packs enable row level security;
alter table public.medicine_barcodes enable row level security;
alter table public.branch_medicine_settings enable row level security;
alter table public.batches enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.stock_adjustments enable row level security;

-- Catalog: readable by every member; editable with catalog.manage.
do $$
declare
  t text;
begin
  foreach t in array array['manufacturers', 'generics', 'medicines', 'medicine_packs', 'medicine_barcodes'] loop
    execute format(
      'create policy %1$s_select on public.%1$s for select to authenticated
         using (organization_id in (select app.user_org_ids()))', t);
    execute format(
      'create policy %1$s_insert on public.%1$s for insert to authenticated
         with check (app.has_permission(organization_id, ''catalog.manage''))', t);
    execute format(
      'create policy %1$s_update on public.%1$s for update to authenticated
         using (app.has_permission(organization_id, ''catalog.manage''))
         with check (app.has_permission(organization_id, ''catalog.manage''))', t);
  end loop;
end;
$$;

create policy medicine_packs_delete on public.medicine_packs for delete to authenticated
  using (app.has_permission(organization_id, 'catalog.manage'));
create policy medicine_barcodes_delete on public.medicine_barcodes for delete to authenticated
  using (app.has_permission(organization_id, 'catalog.manage'));

create policy branch_medicine_settings_select on public.branch_medicine_settings for select to authenticated
  using (branch_id in (select app.user_branch_ids()));
create policy branch_medicine_settings_insert on public.branch_medicine_settings for insert to authenticated
  with check (app.can(branch_id, 'catalog.manage')
              and organization_id = app.branch_org_id(branch_id));
create policy branch_medicine_settings_update on public.branch_medicine_settings for update to authenticated
  using (app.can(branch_id, 'catalog.manage'))
  with check (app.can(branch_id, 'catalog.manage'));

-- Branch stock: readable in accessible branches; written only by functions.
create policy batches_select on public.batches for select to authenticated
  using (branch_id in (select app.user_branch_ids()));
create policy inventory_movements_select on public.inventory_movements for select to authenticated
  using (branch_id in (select app.user_branch_ids()));
create policy stock_adjustments_select on public.stock_adjustments for select to authenticated
  using (branch_id in (select app.user_branch_ids()) and app.has_permission(organization_id, 'reports.view'));

grant select on public.manufacturers, public.generics, public.medicines, public.medicine_packs,
  public.medicine_barcodes, public.branch_medicine_settings, public.stock_adjustments to authenticated;
grant insert (organization_id, name, country) on public.manufacturers to authenticated;
grant update (name, country, is_active) on public.manufacturers to authenticated;
grant insert (organization_id, name, therapeutic_class) on public.generics to authenticated;
grant update (name, therapeutic_class, is_active) on public.generics to authenticated;
grant insert (organization_id, brand_name, generic_id, manufacturer_id, dosage_form, strength,
  base_unit_label, schedule, loyalty_eligible, sku, notes) on public.medicines to authenticated;
grant update (brand_name, generic_id, manufacturer_id, dosage_form, strength, base_unit_label,
  schedule, loyalty_eligible, sku, notes, is_active) on public.medicines to authenticated;
grant insert (organization_id, medicine_id, name, units_per_pack, is_default) on public.medicine_packs to authenticated;
grant update (name, units_per_pack, is_default) on public.medicine_packs to authenticated;
grant delete on public.medicine_packs to authenticated;
grant insert (organization_id, medicine_id, pack_id, barcode) on public.medicine_barcodes to authenticated;
grant delete on public.medicine_barcodes to authenticated;
grant insert (organization_id, branch_id, medicine_id, reorder_level, max_stock_level, rack_location)
  on public.branch_medicine_settings to authenticated;
grant update (reorder_level, max_stock_level, rack_location) on public.branch_medicine_settings to authenticated;

-- Cost columns are deliberately NOT granted: purchase cost and profit are visible only through
-- permission-checked report functions (reports.view_cost).
grant select (id, organization_id, branch_id, medicine_id, batch_no, expiry_date, mrp_paisa,
  sale_price_paisa, quantity_on_hand, received_at, created_at, created_by, updated_at, updated_by)
  on public.batches to authenticated;
grant select (id, organization_id, branch_id, batch_id, medicine_id, movement_type, quantity,
  reference_type, reference_id, note, created_by, created_at)
  on public.inventory_movements to authenticated;

-- Default the creator columns from the JWT on direct (RLS-checked) inserts.
create or replace function app.set_created_by()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.created_by := coalesce(auth.uid(), new.created_by);
  return new;
end;
$$;

create trigger manufacturers_created_by before insert on public.manufacturers
  for each row execute function app.set_created_by();
create trigger generics_created_by before insert on public.generics
  for each row execute function app.set_created_by();
create trigger medicines_created_by before insert on public.medicines
  for each row execute function app.set_created_by();
create trigger medicine_packs_created_by before insert on public.medicine_packs
  for each row execute function app.set_created_by();
create trigger medicine_barcodes_created_by before insert on public.medicine_barcodes
  for each row execute function app.set_created_by();

-- -----------------------------------------------------------------------------
-- Internal: post one stock movement and update the batch projection atomically.
-- Callers must already hold the batch row lock (SELECT ... FOR UPDATE) when ordering matters.
-- -----------------------------------------------------------------------------
create or replace function app.post_movement(
  p_batch_id uuid,
  p_type public.movement_type,
  p_quantity integer,
  p_reference_type text,
  p_reference_id uuid,
  p_note text default null
)
returns public.batches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.batches;
begin
  update public.batches
     set quantity_on_hand = quantity_on_hand + p_quantity,
         updated_by = auth.uid()
   where id = p_batch_id
     and quantity_on_hand + p_quantity >= 0
  returning * into v_batch;

  if v_batch.id is null then
    if not exists (select 1 from public.batches where id = p_batch_id) then
      perform app.fail('not_found', 'Batch not found');
    end if;
    perform app.fail('insufficient_stock', 'Not enough stock in this batch');
  end if;

  insert into public.inventory_movements (
    organization_id, branch_id, batch_id, medicine_id, movement_type, quantity,
    unit_cost_paisa, reference_type, reference_id, note, created_by
  ) values (
    v_batch.organization_id, v_batch.branch_id, v_batch.id, v_batch.medicine_id, p_type, p_quantity,
    v_batch.cost_paisa, p_reference_type, p_reference_id, p_note, auth.uid()
  );

  return v_batch;
end;
$$;

-- Validates a new batch's prices and dates; returns nothing, raises on error.
create or replace function app.validate_batch_input(
  p_organization_id uuid,
  p_medicine_id uuid,
  p_expiry_date date,
  p_mrp_paisa bigint,
  p_sale_price_paisa bigint,
  p_cost_paisa bigint
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.medicines m
     where m.id = p_medicine_id and m.organization_id = p_organization_id and m.is_active
  ) then
    perform app.fail('invalid_medicine', 'Medicine not found or inactive');
  end if;
  if p_expiry_date is null or p_expiry_date <= app.business_date(p_organization_id) then
    perform app.fail('expired_batch', 'Expiry date must be in the future');
  end if;
  if p_mrp_paisa is null or p_mrp_paisa <= 0 then
    perform app.fail('invalid_price', 'MRP must be greater than zero');
  end if;
  if p_sale_price_paisa is null or p_sale_price_paisa <= 0 or p_sale_price_paisa > p_mrp_paisa then
    perform app.fail('price_above_mrp', 'Sale price must be greater than zero and not above MRP');
  end if;
  if p_cost_paisa is null or p_cost_paisa < 0 then
    perform app.fail('invalid_cost', 'Cost cannot be negative');
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC: inventory operations
-- -----------------------------------------------------------------------------

-- Loads existing stock when a branch goes live. Items:
-- [{medicine_id, batch_no, expiry_date, quantity, cost_paisa, mrp_paisa, sale_price_paisa}]
create or replace function public.add_opening_stock(p_branch_id uuid, p_items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := app.require_branch_permission(p_branch_id, 'stock.adjust');
  v_item jsonb;
  v_batch uuid;
  v_qty integer;
  v_count integer := 0;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 1000 then
    perform app.fail('invalid_items', 'Provide between 1 and 1000 items');
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item ->> 'quantity')::integer;
    if v_qty is null or v_qty <= 0 then
      perform app.fail('invalid_quantity', 'Quantity must be greater than zero');
    end if;
    perform app.validate_batch_input(v_org, (v_item ->> 'medicine_id')::uuid,
      (v_item ->> 'expiry_date')::date, (v_item ->> 'mrp_paisa')::bigint,
      (v_item ->> 'sale_price_paisa')::bigint, (v_item ->> 'cost_paisa')::bigint);

    insert into public.batches (
      organization_id, branch_id, medicine_id, batch_no, expiry_date, cost_paisa, mrp_paisa,
      sale_price_paisa, created_by, updated_by
    ) values (
      v_org, p_branch_id, (v_item ->> 'medicine_id')::uuid, btrim(v_item ->> 'batch_no'),
      (v_item ->> 'expiry_date')::date, (v_item ->> 'cost_paisa')::bigint,
      (v_item ->> 'mrp_paisa')::bigint, (v_item ->> 'sale_price_paisa')::bigint, auth.uid(), auth.uid()
    ) returning id into v_batch;

    perform app.post_movement(v_batch, 'opening_balance', v_qty, 'opening_stock', null, 'Opening stock');
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- Manual stock correction (damage, loss, count correction, expiry write-off...).
create or replace function public.adjust_stock(
  p_batch_id uuid,
  p_quantity_delta integer,
  p_reason public.adjustment_reason,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.batches;
  v_adjustment uuid;
  v_type public.movement_type;
begin
  select * into v_batch from public.batches where id = p_batch_id for update;
  if v_batch.id is null then
    perform app.fail('not_found', 'Batch not found');
  end if;
  perform app.require_branch_permission(v_batch.branch_id, 'stock.adjust');

  if p_quantity_delta is null or p_quantity_delta = 0 then
    perform app.fail('invalid_quantity', 'Adjustment quantity cannot be zero');
  end if;
  if p_reason = 'opening_balance' then
    perform app.fail('invalid_reason', 'Use add_opening_stock for opening balances');
  end if;
  if p_reason = 'expired_writeoff' and p_quantity_delta > 0 then
    perform app.fail('invalid_quantity', 'An expiry write-off must reduce stock');
  end if;

  v_type := case p_reason
    when 'expired_writeoff' then 'expiry_writeoff'
    when 'count_correction' then 'count_correction'
    else 'adjustment'
  end;

  insert into public.stock_adjustments (
    organization_id, branch_id, batch_id, quantity_delta, reason, note, created_by
  ) values (
    v_batch.organization_id, v_batch.branch_id, v_batch.id, p_quantity_delta, p_reason,
    nullif(btrim(p_note), ''), auth.uid()
  ) returning id into v_adjustment;

  perform app.post_movement(v_batch.id, v_type, p_quantity_delta, 'stock_adjustment', v_adjustment, p_note);
  return v_adjustment;
end;
$$;

-- Changes the selling price / MRP of a batch (audited).
create or replace function public.set_batch_price(
  p_batch_id uuid,
  p_sale_price_paisa bigint,
  p_mrp_paisa bigint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.batches;
  v_mrp bigint;
begin
  select * into v_batch from public.batches where id = p_batch_id for update;
  if v_batch.id is null then
    perform app.fail('not_found', 'Batch not found');
  end if;
  perform app.require_branch_permission(v_batch.branch_id, 'pricing.manage');
  v_mrp := coalesce(p_mrp_paisa, v_batch.mrp_paisa);
  if v_mrp <= 0 or p_sale_price_paisa is null or p_sale_price_paisa <= 0 or p_sale_price_paisa > v_mrp then
    perform app.fail('price_above_mrp', 'Sale price must be greater than zero and not above MRP');
  end if;
  update public.batches
     set sale_price_paisa = p_sale_price_paisa, mrp_paisa = v_mrp
   where id = p_batch_id;
end;
$$;

-- POS search by barcode, brand or generic name with live branch stock and the FEFO price.
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
  nearest_expiry date
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_query text := btrim(coalesce(p_query, ''));
  v_pattern text;
  v_today date;
  v_block integer;
begin
  if not app.has_branch_access(p_branch_id) then
    perform app.fail('forbidden', 'You do not have access to this branch');
  end if;
  if length(v_query) < 2 then
    return;
  end if;
  v_pattern := '%' || replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  v_today := app.business_date(app.branch_org_id(p_branch_id));
  select s.near_expiry_block_days into v_block
    from public.organization_settings s where s.organization_id = app.branch_org_id(p_branch_id);

  return query
  with matches as (
    select m.id,
           case
             when exists (select 1 from public.medicine_barcodes mb where mb.medicine_id = m.id and mb.barcode = v_query) then 3.0
             when m.brand_name ilike v_query || '%' then 2.0 + extensions.similarity(m.brand_name, v_query)
             else greatest(extensions.similarity(m.brand_name, v_query), coalesce(extensions.similarity(g.name, v_query), 0))
           end as score
      from public.medicines m
      left join public.generics g on g.id = m.generic_id
     where m.organization_id = app.branch_org_id(p_branch_id)
       and m.is_active
       and (
         m.brand_name ilike v_pattern
         or g.name ilike v_pattern
         or exists (select 1 from public.medicine_barcodes mb where mb.medicine_id = m.id and mb.barcode = v_query)
       )
  )
  select m.id, m.brand_name, g.name, mf.name, m.dosage_form, m.strength, m.schedule, m.base_unit_label,
         coalesce(stock.qty, 0)::bigint,
         fefo.sale_price_paisa,
         fefo.expiry_date
    from matches x
    join public.medicines m on m.id = x.id
    left join public.generics g on g.id = m.generic_id
    left join public.manufacturers mf on mf.id = m.manufacturer_id
    left join lateral (
      select sum(b.quantity_on_hand) as qty
        from public.batches b
       where b.branch_id = p_branch_id and b.medicine_id = m.id
         and b.quantity_on_hand > 0 and b.expiry_date > v_today + v_block
    ) stock on true
    left join lateral (
      select b.sale_price_paisa, b.expiry_date
        from public.batches b
       where b.branch_id = p_branch_id and b.medicine_id = m.id
         and b.quantity_on_hand > 0 and b.expiry_date > v_today + v_block
       order by b.expiry_date, b.received_at, b.id
       limit 1
    ) fefo on true
   order by x.score desc, m.brand_name
   limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

grant execute on function
  public.add_opening_stock(uuid, jsonb),
  public.adjust_stock(uuid, integer, public.adjustment_reason, text),
  public.set_batch_price(uuid, bigint, bigint),
  public.search_medicines(uuid, text, integer)
to authenticated;

-- search_medicines runs as the caller (RLS applies) and needs these helpers.
grant execute on function app.branch_org_id(uuid), app.business_date(uuid, timestamptz), app.fail(text, text, text)
  to authenticated;

call app.harden_privileges();
