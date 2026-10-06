-- =============================================================================
-- Migration: sales (POS), prescriptions, controlled-drug register, voids, returns, daily summary
--
-- Invariants enforced here:
--   * prices, discounts and totals are computed by the database, never trusted from the client
--   * stock is allocated FEFO (first expiry, first out); expired / blocked batches are never sold
--   * invoice numbers are gapless per branch per fiscal year
--   * a retried request (same client_request_id) never creates a second sale
--   * per sale:  paid - change + due = total;  per line: net = gross - discounts >= 0
--   * concurrency: batch rows are locked in (medicine_id, expiry, received_at, id) order
-- =============================================================================

create type public.sale_status as enum ('completed', 'voided');

-- -----------------------------------------------------------------------------
-- Prescriptions and controlled drugs
-- -----------------------------------------------------------------------------
create table public.prescriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  customer_id uuid,
  patient_name text not null check (length(btrim(patient_name)) between 2 and 120),
  patient_age integer check (patient_age between 0 and 130),
  doctor_name text not null check (length(btrim(doctor_name)) between 2 and 120),
  doctor_reg_no text check (length(doctor_reg_no) <= 40),
  prescription_date date not null,
  storage_path text check (length(storage_path) <= 300),
  notes text check (length(notes) <= 500),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  foreign key (organization_id, customer_id) references public.customers (organization_id, id)
);
create index prescriptions_branch_time_idx on public.prescriptions (branch_id, created_at desc);

comment on table public.prescriptions is 'Prescription details captured at sale time (sensitive health data).';

-- -----------------------------------------------------------------------------
-- Sales
-- -----------------------------------------------------------------------------
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  invoice_no text not null,
  business_date date not null,
  status public.sale_status not null default 'completed',
  customer_id uuid,
  loyalty_card_id uuid,
  loyalty_membership_id uuid,
  prescription_id uuid,
  gross_paisa bigint not null check (gross_paisa >= 0),
  line_discount_paisa bigint not null check (line_discount_paisa >= 0),
  invoice_discount_paisa bigint not null check (invoice_discount_paisa >= 0),
  loyalty_discount_paisa bigint not null check (loyalty_discount_paisa >= 0),
  net_paisa bigint not null check (net_paisa >= 0),
  rounding_paisa bigint not null default 0 check (rounding_paisa between -50 and 50),
  total_paisa bigint not null check (total_paisa >= 0),
  vat_included_paisa bigint not null default 0 check (vat_included_paisa >= 0),
  paid_paisa bigint not null check (paid_paisa >= 0),
  change_paisa bigint not null check (change_paisa >= 0),
  due_paisa bigint not null check (due_paisa >= 0),
  cost_paisa bigint not null check (cost_paisa >= 0),
  points_earned integer not null default 0 check (points_earned >= 0),
  points_redeemed integer not null default 0 check (points_redeemed >= 0),
  points_redeemed_value_paisa bigint not null default 0 check (points_redeemed_value_paisa >= 0),
  refunded_paisa bigint not null default 0 check (refunded_paisa >= 0 and refunded_paisa <= net_paisa),
  note text check (length(note) <= 500),
  client_request_id uuid not null,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references auth.users (id),
  void_reason text check (length(void_reason) <= 200),
  unique (organization_id, id),
  unique (organization_id, invoice_no),
  unique (organization_id, client_request_id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  foreign key (organization_id, customer_id) references public.customers (organization_id, id),
  foreign key (organization_id, loyalty_card_id) references public.loyalty_cards (organization_id, id),
  foreign key (organization_id, loyalty_membership_id) references public.loyalty_memberships (organization_id, id),
  foreign key (organization_id, prescription_id) references public.prescriptions (organization_id, id),
  constraint sales_net check (net_paisa = gross_paisa - line_discount_paisa - invoice_discount_paisa - loyalty_discount_paisa),
  constraint sales_total check (total_paisa = net_paisa + rounding_paisa),
  constraint sales_settlement check (paid_paisa - change_paisa + due_paisa = total_paisa),
  constraint sales_due_needs_customer check (due_paisa = 0 or customer_id is not null),
  constraint sales_void_fields check ((status = 'voided') = (voided_at is not null))
);

create index sales_branch_date_idx on public.sales (branch_id, business_date desc, created_at desc);
create index sales_customer_idx on public.sales (customer_id, created_at desc) where customer_id is not null;
create index sales_loyalty_card_idx on public.sales (loyalty_card_id, business_date) where loyalty_card_id is not null;
create index sales_org_date_idx on public.sales (organization_id, business_date);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  sale_id uuid not null,
  branch_id uuid not null,
  line_no integer not null check (line_no > 0),
  medicine_id uuid not null,
  quantity integer not null check (quantity > 0),
  gross_paisa bigint not null check (gross_paisa >= 0),
  line_discount_bp integer not null default 0 check (line_discount_bp between 0 and 10000),
  line_discount_paisa bigint not null check (line_discount_paisa >= 0),
  invoice_discount_paisa bigint not null check (invoice_discount_paisa >= 0),
  loyalty_discount_paisa bigint not null check (loyalty_discount_paisa >= 0),
  net_paisa bigint not null check (net_paisa >= 0),
  cost_paisa bigint not null check (cost_paisa >= 0),
  returned_quantity integer not null default 0 check (returned_quantity >= 0 and returned_quantity <= quantity),
  unique (organization_id, id),
  unique (sale_id, line_no),
  unique (sale_id, medicine_id),
  foreign key (organization_id, sale_id) references public.sales (organization_id, id),
  foreign key (organization_id, medicine_id) references public.medicines (organization_id, id),
  constraint sale_items_net check (net_paisa = gross_paisa - line_discount_paisa - invoice_discount_paisa - loyalty_discount_paisa)
);
create index sale_items_sale_idx on public.sale_items (sale_id);
create index sale_items_medicine_idx on public.sale_items (medicine_id);

-- FEFO allocation of each sale line to batches.
create table public.sale_item_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  sale_item_id uuid not null,
  batch_id uuid not null,
  quantity integer not null check (quantity > 0),
  unit_price_paisa bigint not null check (unit_price_paisa > 0),
  unit_cost_paisa bigint not null check (unit_cost_paisa >= 0),
  returned_quantity integer not null default 0 check (returned_quantity >= 0 and returned_quantity <= quantity),
  foreign key (organization_id, sale_item_id) references public.sale_items (organization_id, id),
  foreign key (organization_id, batch_id) references public.batches (organization_id, id)
);
create index sale_item_batches_item_idx on public.sale_item_batches (sale_item_id);
create index sale_item_batches_batch_idx on public.sale_item_batches (batch_id);

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  sale_id uuid not null,
  method public.payment_method not null,
  amount_paisa bigint not null check (amount_paisa > 0),
  reference text check (length(reference) <= 80),
  created_at timestamptz not null default now(),
  foreign key (organization_id, sale_id) references public.sales (organization_id, id)
);
create index sale_payments_sale_idx on public.sale_payments (sale_id);

create trigger sale_payments_append_only
  before update or delete on public.sale_payments
  for each row execute function app.forbid_mutation();
create trigger prescriptions_append_only
  before update or delete on public.prescriptions
  for each row execute function app.forbid_mutation();

create table public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  sale_id uuid not null,
  return_no text not null,
  business_date date not null,
  refund_paisa bigint not null check (refund_paisa >= 0),
  cash_refund_paisa bigint not null check (cash_refund_paisa >= 0),
  due_reduction_paisa bigint not null check (due_reduction_paisa >= 0),
  points_refund_value_paisa bigint not null default 0 check (points_refund_value_paisa >= 0),
  refund_method public.payment_method,
  cost_paisa bigint not null check (cost_paisa >= 0),
  points_returned integer not null default 0 check (points_returned >= 0),
  points_reversed integer not null default 0 check (points_reversed >= 0),
  reason text not null check (length(btrim(reason)) between 3 and 200),
  client_request_id uuid not null,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, return_no),
  unique (organization_id, client_request_id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  foreign key (organization_id, sale_id) references public.sales (organization_id, id),
  constraint sale_returns_split check (refund_paisa = cash_refund_paisa + due_reduction_paisa + points_refund_value_paisa)
);
create index sale_returns_sale_idx on public.sale_returns (sale_id);
create index sale_returns_branch_date_idx on public.sale_returns (branch_id, business_date desc);

create table public.sale_return_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  sale_return_id uuid not null,
  sale_item_id uuid not null,
  quantity integer not null check (quantity > 0),
  refund_paisa bigint not null check (refund_paisa >= 0),
  cost_paisa bigint not null check (cost_paisa >= 0),
  foreign key (organization_id, sale_return_id) references public.sale_returns (organization_id, id),
  foreign key (organization_id, sale_item_id) references public.sale_items (organization_id, id)
);
create index sale_return_items_return_idx on public.sale_return_items (sale_return_id);

create trigger sale_returns_append_only
  before update or delete on public.sale_returns
  for each row execute function app.forbid_mutation();
create trigger sale_return_items_append_only
  before update or delete on public.sale_return_items
  for each row execute function app.forbid_mutation();

-- Controlled drug register (DGDA): one signed row per sale / void / return of a controlled medicine.
create table public.controlled_drug_register (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  branch_id uuid not null,
  medicine_id uuid not null,
  sale_id uuid not null,
  sale_item_id uuid not null,
  prescription_id uuid,
  entry_type text not null check (entry_type in ('sale', 'void', 'return')),
  quantity integer not null check (quantity <> 0),
  patient_name text,
  doctor_name text,
  doctor_reg_no text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  foreign key (organization_id, medicine_id) references public.medicines (organization_id, id),
  foreign key (organization_id, sale_id) references public.sales (organization_id, id),
  constraint controlled_drug_register_direction check ((entry_type = 'sale') = (quantity < 0))
);
create index controlled_drug_register_branch_time_idx on public.controlled_drug_register (branch_id, created_at desc);
create index controlled_drug_register_medicine_idx on public.controlled_drug_register (medicine_id, created_at desc);

create trigger controlled_drug_register_append_only
  before update or delete on public.controlled_drug_register
  for each row execute function app.forbid_mutation();

-- Sales / sale lines are only ever changed by void and return functions, and only these columns.
create or replace function app.sales_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (to_jsonb(new) - array['status', 'voided_at', 'voided_by', 'void_reason', 'refunded_paisa'])
     is distinct from (to_jsonb(old) - array['status', 'voided_at', 'voided_by', 'void_reason', 'refunded_paisa']) then
    perform app.fail('immutable_sale', 'A completed sale cannot be edited; void or return it instead');
  end if;
  if old.status = 'voided' then
    perform app.fail('immutable_sale', 'A voided sale cannot be changed');
  end if;
  return new;
end;
$$;

create or replace function app.sale_lines_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (to_jsonb(new) - 'returned_quantity') is distinct from (to_jsonb(old) - 'returned_quantity')
     or new.returned_quantity < old.returned_quantity then
    perform app.fail('immutable_sale', 'Sale lines cannot be edited');
  end if;
  return new;
end;
$$;

create trigger sales_guard_update before update on public.sales
  for each row execute function app.sales_guard_update();
create trigger sales_forbid_delete before delete on public.sales
  for each row execute function app.forbid_mutation();
create trigger sale_items_guard_update before update on public.sale_items
  for each row execute function app.sale_lines_guard_update();
create trigger sale_items_forbid_delete before delete on public.sale_items
  for each row execute function app.forbid_mutation();
create trigger sale_item_batches_guard_update before update on public.sale_item_batches
  for each row execute function app.sale_lines_guard_update();
create trigger sale_item_batches_forbid_delete before delete on public.sale_item_batches
  for each row execute function app.forbid_mutation();

-- Voids are audited (status change); creation is already fully recorded in the sales tables.
create trigger audit_void
  after update on public.sales
  for each row
  when (old.status is distinct from new.status)
  execute function app.audit_row();

-- -----------------------------------------------------------------------------
-- Daily summary per branch (keeps dashboards fast regardless of history size)
-- -----------------------------------------------------------------------------
create table public.daily_branch_sales (
  organization_id uuid not null,
  branch_id uuid not null,
  business_date date not null,
  sales_count integer not null default 0,
  gross_paisa bigint not null default 0,
  discount_paisa bigint not null default 0,
  loyalty_discount_paisa bigint not null default 0,
  net_paisa bigint not null default 0,
  cost_paisa bigint not null default 0,
  credit_sales_paisa bigint not null default 0,
  returns_count integer not null default 0,
  returns_paisa bigint not null default 0,
  returns_cost_paisa bigint not null default 0,
  voids_count integer not null default 0,
  voided_paisa bigint not null default 0,
  voided_cost_paisa bigint not null default 0,
  primary key (branch_id, business_date),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id)
);
create index daily_branch_sales_org_date_idx on public.daily_branch_sales (organization_id, business_date);

create or replace function app.bump_daily_sales(
  p_organization_id uuid,
  p_branch_id uuid,
  p_business_date date,
  p_sales_count integer default 0,
  p_gross bigint default 0,
  p_discount bigint default 0,
  p_loyalty_discount bigint default 0,
  p_net bigint default 0,
  p_cost bigint default 0,
  p_credit bigint default 0,
  p_returns_count integer default 0,
  p_returns bigint default 0,
  p_returns_cost bigint default 0,
  p_voids_count integer default 0,
  p_voided bigint default 0,
  p_voided_cost bigint default 0
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.daily_branch_sales as d (
    organization_id, branch_id, business_date, sales_count, gross_paisa, discount_paisa,
    loyalty_discount_paisa, net_paisa, cost_paisa, credit_sales_paisa, returns_count, returns_paisa,
    returns_cost_paisa, voids_count, voided_paisa, voided_cost_paisa
  ) values (
    p_organization_id, p_branch_id, p_business_date, p_sales_count, p_gross, p_discount, p_loyalty_discount,
    p_net, p_cost, p_credit, p_returns_count, p_returns, p_returns_cost, p_voids_count, p_voided, p_voided_cost
  )
  on conflict (branch_id, business_date) do update set
    sales_count = d.sales_count + excluded.sales_count,
    gross_paisa = d.gross_paisa + excluded.gross_paisa,
    discount_paisa = d.discount_paisa + excluded.discount_paisa,
    loyalty_discount_paisa = d.loyalty_discount_paisa + excluded.loyalty_discount_paisa,
    net_paisa = d.net_paisa + excluded.net_paisa,
    cost_paisa = d.cost_paisa + excluded.cost_paisa,
    credit_sales_paisa = d.credit_sales_paisa + excluded.credit_sales_paisa,
    returns_count = d.returns_count + excluded.returns_count,
    returns_paisa = d.returns_paisa + excluded.returns_paisa,
    returns_cost_paisa = d.returns_cost_paisa + excluded.returns_cost_paisa,
    voids_count = d.voids_count + excluded.voids_count,
    voided_paisa = d.voided_paisa + excluded.voided_paisa,
    voided_cost_paisa = d.voided_cost_paisa + excluded.voided_cost_paisa
$$;

-- -----------------------------------------------------------------------------
-- RLS and grants
-- -----------------------------------------------------------------------------
alter table public.prescriptions enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.sale_item_batches enable row level security;
alter table public.sale_payments enable row level security;
alter table public.sale_returns enable row level security;
alter table public.sale_return_items enable row level security;
alter table public.controlled_drug_register enable row level security;
alter table public.daily_branch_sales enable row level security;

create policy prescriptions_select on public.prescriptions for select to authenticated
  using (branch_id in (select app.user_branch_ids()));
create policy sales_select on public.sales for select to authenticated
  using (branch_id in (select app.user_branch_ids()));
create policy sale_items_select on public.sale_items for select to authenticated
  using (branch_id in (select app.user_branch_ids()));
create policy sale_item_batches_select on public.sale_item_batches for select to authenticated
  using (exists (
    select 1 from public.sale_items si
     where si.id = sale_item_batches.sale_item_id and si.branch_id in (select app.user_branch_ids())
  ));
create policy sale_payments_select on public.sale_payments for select to authenticated
  using (exists (
    select 1 from public.sales s
     where s.id = sale_payments.sale_id and s.branch_id in (select app.user_branch_ids())
  ));
create policy sale_returns_select on public.sale_returns for select to authenticated
  using (branch_id in (select app.user_branch_ids()));
create policy sale_return_items_select on public.sale_return_items for select to authenticated
  using (exists (
    select 1 from public.sale_returns r
     where r.id = sale_return_items.sale_return_id and r.branch_id in (select app.user_branch_ids())
  ));
create policy controlled_drug_register_select on public.controlled_drug_register for select to authenticated
  using (branch_id in (select app.user_branch_ids()) and app.has_permission(organization_id, 'reports.view'));
create policy daily_branch_sales_select on public.daily_branch_sales for select to authenticated
  using (branch_id in (select app.user_branch_ids()) and app.has_permission(organization_id, 'reports.view'));

grant select on public.prescriptions, public.sale_payments, public.sale_return_items,
  public.controlled_drug_register to authenticated;
-- Cost columns are excluded (see reports functions for permission-checked profit figures).
grant select (id, organization_id, branch_id, invoice_no, business_date, status, customer_id, loyalty_card_id,
  loyalty_membership_id, prescription_id, gross_paisa, line_discount_paisa, invoice_discount_paisa,
  loyalty_discount_paisa, net_paisa, rounding_paisa, total_paisa, vat_included_paisa, paid_paisa, change_paisa,
  due_paisa, points_earned, points_redeemed, points_redeemed_value_paisa, refunded_paisa, note, client_request_id,
  created_by, created_at, voided_at, voided_by, void_reason) on public.sales to authenticated;
grant select (id, organization_id, sale_id, branch_id, line_no, medicine_id, quantity, gross_paisa,
  line_discount_bp, line_discount_paisa, invoice_discount_paisa, loyalty_discount_paisa, net_paisa,
  returned_quantity) on public.sale_items to authenticated;
grant select (id, organization_id, sale_item_id, batch_id, quantity, unit_price_paisa, returned_quantity)
  on public.sale_item_batches to authenticated;
grant select (id, organization_id, branch_id, sale_id, return_no, business_date, refund_paisa, cash_refund_paisa,
  due_reduction_paisa, points_refund_value_paisa, refund_method, points_returned, points_reversed, reason,
  client_request_id, created_by, created_at) on public.sale_returns to authenticated;
grant select (organization_id, branch_id, business_date, sales_count, gross_paisa, discount_paisa,
  loyalty_discount_paisa, net_paisa, credit_sales_paisa, returns_count, returns_paisa, voids_count, voided_paisa)
  on public.daily_branch_sales to authenticated;

-- -----------------------------------------------------------------------------
-- create_sale
-- -----------------------------------------------------------------------------
-- p_items:    [{ "medicine_id": uuid, "quantity": int, "discount_bp": int? }]
-- p_payments: [{ "method": payment_method, "amount_paisa": int, "reference": text? }]
-- p_prescription (required for controlled medicines):
--             { "patient_name", "patient_age"?, "doctor_name", "doctor_reg_no", "prescription_date",
--               "storage_path"?, "notes"? }
create or replace function public.create_sale(
  p_branch_id uuid,
  p_items jsonb,
  p_payments jsonb,
  p_client_request_id uuid,
  p_customer_id uuid default null,
  p_loyalty_card_no text default null,
  p_invoice_discount_paisa bigint default 0,
  p_prescription jsonb default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid := app.require_branch_permission(p_branch_id, 'sales.create');
  v_settings public.organization_settings;
  v_today date;
  v_existing public.sales;
  v_membership public.loyalty_memberships;
  v_customer public.customers;
  v_sale_id uuid := gen_random_uuid();
  v_invoice_no text;
  v_prescription_id uuid;
  v_max_bp integer;

  -- per-line working arrays (index = line number in medicine_id order)
  v_medicine_ids uuid[] := '{}';
  v_quantities integer[] := '{}';
  v_discount_bps integer[] := '{}';
  v_eligible boolean[] := '{}';
  v_controlled boolean[] := '{}';
  v_gross bigint[] := '{}';
  v_line_disc bigint[] := '{}';
  v_inv_disc bigint[];
  v_loy_disc bigint[] := '{}';
  v_net bigint[] := '{}';
  v_cost bigint[] := '{}';
  v_allocations jsonb[] := '{}';
  v_after_line bigint[] := '{}';

  v_item record;
  v_batch record;
  v_medicine public.medicines;
  v_need integer;
  v_take integer;
  v_alloc jsonb;
  v_line_gross bigint;
  v_line_cost bigint;
  v_n integer := 0;
  i integer;

  v_gross_total bigint := 0;
  v_line_disc_total bigint := 0;
  v_loy_total bigint := 0;
  v_net_total bigint := 0;
  v_cost_total bigint := 0;
  v_rounding bigint := 0;
  v_total bigint;
  v_vat bigint;
  v_eligible_net bigint := 0;

  v_payment jsonb;
  v_method public.payment_method;
  v_amount bigint;
  v_paid bigint := 0;
  v_cash bigint := 0;
  v_points_value bigint := 0;
  v_points_redeemed integer := 0;
  v_points_earned integer := 0;
  v_change bigint := 0;
  v_due bigint := 0;
  v_has_controlled boolean := false;
  v_has_rx boolean := false;
  v_sale_item_id uuid;
begin
  -- 1. Idempotency: a retried request returns the original sale.
  if p_client_request_id is null then
    perform app.fail('missing_request_id', 'client_request_id is required');
  end if;
  select * into v_existing from public.sales
   where organization_id = v_org and client_request_id = p_client_request_id;
  if v_existing.id is not null then
    if v_existing.created_by <> v_user or v_existing.branch_id <> p_branch_id then
      perform app.fail('request_id_conflict', 'This request id was already used for another sale');
    end if;
    return jsonb_build_object('sale_id', v_existing.id, 'invoice_no', v_existing.invoice_no,
      'total_paisa', v_existing.total_paisa, 'paid_paisa', v_existing.paid_paisa,
      'change_paisa', v_existing.change_paisa, 'due_paisa', v_existing.due_paisa,
      'points_earned', v_existing.points_earned, 'replayed', true);
  end if;

  select * into v_settings from public.organization_settings where organization_id = v_org;
  v_today := app.business_date(v_org);
  v_max_bp := app.max_discount_bp(v_org);

  -- 2. Input shape
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200 then
    perform app.fail('invalid_items', 'A sale needs between 1 and 200 lines');
  end if;
  if jsonb_typeof(coalesce(p_payments, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_payments, '[]'::jsonb)) > 10 then
    perform app.fail('invalid_payments', 'Too many payment lines');
  end if;
  if (select count(distinct e ->> 'medicine_id') from jsonb_array_elements(p_items) e) <> jsonb_array_length(p_items) then
    perform app.fail('duplicate_items', 'Each medicine may appear only once; change the quantity instead');
  end if;

  -- 3. Customer and loyalty
  if p_customer_id is not null then
    select * into v_customer from public.customers where id = p_customer_id and organization_id = v_org;
    if v_customer.id is null or not v_customer.is_active then
      perform app.fail('invalid_customer', 'Customer not found or inactive');
    end if;
  end if;
  if p_loyalty_card_no is not null and btrim(p_loyalty_card_no) <> '' then
    if not v_settings.loyalty_enabled then
      perform app.fail('loyalty_disabled', 'The loyalty programme is turned off');
    end if;
    v_membership := app.active_membership_by_card(v_org, p_loyalty_card_no, v_today);
    if v_membership.id is null then
      perform app.fail('loyalty_inactive', 'This loyalty card has no active membership today');
    end if;
    if v_customer.id is not null and v_customer.id <> v_membership.customer_id then
      perform app.fail('loyalty_customer_mismatch', 'The loyalty card belongs to a different customer');
    end if;
    select * into v_customer from public.customers where id = v_membership.customer_id;
  end if;

  -- 4. Lines in medicine_id order (global lock order => no deadlocks between concurrent sales)
  for v_item in
    select (e ->> 'medicine_id')::uuid as medicine_id,
           (e ->> 'quantity')::integer as quantity,
           coalesce((e ->> 'discount_bp')::integer, 0) as discount_bp
      from jsonb_array_elements(p_items) e
     order by 1
  loop
    v_n := v_n + 1;
    select * into v_medicine from public.medicines
     where id = v_item.medicine_id and organization_id = v_org and is_active;
    if v_medicine.id is null then
      perform app.fail('invalid_medicine', 'Medicine not found or inactive');
    end if;
    if v_item.quantity is null or v_item.quantity not between 1 and 100000 then
      perform app.fail('invalid_quantity', format('Invalid quantity for %s', v_medicine.brand_name));
    end if;
    if v_item.discount_bp not between 0 and 10000 then
      perform app.fail('invalid_discount', 'Line discount must be between 0% and 100%');
    end if;
    if v_item.discount_bp > v_max_bp then
      perform app.fail('discount_limit', 'Discount exceeds your limit', 'Ask a manager to apply this discount');
    end if;

    -- FEFO allocation with row locks.
    v_need := v_item.quantity;
    v_line_gross := 0;
    v_line_cost := 0;
    v_alloc := '[]'::jsonb;
    for v_batch in
      select b.id, b.quantity_on_hand, b.sale_price_paisa, b.cost_paisa
        from public.batches b
       where b.branch_id = p_branch_id
         and b.medicine_id = v_medicine.id
         and b.quantity_on_hand > 0
         and b.expiry_date > v_today + v_settings.near_expiry_block_days
       order by b.expiry_date, b.received_at, b.id
       for update
    loop
      exit when v_need = 0;
      v_take := least(v_need, v_batch.quantity_on_hand);
      v_alloc := v_alloc || jsonb_build_object('batch_id', v_batch.id, 'quantity', v_take,
        'unit_price_paisa', v_batch.sale_price_paisa, 'unit_cost_paisa', v_batch.cost_paisa);
      v_line_gross := v_line_gross + v_take::bigint * v_batch.sale_price_paisa;
      v_line_cost := v_line_cost + v_take::bigint * v_batch.cost_paisa;
      v_need := v_need - v_take;
    end loop;
    if v_need > 0 then
      perform app.fail('insufficient_stock',
        format('Not enough sellable stock for %s (short by %s)', v_medicine.brand_name, v_need));
    end if;

    v_medicine_ids := v_medicine_ids || v_medicine.id;
    v_quantities := v_quantities || v_item.quantity;
    v_discount_bps := v_discount_bps || v_item.discount_bp;
    v_eligible := v_eligible || (v_medicine.loyalty_eligible and v_medicine.schedule <> 'controlled');
    v_controlled := v_controlled || (v_medicine.schedule = 'controlled');
    v_has_controlled := v_has_controlled or v_medicine.schedule = 'controlled';
    v_has_rx := v_has_rx or v_medicine.schedule = 'rx';
    v_gross := v_gross || v_line_gross;
    v_cost := v_cost || v_line_cost;
    v_allocations := v_allocations || v_alloc;
    v_line_disc := v_line_disc || app.percent_of(v_line_gross, v_item.discount_bp);
    v_after_line := v_after_line || (v_line_gross - v_line_disc[v_n]);
    v_gross_total := v_gross_total + v_line_gross;
    v_line_disc_total := v_line_disc_total + v_line_disc[v_n];
    v_cost_total := v_cost_total + v_line_cost;
  end loop;

  -- 5. Prescription rules
  if v_has_controlled or (v_has_rx and v_settings.require_prescription_for_rx) then
    if p_prescription is null
       or coalesce(length(btrim(p_prescription ->> 'patient_name')), 0) < 2
       or coalesce(length(btrim(p_prescription ->> 'doctor_name')), 0) < 2
       or (p_prescription ->> 'prescription_date') is null then
      perform app.fail('prescription_required', 'Prescription details are required for this sale');
    end if;
    if v_has_controlled and coalesce(length(btrim(p_prescription ->> 'doctor_reg_no')), 0) < 2 then
      perform app.fail('prescription_required', 'Doctor registration number is required for controlled medicines');
    end if;
    if (p_prescription ->> 'prescription_date')::date > v_today
       or (p_prescription ->> 'prescription_date')::date < v_today - 180 then
      perform app.fail('invalid_prescription', 'Prescription date must be within the last 180 days');
    end if;
  end if;
  if p_prescription is not null then
    insert into public.prescriptions (
      organization_id, branch_id, customer_id, patient_name, patient_age, doctor_name, doctor_reg_no,
      prescription_date, storage_path, notes, created_by
    ) values (
      v_org, p_branch_id, v_customer.id, btrim(p_prescription ->> 'patient_name'),
      (p_prescription ->> 'patient_age')::integer, btrim(p_prescription ->> 'doctor_name'),
      nullif(btrim(p_prescription ->> 'doctor_reg_no'), ''), (p_prescription ->> 'prescription_date')::date,
      nullif(btrim(p_prescription ->> 'storage_path'), ''), nullif(btrim(p_prescription ->> 'notes'), ''), v_user
    ) returning id into v_prescription_id;
  end if;

  -- 6. Invoice discount (spread over lines) and role discount limit on the whole invoice
  if p_invoice_discount_paisa is null or p_invoice_discount_paisa < 0
     or p_invoice_discount_paisa > v_gross_total - v_line_disc_total then
    perform app.fail('invalid_discount', 'Invoice discount must be between zero and the amount after line discounts');
  end if;
  if v_line_disc_total + p_invoice_discount_paisa > app.percent_of(v_gross_total, v_max_bp) then
    perform app.fail('discount_limit', 'Total discount exceeds your limit', 'Ask a manager to apply this discount');
  end if;
  v_inv_disc := app.allocate_proportionally(p_invoice_discount_paisa, v_after_line);

  -- 7. Loyalty discount on eligible lines (snapshotted membership terms, optional cap per invoice)
  for i in 1..v_n loop
    if v_membership.id is not null and v_eligible[i] and v_membership.discount_bp > 0 then
      v_loy_disc := v_loy_disc || app.percent_of(v_after_line[i] - v_inv_disc[i], v_membership.discount_bp);
    else
      v_loy_disc := v_loy_disc || 0::bigint;
    end if;
    v_loy_total := v_loy_total + v_loy_disc[i];
  end loop;
  if v_membership.max_discount_per_invoice_paisa is not null and v_loy_total > v_membership.max_discount_per_invoice_paisa then
    v_loy_disc := app.allocate_proportionally(v_membership.max_discount_per_invoice_paisa, v_loy_disc);
    v_loy_total := v_membership.max_discount_per_invoice_paisa;
  end if;

  for i in 1..v_n loop
    v_net := v_net || (v_after_line[i] - v_inv_disc[i] - v_loy_disc[i]);
    v_net_total := v_net_total + v_net[i];
    if v_eligible[i] then
      v_eligible_net := v_eligible_net + v_net[i];
    end if;
  end loop;

  -- 8. Rounding and VAT (prices are VAT-inclusive; VAT is reported, not added)
  if v_settings.cash_rounding = 'nearest_taka' then
    v_rounding := round(v_net_total / 100.0)::bigint * 100 - v_net_total;
  end if;
  v_total := v_net_total + v_rounding;
  v_vat := case when v_settings.vat_bp > 0
                then round(v_total::numeric * v_settings.vat_bp / (10000 + v_settings.vat_bp))::bigint
                else 0 end;

  -- 9. Payments
  for v_payment in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    v_method := (v_payment ->> 'method')::public.payment_method;
    v_amount := (v_payment ->> 'amount_paisa')::bigint;
    if v_amount is null or v_amount <= 0 then
      perform app.fail('invalid_payment', 'Payment amounts must be greater than zero');
    end if;
    if v_method = 'cash' then
      v_cash := v_cash + v_amount;
    elsif v_method = 'loyalty_points' then
      if v_membership.id is null or v_membership.point_value_paisa = 0 then
        perform app.fail('invalid_payment', 'Points can only be redeemed with an active loyalty card');
      end if;
      if v_amount % v_membership.point_value_paisa <> 0 then
        perform app.fail('invalid_payment', 'Points amount must be a whole number of points');
      end if;
      v_points_value := v_points_value + v_amount;
    end if;
    v_paid := v_paid + v_amount;
  end loop;
  if v_points_value > 0 then
    v_points_redeemed := (v_points_value / v_membership.point_value_paisa)::integer;
    perform 1 from public.loyalty_cards where id = v_membership.card_id for update;
    if v_points_redeemed < v_membership.min_redeem_points then
      perform app.fail('invalid_payment', format('At least %s points must be redeemed', v_membership.min_redeem_points));
    end if;
    if app.loyalty_points_balance(v_membership.card_id) < v_points_redeemed then
      perform app.fail('insufficient_points', 'Not enough loyalty points');
    end if;
  end if;
  if v_paid - v_cash > v_total then
    perform app.fail('overpayment', 'Card, mobile banking and points payments cannot exceed the total');
  end if;
  v_change := greatest(v_paid - v_total, 0);
  v_due := greatest(v_total - v_paid, 0);

  if v_due > 0 then
    if v_customer.id is null then
      perform app.fail('customer_required', 'Select a customer to sell on credit (due)');
    end if;
    perform app.require_branch_permission(p_branch_id, 'sales.credit');
    perform 1 from public.customers where id = v_customer.id for update;
    if app.customer_balance(v_customer.id) + v_due > v_customer.credit_limit_paisa then
      perform app.fail('credit_limit', 'This sale would exceed the customer''s credit limit');
    end if;
  end if;

  -- 10. Points earned on money spent on eligible items (not on the part paid with points)
  if v_membership.id is not null and v_membership.points_per_100_taka > 0 then
    v_points_earned := ((greatest(v_eligible_net - v_points_value, 0) / 10000) * v_membership.points_per_100_taka)::integer;
  end if;

  -- 11. Persist
  v_invoice_no := app.next_branch_document_no(p_branch_id, 'sale', '');

  insert into public.sales (
    id, organization_id, branch_id, invoice_no, business_date, customer_id, loyalty_card_id,
    loyalty_membership_id, prescription_id, gross_paisa, line_discount_paisa, invoice_discount_paisa,
    loyalty_discount_paisa, net_paisa, rounding_paisa, total_paisa, vat_included_paisa, paid_paisa,
    change_paisa, due_paisa, cost_paisa, points_earned, points_redeemed, points_redeemed_value_paisa,
    note, client_request_id, created_by
  ) values (
    v_sale_id, v_org, p_branch_id, v_invoice_no, v_today, v_customer.id, v_membership.card_id,
    v_membership.id, v_prescription_id, v_gross_total, v_line_disc_total, p_invoice_discount_paisa,
    v_loy_total, v_net_total, v_rounding, v_total, v_vat, v_paid, v_change, v_due, v_cost_total,
    v_points_earned, v_points_redeemed, v_points_value, nullif(btrim(p_note), ''), p_client_request_id, v_user
  );

  for i in 1..v_n loop
    insert into public.sale_items (
      organization_id, sale_id, branch_id, line_no, medicine_id, quantity, gross_paisa, line_discount_bp,
      line_discount_paisa, invoice_discount_paisa, loyalty_discount_paisa, net_paisa, cost_paisa
    ) values (
      v_org, v_sale_id, p_branch_id, i, v_medicine_ids[i], v_quantities[i], v_gross[i], v_discount_bps[i],
      v_line_disc[i], v_inv_disc[i], v_loy_disc[i], v_net[i], v_cost[i]
    ) returning id into v_sale_item_id;

    for v_alloc in select * from jsonb_array_elements(v_allocations[i]) loop
      insert into public.sale_item_batches (
        organization_id, sale_item_id, batch_id, quantity, unit_price_paisa, unit_cost_paisa
      ) values (
        v_org, v_sale_item_id, (v_alloc ->> 'batch_id')::uuid, (v_alloc ->> 'quantity')::integer,
        (v_alloc ->> 'unit_price_paisa')::bigint, (v_alloc ->> 'unit_cost_paisa')::bigint
      );
      perform app.post_movement((v_alloc ->> 'batch_id')::uuid, 'sale', -((v_alloc ->> 'quantity')::integer),
        'sale', v_sale_id);
    end loop;

    if v_controlled[i] then
      insert into public.controlled_drug_register (
        organization_id, branch_id, medicine_id, sale_id, sale_item_id, prescription_id, entry_type, quantity,
        patient_name, doctor_name, doctor_reg_no, created_by
      ) values (
        v_org, p_branch_id, v_medicine_ids[i], v_sale_id, v_sale_item_id, v_prescription_id, 'sale',
        -v_quantities[i], p_prescription ->> 'patient_name', p_prescription ->> 'doctor_name',
        p_prescription ->> 'doctor_reg_no', v_user
      );
    end if;
  end loop;

  for v_payment in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    insert into public.sale_payments (organization_id, sale_id, method, amount_paisa, reference)
    values (v_org, v_sale_id, (v_payment ->> 'method')::public.payment_method,
            (v_payment ->> 'amount_paisa')::bigint, nullif(left(btrim(v_payment ->> 'reference'), 80), ''));
  end loop;

  if v_due > 0 then
    insert into public.customer_ledger_entries (
      organization_id, customer_id, branch_id, entry_type, amount_paisa, reference_type, reference_id, created_by
    ) values (v_org, v_customer.id, p_branch_id, 'credit_sale', v_due, 'sale', v_sale_id, v_user);
  end if;

  if v_points_redeemed > 0 then
    insert into public.loyalty_point_ledger (organization_id, card_id, branch_id, entry_type, points, sale_id, created_by)
    values (v_org, v_membership.card_id, p_branch_id, 'redeem', -v_points_redeemed, v_sale_id, v_user);
  end if;
  if v_points_earned > 0 then
    insert into public.loyalty_point_ledger (organization_id, card_id, branch_id, entry_type, points, sale_id, created_by)
    values (v_org, v_membership.card_id, p_branch_id, 'earn', v_points_earned, v_sale_id, v_user);
  end if;

  perform app.bump_daily_sales(v_org, p_branch_id, v_today,
    p_sales_count => 1, p_gross => v_gross_total,
    p_discount => v_line_disc_total + p_invoice_discount_paisa + v_loy_total,
    p_loyalty_discount => v_loy_total, p_net => v_total, p_cost => v_cost_total, p_credit => v_due);

  return jsonb_build_object('sale_id', v_sale_id, 'invoice_no', v_invoice_no, 'total_paisa', v_total,
    'paid_paisa', v_paid, 'change_paisa', v_change, 'due_paisa', v_due, 'points_earned', v_points_earned,
    'loyalty_discount_paisa', v_loy_total, 'replayed', false);
end;
$$;

-- -----------------------------------------------------------------------------
-- void_sale: cancels a sale completely (same-day mistakes). Not allowed after any return.
-- -----------------------------------------------------------------------------
create or replace function public.void_sale(p_sale_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
  v_settings public.organization_settings;
  v_alloc record;
  v_points_balance integer;
begin
  select * into v_sale from public.sales where id = p_sale_id for update;
  if v_sale.id is null then
    perform app.fail('not_found', 'Sale not found');
  end if;
  perform app.require_branch_permission(v_sale.branch_id, 'sales.void');
  if v_sale.status = 'voided' then
    perform app.fail('already_voided', 'This sale is already voided');
  end if;
  if coalesce(length(btrim(p_reason)), 0) < 3 then
    perform app.fail('reason_required', 'A reason is required');
  end if;
  select * into v_settings from public.organization_settings where organization_id = v_sale.organization_id;
  if now() - v_sale.created_at > make_interval(hours => v_settings.void_window_hours) then
    perform app.fail('void_window_passed', 'This sale is too old to void; process a return instead');
  end if;
  if exists (select 1 from public.sale_returns r where r.sale_id = p_sale_id) then
    perform app.fail('has_returns', 'A sale with returns cannot be voided');
  end if;

  -- Restock every allocation (batches locked in id order).
  for v_alloc in
    select sib.batch_id, sib.quantity
      from public.sale_item_batches sib
      join public.sale_items si on si.id = sib.sale_item_id
     where si.sale_id = p_sale_id
     order by sib.batch_id
  loop
    perform 1 from public.batches where id = v_alloc.batch_id for update;
    perform app.post_movement(v_alloc.batch_id, 'sale_void', v_alloc.quantity, 'sale_void', p_sale_id, btrim(p_reason));
  end loop;

  if v_sale.due_paisa > 0 then
    insert into public.customer_ledger_entries (
      organization_id, customer_id, branch_id, entry_type, amount_paisa, reference_type, reference_id, created_by
    ) values (v_sale.organization_id, v_sale.customer_id, v_sale.branch_id, 'sale_void', -v_sale.due_paisa,
              'sale_void', p_sale_id, auth.uid());
  end if;

  if v_sale.loyalty_card_id is not null then
    perform 1 from public.loyalty_cards where id = v_sale.loyalty_card_id for update;
    if v_sale.points_redeemed > 0 then
      insert into public.loyalty_point_ledger (organization_id, card_id, branch_id, entry_type, points, sale_id, created_by)
      values (v_sale.organization_id, v_sale.loyalty_card_id, v_sale.branch_id, 'reverse_redeem',
              v_sale.points_redeemed, p_sale_id, auth.uid());
    end if;
    if v_sale.points_earned > 0 then
      v_points_balance := app.loyalty_points_balance(v_sale.loyalty_card_id);
      if least(v_sale.points_earned, v_points_balance) > 0 then
        insert into public.loyalty_point_ledger (organization_id, card_id, branch_id, entry_type, points, sale_id, created_by)
        values (v_sale.organization_id, v_sale.loyalty_card_id, v_sale.branch_id, 'reverse_earn',
                -least(v_sale.points_earned, v_points_balance), p_sale_id, auth.uid());
      end if;
    end if;
  end if;

  insert into public.controlled_drug_register (
    organization_id, branch_id, medicine_id, sale_id, sale_item_id, prescription_id, entry_type, quantity,
    patient_name, doctor_name, doctor_reg_no, created_by
  )
  select r.organization_id, r.branch_id, r.medicine_id, r.sale_id, r.sale_item_id, r.prescription_id, 'void',
         -r.quantity, r.patient_name, r.doctor_name, r.doctor_reg_no, auth.uid()
    from public.controlled_drug_register r
   where r.sale_id = p_sale_id and r.entry_type = 'sale';

  update public.sales
     set status = 'voided', voided_at = now(), voided_by = auth.uid(), void_reason = btrim(p_reason)
   where id = p_sale_id;

  perform app.bump_daily_sales(v_sale.organization_id, v_sale.branch_id, v_sale.business_date,
    p_voids_count => 1, p_voided => v_sale.total_paisa, p_voided_cost => v_sale.cost_paisa);
end;
$$;

-- -----------------------------------------------------------------------------
-- process_sale_return: partial or full return against the original invoice.
-- p_items: [{ "sale_item_id": uuid, "quantity": int }]
-- Refunds use cumulative proportional rounding so that all returns of a line add up exactly to
-- the line's net amount. Refund order: points paid -> outstanding due on this sale -> money.
-- -----------------------------------------------------------------------------
create or replace function public.process_sale_return(
  p_sale_id uuid,
  p_items jsonb,
  p_reason text,
  p_client_request_id uuid,
  p_refund_method public.payment_method default 'cash'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_sale public.sales;
  v_settings public.organization_settings;
  v_existing public.sale_returns;
  v_today date;
  v_return_id uuid := gen_random_uuid();
  v_return_no text;
  v_req record;
  v_line public.sale_items;
  v_alloc record;
  v_left integer;
  v_take integer;
  v_refund bigint := 0;
  v_cost bigint := 0;
  v_line_ids uuid[] := '{}';
  v_line_qty integer[] := '{}';
  v_line_refund bigint[] := '{}';
  v_line_cost bigint[] := '{}';
  v_restock jsonb := '[]'::jsonb;
  v_r jsonb;
  v_point_unit bigint;
  v_points_value_back bigint := 0;
  v_points_back integer := 0;
  v_points_reverse integer := 0;
  v_due_reduction bigint := 0;
  v_due_left bigint;
  v_cash_refund bigint;
  i integer;
begin
  if p_client_request_id is null then
    perform app.fail('missing_request_id', 'client_request_id is required');
  end if;
  select * into v_sale from public.sales where id = p_sale_id for update;
  if v_sale.id is null then
    perform app.fail('not_found', 'Sale not found');
  end if;
  perform app.require_branch_permission(v_sale.branch_id, 'sales.return');

  select * into v_existing from public.sale_returns
   where organization_id = v_sale.organization_id and client_request_id = p_client_request_id;
  if v_existing.id is not null then
    return jsonb_build_object('sale_return_id', v_existing.id, 'return_no', v_existing.return_no,
      'refund_paisa', v_existing.refund_paisa, 'cash_refund_paisa', v_existing.cash_refund_paisa,
      'due_reduction_paisa', v_existing.due_reduction_paisa, 'points_returned', v_existing.points_returned,
      'points_reversed', v_existing.points_reversed, 'replayed', true);
  end if;

  if v_sale.status <> 'completed' then
    perform app.fail('sale_voided', 'A voided sale cannot be returned');
  end if;
  if coalesce(length(btrim(p_reason)), 0) < 3 then
    perform app.fail('reason_required', 'A reason is required');
  end if;
  if p_refund_method is null or p_refund_method = 'loyalty_points' then
    perform app.fail('invalid_payment', 'Choose a money refund method');
  end if;
  select * into v_settings from public.organization_settings where organization_id = v_sale.organization_id;
  v_today := app.business_date(v_sale.organization_id);
  if v_today - v_sale.business_date > v_settings.return_window_days then
    perform app.fail('return_window_passed', format('Returns are accepted within %s days', v_settings.return_window_days));
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 200 then
    perform app.fail('invalid_items', 'Provide the lines to return');
  end if;

  -- Pass 1: lock and validate lines, compute refunds with cumulative rounding.
  for v_req in
    select (e ->> 'sale_item_id')::uuid as sale_item_id, sum((e ->> 'quantity')::integer)::integer as quantity
      from jsonb_array_elements(p_items) e
     group by 1
     order by 1
  loop
    select * into v_line from public.sale_items
     where id = v_req.sale_item_id and sale_id = p_sale_id for update;
    if v_line.id is null then
      perform app.fail('invalid_item', 'Line does not belong to this sale');
    end if;
    if v_req.quantity is null or v_req.quantity <= 0 or v_req.quantity > v_line.quantity - v_line.returned_quantity then
      perform app.fail('invalid_quantity', 'Return quantity exceeds the quantity still returnable');
    end if;
    v_line_ids := v_line_ids || v_line.id;
    v_line_qty := v_line_qty || v_req.quantity;
    v_line_refund := v_line_refund || (
      round(v_line.net_paisa::numeric * (v_line.returned_quantity + v_req.quantity) / v_line.quantity)::bigint
      - round(v_line.net_paisa::numeric * v_line.returned_quantity / v_line.quantity)::bigint);
    v_line_cost := v_line_cost || (
      round(v_line.cost_paisa::numeric * (v_line.returned_quantity + v_req.quantity) / v_line.quantity)::bigint
      - round(v_line.cost_paisa::numeric * v_line.returned_quantity / v_line.quantity)::bigint);
    v_refund := v_refund + v_line_refund[array_length(v_line_ids, 1)];
    v_cost := v_cost + v_line_cost[array_length(v_line_ids, 1)];
  end loop;

  -- Split the refund: points paid (proportional) -> this sale's unpaid due -> money.
  if v_sale.points_redeemed > 0 and v_sale.net_paisa > 0 then
    v_point_unit := v_sale.points_redeemed_value_paisa / v_sale.points_redeemed;
    v_points_back := (v_sale.points_redeemed::numeric * (v_sale.refunded_paisa + v_refund) / v_sale.net_paisa)::bigint
                   - (v_sale.points_redeemed::numeric * v_sale.refunded_paisa / v_sale.net_paisa)::bigint;
    v_points_back := least(v_points_back, (v_refund / v_point_unit)::integer);
    v_points_value_back := v_points_back::bigint * v_point_unit;
  end if;

  if v_sale.due_paisa > 0 then
    perform 1 from public.customers where id = v_sale.customer_id for update;
    v_due_left := v_sale.due_paisa - coalesce((
      select sum(r.due_reduction_paisa) from public.sale_returns r where r.sale_id = p_sale_id
    ), 0);
    v_due_reduction := greatest(least(v_refund - v_points_value_back, v_due_left,
                                      app.customer_balance(v_sale.customer_id)), 0);
  end if;
  v_cash_refund := v_refund - v_points_value_back - v_due_reduction;

  if v_sale.loyalty_card_id is not null and v_sale.points_earned > 0 and v_sale.net_paisa > 0 then
    perform 1 from public.loyalty_cards where id = v_sale.loyalty_card_id for update;
    v_points_reverse := (v_sale.points_earned::numeric * (v_sale.refunded_paisa + v_refund) / v_sale.net_paisa)::bigint
                      - (v_sale.points_earned::numeric * v_sale.refunded_paisa / v_sale.net_paisa)::bigint;
    -- Points already spent cannot be clawed back below zero.
    v_points_reverse := greatest(least(v_points_reverse,
                                       app.loyalty_points_balance(v_sale.loyalty_card_id) + v_points_back), 0);
  end if;

  -- Write the return.
  v_return_no := app.next_branch_document_no(v_sale.branch_id, 'sale_return', 'R');
  insert into public.sale_returns (
    id, organization_id, branch_id, sale_id, return_no, business_date, refund_paisa, cash_refund_paisa,
    due_reduction_paisa, points_refund_value_paisa, refund_method, cost_paisa, points_returned, points_reversed,
    reason, client_request_id, created_by
  ) values (
    v_return_id, v_sale.organization_id, v_sale.branch_id, p_sale_id, v_return_no, v_today, v_refund,
    v_cash_refund, v_due_reduction, v_points_value_back, case when v_cash_refund > 0 then p_refund_method end,
    v_cost, v_points_back, v_points_reverse, btrim(p_reason), p_client_request_id, v_user
  );

  -- Pass 2: lines, restock plan, controlled register.
  for i in 1..coalesce(array_length(v_line_ids, 1), 0) loop
    insert into public.sale_return_items (organization_id, sale_return_id, sale_item_id, quantity, refund_paisa, cost_paisa)
    values (v_sale.organization_id, v_return_id, v_line_ids[i], v_line_qty[i], v_line_refund[i], v_line_cost[i]);

    update public.sale_items set returned_quantity = returned_quantity + v_line_qty[i] where id = v_line_ids[i];

    -- Put stock back into the batches it came from (latest-expiry allocation first).
    v_left := v_line_qty[i];
    for v_alloc in
      select sib.id, sib.batch_id, sib.quantity - sib.returned_quantity as returnable
        from public.sale_item_batches sib
        join public.batches b on b.id = sib.batch_id
       where sib.sale_item_id = v_line_ids[i] and sib.quantity > sib.returned_quantity
       order by b.expiry_date desc, sib.id desc
    loop
      exit when v_left = 0;
      v_take := least(v_left, v_alloc.returnable);
      update public.sale_item_batches set returned_quantity = returned_quantity + v_take where id = v_alloc.id;
      v_restock := v_restock || jsonb_build_object('batch_id', v_alloc.batch_id, 'quantity', v_take);
      v_left := v_left - v_take;
    end loop;

    insert into public.controlled_drug_register (
      organization_id, branch_id, medicine_id, sale_id, sale_item_id, prescription_id, entry_type, quantity,
      patient_name, doctor_name, doctor_reg_no, created_by
    )
    select r.organization_id, r.branch_id, r.medicine_id, r.sale_id, r.sale_item_id, r.prescription_id, 'return',
           v_line_qty[i], r.patient_name, r.doctor_name, r.doctor_reg_no, v_user
      from public.controlled_drug_register r
     where r.sale_item_id = v_line_ids[i] and r.entry_type = 'sale';
  end loop;

  -- Restock in batch id order (deadlock-safe).
  for v_r in
    select x from jsonb_array_elements(v_restock) x order by (x ->> 'batch_id')
  loop
    perform 1 from public.batches where id = (v_r ->> 'batch_id')::uuid for update;
    perform app.post_movement((v_r ->> 'batch_id')::uuid, 'sale_return', (v_r ->> 'quantity')::integer,
      'sale_return', v_return_id);
  end loop;

  if v_due_reduction > 0 then
    insert into public.customer_ledger_entries (
      organization_id, customer_id, branch_id, entry_type, amount_paisa, reference_type, reference_id, created_by
    ) values (v_sale.organization_id, v_sale.customer_id, v_sale.branch_id, 'sale_return', -v_due_reduction,
              'sale_return', v_return_id, v_user);
  end if;
  if v_points_back > 0 then
    insert into public.loyalty_point_ledger (organization_id, card_id, branch_id, entry_type, points, sale_id, note, created_by)
    values (v_sale.organization_id, v_sale.loyalty_card_id, v_sale.branch_id, 'reverse_redeem', v_points_back,
            p_sale_id, v_return_no, v_user);
  end if;
  if v_points_reverse > 0 then
    insert into public.loyalty_point_ledger (organization_id, card_id, branch_id, entry_type, points, sale_id, note, created_by)
    values (v_sale.organization_id, v_sale.loyalty_card_id, v_sale.branch_id, 'reverse_earn', -v_points_reverse,
            p_sale_id, v_return_no, v_user);
  end if;

  update public.sales set refunded_paisa = refunded_paisa + v_refund where id = p_sale_id;

  perform app.bump_daily_sales(v_sale.organization_id, v_sale.branch_id, v_today,
    p_returns_count => 1, p_returns => v_refund, p_returns_cost => v_cost);

  return jsonb_build_object('sale_return_id', v_return_id, 'return_no', v_return_no, 'refund_paisa', v_refund,
    'cash_refund_paisa', v_cash_refund, 'due_reduction_paisa', v_due_reduction,
    'points_returned', v_points_back, 'points_reversed', v_points_reverse, 'replayed', false);
end;
$$;

-- Loyalty usage per card per day, for abuse monitoring (RLS applies through security_invoker).
create view public.loyalty_usage_daily with (security_invoker = true) as
  select s.organization_id, s.loyalty_card_id, s.business_date, count(*)::integer as sales_count,
         sum(s.loyalty_discount_paisa)::bigint as loyalty_discount_paisa,
         count(distinct s.branch_id)::integer as branches_count
    from public.sales s
   where s.loyalty_card_id is not null and s.status = 'completed'
   group by s.organization_id, s.loyalty_card_id, s.business_date;

grant select on public.loyalty_usage_daily to authenticated;

grant execute on function
  public.create_sale(uuid, jsonb, jsonb, uuid, uuid, text, bigint, jsonb, text),
  public.void_sale(uuid, text),
  public.process_sale_return(uuid, jsonb, text, uuid, public.payment_method)
to authenticated;

call app.harden_privileges();
