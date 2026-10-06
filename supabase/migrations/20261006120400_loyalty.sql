-- =============================================================================
-- Migration: loyalty card programme
-- Configurable membership plans (3 and 6 months seeded, inactive until the owner sets fee and
-- benefits), cards with Luhn-checked numbers, time-boxed memberships that cannot overlap,
-- and an append-only points ledger. Cards work in every branch of the organization.
-- =============================================================================

create type public.loyalty_membership_status as enum ('active', 'cancelled');

create table public.loyalty_plans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  name text not null check (length(btrim(name)) between 2 and 60),
  duration_months integer not null check (duration_months between 1 and 36),
  fee_paisa bigint not null default 0 check (fee_paisa >= 0),
  discount_bp integer not null default 0 check (discount_bp between 0 and 5000),
  max_discount_per_invoice_paisa bigint check (max_discount_per_invoice_paisa is null or max_discount_per_invoice_paisa > 0),
  points_per_100_taka integer not null default 0 check (points_per_100_taka between 0 and 1000),
  point_value_paisa integer not null default 0 check (point_value_paisa between 0 and 100000),
  min_redeem_points integer not null default 0 check (min_redeem_points >= 0),
  is_active boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique (organization_id, id)
);
create unique index loyalty_plans_org_name_key on public.loyalty_plans (organization_id, lower(name));

comment on table public.loyalty_plans is
  'Membership plan. discount_bp applies to loyalty-eligible items; points_per_100_taka are earned per 100 taka spent; point_value_paisa is the redemption value of one point.';

create table public.loyalty_cards (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  customer_id uuid not null,
  card_no text not null check (card_no ~ '^[0-9]{6,16}$'),
  is_active boolean not null default true,
  issued_at timestamptz not null default now(),
  issued_by uuid references auth.users (id),
  deactivated_at timestamptz,
  deactivation_reason text check (length(deactivation_reason) <= 200),
  unique (organization_id, card_no),
  unique (organization_id, id),
  foreign key (organization_id, customer_id) references public.customers (organization_id, id)
);
create unique index loyalty_cards_one_active_per_customer on public.loyalty_cards (organization_id, customer_id)
  where is_active;

create table public.loyalty_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  card_id uuid not null,
  customer_id uuid not null,
  plan_id uuid not null,
  branch_id uuid not null,
  starts_on date not null,
  ends_on date not null,
  status public.loyalty_membership_status not null default 'active',
  fee_paid_paisa bigint not null check (fee_paid_paisa >= 0),
  payment_method public.payment_method check (payment_method is null or payment_method <> 'loyalty_points'),
  -- Plan terms are snapshotted so later plan edits never change an existing membership.
  discount_bp integer not null,
  max_discount_per_invoice_paisa bigint,
  points_per_100_taka integer not null,
  point_value_paisa integer not null,
  min_redeem_points integer not null,
  renewed_from_id uuid references public.loyalty_memberships (id),
  client_request_id uuid not null,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users (id),
  cancel_reason text check (length(cancel_reason) <= 200),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, client_request_id),
  foreign key (organization_id, card_id) references public.loyalty_cards (organization_id, id),
  foreign key (organization_id, customer_id) references public.customers (organization_id, id),
  foreign key (organization_id, plan_id) references public.loyalty_plans (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  constraint loyalty_memberships_dates check (ends_on >= starts_on),
  constraint loyalty_memberships_fee_method check (fee_paid_paisa = 0 or payment_method is not null),
  constraint loyalty_memberships_cancel_fields check ((status = 'cancelled') = (cancelled_at is not null)),
  constraint loyalty_memberships_no_overlap exclude using gist (
    card_id with =,
    daterange(starts_on, ends_on, '[]') with &&
  ) where (status = 'active')
);
create index loyalty_memberships_customer_idx on public.loyalty_memberships (customer_id);
create index loyalty_memberships_ends_idx on public.loyalty_memberships (organization_id, ends_on) where status = 'active';

create table public.loyalty_point_ledger (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  card_id uuid not null,
  branch_id uuid,
  entry_type text not null check (entry_type in ('earn', 'redeem', 'reverse_earn', 'reverse_redeem', 'adjust', 'expire')),
  points integer not null check (points <> 0),
  sale_id uuid,
  note text check (length(note) <= 200),
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  foreign key (organization_id, card_id) references public.loyalty_cards (organization_id, id),
  foreign key (organization_id, branch_id) references public.branches (organization_id, id),
  constraint loyalty_point_ledger_direction check (
    case entry_type
      when 'earn' then points > 0
      when 'reverse_redeem' then points > 0
      when 'redeem' then points < 0
      when 'reverse_earn' then points < 0
      when 'expire' then points < 0
      else true
    end
  )
);
create index loyalty_point_ledger_card_idx on public.loyalty_point_ledger (card_id, id);

create trigger loyalty_point_ledger_append_only
  before update or delete on public.loyalty_point_ledger
  for each row execute function app.forbid_mutation();

create trigger loyalty_plans_touch before update on public.loyalty_plans
  for each row execute function app.touch_updated();
create trigger loyalty_plans_guard_org before update on public.loyalty_plans
  for each row execute function app.guard_organization_id();
create trigger loyalty_plans_created_by before insert on public.loyalty_plans
  for each row execute function app.set_created_by();

call app.enable_audit('public.loyalty_plans');
call app.enable_audit('public.loyalty_cards');
call app.enable_audit('public.loyalty_memberships');

-- Seed the two plans the owner asked for, inactive until fee and benefits are configured.
create or replace function app.seed_loyalty_plans()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.loyalty_plans (organization_id, name, duration_months, sort_order, created_by)
  values (new.id, '3-Month Card', 3, 1, new.created_by),
         (new.id, '6-Month Card', 6, 2, new.created_by);
  return new;
end;
$$;

create trigger organizations_seed_loyalty_plans
  after insert on public.organizations
  for each row execute function app.seed_loyalty_plans();

-- -----------------------------------------------------------------------------
-- RLS and grants
-- -----------------------------------------------------------------------------
alter table public.loyalty_plans enable row level security;
alter table public.loyalty_cards enable row level security;
alter table public.loyalty_memberships enable row level security;
alter table public.loyalty_point_ledger enable row level security;

create policy loyalty_plans_select on public.loyalty_plans for select to authenticated
  using (organization_id in (select app.user_org_ids()));
create policy loyalty_plans_insert on public.loyalty_plans for insert to authenticated
  with check (app.has_permission(organization_id, 'loyalty.manage_plans'));
create policy loyalty_plans_update on public.loyalty_plans for update to authenticated
  using (app.has_permission(organization_id, 'loyalty.manage_plans'))
  with check (app.has_permission(organization_id, 'loyalty.manage_plans'));

create policy loyalty_cards_select on public.loyalty_cards for select to authenticated
  using (organization_id in (select app.user_org_ids()));
create policy loyalty_memberships_select on public.loyalty_memberships for select to authenticated
  using (organization_id in (select app.user_org_ids()));
create policy loyalty_point_ledger_select on public.loyalty_point_ledger for select to authenticated
  using (organization_id in (select app.user_org_ids()));

grant select on public.loyalty_plans, public.loyalty_cards, public.loyalty_memberships,
  public.loyalty_point_ledger to authenticated;
grant insert (organization_id, name, duration_months, fee_paisa, discount_bp, max_discount_per_invoice_paisa,
  points_per_100_taka, point_value_paisa, min_redeem_points, is_active, sort_order)
  on public.loyalty_plans to authenticated;
grant update (name, duration_months, fee_paisa, discount_bp, max_discount_per_invoice_paisa,
  points_per_100_taka, point_value_paisa, min_redeem_points, is_active, sort_order)
  on public.loyalty_plans to authenticated;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function app.loyalty_points_balance(p_card_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(points), 0)::integer from public.loyalty_point_ledger where card_id = p_card_id
$$;

-- Active membership on a date for a card number (NULL if none).
create or replace function app.active_membership_by_card(p_organization_id uuid, p_card_no text, p_on date)
returns public.loyalty_memberships
language sql
stable
security definer
set search_path = ''
as $$
  select lm.*
    from public.loyalty_cards c
    join public.loyalty_memberships lm on lm.card_id = c.id
   where c.organization_id = p_organization_id
     and c.card_no = btrim(p_card_no)
     and c.is_active
     and lm.status = 'active'
     and p_on between lm.starts_on and lm.ends_on
   limit 1
$$;

create or replace function app.generate_card_no(p_organization_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_body text;
begin
  loop
    v_body := '8' || lpad(app.next_number(p_organization_id, 'loyalty_card')::text, 9, '0');
    exit when not exists (
      select 1 from public.loyalty_cards
       where organization_id = p_organization_id
         and card_no = v_body || app.luhn_check_digit(v_body)::text
    );
  end loop;
  return v_body || app.luhn_check_digit(v_body)::text;
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC
-- -----------------------------------------------------------------------------

-- Enrols a customer, or renews: if the card already has an active membership, the new one starts
-- the day after it ends. A card is issued automatically (or p_card_no for pre-printed cards).
create or replace function public.enroll_loyalty(
  p_customer_id uuid,
  p_plan_id uuid,
  p_branch_id uuid,
  p_client_request_id uuid,
  p_payment_method public.payment_method default 'cash',
  p_card_no text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := app.require_branch_permission(p_branch_id, 'loyalty.enroll');
  v_existing public.loyalty_memberships;
  v_plan public.loyalty_plans;
  v_customer public.customers;
  v_card public.loyalty_cards;
  v_current public.loyalty_memberships;
  v_today date := app.business_date(v_org);
  v_starts date;
  v_membership uuid;
begin
  if p_client_request_id is null then
    perform app.fail('missing_request_id', 'client_request_id is required');
  end if;
  select * into v_existing from public.loyalty_memberships
   where organization_id = v_org and client_request_id = p_client_request_id;
  if v_existing.id is not null then
    return jsonb_build_object('membership_id', v_existing.id,
      'card_no', (select card_no from public.loyalty_cards where id = v_existing.card_id),
      'starts_on', v_existing.starts_on, 'ends_on', v_existing.ends_on, 'replayed', true);
  end if;

  if not (select s.loyalty_enabled from public.organization_settings s where s.organization_id = v_org) then
    perform app.fail('loyalty_disabled', 'The loyalty programme is turned off');
  end if;
  select * into v_plan from public.loyalty_plans where id = p_plan_id and organization_id = v_org;
  if v_plan.id is null or not v_plan.is_active then
    perform app.fail('invalid_plan', 'Loyalty plan not found or not active');
  end if;
  select * into v_customer from public.customers
   where id = p_customer_id and organization_id = v_org for update;
  if v_customer.id is null or not v_customer.is_active then
    perform app.fail('invalid_customer', 'Customer not found or inactive');
  end if;
  if v_customer.phone is null then
    perform app.fail('phone_required', 'A mobile number is required for a loyalty card');
  end if;
  if v_plan.fee_paisa > 0 and (p_payment_method is null or p_payment_method = 'loyalty_points') then
    perform app.fail('invalid_payment', 'Choose how the membership fee is paid');
  end if;

  select * into v_card from public.loyalty_cards
   where organization_id = v_org and customer_id = p_customer_id and is_active;
  if v_card.id is null then
    if p_card_no is not null then
      if btrim(p_card_no) !~ '^[0-9]{6,16}$'
         or app.luhn_check_digit(left(btrim(p_card_no), -1)) <> right(btrim(p_card_no), 1)::integer then
        perform app.fail('invalid_card_no', 'Card number is not valid');
      end if;
    end if;
    insert into public.loyalty_cards (organization_id, customer_id, card_no, issued_by)
    values (v_org, p_customer_id, coalesce(btrim(p_card_no), app.generate_card_no(v_org)), auth.uid())
    returning * into v_card;
  elsif p_card_no is not null and btrim(p_card_no) <> v_card.card_no then
    perform app.fail('card_mismatch', 'This customer already has a different active card');
  end if;

  -- Renewal: start after the latest active membership that has not yet ended.
  select * into v_current from public.loyalty_memberships
   where card_id = v_card.id and status = 'active' and ends_on >= v_today
   order by ends_on desc
   limit 1;
  v_starts := case when v_current.id is null then v_today else v_current.ends_on + 1 end;

  insert into public.loyalty_memberships (
    organization_id, card_id, customer_id, plan_id, branch_id, starts_on, ends_on, fee_paid_paisa,
    payment_method, discount_bp, max_discount_per_invoice_paisa, points_per_100_taka, point_value_paisa,
    min_redeem_points, renewed_from_id, client_request_id, created_by
  ) values (
    v_org, v_card.id, p_customer_id, v_plan.id, p_branch_id, v_starts,
    (v_starts + make_interval(months => v_plan.duration_months))::date - 1,
    v_plan.fee_paisa, case when v_plan.fee_paisa > 0 then p_payment_method end,
    v_plan.discount_bp, v_plan.max_discount_per_invoice_paisa, v_plan.points_per_100_taka,
    v_plan.point_value_paisa, v_plan.min_redeem_points, v_current.id, p_client_request_id, auth.uid()
  ) returning id into v_membership;

  return jsonb_build_object('membership_id', v_membership, 'card_no', v_card.card_no,
    'starts_on', v_starts, 'ends_on', (v_starts + make_interval(months => v_plan.duration_months))::date - 1,
    'fee_paisa', v_plan.fee_paisa, 'replayed', false);
end;
$$;

create or replace function public.cancel_loyalty_membership(p_membership_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership public.loyalty_memberships;
begin
  select * into v_membership from public.loyalty_memberships where id = p_membership_id for update;
  if v_membership.id is null then
    perform app.fail('not_found', 'Membership not found');
  end if;
  perform app.require_permission(v_membership.organization_id, 'loyalty.cancel');
  if v_membership.status = 'cancelled' then
    perform app.fail('already_cancelled', 'Membership is already cancelled');
  end if;
  if coalesce(length(btrim(p_reason)), 0) < 3 then
    perform app.fail('reason_required', 'A reason is required');
  end if;
  update public.loyalty_memberships
     set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = btrim(p_reason)
   where id = p_membership_id;
end;
$$;

-- Lost/damaged card: deactivate it and issue a new number; memberships and points move with it.
create or replace function public.replace_loyalty_card(p_card_id uuid, p_reason text, p_new_card_no text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_card public.loyalty_cards;
  v_new public.loyalty_cards;
  v_points integer;
begin
  select * into v_card from public.loyalty_cards where id = p_card_id for update;
  if v_card.id is null or not v_card.is_active then
    perform app.fail('not_found', 'Active card not found');
  end if;
  perform app.require_permission(v_card.organization_id, 'loyalty.cancel');
  if coalesce(length(btrim(p_reason)), 0) < 3 then
    perform app.fail('reason_required', 'A reason is required');
  end if;
  if p_new_card_no is not null and (btrim(p_new_card_no) !~ '^[0-9]{6,16}$'
     or app.luhn_check_digit(left(btrim(p_new_card_no), -1)) <> right(btrim(p_new_card_no), 1)::integer) then
    perform app.fail('invalid_card_no', 'Card number is not valid');
  end if;

  update public.loyalty_cards
     set is_active = false, deactivated_at = now(), deactivation_reason = btrim(p_reason)
   where id = p_card_id;
  insert into public.loyalty_cards (organization_id, customer_id, card_no, issued_by)
  values (v_card.organization_id, v_card.customer_id,
          coalesce(btrim(p_new_card_no), app.generate_card_no(v_card.organization_id)), auth.uid())
  returning * into v_new;

  -- Move current and future memberships to the new card.
  update public.loyalty_memberships set card_id = v_new.id
   where card_id = v_card.id and status = 'active' and ends_on >= app.business_date(v_card.organization_id);

  v_points := app.loyalty_points_balance(v_card.id);
  if v_points <> 0 then
    insert into public.loyalty_point_ledger (organization_id, card_id, entry_type, points, note, created_by)
    values (v_card.organization_id, v_card.id, 'adjust', -v_points, 'Transferred to replacement card', auth.uid()),
           (v_card.organization_id, v_new.id, 'adjust', v_points, 'Transferred from replaced card', auth.uid());
  end if;
  return v_new.card_no;
end;
$$;

-- Card lookup for the POS (by card number or mobile number).
create or replace function public.lookup_loyalty(p_organization_id uuid, p_card_or_phone text)
returns table (
  card_id uuid,
  card_no text,
  customer_id uuid,
  customer_name text,
  membership_id uuid,
  plan_name text,
  starts_on date,
  ends_on date,
  discount_bp integer,
  points_balance integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_input text := btrim(coalesce(p_card_or_phone, ''));
  v_phone text;
  v_today date;
begin
  if p_organization_id not in (select app.user_org_ids()) then
    perform app.fail('forbidden', 'You do not have access to this organization');
  end if;
  v_today := app.business_date(p_organization_id);
  if regexp_replace(v_input, '[^0-9]', '', 'g') ~ '^(88)?01[3-9][0-9]{8}$' then
    v_phone := app.normalize_bd_phone(v_input);
  end if;
  return query
  select c.id, c.card_no, cu.id, cu.name, lm.id, lp.name, lm.starts_on, lm.ends_on, lm.discount_bp,
         app.loyalty_points_balance(c.id)
    from public.loyalty_cards c
    join public.customers cu on cu.id = c.customer_id
    left join public.loyalty_memberships lm
      on lm.card_id = c.id and lm.status = 'active' and v_today between lm.starts_on and lm.ends_on
    left join public.loyalty_plans lp on lp.id = lm.plan_id
   where c.organization_id = p_organization_id
     and c.is_active
     and (c.card_no = v_input or (v_phone is not null and cu.phone = v_phone))
   limit 1;
end;
$$;

-- Abuse monitoring: loyalty use per card per day (security_invoker: RLS applies).
-- Defined in the sales migration once the sales table exists.

grant execute on function
  public.enroll_loyalty(uuid, uuid, uuid, uuid, public.payment_method, text),
  public.cancel_loyalty_membership(uuid, text),
  public.replace_loyalty_card(uuid, text, text),
  public.lookup_loyalty(uuid, text)
to authenticated;

call app.harden_privileges();
