-- =============================================================================
-- Migration: suppliers, customers and purchasing
-- Supplier and customer balances are derived from append-only ledgers (positive amount = the
-- counter-party's balance with us grows: we owe the supplier more / the customer owes us more).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Suppliers
-- -----------------------------------------------------------------------------
create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  name text not null check (length(btrim(name)) between 2 and 160),
  contact_person text check (length(contact_person) <= 120),
  phone text check (phone is null or phone ~ '^\+8801[3-9][0-9]{8}$'),
  email text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  address text check (length(address) <= 500),
  notes text check (length(notes) <= 1000),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (organization_id, id)
);
create unique index suppliers_org_name_key on public.suppliers (organization_id, lower(name));

create table public.supplier_ledger_entries (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  supplier_id uuid not null,
  branch_id uuid,
  entry_type text not null check (entry_type in ('purchase', 'payment', 'purchase_return', 'opening_balance', 'adjustment')),
  amount_paisa bigint not null check (amount_paisa <> 0),
  reference_type text check (length(reference_type) <= 40),
  reference_id uuid,
  note text check (length(note) <= 500),
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  foreign key (organization_id, supplier_id) references public.suppliers (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  constraint supplier_ledger_direction check (
    case entry_type
      when 'purchase' then amount_paisa > 0
      when 'payment' then amount_paisa < 0
      when 'purchase_return' then amount_paisa < 0
      else true
    end
  )
);
create index supplier_ledger_supplier_idx on public.supplier_ledger_entries (supplier_id, id);

create trigger supplier_ledger_append_only
  before update or delete on public.supplier_ledger_entries
  for each row execute function app.forbid_mutation();

create table public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  supplier_id uuid not null,
  branch_id uuid,
  goods_receipt_id uuid,
  amount_paisa bigint not null check (amount_paisa > 0),
  method public.payment_method not null check (method <> 'loyalty_points'),
  reference text check (length(reference) <= 80),
  note text check (length(note) <= 500),
  paid_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id),
  foreign key (organization_id, supplier_id) references public.suppliers (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id)
);
create index supplier_payments_supplier_idx on public.supplier_payments (supplier_id, paid_at desc);

create trigger supplier_payments_append_only
  before update or delete on public.supplier_payments
  for each row execute function app.forbid_mutation();

-- -----------------------------------------------------------------------------
-- Customers
-- -----------------------------------------------------------------------------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  name text not null check (length(btrim(name)) between 1 and 120),
  phone text check (phone is null or phone ~ '^\+8801[3-9][0-9]{8}$'),
  address text check (length(address) <= 500),
  credit_limit_paisa bigint not null default 0 check (credit_limit_paisa >= 0),
  notes text check (length(notes) <= 1000),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (organization_id, id)
);

comment on column public.customers.credit_limit_paisa is 'Maximum outstanding due (বাকি). 0 = credit not allowed.';

create unique index customers_org_phone_key on public.customers (organization_id, phone) where phone is not null;
create index customers_name_trgm_idx on public.customers using gin (name extensions.gin_trgm_ops);

create table public.customer_ledger_entries (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  customer_id uuid not null,
  branch_id uuid,
  entry_type text not null check (entry_type in ('credit_sale', 'payment', 'sale_return', 'sale_void', 'opening_balance', 'adjustment')),
  amount_paisa bigint not null check (amount_paisa <> 0),
  method public.payment_method,
  reference_type text check (length(reference_type) <= 40),
  reference_id uuid,
  note text check (length(note) <= 500),
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  foreign key (organization_id, customer_id) references public.customers (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  constraint customer_ledger_direction check (
    case entry_type
      when 'credit_sale' then amount_paisa > 0
      when 'payment' then amount_paisa < 0
      when 'sale_return' then amount_paisa < 0
      when 'sale_void' then amount_paisa < 0
      else true
    end
  )
);
create index customer_ledger_customer_idx on public.customer_ledger_entries (customer_id, id);
create index customer_ledger_branch_time_idx on public.customer_ledger_entries (branch_id, created_at desc);

create trigger customer_ledger_append_only
  before update or delete on public.customer_ledger_entries
  for each row execute function app.forbid_mutation();

-- Normalise phone numbers on write so lookups by phone are exact.
create or replace function app.normalize_phone_column()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.phone := app.normalize_bd_phone(new.phone);
  return new;
end;
$$;

create trigger customers_normalize_phone before insert or update of phone on public.customers
  for each row execute function app.normalize_phone_column();
create trigger suppliers_normalize_phone before insert or update of phone on public.suppliers
  for each row execute function app.normalize_phone_column();

-- -----------------------------------------------------------------------------
-- Goods receipts (purchases) and purchase returns
-- -----------------------------------------------------------------------------
create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  supplier_id uuid not null,
  receipt_no text not null,
  supplier_invoice_no text check (length(supplier_invoice_no) <= 60),
  supplier_invoice_date date,
  business_date date not null,
  subtotal_paisa bigint not null check (subtotal_paisa >= 0),
  discount_paisa bigint not null default 0 check (discount_paisa >= 0 and discount_paisa <= subtotal_paisa),
  total_paisa bigint not null check (total_paisa = subtotal_paisa - discount_paisa),
  paid_paisa bigint not null default 0 check (paid_paisa >= 0 and paid_paisa <= total_paisa),
  note text check (length(note) <= 500),
  client_request_id uuid not null,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, receipt_no),
  unique (organization_id, client_request_id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  foreign key (organization_id, supplier_id) references public.suppliers (organization_id, id)
);
-- The same supplier invoice cannot be entered twice.
create unique index goods_receipts_supplier_invoice_key
  on public.goods_receipts (organization_id, supplier_id, lower(supplier_invoice_no))
  where supplier_invoice_no is not null;
create index goods_receipts_branch_date_idx on public.goods_receipts (branch_id, business_date desc);

create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  goods_receipt_id uuid not null,
  medicine_id uuid not null,
  batch_id uuid not null,
  batch_no text not null,
  expiry_date date not null,
  quantity integer not null check (quantity > 0),
  bonus_quantity integer not null default 0 check (bonus_quantity >= 0),
  unit_cost_paisa bigint not null check (unit_cost_paisa >= 0),
  mrp_paisa bigint not null check (mrp_paisa > 0),
  sale_price_paisa bigint not null check (sale_price_paisa > 0 and sale_price_paisa <= mrp_paisa),
  line_total_paisa bigint not null check (line_total_paisa = quantity * unit_cost_paisa),
  foreign key (organization_id, goods_receipt_id) references public.goods_receipts (organization_id, id),
  foreign key (organization_id, medicine_id) references public.medicines (organization_id, id),
  foreign key (organization_id, batch_id) references public.batches (organization_id, id)
);
create index goods_receipt_items_receipt_idx on public.goods_receipt_items (goods_receipt_id);
create index goods_receipt_items_medicine_idx on public.goods_receipt_items (medicine_id);

alter table public.supplier_payments
  add foreign key (organization_id, goods_receipt_id) references public.goods_receipts (organization_id, id);

create table public.purchase_returns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  branch_id uuid not null,
  supplier_id uuid not null,
  return_no text not null,
  business_date date not null,
  total_paisa bigint not null check (total_paisa >= 0),
  reason text not null check (length(btrim(reason)) between 3 and 200),
  note text check (length(note) <= 500),
  client_request_id uuid not null,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, return_no),
  unique (organization_id, client_request_id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  foreign key (organization_id, supplier_id) references public.suppliers (organization_id, id)
);
create index purchase_returns_branch_date_idx on public.purchase_returns (branch_id, business_date desc);

create table public.purchase_return_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  purchase_return_id uuid not null,
  batch_id uuid not null,
  medicine_id uuid not null,
  quantity integer not null check (quantity > 0),
  unit_cost_paisa bigint not null check (unit_cost_paisa >= 0),
  line_total_paisa bigint not null check (line_total_paisa = quantity * unit_cost_paisa),
  foreign key (organization_id, purchase_return_id) references public.purchase_returns (organization_id, id),
  foreign key (organization_id, batch_id) references public.batches (organization_id, id),
  foreign key (organization_id, medicine_id) references public.medicines (organization_id, id)
);
create index purchase_return_items_return_idx on public.purchase_return_items (purchase_return_id);

do $$
declare
  t text;
begin
  foreach t in array array['goods_receipts', 'goods_receipt_items', 'purchase_returns', 'purchase_return_items'] loop
    execute format(
      'create trigger %1$s_append_only before update or delete on public.%1$s
         for each row execute function app.forbid_mutation()', t);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Triggers, audit, RLS, grants
-- -----------------------------------------------------------------------------
create trigger suppliers_touch before update on public.suppliers
  for each row execute function app.touch_updated();
create trigger customers_touch before update on public.customers
  for each row execute function app.touch_updated();
create trigger suppliers_guard_org before update on public.suppliers
  for each row execute function app.guard_organization_id();
create trigger customers_guard_org before update on public.customers
  for each row execute function app.guard_organization_id();
create trigger suppliers_created_by before insert on public.suppliers
  for each row execute function app.set_created_by();
create trigger customers_created_by before insert on public.customers
  for each row execute function app.set_created_by();

call app.enable_audit('public.suppliers');
call app.enable_audit('public.customers');

alter table public.suppliers enable row level security;
alter table public.supplier_ledger_entries enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.customers enable row level security;
alter table public.customer_ledger_entries enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;
alter table public.purchase_returns enable row level security;
alter table public.purchase_return_items enable row level security;

create policy suppliers_select on public.suppliers for select to authenticated
  using (app.has_permission(organization_id, 'purchases.view'));
create policy suppliers_insert on public.suppliers for insert to authenticated
  with check (app.has_permission(organization_id, 'suppliers.manage'));
create policy suppliers_update on public.suppliers for update to authenticated
  using (app.has_permission(organization_id, 'suppliers.manage'))
  with check (app.has_permission(organization_id, 'suppliers.manage'));

create policy supplier_ledger_select on public.supplier_ledger_entries for select to authenticated
  using (app.has_permission(organization_id, 'purchases.view'));
create policy supplier_payments_select on public.supplier_payments for select to authenticated
  using (app.has_permission(organization_id, 'purchases.view'));

create policy goods_receipts_select on public.goods_receipts for select to authenticated
  using (branch_id in (select app.user_branch_ids()) and app.has_permission(organization_id, 'purchases.view'));
create policy goods_receipt_items_select on public.goods_receipt_items for select to authenticated
  using (exists (
    select 1 from public.goods_receipts gr
     where gr.id = goods_receipt_items.goods_receipt_id
       and gr.branch_id in (select app.user_branch_ids())
       and app.has_permission(gr.organization_id, 'purchases.view')
  ));
create policy purchase_returns_select on public.purchase_returns for select to authenticated
  using (branch_id in (select app.user_branch_ids()) and app.has_permission(organization_id, 'purchases.view'));
create policy purchase_return_items_select on public.purchase_return_items for select to authenticated
  using (exists (
    select 1 from public.purchase_returns pr
     where pr.id = purchase_return_items.purchase_return_id
       and pr.branch_id in (select app.user_branch_ids())
       and app.has_permission(pr.organization_id, 'purchases.view')
  ));

create policy customers_select on public.customers for select to authenticated
  using (organization_id in (select app.user_org_ids()));
create policy customers_insert on public.customers for insert to authenticated
  with check (app.has_permission(organization_id, 'customers.manage'));
create policy customers_update on public.customers for update to authenticated
  using (app.has_permission(organization_id, 'customers.manage'))
  with check (app.has_permission(organization_id, 'customers.manage'));

create policy customer_ledger_select on public.customer_ledger_entries for select to authenticated
  using (
    app.has_permission(organization_id, 'customers.collect')
    or app.has_permission(organization_id, 'reports.view')
  );

grant select on public.suppliers, public.supplier_ledger_entries, public.supplier_payments,
  public.customers, public.customer_ledger_entries, public.goods_receipts, public.goods_receipt_items,
  public.purchase_returns, public.purchase_return_items to authenticated;
grant insert (organization_id, name, contact_person, phone, email, address, notes) on public.suppliers to authenticated;
grant update (name, contact_person, phone, email, address, notes, is_active) on public.suppliers to authenticated;
grant insert (organization_id, name, phone, address, notes) on public.customers to authenticated;
grant update (name, phone, address, notes, is_active) on public.customers to authenticated;

-- Credit limits are financial controls: only changeable through set_customer_credit_limit.
create or replace function public.set_customer_credit_limit(p_customer_id uuid, p_credit_limit_paisa bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from public.customers where id = p_customer_id;
  if v_org is null then
    perform app.fail('not_found', 'Customer not found');
  end if;
  if app.user_role(v_org) is distinct from 'owner' and app.user_role(v_org) is distinct from 'manager' then
    perform app.fail('forbidden', 'Only an owner or manager can change credit limits');
  end if;
  perform app.require_permission(v_org, 'customers.manage');
  if p_credit_limit_paisa is null or p_credit_limit_paisa < 0 then
    perform app.fail('invalid_amount', 'Credit limit cannot be negative');
  end if;
  update public.customers set credit_limit_paisa = p_credit_limit_paisa where id = p_customer_id;
end;
$$;

-- Balances (views run with the caller's privileges, so RLS on the ledgers applies).
create view public.customer_balances with (security_invoker = true) as
  select c.organization_id, c.id as customer_id, c.name, c.phone, c.credit_limit_paisa,
         coalesce(sum(l.amount_paisa), 0)::bigint as balance_paisa
    from public.customers c
    left join public.customer_ledger_entries l on l.customer_id = c.id
   group by c.id;

create view public.supplier_balances with (security_invoker = true) as
  select s.organization_id, s.id as supplier_id, s.name,
         coalesce(sum(l.amount_paisa), 0)::bigint as balance_paisa
    from public.suppliers s
    left join public.supplier_ledger_entries l on l.supplier_id = s.id
   group by s.id;

grant select on public.customer_balances, public.supplier_balances to authenticated;

create or replace function app.customer_balance(p_customer_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(amount_paisa), 0)::bigint
    from public.customer_ledger_entries
   where customer_id = p_customer_id
$$;

-- -----------------------------------------------------------------------------
-- RPC: purchasing
-- -----------------------------------------------------------------------------

-- Receives goods from a supplier into a branch. Items:
-- [{medicine_id, batch_no, expiry_date, quantity, bonus_quantity, unit_cost_paisa, mrp_paisa, sale_price_paisa}]
-- The invoice discount is spread over lines; each batch's cost = net line cost / (quantity + bonus).
create or replace function public.receive_goods(
  p_branch_id uuid,
  p_supplier_id uuid,
  p_items jsonb,
  p_client_request_id uuid,
  p_supplier_invoice_no text default null,
  p_supplier_invoice_date date default null,
  p_discount_paisa bigint default 0,
  p_paid_paisa bigint default 0,
  p_payment_method public.payment_method default 'cash',
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := app.require_branch_permission(p_branch_id, 'purchases.receive');
  v_existing public.goods_receipts;
  v_receipt_id uuid := gen_random_uuid();
  v_receipt_no text;
  v_item jsonb;
  v_items jsonb[];
  v_line_totals bigint[] := '{}';
  v_discounts bigint[];
  v_subtotal bigint := 0;
  v_total bigint;
  v_qty integer;
  v_bonus integer;
  v_cost bigint;
  v_batch uuid;
  i integer;
begin
  if p_client_request_id is null then
    perform app.fail('missing_request_id', 'client_request_id is required');
  end if;
  select * into v_existing from public.goods_receipts
   where organization_id = v_org and client_request_id = p_client_request_id;
  if v_existing.id is not null then
    return jsonb_build_object('goods_receipt_id', v_existing.id, 'receipt_no', v_existing.receipt_no,
      'total_paisa', v_existing.total_paisa, 'replayed', true);
  end if;

  if not exists (select 1 from public.suppliers s where s.id = p_supplier_id and s.organization_id = v_org and s.is_active) then
    perform app.fail('invalid_supplier', 'Supplier not found or inactive');
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 300 then
    perform app.fail('invalid_items', 'Provide between 1 and 300 items');
  end if;
  if (select count(*) from jsonb_array_elements(p_items) e)
     <> (select count(distinct (e ->> 'medicine_id', lower(btrim(e ->> 'batch_no')))) from jsonb_array_elements(p_items) e) then
    perform app.fail('duplicate_items', 'Each medicine batch may appear only once');
  end if;
  if p_supplier_invoice_date is not null and p_supplier_invoice_date > app.business_date(v_org) then
    perform app.fail('invalid_date', 'Supplier invoice date cannot be in the future');
  end if;

  v_items := array(select e from jsonb_array_elements(p_items) e);
  for i in 1..array_length(v_items, 1) loop
    v_item := v_items[i];
    v_qty := (v_item ->> 'quantity')::integer;
    v_bonus := coalesce((v_item ->> 'bonus_quantity')::integer, 0);
    if v_qty is null or v_qty <= 0 or v_bonus < 0 then
      perform app.fail('invalid_quantity', 'Quantity must be greater than zero and bonus cannot be negative');
    end if;
    if coalesce(btrim(v_item ->> 'batch_no'), '') = '' then
      perform app.fail('invalid_batch', 'Batch number is required');
    end if;
    perform app.validate_batch_input(v_org, (v_item ->> 'medicine_id')::uuid,
      (v_item ->> 'expiry_date')::date, (v_item ->> 'mrp_paisa')::bigint,
      (v_item ->> 'sale_price_paisa')::bigint, (v_item ->> 'unit_cost_paisa')::bigint);
    v_line_totals := v_line_totals || (v_qty::bigint * (v_item ->> 'unit_cost_paisa')::bigint);
    v_subtotal := v_subtotal + v_line_totals[i];
  end loop;

  if p_discount_paisa is null or p_discount_paisa < 0 or p_discount_paisa > v_subtotal then
    perform app.fail('invalid_discount', 'Discount must be between zero and the subtotal');
  end if;
  v_total := v_subtotal - p_discount_paisa;
  if p_paid_paisa is null or p_paid_paisa < 0 or p_paid_paisa > v_total then
    perform app.fail('invalid_payment', 'Paid amount must be between zero and the total');
  end if;
  if p_paid_paisa > 0 and p_payment_method = 'loyalty_points' then
    perform app.fail('invalid_payment', 'Loyalty points cannot pay suppliers');
  end if;

  v_receipt_no := app.next_branch_document_no(p_branch_id, 'goods_receipt', 'G');
  v_discounts := app.allocate_proportionally(p_discount_paisa, v_line_totals);

  insert into public.goods_receipts (
    id, organization_id, branch_id, supplier_id, receipt_no, supplier_invoice_no, supplier_invoice_date,
    business_date, subtotal_paisa, discount_paisa, total_paisa, paid_paisa, note, client_request_id, created_by
  ) values (
    v_receipt_id, v_org, p_branch_id, p_supplier_id, v_receipt_no, nullif(btrim(p_supplier_invoice_no), ''),
    p_supplier_invoice_date, app.business_date(v_org), v_subtotal, p_discount_paisa, v_total, p_paid_paisa,
    nullif(btrim(p_note), ''), p_client_request_id, auth.uid()
  );

  for i in 1..array_length(v_items, 1) loop
    v_item := v_items[i];
    v_qty := (v_item ->> 'quantity')::integer;
    v_bonus := coalesce((v_item ->> 'bonus_quantity')::integer, 0);
    v_cost := round((v_line_totals[i] - v_discounts[i])::numeric / (v_qty + v_bonus))::bigint;

    insert into public.batches (
      organization_id, branch_id, medicine_id, batch_no, expiry_date, cost_paisa, mrp_paisa,
      sale_price_paisa, created_by, updated_by
    ) values (
      v_org, p_branch_id, (v_item ->> 'medicine_id')::uuid, btrim(v_item ->> 'batch_no'),
      (v_item ->> 'expiry_date')::date, v_cost, (v_item ->> 'mrp_paisa')::bigint,
      (v_item ->> 'sale_price_paisa')::bigint, auth.uid(), auth.uid()
    ) returning id into v_batch;

    insert into public.goods_receipt_items (
      organization_id, goods_receipt_id, medicine_id, batch_id, batch_no, expiry_date, quantity,
      bonus_quantity, unit_cost_paisa, mrp_paisa, sale_price_paisa, line_total_paisa
    ) values (
      v_org, v_receipt_id, (v_item ->> 'medicine_id')::uuid, v_batch, btrim(v_item ->> 'batch_no'),
      (v_item ->> 'expiry_date')::date, v_qty, v_bonus, (v_item ->> 'unit_cost_paisa')::bigint,
      (v_item ->> 'mrp_paisa')::bigint, (v_item ->> 'sale_price_paisa')::bigint, v_line_totals[i]
    );

    perform app.post_movement(v_batch, 'purchase_receipt', v_qty + v_bonus, 'goods_receipt', v_receipt_id);
  end loop;

  if v_total > 0 then
    insert into public.supplier_ledger_entries (
      organization_id, supplier_id, branch_id, entry_type, amount_paisa, reference_type, reference_id, created_by
    ) values (v_org, p_supplier_id, p_branch_id, 'purchase', v_total, 'goods_receipt', v_receipt_id, auth.uid());
  end if;

  if p_paid_paisa > 0 then
    insert into public.supplier_payments (
      organization_id, supplier_id, branch_id, goods_receipt_id, amount_paisa, method, created_by
    ) values (v_org, p_supplier_id, p_branch_id, v_receipt_id, p_paid_paisa, p_payment_method, auth.uid());
    insert into public.supplier_ledger_entries (
      organization_id, supplier_id, branch_id, entry_type, amount_paisa, reference_type, reference_id, created_by
    ) values (v_org, p_supplier_id, p_branch_id, 'payment', -p_paid_paisa, 'goods_receipt', v_receipt_id, auth.uid());
  end if;

  return jsonb_build_object('goods_receipt_id', v_receipt_id, 'receipt_no', v_receipt_no,
    'total_paisa', v_total, 'replayed', false);
end;
$$;

create or replace function public.record_supplier_payment(
  p_supplier_id uuid,
  p_amount_paisa bigint,
  p_method public.payment_method,
  p_branch_id uuid default null,
  p_reference text default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_payment uuid;
begin
  select organization_id into v_org from public.suppliers where id = p_supplier_id;
  if v_org is null then
    perform app.fail('not_found', 'Supplier not found');
  end if;
  if p_branch_id is not null then
    perform app.require_branch_permission(p_branch_id, 'suppliers.pay');
    if app.branch_org_id(p_branch_id) <> v_org then
      perform app.fail('invalid_branch', 'Branch belongs to another organization');
    end if;
  else
    perform app.require_permission(v_org, 'suppliers.pay');
  end if;
  if p_amount_paisa is null or p_amount_paisa <= 0 then
    perform app.fail('invalid_amount', 'Amount must be greater than zero');
  end if;
  if p_method = 'loyalty_points' then
    perform app.fail('invalid_payment', 'Loyalty points cannot pay suppliers');
  end if;

  insert into public.supplier_payments (
    organization_id, supplier_id, branch_id, amount_paisa, method, reference, note, created_by
  ) values (v_org, p_supplier_id, p_branch_id, p_amount_paisa, p_method,
            nullif(btrim(p_reference), ''), nullif(btrim(p_note), ''), auth.uid())
  returning id into v_payment;

  insert into public.supplier_ledger_entries (
    organization_id, supplier_id, branch_id, entry_type, amount_paisa, reference_type, reference_id, created_by
  ) values (v_org, p_supplier_id, p_branch_id, 'payment', -p_amount_paisa, 'supplier_payment', v_payment, auth.uid());

  return v_payment;
end;
$$;

-- Returns stock to a supplier (e.g. near-expiry). Items: [{batch_id, quantity}]. Valued at batch cost.
create or replace function public.process_purchase_return(
  p_branch_id uuid,
  p_supplier_id uuid,
  p_items jsonb,
  p_reason text,
  p_client_request_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := app.require_branch_permission(p_branch_id, 'purchases.return');
  v_existing public.purchase_returns;
  v_return_id uuid := gen_random_uuid();
  v_return_no text;
  v_item record;
  v_batch public.batches;
  v_total bigint := 0;
begin
  if p_client_request_id is null then
    perform app.fail('missing_request_id', 'client_request_id is required');
  end if;
  select * into v_existing from public.purchase_returns
   where organization_id = v_org and client_request_id = p_client_request_id;
  if v_existing.id is not null then
    return jsonb_build_object('purchase_return_id', v_existing.id, 'return_no', v_existing.return_no,
      'total_paisa', v_existing.total_paisa, 'replayed', true);
  end if;
  if not exists (select 1 from public.suppliers s where s.id = p_supplier_id and s.organization_id = v_org) then
    perform app.fail('invalid_supplier', 'Supplier not found');
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 300 then
    perform app.fail('invalid_items', 'Provide between 1 and 300 items');
  end if;
  if coalesce(length(btrim(p_reason)), 0) < 3 then
    perform app.fail('reason_required', 'A reason is required');
  end if;

  -- Pass 1: lock batches in id order (deadlock-safe with concurrent sales) and validate.
  for v_item in
    select (e ->> 'batch_id')::uuid as batch_id, sum((e ->> 'quantity')::integer) as quantity
      from jsonb_array_elements(p_items) e
     group by 1
     order by 1
  loop
    select * into v_batch from public.batches where id = v_item.batch_id for update;
    if v_batch.id is null or v_batch.branch_id <> p_branch_id then
      perform app.fail('invalid_batch', 'Batch not found in this branch');
    end if;
    if v_item.quantity is null or v_item.quantity <= 0 then
      perform app.fail('invalid_quantity', 'Quantity must be greater than zero');
    end if;
    if v_item.quantity > v_batch.quantity_on_hand then
      perform app.fail('insufficient_stock', 'Not enough stock in this batch');
    end if;
    v_total := v_total + v_item.quantity * v_batch.cost_paisa;
  end loop;

  v_return_no := app.next_branch_document_no(p_branch_id, 'purchase_return', 'PR');
  insert into public.purchase_returns (
    id, organization_id, branch_id, supplier_id, return_no, business_date, total_paisa, reason, note,
    client_request_id, created_by
  ) values (
    v_return_id, v_org, p_branch_id, p_supplier_id, v_return_no, app.business_date(v_org), v_total,
    btrim(p_reason), nullif(btrim(p_note), ''), p_client_request_id, auth.uid()
  );

  -- Pass 2: write lines and stock movements (locks are already held).
  for v_item in
    select (e ->> 'batch_id')::uuid as batch_id, sum((e ->> 'quantity')::integer) as quantity
      from jsonb_array_elements(p_items) e
     group by 1
     order by 1
  loop
    select * into v_batch from public.batches where id = v_item.batch_id;
    insert into public.purchase_return_items (
      organization_id, purchase_return_id, batch_id, medicine_id, quantity, unit_cost_paisa, line_total_paisa
    ) values (v_org, v_return_id, v_batch.id, v_batch.medicine_id, v_item.quantity, v_batch.cost_paisa,
              v_item.quantity * v_batch.cost_paisa);
    perform app.post_movement(v_batch.id, 'purchase_return', -v_item.quantity, 'purchase_return', v_return_id);
  end loop;

  if v_total > 0 then
    insert into public.supplier_ledger_entries (
      organization_id, supplier_id, branch_id, entry_type, amount_paisa, reference_type, reference_id, created_by
    ) values (v_org, p_supplier_id, p_branch_id, 'purchase_return', -v_total, 'purchase_return', v_return_id, auth.uid());
  end if;

  return jsonb_build_object('purchase_return_id', v_return_id, 'return_no', v_return_no,
    'total_paisa', v_total, 'replayed', false);
end;
$$;

-- Customer pays off part of their due (বাকি).
create or replace function public.record_customer_payment(
  p_customer_id uuid,
  p_branch_id uuid,
  p_amount_paisa bigint,
  p_method public.payment_method,
  p_reference text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := app.require_branch_permission(p_branch_id, 'customers.collect');
  v_balance bigint;
begin
  perform 1 from public.customers where id = p_customer_id and organization_id = v_org for update;
  if not found then
    perform app.fail('not_found', 'Customer not found');
  end if;
  if p_amount_paisa is null or p_amount_paisa <= 0 then
    perform app.fail('invalid_amount', 'Amount must be greater than zero');
  end if;
  if p_method = 'loyalty_points' then
    perform app.fail('invalid_payment', 'Loyalty points cannot settle dues');
  end if;
  v_balance := app.customer_balance(p_customer_id);
  if p_amount_paisa > v_balance then
    perform app.fail('overpayment', 'Payment is larger than the outstanding due');
  end if;

  insert into public.customer_ledger_entries (
    organization_id, customer_id, branch_id, entry_type, amount_paisa, method, reference_type, note, created_by
  ) values (v_org, p_customer_id, p_branch_id, 'payment', -p_amount_paisa, p_method, 'customer_payment',
            nullif(btrim(p_reference), ''), auth.uid());

  return v_balance - p_amount_paisa;
end;
$$;

grant execute on function
  public.set_customer_credit_limit(uuid, bigint),
  public.receive_goods(uuid, uuid, jsonb, uuid, text, date, bigint, bigint, public.payment_method, text),
  public.record_supplier_payment(uuid, bigint, public.payment_method, uuid, text, text),
  public.process_purchase_return(uuid, uuid, jsonb, text, uuid, text),
  public.record_customer_payment(uuid, uuid, bigint, public.payment_method, text)
to authenticated;

call app.harden_privileges();
