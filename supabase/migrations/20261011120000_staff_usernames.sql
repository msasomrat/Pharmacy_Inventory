-- =============================================================================
-- Migration: staff sign in with a username
-- Owner decision: staff have no email address in the app. A username is stored in Supabase Auth as an
-- internal sign-in address <username>@staff.invalid (".invalid" is reserved: such addresses can never
-- receive mail). The admin-users Edge Function creates these accounts with the service role and
-- stamps app_metadata.staff_org = the organization that created them (app_metadata is writable only
-- by the service role).
--
-- Binding: an account stamped with staff_org can only see and accept invitations of that
-- organization, so another pharmacy cannot pull a staff account into its own organization (and the
-- Edge Function resets passwords only for accounts stamped with the caller's organization).
-- =============================================================================

-- Organization that created this staff sign-in, or null for a self-registered (email) account.
create or replace function app.staff_org(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select nullif(u.raw_app_meta_data ->> 'staff_org', '')::uuid
    from auth.users u
   where u.id = p_user_id
$$;

-- Pending invitations addressed to the signed-in user's email.
create or replace function public.my_invitations()
returns table (
  invitation_id uuid,
  organization_id uuid,
  organization_name text,
  role public.org_role,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, i.organization_id, o.name, i.role, i.expires_at
    from public.invitations i
    join public.organizations o on o.id = i.organization_id
   where i.email = (select lower(u.email) from auth.users u where u.id = auth.uid())
     and coalesce(app.staff_org(auth.uid()) = i.organization_id, true)
     and i.accepted_at is null
     and i.revoked_at is null
     and i.expires_at > now()
     and o.is_active
   order by i.created_at
$$;

-- The invitee accepts an invitation addressed to their own email; only now is the membership created.
create or replace function public.accept_invitation(p_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_invitation public.invitations;
  v_membership uuid;
  v_branch uuid;
begin
  if v_user is null then
    perform app.fail('not_authenticated', 'You must be signed in');
  end if;
  select i.* into v_invitation
    from public.invitations i
   where i.id = p_invitation_id
     and i.email = (select lower(u.email) from auth.users u where u.id = v_user)
     for update;
  if v_invitation.id is null
     or not coalesce(app.staff_org(v_user) = v_invitation.organization_id, true)
     or v_invitation.accepted_at is not null
     or v_invitation.revoked_at is not null
     or v_invitation.expires_at <= now()
     or not exists (
       select 1 from public.organizations o where o.id = v_invitation.organization_id and o.is_active
     ) then
    perform app.fail('invalid_invitation', 'This invitation is not valid or has expired');
  end if;

  insert into public.memberships (organization_id, user_id, role, created_by, updated_by)
  values (v_invitation.organization_id, v_user, v_invitation.role, v_invitation.invited_by, v_user)
  on conflict (organization_id, user_id) do nothing
  returning id into v_membership;
  if v_membership is null then
    perform app.fail('already_member', 'You are already a member of this organization');
  end if;

  foreach v_branch in array app.validated_branch_ids(v_invitation.organization_id, v_invitation.branch_ids) loop
    insert into public.branch_assignments (organization_id, branch_id, user_id, created_by)
    values (v_invitation.organization_id, v_branch, v_user, v_invitation.invited_by);
  end loop;

  update public.invitations set accepted_at = now(), accepted_by = v_user where id = v_invitation.id;
  return v_membership;
end;
$$;

call app.harden_privileges();
