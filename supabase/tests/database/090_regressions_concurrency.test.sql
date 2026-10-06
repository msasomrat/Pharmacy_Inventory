-- Concurrency regression tests (real interleavings through extra sessions opened with dblink).
-- Scenarios (one per confirmed finding):
--   A. batch-lock-order-deadlock (8 assertions)
--   B. idempotency-check-then-insert-race (8 assertions)
--   C. customer-card-forupdate-vs-invoice-counter-deadlock (6 assertions)
--   D. sale-return-locks-customer-before-batches (3 assertions)
--   E. last-owner-write-skew (2 assertions)
--   F. enroll-vs-replace-card-deadlock (2 assertions)
--
-- Remote sessions cannot see uncommitted rows, so each scenario's setup data is COMMITTED (unique
-- names per run, so the file can run repeatedly against the same database). The remote transactions
-- under test are always rolled back. The file runs last on purpose and skips itself when dblink is not
-- installed or cannot open a session (for example on a hosted database without trust authentication).

select exists (select 1 from pg_catalog.pg_available_extensions where name = 'dblink') as has_dblink \gset
\if :has_dblink
begin;
create extension if not exists dblink with schema extensions;
select format('host=%s port=%s dbname=%s user=%s', split_part(current_setting('unix_socket_directories'), ',', 1),
  current_setting('port'), current_database(), current_user) as connstr \gset
create function pg_temp.can_connect(p_connstr text) returns boolean language plpgsql as $$
begin
  perform extensions.dblink_connect('probe', p_connstr);
  perform extensions.dblink_disconnect('probe');
  return true;
exception when others then
  return false;
end;
$$;
select pg_temp.can_connect(:'connstr') as connected \gset
rollback;
\else
\set connected false
\endif

\if :connected

-- =================================================================================================
-- Committed setup: batch-lock-order-deadlock
-- Regression: batch-lock-order-deadlock.
-- create_sale locks lots in (medicine_id, expiry_date, received_at, id) order; void_sale and
-- process_sale_return lock them in plain batch-id order. When the two orders disagree, a sale and a
-- void/return that touch the same lots deadlock (40P01) and one of them is aborted.
-- Lots are given ids so that the orders disagree: medicine ids A < Mid < B, lot ids b < mid < a.
-- A third session holds the MedMid lot briefly (as any concurrent sale of MedMid would) so the
-- interleaving is deterministic.
-- Needs the dblink extension and committed setup data (remote sessions cannot see uncommitted rows).

-- ---------------------------------------------------------------------------------------------
-- Committed setup (unique names, so the file can run repeatedly against the same database)
-- ---------------------------------------------------------------------------------------------
-- =================================================================================================
begin;
select format('owner-%s@lockorder.test', gen_random_uuid()) as owner_email \gset sa_
select format('manager-%s@lockorder.test', gen_random_uuid()) as manager_email \gset sa_
select format('sales-%s@lockorder.test', gen_random_uuid()) as sales_email \gset sa_
select tests.create_user(:'sa_owner_email') as owner \gset sa_
select tests.create_user(:'sa_manager_email') as manager \gset sa_
select tests.create_user(:'sa_sales_email') as sales \gset sa_

select tests.authenticate_as(:'sa_owner');
select public.create_organization('Lock Order Pharmacy', 'Mohammadpur', 'MPR') as org \gset sa_
select id as branch from public.branches where organization_id = :'sa_org' \gset sa_
select app.business_date(:'sa_org') as today \gset sa_
select tests.add_member(:'sa_org', :'sa_manager_email', 'manager', array[:'sa_branch']::uuid[]);
select tests.add_member(:'sa_org', :'sa_sales_email', 'salesman', array[:'sa_branch']::uuid[]);
select tests.clear_authentication();

-- Medicine ids sort A < Mid < B; lot ids sort b < mid < a (first hex digit decides).
select overlay(gen_random_uuid()::text placing '1' from 1 for 1)::uuid as med_a,
       overlay(gen_random_uuid()::text placing '5' from 1 for 1)::uuid as med_mid,
       overlay(gen_random_uuid()::text placing '9' from 1 for 1)::uuid as med_b,
       overlay(gen_random_uuid()::text placing 'f' from 1 for 1)::uuid as lot_a,
       overlay(gen_random_uuid()::text placing '8' from 1 for 1)::uuid as lot_mid,
       overlay(gen_random_uuid()::text placing '0' from 1 for 1)::uuid as lot_b \gset sa_

insert into public.medicines (id, organization_id, brand_name, dosage_form, strength, base_unit_label) values
  (:'sa_med_a', :'sa_org', 'MedA', 'tablet', '1 mg', 'tablet'),
  (:'sa_med_mid', :'sa_org', 'MedMid', 'tablet', '1 mg', 'tablet'),
  (:'sa_med_b', :'sa_org', 'MedB', 'tablet', '1 mg', 'tablet');
insert into public.batches (id, organization_id, branch_id, medicine_id, batch_no, expiry_date, cost_paisa, mrp_paisa, sale_price_paisa) values
  (:'sa_lot_a', :'sa_org', :'sa_branch', :'sa_med_a', 'A-1', :'sa_today'::date + 300, 50, 100, 100),
  (:'sa_lot_mid', :'sa_org', :'sa_branch', :'sa_med_mid', 'M-1', :'sa_today'::date + 300, 50, 100, 100),
  (:'sa_lot_b', :'sa_org', :'sa_branch', :'sa_med_b', 'B-1', :'sa_today'::date + 300, 50, 100, 100);
select 1 from app.post_movement(:'sa_lot_a', 'opening_balance', 100, 'opening_stock', null);
select 1 from app.post_movement(:'sa_lot_mid', 'opening_balance', 100, 'opening_stock', null);
select 1 from app.post_movement(:'sa_lot_b', 'opening_balance', 100, 'opening_stock', null);

-- Two earlier sales of MedA + MedB: S0 will be voided, S1 returned.
select tests.authenticate_as(:'sa_sales', 'aal1');
select public.create_sale(:'sa_branch', jsonb_build_array(
    jsonb_build_object('medicine_id', :'sa_med_a', 'quantity', 1), jsonb_build_object('medicine_id', :'sa_med_b', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 200}]'::jsonb, gen_random_uuid()) ->> 'sale_id' as s0 \gset sa_
select public.create_sale(:'sa_branch', jsonb_build_array(
    jsonb_build_object('medicine_id', :'sa_med_a', 'quantity', 1), jsonb_build_object('medicine_id', :'sa_med_b', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 200}]'::jsonb, gen_random_uuid()) ->> 'sale_id' as s1 \gset sa_
select tests.clear_authentication();
select id as s1_line_a from public.sale_items where sale_id = :'sa_s1' and medicine_id = :'sa_med_a' \gset sa_
select id as s1_line_b from public.sale_items where sale_id = :'sa_s1' and medicine_id = :'sa_med_b' \gset sa_
commit;

-- =================================================================================================
-- Committed setup: idempotency-check-then-insert-race
-- Regression: idempotency-check-then-insert-race.
-- create_sale / receive_goods / enroll_loyalty check for an existing client_request_id with a plain
-- SELECT and insert much later. A retry that arrives while the first call is still running passes
-- the check, waits on the first call's locks and then fails (insufficient stock or 23505) instead of
-- returning the original result.
-- Needs the dblink extension and committed setup data (remote sessions cannot see uncommitted rows).

-- ---------------------------------------------------------------------------------------------
-- Committed setup
-- ---------------------------------------------------------------------------------------------
-- =================================================================================================
begin;
select format('owner-%s@idem.test', gen_random_uuid()) as owner_email \gset sb_
select format('manager-%s@idem.test', gen_random_uuid()) as manager_email \gset sb_
select format('sales-%s@idem.test', gen_random_uuid()) as sales_email \gset sb_
select tests.create_user(:'sb_owner_email') as owner \gset sb_
select tests.create_user(:'sb_manager_email') as manager \gset sb_
select tests.create_user(:'sb_sales_email') as sales \gset sb_

select tests.authenticate_as(:'sb_owner');
select public.create_organization('Idempotency Pharmacy', 'Mohammadpur', 'MPR') as org \gset sb_
select id as branch from public.branches where organization_id = :'sb_org' \gset sb_
select app.business_date(:'sb_org') as today \gset sb_
select tests.add_member(:'sb_org', :'sb_manager_email', 'manager', array[:'sb_branch']::uuid[]);
select tests.add_member(:'sb_org', :'sb_sales_email', 'salesman', array[:'sb_branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'sb_org', 'MedLast', 'tablet', '1 mg', 'tablet') returning id as med_last \gset sb_
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'sb_org', 'MedPlenty', 'tablet', '1 mg', 'tablet') returning id as med_plenty \gset sb_
insert into public.suppliers (organization_id, name) values (:'sb_org', 'Depot') returning id as supplier \gset sb_
insert into public.customers (organization_id, name, phone) values (:'sb_org', 'Karim', '01811223344') returning id as customer \gset sb_
update public.loyalty_plans set is_active = true, discount_bp = 500
 where organization_id = :'sb_org' and duration_months = 3 returning id as plan3 \gset sb_

select tests.authenticate_as(:'sb_manager');
select public.receive_goods(:'sb_branch', :'sb_supplier', jsonb_build_array(
  jsonb_build_object('medicine_id', :'sb_med_last', 'batch_no', 'L-1', 'expiry_date', :'sb_today'::date + 300,
    'quantity', 1, 'unit_cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120),
  jsonb_build_object('medicine_id', :'sb_med_plenty', 'batch_no', 'P-1', 'expiry_date', :'sb_today'::date + 300,
    'quantity', 100, 'unit_cost_paisa', 80, 'mrp_paisa', 120, 'sale_price_paisa', 120)), gen_random_uuid());
-- a first sale so the invoice counter row exists
select tests.authenticate_as(:'sb_sales', 'aal1');
select public.create_sale(:'sb_branch', jsonb_build_array(jsonb_build_object('medicine_id', :'sb_med_plenty', 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 120}]'::jsonb, gen_random_uuid()) is not null;
select tests.clear_authentication();
commit;

-- =================================================================================================
-- Committed setup: customer-card-forupdate-vs-invoice-counter-deadlock
-- Regression: customer-card-forupdate-vs-invoice-counter-deadlock.
-- A credit sale locks the customer row FOR UPDATE (and a points-redeeming sale locks the card row FOR
-- UPDATE) before it takes the branch invoice counter. Any other sale that references the same customer
-- (or card) and already holds the counter then blocks on its foreign-key check (FOR KEY SHARE conflicts
-- with FOR UPDATE): a lock cycle, 40P01.
-- A third session holds the invoice counter briefly, as any in-flight sale in the branch does, so the
-- queue order (cash sale first, then credit sale) is deterministic.
-- Needs the dblink extension and committed setup data (remote sessions cannot see uncommitted rows).

-- ---------------------------------------------------------------------------------------------
-- Committed setup
-- ---------------------------------------------------------------------------------------------
-- =================================================================================================
begin;
select format('owner-%s@counter.test', gen_random_uuid()) as owner_email \gset sc_
select format('sales-%s@counter.test', gen_random_uuid()) as sales_email \gset sc_
select tests.create_user(:'sc_owner_email') as owner \gset sc_
select tests.create_user(:'sc_sales_email') as sales \gset sc_

select tests.authenticate_as(:'sc_owner');
select public.create_organization('Counter Pharmacy', 'Mohammadpur', 'MPR') as org \gset sc_
select id as branch from public.branches where organization_id = :'sc_org' \gset sc_
select app.business_date(:'sc_org') as today \gset sc_
select tests.add_member(:'sc_org', :'sc_sales_email', 'salesman', array[:'sc_branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'sc_org', 'MedX', 'tablet', '1 mg', 'tablet') returning id as med_x \gset sc_
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'sc_org', 'MedY', 'tablet', '1 mg', 'tablet') returning id as med_y \gset sc_
insert into public.customers (organization_id, name, phone) values (:'sc_org', 'Karim', '01811223344') returning id as customer \gset sc_
select public.set_customer_credit_limit(:'sc_customer', 1000000);
update public.loyalty_plans
   set is_active = true, points_per_100_taka = 1, point_value_paisa = 100
 where organization_id = :'sc_org' and duration_months = 3 returning id as plan3 \gset sc_
select public.add_opening_stock(:'sc_branch', jsonb_build_array(
  jsonb_build_object('medicine_id', :'sc_med_x', 'batch_no', 'X-1', 'expiry_date', :'sc_today'::date + 300,
    'quantity', 10000, 'cost_paisa', 50, 'mrp_paisa', 100, 'sale_price_paisa', 100),
  jsonb_build_object('medicine_id', :'sc_med_y', 'batch_no', 'Y-1', 'expiry_date', :'sc_today'::date + 300,
    'quantity', 10000, 'cost_paisa', 50, 'mrp_paisa', 100, 'sale_price_paisa', 100)), gen_random_uuid());

select tests.authenticate_as(:'sc_sales', 'aal1');
select public.enroll_loyalty(:'sc_customer', :'sc_plan3', :'sc_branch', gen_random_uuid()) ->> 'card_no' as card_no \gset sc_
-- Earn 50 points; this also creates the branch invoice counter row.
select public.create_sale(:'sc_branch', jsonb_build_array(jsonb_build_object('medicine_id', :'sc_med_x', 'quantity', 5000)),
  '[{"method": "cash", "amount_paisa": 500000}]'::jsonb, gen_random_uuid(), null, :'sc_card_no') is not null;
select tests.clear_authentication();
select app.fiscal_year_label(:'sc_today'::date, 7) as fy \gset sc_
commit;

-- =================================================================================================
-- Committed setup: sale-return-locks-customer-before-batches
-- Regression: sale-return-locks-customer-before-batches.
-- process_sale_return locks the customer row FOR UPDATE (credit sale) long before it locks the lots it
-- restocks; create_sale locks lots first and needs the customer row (FK check) only when it inserts the
-- sale. A return of a credit sale and a new sale of the same medicine for the same customer therefore
-- wait on each other: 40P01.
-- A third session holds the invoice counter briefly (as any in-flight sale in the branch does) so the
-- new sale is paused between locking the lot and inserting the sale row; this makes it deterministic.
-- Needs the dblink extension and committed setup data (remote sessions cannot see uncommitted rows).

-- ---------------------------------------------------------------------------------------------
-- Committed setup
-- ---------------------------------------------------------------------------------------------
-- =================================================================================================
begin;
select format('owner-%s@retorder.test', gen_random_uuid()) as owner_email \gset sd_
select format('manager-%s@retorder.test', gen_random_uuid()) as manager_email \gset sd_
select format('sales-%s@retorder.test', gen_random_uuid()) as sales_email \gset sd_
select tests.create_user(:'sd_owner_email') as owner \gset sd_
select tests.create_user(:'sd_manager_email') as manager \gset sd_
select tests.create_user(:'sd_sales_email') as sales \gset sd_

select tests.authenticate_as(:'sd_owner');
select public.create_organization('Return Order Pharmacy', 'Mohammadpur', 'MPR') as org \gset sd_
select id as branch from public.branches where organization_id = :'sd_org' \gset sd_
select app.business_date(:'sd_org') as today \gset sd_
select tests.add_member(:'sd_org', :'sd_manager_email', 'manager', array[:'sd_branch']::uuid[]);
select tests.add_member(:'sd_org', :'sd_sales_email', 'salesman', array[:'sd_branch']::uuid[]);
insert into public.medicines (organization_id, brand_name, dosage_form, strength, base_unit_label)
  values (:'sd_org', 'Napa', 'tablet', '500 mg', 'tablet') returning id as napa \gset sd_
insert into public.customers (organization_id, name, phone) values (:'sd_org', 'Karim', '01811223344') returning id as customer \gset sd_
select public.set_customer_credit_limit(:'sd_customer', 1000000);
select public.add_opening_stock(:'sd_branch', jsonb_build_array(
  jsonb_build_object('medicine_id', :'sd_napa', 'batch_no', 'NA-1', 'expiry_date', :'sd_today'::date + 300,
    'quantity', 1000, 'cost_paisa', 50, 'mrp_paisa', 100, 'sale_price_paisa', 100)), gen_random_uuid());

-- Credit sale S for the customer (nothing paid).
select tests.authenticate_as(:'sd_sales', 'aal1');
select public.create_sale(:'sd_branch', jsonb_build_array(jsonb_build_object('medicine_id', :'sd_napa', 'quantity', 5)),
  '[]'::jsonb, gen_random_uuid(), :'sd_customer') ->> 'sale_id' as sale_s \gset sd_
select tests.clear_authentication();
select id as sale_s_line from public.sale_items where sale_id = :'sd_sale_s' \gset sd_
select app.fiscal_year_label(:'sd_today'::date, 7) as fy \gset sd_
commit;

-- =================================================================================================
-- Committed setup: last-owner-write-skew
-- Regression: last-owner-write-skew.
-- update_member locks only the membership being changed and app.assert_not_last_owner reads the other
-- owners without a lock. Two owners who step down at the same time each still see the other as an
-- active owner, both commits succeed, and the organization is left with no active owner.
-- Needs the dblink extension and committed setup data (remote sessions cannot see uncommitted rows).

-- ---------------------------------------------------------------------------------------------
-- Committed setup: organization with two owners A and B
-- ---------------------------------------------------------------------------------------------
-- =================================================================================================
begin;
select format('owner-a-%s@owners.test', gen_random_uuid()) as a_email \gset se_
select format('owner-b-%s@owners.test', gen_random_uuid()) as b_email \gset se_
select tests.create_user(:'se_a_email') as owner_a \gset se_
select tests.create_user(:'se_b_email') as owner_b \gset se_

select tests.authenticate_as(:'se_owner_a');
select public.create_organization('Two Owners Pharmacy', 'Mohammadpur', 'MPR') as org \gset se_
select tests.add_member(:'se_org', :'se_b_email', 'owner') as membership_b \gset se_
select id as membership_a from public.memberships where organization_id = :'se_org' and user_id = :'se_owner_a' \gset se_
select tests.clear_authentication();
commit;

-- =================================================================================================
-- Committed setup: enroll-vs-replace-card-deadlock
-- Regression: enroll-vs-replace-card-deadlock.
-- enroll_loyalty locks the customer FOR UPDATE and then needs FOR KEY SHARE on the card (FK of the new
-- membership); replace_loyalty_card locks the card FOR UPDATE and then needs FOR KEY SHARE on the
-- customer (FK of the new card). Renewing and replacing the same customer's card at the same time
-- deadlocks (40P01).
-- A third session holds the organization's card-number counter briefly (as any concurrent enrolment
-- does) so the replacement is paused between locking the old card and inserting the new one.
-- Needs the dblink extension and committed setup data (remote sessions cannot see uncommitted rows).

-- ---------------------------------------------------------------------------------------------
-- Committed setup
-- ---------------------------------------------------------------------------------------------
-- =================================================================================================
begin;
select format('owner-%s@cardlock.test', gen_random_uuid()) as owner_email \gset sf_
select format('manager-%s@cardlock.test', gen_random_uuid()) as manager_email \gset sf_
select format('sales-%s@cardlock.test', gen_random_uuid()) as sales_email \gset sf_
select tests.create_user(:'sf_owner_email') as owner \gset sf_
select tests.create_user(:'sf_manager_email') as manager \gset sf_
select tests.create_user(:'sf_sales_email') as sales \gset sf_

select tests.authenticate_as(:'sf_owner');
select public.create_organization('Card Lock Pharmacy', 'Mohammadpur', 'MPR') as org \gset sf_
select id as branch from public.branches where organization_id = :'sf_org' \gset sf_
select tests.add_member(:'sf_org', :'sf_manager_email', 'manager', array[:'sf_branch']::uuid[]);
select tests.add_member(:'sf_org', :'sf_sales_email', 'salesman', array[:'sf_branch']::uuid[]);
insert into public.customers (organization_id, name, phone) values (:'sf_org', 'Karim', '01811223344') returning id as customer \gset sf_
update public.loyalty_plans set is_active = true, discount_bp = 500
 where organization_id = :'sf_org' and duration_months = 3 returning id as plan3 \gset sf_
select tests.authenticate_as(:'sf_sales', 'aal1');
select public.enroll_loyalty(:'sf_customer', :'sf_plan3', :'sf_branch', gen_random_uuid()) ->> 'card_no' as card_no \gset sf_
select tests.clear_authentication();
select id as card from public.loyalty_cards where organization_id = :'sf_org' and card_no = :'sf_card_no' \gset sf_
commit;

-- =================================================================================================
-- Scenarios
-- =================================================================================================
begin;
select plan(29);
create extension if not exists dblink with schema extensions;

-- ---- multi-session harness (dblink) --------------------------------------------------------
-- Opens extra sessions to the same database so two RPC calls can interleave deterministically.
-- Data the remote sessions need was committed above; the remote transactions are rolled back.
select format('host=%s port=%s dbname=%s user=%s', split_part(current_setting('unix_socket_directories'), ',', 1),
  current_setting('port'), current_database(), current_user) as connstr \gset

create temp table conn_pids (conn text primary key, pid integer not null) on commit drop;

create function pg_temp.connect(p_conn text, p_connstr text)
returns void language plpgsql as $$
declare
  v_pid integer;
begin
  perform extensions.dblink_connect(p_conn, p_connstr);
  -- safety net so a broken scenario can never hang the suite
  perform extensions.dblink_exec(p_conn, 'set statement_timeout = ''30s''');
  select pid into v_pid from extensions.dblink(p_conn, 'select pg_backend_pid()') as t(pid integer);
  insert into pg_temp.conn_pids values (p_conn, v_pid);
end;
$$;

-- Runs a statement synchronously (no result rows expected).
create function pg_temp.exec(p_conn text, p_sql text)
returns void language plpgsql as $$
begin
  perform extensions.dblink_exec(p_conn, p_sql);
end;
$$;

-- Runs a one-column query synchronously and returns the first value as text.
create function pg_temp.run(p_conn text, p_sql text)
returns text language plpgsql as $$
declare
  v_res text;
begin
  select x into v_res from extensions.dblink(p_conn, p_sql) as t(x text) limit 1;
  return v_res;
end;
$$;

-- Starts a one-column query asynchronously.
create function pg_temp.send(p_conn text, p_sql text)
returns void language plpgsql as $$
begin
  perform extensions.dblink_send_query(p_conn, p_sql);
end;
$$;

-- Waits until p_conn's backend is blocked by p_blocker's backend (true), or p_conn finished (false).
create function pg_temp.wait_blocked_by(p_conn text, p_blocker text, p_timeout_ms integer default 15000)
returns boolean language plpgsql as $$
declare
  v_pid integer := (select pid from pg_temp.conn_pids where conn = p_conn);
  v_blocker integer := (select pid from pg_temp.conn_pids where conn = p_blocker);
  v_waited integer := 0;
begin
  loop
    if v_blocker = any (pg_blocking_pids(v_pid)) then
      return true;
    end if;
    if extensions.dblink_is_busy(p_conn) = 0 then
      return false;
    end if;
    exit when v_waited > p_timeout_ms;
    perform pg_sleep(0.02);
    v_waited := v_waited + 20;
  end loop;
  return false;
end;
$$;

-- Waits until p_conn's backend is waiting for a lock held (or queued) by any other session.
create function pg_temp.wait_blocked(p_conn text, p_timeout_ms integer default 15000)
returns boolean language plpgsql as $$
declare
  v_pid integer := (select pid from pg_temp.conn_pids where conn = p_conn);
  v_waited integer := 0;
begin
  loop
    if cardinality(pg_blocking_pids(v_pid)) > 0 then
      return true;
    end if;
    if extensions.dblink_is_busy(p_conn) = 0 then
      return false;
    end if;
    exit when v_waited > p_timeout_ms;
    perform pg_sleep(0.02);
    v_waited := v_waited + 20;
  end loop;
  return false;
end;
$$;

-- Waits for the async query on p_conn and returns its value, or 'ERROR <sqlstate>: <message>'.
create function pg_temp.result(p_conn text)
returns text language plpgsql as $$
declare
  v_res text;
  v_state text;
  v_msg text;
begin
  while extensions.dblink_is_busy(p_conn) = 1 loop
    perform pg_sleep(0.02);
  end loop;
  begin
    select x into v_res from extensions.dblink_get_result(p_conn) as t(x text);
  exception when others or query_canceled then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    v_res := format('ERROR %s: %s', v_state, v_msg);
  end;
  perform * from extensions.dblink_get_result(p_conn, false) as t(x text);
  return coalesce(v_res, '');
end;
$$;

-- Collects the async results of several sessions in whatever order they finish, rolling each
-- remote transaction back as soon as it has finished (so a session waiting on it can proceed).
create temp table conn_results (conn text primary key, result text) on commit drop;
create function pg_temp.settle(variadic p_conns text[])
returns void language plpgsql as $$
declare
  v_conn text;
  v_left text[] := p_conns;
begin
  delete from pg_temp.conn_results where conn = any (p_conns);
  while cardinality(v_left) > 0 loop
    foreach v_conn in array v_left loop
      if extensions.dblink_is_busy(v_conn) = 0 then
        insert into pg_temp.conn_results values (v_conn, pg_temp.result(v_conn));
        perform extensions.dblink_exec(v_conn, 'rollback', false);
        v_left := array_remove(v_left, v_conn);
      end if;
    end loop;
    perform pg_sleep(0.02);
  end loop;
end;
$$;

create function pg_temp.outcome(p_conn text)
returns text language sql as $$
  select result from pg_temp.conn_results where conn = p_conn
$$;

create function pg_temp.disconnect_all()
returns void language plpgsql as $$
declare
  c record;
begin
  for c in select conn from pg_temp.conn_pids loop
    perform extensions.dblink_exec(c.conn, 'rollback', false);
    perform extensions.dblink_disconnect(c.conn);
  end loop;
  delete from pg_temp.conn_pids;
end;
$$;
-- ---- end of harness -------------------------------------------------------------------------

-- =================================================================================================
-- A. batch-lock-order-deadlock
-- =================================================================================================
select pg_temp.connect('other', :'connstr');
select pg_temp.connect('cashier', :'connstr');
select pg_temp.connect('manager', :'connstr');

select format($$select public.create_sale(%L, jsonb_build_array(
    jsonb_build_object('medicine_id', %L, 'quantity', 1), jsonb_build_object('medicine_id', %L, 'quantity', 1),
    jsonb_build_object('medicine_id', %L, 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 300}]'::jsonb, gen_random_uuid())::text$$,
  :'sa_branch', :'sa_med_a', :'sa_med_mid', :'sa_med_b') as new_sale_sql \gset sa_

-- ---------------------------------------------------------------------------------------------
-- Scenario 1: new sale (MedA + MedMid + MedB) while a manager voids S0 (MedA + MedB)
-- ---------------------------------------------------------------------------------------------
select pg_temp.exec('other', 'begin');
select pg_temp.run('other', format('select id::text from public.batches where id = %L for update', :'sa_lot_mid'));

select pg_temp.exec('cashier', 'begin');
select pg_temp.run('cashier', format('select tests.authenticate_as(%L, %L)::text', :'sa_sales', 'aal1'));
select pg_temp.send('cashier', :'sa_new_sale_sql');
select ok(pg_temp.wait_blocked_by('cashier', 'other'),
  'setup: the new sale has locked the MedA lot and waits for the MedMid lot');

select pg_temp.exec('manager', 'begin');
select pg_temp.run('manager', format('select tests.authenticate_as(%L)::text', :'sa_manager'));
select pg_temp.send('manager', format('select public.void_sale(%L, %L)::text', :'sa_s0', 'wrong items'));
select ok(pg_temp.wait_blocked_by('manager', 'cashier'),
  'setup: void_sale waits for a lot held by the in-flight sale');

select pg_temp.exec('other', 'rollback');
select pg_temp.settle('cashier', 'manager');
select pg_temp.outcome('cashier') as r_sale, pg_temp.outcome('manager') as r_void \gset sa_

select unalike(:'sa_r_sale'::text, 'ERROR%', 'a sale running alongside a void of an earlier sale is not aborted');
select unalike(:'sa_r_void'::text, 'ERROR%', 'a void running alongside a new sale is not aborted');
select ok(:'sa_r_sale' not like 'ERROR 40P01%' and :'sa_r_void' not like 'ERROR 40P01%',
  'sale vs void: no deadlock (one canonical lot lock order)');

-- ---------------------------------------------------------------------------------------------
-- Scenario 2: same new sale while a manager processes a return of S1 (MedA + MedB)
-- ---------------------------------------------------------------------------------------------
select pg_temp.exec('other', 'begin');
select pg_temp.run('other', format('select id::text from public.batches where id = %L for update', :'sa_lot_mid'));

select pg_temp.exec('cashier', 'begin');
select pg_temp.run('cashier', format('select tests.authenticate_as(%L, %L)::text', :'sa_sales', 'aal1'));
select pg_temp.send('cashier', :'sa_new_sale_sql');
select ok(pg_temp.wait_blocked_by('cashier', 'other'),
  'setup: the new sale has locked the MedA lot and waits for the MedMid lot');

select pg_temp.exec('manager', 'begin');
select pg_temp.run('manager', format('select tests.authenticate_as(%L)::text', :'sa_manager'));
select pg_temp.send('manager', format($$select public.process_sale_return(%L, jsonb_build_array(
    jsonb_build_object('sale_item_id', %L, 'quantity', 1), jsonb_build_object('sale_item_id', %L, 'quantity', 1)),
  'customer returned', gen_random_uuid())::text$$, :'sa_s1', :'sa_s1_line_a', :'sa_s1_line_b'));
select ok(pg_temp.wait_blocked_by('manager', 'cashier'),
  'setup: process_sale_return waits for a lot held by the in-flight sale');

select pg_temp.exec('other', 'rollback');
select pg_temp.settle('cashier', 'manager');
select pg_temp.outcome('cashier') as r_sale2, pg_temp.outcome('manager') as r_return \gset sa_

select ok(:'sa_r_sale2' not like 'ERROR 40P01%' and :'sa_r_return' not like 'ERROR 40P01%',
  'sale vs return: no deadlock (one canonical lot lock order)');
select diag('scenario 1: sale -> ' || left(:'sa_r_sale', 160) || ' | void -> ' || left(:'sa_r_void', 160));
select diag('scenario 2: sale -> ' || left(:'sa_r_sale2', 160) || ' | return -> ' || left(:'sa_r_return', 160));

select pg_temp.disconnect_all();

-- =================================================================================================
-- B. idempotency-check-then-insert-race
-- =================================================================================================
-- true when an RPC result is a replay of the original document (key = the id field to compare)
create function pg_temp.is_replay(p_retry text, p_first text, p_key text)
returns boolean language plpgsql as $$
begin
  return (p_retry::jsonb ->> 'replayed')::boolean and p_retry::jsonb ->> p_key = p_first::jsonb ->> p_key;
exception when others then
  return false;
end;
$$;

select pg_temp.connect('first', :'connstr');
select pg_temp.connect('retry', :'connstr');

-- Scenario a: the last unit. First call is still in flight when the client retries.
select gen_random_uuid() as req_a \gset sb_
select format($$select public.create_sale(%L, jsonb_build_array(jsonb_build_object('medicine_id', %L, 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 120}]'::jsonb, %L)::text$$, :'sb_branch', :'sb_med_last', :'sb_req_a') as sale_a_sql \gset sb_
select pg_temp.exec('first', 'begin');
select pg_temp.run('first', format('select tests.authenticate_as(%L, %L)::text', :'sb_sales', 'aal1'));
select pg_temp.run('first', :'sb_sale_a_sql') as first_a \gset sb_
select pg_temp.exec('retry', 'begin');
select pg_temp.run('retry', format('select tests.authenticate_as(%L, %L)::text', :'sb_sales', 'aal1'));
select pg_temp.send('retry', :'sb_sale_a_sql');
select ok(pg_temp.wait_blocked_by('retry', 'first'), 'setup: the retry waits for the in-flight first call');
select pg_temp.exec('first', 'commit');
select pg_temp.result('retry') as retry_a \gset sb_
select pg_temp.exec('retry', 'rollback');
select diag('sale, last unit: retry -> ' || left(:'sb_retry_a', 200));
select unalike(:'sb_retry_a'::text, 'ERROR%', 'create_sale retry (last unit) does not fail');
select ok(pg_temp.is_replay(:'sb_retry_a', :'sb_first_a', 'sale_id'), 'create_sale retry (last unit) returns the original sale');

-- Scenario b: plenty of stock.
select gen_random_uuid() as req_b \gset sb_
select format($$select public.create_sale(%L, jsonb_build_array(jsonb_build_object('medicine_id', %L, 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 120}]'::jsonb, %L)::text$$, :'sb_branch', :'sb_med_plenty', :'sb_req_b') as sale_b_sql \gset sb_
select pg_temp.exec('first', 'begin');
select pg_temp.run('first', format('select tests.authenticate_as(%L, %L)::text', :'sb_sales', 'aal1'));
select pg_temp.run('first', :'sb_sale_b_sql') as first_b \gset sb_
select pg_temp.exec('retry', 'begin');
select pg_temp.run('retry', format('select tests.authenticate_as(%L, %L)::text', :'sb_sales', 'aal1'));
select pg_temp.send('retry', :'sb_sale_b_sql');
select ok(pg_temp.wait_blocked_by('retry', 'first'), 'setup: the retry waits for the in-flight first call');
select pg_temp.exec('first', 'commit');
select pg_temp.result('retry') as retry_b \gset sb_
select pg_temp.exec('retry', 'rollback');
select diag('sale, enough stock: retry -> ' || left(:'sb_retry_b', 200));
select ok(pg_temp.is_replay(:'sb_retry_b', :'sb_first_b', 'sale_id'), 'create_sale retry (enough stock) returns the original sale');

-- Scenario c: goods receipt retried while the first receipt is in flight.
select gen_random_uuid() as req_c \gset sb_
select format($$select public.receive_goods(%L, %L, jsonb_build_array(jsonb_build_object('medicine_id', %L,
  'batch_no', 'P-2', 'expiry_date', %L, 'quantity', 10, 'unit_cost_paisa', 80, 'mrp_paisa', 120,
  'sale_price_paisa', 120)), %L)::text$$, :'sb_branch', :'sb_supplier', :'sb_med_plenty', :'sb_today'::date + 200, :'sb_req_c') as grn_sql \gset sb_
select pg_temp.exec('first', 'begin');
select pg_temp.run('first', format('select tests.authenticate_as(%L)::text', :'sb_manager'));
select pg_temp.run('first', :'sb_grn_sql') as first_c \gset sb_
select pg_temp.exec('retry', 'begin');
select pg_temp.run('retry', format('select tests.authenticate_as(%L)::text', :'sb_manager'));
select pg_temp.send('retry', :'sb_grn_sql');
select ok(pg_temp.wait_blocked_by('retry', 'first'), 'setup: the GRN retry waits for the in-flight first call');
select pg_temp.exec('first', 'commit');
select pg_temp.result('retry') as retry_c \gset sb_
select pg_temp.exec('retry', 'rollback');
select diag('receive_goods: retry -> ' || left(:'sb_retry_c', 200));
select ok(pg_temp.is_replay(:'sb_retry_c', :'sb_first_c', 'goods_receipt_id'), 'receive_goods retry returns the original receipt');

-- Scenario d: enroll_loyalty retried while the first enrolment is in flight.
select gen_random_uuid() as req_d \gset sb_
select format($$select public.enroll_loyalty(%L, %L, %L, %L)::text$$, :'sb_customer', :'sb_plan3', :'sb_branch', :'sb_req_d') as enrol_sql \gset sb_
select pg_temp.exec('first', 'begin');
select pg_temp.run('first', format('select tests.authenticate_as(%L, %L)::text', :'sb_sales', 'aal1'));
select pg_temp.run('first', :'sb_enrol_sql') as first_d \gset sb_
select pg_temp.exec('retry', 'begin');
select pg_temp.run('retry', format('select tests.authenticate_as(%L, %L)::text', :'sb_sales', 'aal1'));
select pg_temp.send('retry', :'sb_enrol_sql');
select pg_temp.wait_blocked_by('retry', 'first');
select pg_temp.exec('first', 'commit');
select pg_temp.result('retry') as retry_d \gset sb_
select pg_temp.exec('retry', 'rollback');
select diag('enroll_loyalty: retry -> ' || left(:'sb_retry_d', 200));
select ok(pg_temp.is_replay(:'sb_retry_d', :'sb_first_d', 'membership_id'), 'enroll_loyalty retry returns the original membership');

select pg_temp.disconnect_all();

-- =================================================================================================
-- C. customer-card-forupdate-vs-invoice-counter-deadlock
-- =================================================================================================
select pg_temp.connect('other', :'connstr');
select pg_temp.connect('counter1', :'connstr');
select pg_temp.connect('counter2', :'connstr');

-- ---------------------------------------------------------------------------------------------
-- Scenario 1: customer row. counter1 rings a cash sale for the customer (queued on the invoice
-- counter); counter2 rings a credit sale for the same customer.
-- ---------------------------------------------------------------------------------------------
select pg_temp.exec('other', 'begin');
select pg_temp.run('other', format('select last_value::text from app.document_sequences where scope_id = %L and doc_type = %L and period = %L for update', :'sc_branch', 'sale', :'sc_fy'));

select pg_temp.exec('counter1', 'begin');
select pg_temp.run('counter1', format('select tests.authenticate_as(%L, %L)::text', :'sc_sales', 'aal1'));
select pg_temp.send('counter1', format($$select public.create_sale(%L,
  jsonb_build_array(jsonb_build_object('medicine_id', %L, 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 100}]'::jsonb, gen_random_uuid(), %L)::text$$, :'sc_branch', :'sc_med_x', :'sc_customer'));
select ok(pg_temp.wait_blocked_by('counter1', 'other'), 'setup: the cash sale for the customer waits for the invoice counter');

select pg_temp.exec('counter2', 'begin');
select pg_temp.run('counter2', format('select tests.authenticate_as(%L, %L)::text', :'sc_sales', 'aal1'));
select pg_temp.send('counter2', format($$select public.create_sale(%L,
  jsonb_build_array(jsonb_build_object('medicine_id', %L, 'quantity', 1)),
  '[]'::jsonb, gen_random_uuid(), %L)::text$$, :'sc_branch', :'sc_med_y', :'sc_customer'));
select ok(pg_temp.wait_blocked('counter2'), 'setup: the credit sale (customer row locked) waits for the invoice counter');

select pg_temp.exec('other', 'rollback');
select pg_temp.settle('counter1', 'counter2');
select pg_temp.outcome('counter1') as r_cash, pg_temp.outcome('counter2') as r_credit \gset sc_
select diag('customer: cash sale -> ' || left(:'sc_r_cash', 120) || ' | credit sale -> ' || left(:'sc_r_credit', 120));
select ok(:'sc_r_cash' not like 'ERROR%' and :'sc_r_credit' not like 'ERROR%',
  'two sales for the same customer (cash and credit) both complete');

-- ---------------------------------------------------------------------------------------------
-- Scenario 2: loyalty card row. counter1 earns points with the card (queued on the counter);
-- counter2 redeems points with the same card.
-- ---------------------------------------------------------------------------------------------
select pg_temp.exec('other', 'begin');
select pg_temp.run('other', format('select last_value::text from app.document_sequences where scope_id = %L and doc_type = %L and period = %L for update', :'sc_branch', 'sale', :'sc_fy'));

select pg_temp.exec('counter1', 'begin');
select pg_temp.run('counter1', format('select tests.authenticate_as(%L, %L)::text', :'sc_sales', 'aal1'));
select pg_temp.send('counter1', format($$select public.create_sale(%L,
  jsonb_build_array(jsonb_build_object('medicine_id', %L, 'quantity', 100)),
  '[{"method": "cash", "amount_paisa": 10000}]'::jsonb, gen_random_uuid(), null, %L)::text$$, :'sc_branch', :'sc_med_x', :'sc_card_no'));
select ok(pg_temp.wait_blocked_by('counter1', 'other'), 'setup: the points-earning sale waits for the invoice counter');

select pg_temp.exec('counter2', 'begin');
select pg_temp.run('counter2', format('select tests.authenticate_as(%L, %L)::text', :'sc_sales', 'aal1'));
select pg_temp.send('counter2', format($$select public.create_sale(%L,
  jsonb_build_array(jsonb_build_object('medicine_id', %L, 'quantity', 10)),
  '[{"method": "loyalty_points", "amount_paisa": 1000}]'::jsonb, gen_random_uuid(), null, %L)::text$$, :'sc_branch', :'sc_med_y', :'sc_card_no'));
select ok(pg_temp.wait_blocked('counter2'), 'setup: the points-redeeming sale waits (for the card row or the invoice counter)');

select pg_temp.exec('other', 'rollback');
select pg_temp.settle('counter1', 'counter2');
select pg_temp.outcome('counter1') as r_earn, pg_temp.outcome('counter2') as r_redeem \gset sc_
select diag('card: earning sale -> ' || left(:'sc_r_earn', 120) || ' | redeeming sale -> ' || left(:'sc_r_redeem', 120));
select ok(:'sc_r_earn' not like 'ERROR%' and :'sc_r_redeem' not like 'ERROR%',
  'two sales with the same loyalty card (earn and redeem) both complete');

select pg_temp.disconnect_all();

-- =================================================================================================
-- D. sale-return-locks-customer-before-batches
-- =================================================================================================
select pg_temp.connect('other', :'connstr');
select pg_temp.connect('cashier', :'connstr');
select pg_temp.connect('manager', :'connstr');

select pg_temp.exec('other', 'begin');
select pg_temp.run('other', format('select last_value::text from app.document_sequences where scope_id = %L and doc_type = %L and period = %L for update', :'sd_branch', 'sale', :'sd_fy'));

-- New cash sale of Napa for the same customer: locks the Napa lot, then waits for the counter.
select pg_temp.exec('cashier', 'begin');
select pg_temp.run('cashier', format('select tests.authenticate_as(%L, %L)::text', :'sd_sales', 'aal1'));
select pg_temp.send('cashier', format($$select public.create_sale(%L,
  jsonb_build_array(jsonb_build_object('medicine_id', %L, 'quantity', 1)),
  '[{"method": "cash", "amount_paisa": 100}]'::jsonb, gen_random_uuid(), %L)::text$$, :'sd_branch', :'sd_napa', :'sd_customer'));
select ok(pg_temp.wait_blocked_by('cashier', 'other'), 'setup: the new sale holds the Napa lot and waits for the invoice counter');

-- Return of one unit of S: locks S, the customer (credit sale), ... then the Napa lot.
select pg_temp.exec('manager', 'begin');
select pg_temp.run('manager', format('select tests.authenticate_as(%L)::text', :'sd_manager'));
select pg_temp.send('manager', format($$select public.process_sale_return(%L,
  jsonb_build_array(jsonb_build_object('sale_item_id', %L, 'quantity', 1)), 'customer returned', gen_random_uuid())::text$$,
  :'sd_sale_s', :'sd_sale_s_line'));
select ok(pg_temp.wait_blocked_by('manager', 'cashier'), 'setup: the return waits for the Napa lot held by the new sale');
select diag('return session holds a customer row lock while waiting for the lot (false: lots are locked first): ' ||
  exists (select 1 from pg_locks l join pg_temp.conn_pids c on c.pid = l.pid
           where c.conn = 'manager' and l.locktype = 'relation' and l.relation = 'public.customers'::regclass
             and l.mode = 'RowShareLock')::text);

select pg_temp.exec('other', 'rollback');
select pg_temp.settle('cashier', 'manager');
select pg_temp.outcome('cashier') as r_sale, pg_temp.outcome('manager') as r_return \gset sd_
select diag('new sale -> ' || left(:'sd_r_sale', 120) || ' | return -> ' || left(:'sd_r_return', 120));
select ok(:'sd_r_sale' not like 'ERROR%' and :'sd_r_return' not like 'ERROR%',
  'a return of a credit sale and a new sale for the same customer and medicine both complete');

select pg_temp.disconnect_all();

-- =================================================================================================
-- E. last-owner-write-skew
-- =================================================================================================
select pg_temp.connect('a', :'connstr');
select pg_temp.connect('b', :'connstr');

-- Sequential sanity check (one remote transaction, rolled back): A steps down, then B cannot.
select pg_temp.exec('a', 'begin');
select pg_temp.run('a', format('select tests.authenticate_as(%L)::text', :'se_owner_a'));
select pg_temp.run('a', format('select public.update_member(%L, %L, false, %L)::text', :'se_membership_a', 'owner', '{}'));
select pg_temp.run('a', format('select tests.authenticate_as(%L)::text', :'se_owner_b'));
select pg_temp.send('a', format('select public.update_member(%L, %L, true, %L)::text', :'se_membership_b', 'manager', '{}'));
select pg_temp.result('a') as seq \gset se_
select pg_temp.exec('a', 'rollback');
select alike(:'se_seq'::text, '%at least one active owner%', 'sequentially, the last active owner cannot step down');

-- Concurrent: A deactivates their own membership while B demotes themselves to manager.
select pg_temp.exec('a', 'begin');
select pg_temp.run('a', format('select tests.authenticate_as(%L)::text', :'se_owner_a'));
select pg_temp.run('a', format('select public.update_member(%L, %L, false, %L)::text', :'se_membership_a', 'owner', '{}'));
select pg_temp.exec('b', 'begin');
select pg_temp.run('b', format('select tests.authenticate_as(%L)::text', :'se_owner_b'));
select pg_temp.send('b', format('select public.update_member(%L, %L, true, %L)::text', :'se_membership_b', 'manager', '{}'));
-- B either finishes at once (no serialization) or waits for A; give it a moment either way.
select pg_temp.wait_blocked('b', 2000);
select pg_temp.exec('a', 'commit');
select pg_temp.result('b') as r_b \gset se_
select pg_temp.exec('b', 'commit');
select diag('B demoting themselves while A deactivates -> ' || coalesce(nullif(:'se_r_b', ''), 'succeeded'));

select cmp_ok((select count(*)::int from public.memberships
                where organization_id = :'se_org' and role = 'owner' and is_active), '>=', 1,
  'concurrent step-downs leave the organization with at least one active owner');

select pg_temp.disconnect_all();

-- =================================================================================================
-- F. enroll-vs-replace-card-deadlock
-- =================================================================================================
select pg_temp.connect('other', :'connstr');
select pg_temp.connect('manager', :'connstr');
select pg_temp.connect('cashier', :'connstr');

select pg_temp.exec('other', 'begin');
select pg_temp.run('other', format('select last_value::text from app.document_sequences where scope_id = %L and doc_type = %L for update', :'sf_org', 'loyalty_card'));

-- Manager replaces the lost card: locks the card, then waits for the card-number counter.
select pg_temp.exec('manager', 'begin');
select pg_temp.run('manager', format('select tests.authenticate_as(%L)::text', :'sf_manager'));
select pg_temp.send('manager', format('select public.replace_loyalty_card(%L, %L)::text', :'sf_card', 'card lost'));
select ok(pg_temp.wait_blocked_by('manager', 'other'), 'setup: the replacement holds the old card and waits for the card-number counter');

-- Cashier renews the membership: locks the customer, then needs the card (FK of the new membership).
select pg_temp.exec('cashier', 'begin');
select pg_temp.run('cashier', format('select tests.authenticate_as(%L, %L)::text', :'sf_sales', 'aal1'));
select pg_temp.send('cashier', format('select public.enroll_loyalty(%L, %L, %L, gen_random_uuid())::text', :'sf_customer', :'sf_plan3', :'sf_branch'));
-- (with the defect it now waits for the card; once fixed it may finish or wait, either is fine)
select pg_temp.wait_blocked('cashier', 3000);

select pg_temp.exec('other', 'rollback');
select pg_temp.settle('manager', 'cashier');
select pg_temp.outcome('manager') as r_replace, pg_temp.outcome('cashier') as r_renew \gset sf_
select diag('replace -> ' || left(:'sf_r_replace', 120) || ' | renew -> ' || left(:'sf_r_renew', 120));
select ok(:'sf_r_replace' not like 'ERROR 40P01%' and :'sf_r_renew' not like 'ERROR 40P01%',
  'renewing and replacing the same customer''s card concurrently does not deadlock');

select pg_temp.disconnect_all();

select * from finish();
rollback;
\else
begin;
select plan(29);
select skip('dblink is not available or cannot open a session to this database', 29);
select * from finish();
rollback;
\endif
