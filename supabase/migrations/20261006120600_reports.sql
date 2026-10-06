-- =============================================================================
-- Migration: reports
-- Permission-checked report functions. Cost and profit are returned only to roles with
-- reports.view_cost; everyone else gets NULL in those columns.
-- =============================================================================

-- Sales summary per branch per day (reads the daily summary table, so it stays fast).
create or replace function public.report_sales_summary(
  p_organization_id uuid,
  p_from date,
  p_to date,
  p_branch_id uuid default null
)
returns table (
  branch_id uuid,
  branch_name text,
  business_date date,
  sales_count integer,
  gross_paisa bigint,
  discount_paisa bigint,
  loyalty_discount_paisa bigint,
  net_sales_paisa bigint,
  returns_paisa bigint,
  voided_paisa bigint,
  credit_sales_paisa bigint,
  cost_paisa bigint,
  gross_profit_paisa bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_show_cost boolean;
begin
  perform app.require_permission(p_organization_id, 'reports.view');
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    perform app.fail('invalid_range', 'Choose a date range of at most 400 days');
  end if;
  v_show_cost := app.has_permission(p_organization_id, 'reports.view_cost');

  return query
  select d.branch_id, b.name, d.business_date, d.sales_count - d.voids_count,
         d.gross_paisa, d.discount_paisa, d.loyalty_discount_paisa,
         d.net_paisa - d.voided_paisa - d.returns_paisa,
         d.returns_paisa, d.voided_paisa, d.credit_sales_paisa,
         case when v_show_cost then d.cost_paisa - d.voided_cost_paisa - d.returns_cost_paisa end,
         case when v_show_cost then (d.net_paisa - d.voided_paisa - d.returns_paisa)
                                  - (d.cost_paisa - d.voided_cost_paisa - d.returns_cost_paisa) end
    from public.daily_branch_sales d
    join public.branches b on b.id = d.branch_id
   where d.organization_id = p_organization_id
     and d.business_date between p_from and p_to
     and (p_branch_id is null or d.branch_id = p_branch_id)
     and d.branch_id in (select app.user_branch_ids())
   order by d.business_date, b.name;
end;
$$;

-- Batches expiring within p_days (default: the organization's expiry_alert_days).
create or replace function public.report_expiring_stock(p_branch_id uuid, p_days integer default null)
returns table (
  batch_id uuid,
  medicine_id uuid,
  brand_name text,
  batch_no text,
  expiry_date date,
  days_left integer,
  quantity_on_hand integer,
  stock_value_mrp_paisa bigint,
  stock_value_cost_paisa bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := app.require_branch_permission(p_branch_id, 'reports.view');
  v_today date := app.business_date(v_org);
  v_days integer;
  v_show_cost boolean := app.has_permission(v_org, 'reports.view_cost');
begin
  select coalesce(p_days, s.expiry_alert_days) into v_days
    from public.organization_settings s where s.organization_id = v_org;
  if v_days not between 0 and 730 then
    perform app.fail('invalid_range', 'Days must be between 0 and 730');
  end if;
  return query
  select b.id, m.id, m.brand_name, b.batch_no, b.expiry_date, (b.expiry_date - v_today)::integer,
         b.quantity_on_hand, b.quantity_on_hand::bigint * b.mrp_paisa,
         case when v_show_cost then b.quantity_on_hand::bigint * b.cost_paisa end
    from public.batches b
    join public.medicines m on m.id = b.medicine_id
   where b.branch_id = p_branch_id
     and b.quantity_on_hand > 0
     and b.expiry_date <= v_today + v_days
   order by b.expiry_date, m.brand_name;
end;
$$;

-- Medicines at or below their reorder level in a branch.
create or replace function public.report_low_stock(p_branch_id uuid)
returns table (
  medicine_id uuid,
  brand_name text,
  generic_name text,
  reorder_level integer,
  sellable_quantity bigint,
  rack_location text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := app.require_branch_permission(p_branch_id, 'reports.view');
  v_today date := app.business_date(v_org);
begin
  return query
  select m.id, m.brand_name, g.name, s.reorder_level,
         coalesce((
           select sum(b.quantity_on_hand) from public.batches b
            where b.branch_id = p_branch_id and b.medicine_id = m.id and b.expiry_date > v_today
         ), 0)::bigint as sellable,
         s.rack_location
    from public.branch_medicine_settings s
    join public.medicines m on m.id = s.medicine_id
    left join public.generics g on g.id = m.generic_id
   where s.branch_id = p_branch_id
     and m.is_active
     and s.reorder_level > 0
     and coalesce((
           select sum(b.quantity_on_hand) from public.batches b
            where b.branch_id = p_branch_id and b.medicine_id = m.id and b.expiry_date > v_today
         ), 0) <= s.reorder_level
   order by m.brand_name;
end;
$$;

-- Current stock value per branch (at MRP, and at cost when permitted).
create or replace function public.report_stock_value(p_organization_id uuid)
returns table (
  branch_id uuid,
  branch_name text,
  sku_count bigint,
  units bigint,
  value_mrp_paisa bigint,
  value_cost_paisa bigint,
  expired_units bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date;
  v_show_cost boolean;
begin
  perform app.require_permission(p_organization_id, 'reports.view');
  v_today := app.business_date(p_organization_id);
  v_show_cost := app.has_permission(p_organization_id, 'reports.view_cost');
  return query
  select br.id, br.name, count(distinct b.medicine_id), coalesce(sum(b.quantity_on_hand), 0)::bigint,
         coalesce(sum(b.quantity_on_hand::bigint * b.mrp_paisa), 0)::bigint,
         case when v_show_cost then coalesce(sum(b.quantity_on_hand::bigint * b.cost_paisa), 0)::bigint end,
         coalesce(sum(b.quantity_on_hand) filter (where b.expiry_date <= v_today), 0)::bigint
    from public.branches br
    left join public.batches b on b.branch_id = br.id and b.quantity_on_hand > 0
   where br.organization_id = p_organization_id
     and br.id in (select app.user_branch_ids())
   group by br.id, br.name
   order by br.name;
end;
$$;

grant execute on function
  public.report_sales_summary(uuid, date, date, uuid),
  public.report_expiring_stock(uuid, integer),
  public.report_low_stock(uuid),
  public.report_stock_value(uuid)
to authenticated;

call app.harden_privileges();
