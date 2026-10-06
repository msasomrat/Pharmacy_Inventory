-- Installs shared pgTAP helpers used by every other test file. This file COMMITS on purpose
-- (files run alphabetically), so the helpers exist for the rest of the run. Test-only schema:
-- never created by migrations, never present in production.
begin;
create extension if not exists pgtap with schema extensions;
create schema if not exists tests;

create or replace function tests.create_user(p_email text, p_full_name text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_id, p_email, jsonb_build_object('full_name', coalesce(p_full_name, p_email)));
  return v_id;
end;
$$;

-- Switches the current transaction to the `authenticated` role with the given user's JWT claims.
-- aal2 = signed in with two-factor authentication.
create or replace function tests.authenticate_as(p_user_id uuid, p_aal text default 'aal2')
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated', 'aal', p_aal)::text, true);
  set local role authenticated;
end;
$$;

create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end;
$$;

create or replace function tests.clear_authentication()
returns void
language plpgsql
as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
end;
$$;

grant usage on schema tests to anon, authenticated, service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

select plan(1);
select pass('test helpers installed');
select * from finish();
commit;
