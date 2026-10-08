-- Staff username sign-ins are bound to the pharmacy that created them (app_metadata.staff_org).
begin;
select plan(9);

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

select tests.create_user('owner-a@names.test', 'Owner A') as owner_a \gset
select tests.create_user('owner-b@names.test', 'Owner B') as owner_b \gset
select tests.create_user('freelance@names.test', 'Email Person') as email_user \gset

select tests.authenticate_as(:'owner_a');
select public.create_organization('Alpha Pharmacy', 'Main', 'ALP') as org_a \gset
select tests.authenticate_as(:'owner_b');
select public.create_organization('Beta Pharmacy', 'Main', 'BET') as org_b \gset

-- What the admin-users Edge Function does for Alpha: an account stamped with staff_org.
select tests.clear_authentication();
select tests.create_user('rafiq@staff.invalid', 'Rafiq') as rafiq \gset
update auth.users set raw_app_meta_data = jsonb_build_object('staff_org', :'org_a') where id = :'rafiq';

select tests.authenticate_as(:'owner_a');
select public.add_member(:'org_a', 'Rafiq@Staff.Invalid', 'salesman') as inv_a \gset
select tests.authenticate_as(:'owner_b');
select public.add_member(:'org_b', 'rafiq@staff.invalid', 'manager') as inv_b \gset
select public.add_member(:'org_b', 'freelance@names.test', 'salesman') as inv_email_b \gset
select tests.authenticate_as(:'owner_a');
select public.add_member(:'org_a', 'freelance@names.test', 'salesman') as inv_email_a \gset

select tests.authenticate_as(:'rafiq', 'aal1');
select is((select array_agg(organization_name) from public.my_invitations()), array['Alpha Pharmacy'],
  'a staff sign-in lists only invitations of the pharmacy that created it');
select is(tests.error_code(format($$ select public.accept_invitation(%L) $$, :'inv_b')), 'invalid_invitation',
  'another pharmacy cannot pull the staff sign-in into its organization');
select ok(public.accept_invitation(:'inv_a') is not null, 'the creating pharmacy''s invitation is accepted');
select is((select count(*)::int from public.memberships where user_id = :'rafiq'), 1,
  'the staff sign-in belongs to exactly one pharmacy');
select ok('sales.create' = any (public.my_permissions(:'org_a')), 'and works there with a password session');

-- Self-registered email accounts are not bound.
select tests.authenticate_as(:'email_user', 'aal1');
select is((select count(*)::int from public.my_invitations()), 2, 'an email account sees invitations from every pharmacy');
select ok(public.accept_invitation(:'inv_email_a') is not null, 'and may accept one');
select ok(public.accept_invitation(:'inv_email_b') is not null, 'and another');

select tests.clear_authentication();
select is(app.staff_org(:'rafiq'), :'org_a'::uuid, 'app.staff_org reads the stamp');

select * from finish();
rollback;
