-- =============================================================================
-- Migration: two-factor authentication for owners only
-- Owner decision: staff (managers, accountants, auditors and salespeople, whatever permissions the
-- owner granted them) sign in with email and password only. Owners still need a TOTP-verified (aal2)
-- session for every sign-in, and everything that governs staff (creating sign-ins, roles,
-- per-member permissions, branches, organization settings) is owner-only, so a stolen staff
-- password can never grant itself more access.
-- =============================================================================

comment on column public.organization_settings.enforce_mfa is
  'When true, owners read and write nothing until their session is aal2 (TOTP-verified) (FR-IAM-005). Other roles sign in with a password only.';

create or replace function app.mfa_satisfied(p_organization_id uuid, p_role public.org_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_role <> 'owner'
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
      or not coalesce((
           select s.enforce_mfa from public.organization_settings s
            where s.organization_id = p_organization_id
         ), true)
$$;

call app.harden_privileges();
