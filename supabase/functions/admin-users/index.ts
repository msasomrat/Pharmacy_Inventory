// Supabase Edge Function entry point (Deno). Deploy: supabase functions deploy admin-users
import { createClient } from 'npm:@supabase/supabase-js@2'

import { handle, type Deps } from './handler.ts'

const url = Deno.env.get('SUPABASE_URL') ?? ''
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
// Comma-separated list, e.g. https://pharmacy-inventory-b9f.pages.dev. Default: any origin (bearer
// tokens, no cookies, so CORS is not the security boundary).
const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') ?? '*').split(',').map((o) => o.trim())

const admin = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

function asCaller(callerJwt: string) {
  return createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${callerJwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

const deps: Deps = {
  async findInvitation(callerJwt, organizationId, email) {
    const { data, error } = await asCaller(callerJwt)
      .from('invitations')
      .select('role')
      .eq('organization_id', organizationId)
      .eq('email', email)
      .is('accepted_at', null)
      .is('revoked_at', null)
      .gt('expires_at', new Date().toISOString())
      .maybeSingle()
    if (error) throw new Error(error.message)
    return data
  },
  async createUser(email, password, fullName, organizationId) {
    const { error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: fullName ? { full_name: fullName } : {},
      // Binds the sign-in to this pharmacy (only the service role can write app_metadata).
      app_metadata: { staff_org: organizationId },
    })
    if (!error) return 'created'
    if (error.code === 'email_exists' || /already (been )?registered/i.test(error.message))
      return 'exists'
    throw new Error(error.message)
  },
  async findMember(callerJwt, organizationId, userId) {
    // list_members requires users.manage: the database decides whether the caller may see the member.
    const { data, error } = await asCaller(callerJwt).rpc('list_members', {
      p_organization_id: organizationId,
    })
    if (error) return null
    const rows = (data ?? []) as { user_id: string; role: string }[]
    const member = rows.find((m) => m.user_id === userId)
    return member ? { role: member.role } : null
  },
  async staffOrgOf(userId) {
    const { data, error } = await admin.auth.admin.getUserById(userId)
    if (error) throw new Error(error.message)
    const org = (data.user.app_metadata as Record<string, unknown> | undefined)?.staff_org
    return typeof org === 'string' ? org : null
  },
  async setPassword(userId, password) {
    const { error } = await admin.auth.admin.updateUserById(userId, { password })
    if (error) throw new Error(error.message)
  },
}

Deno.serve((req) => handle(req, deps, allowedOrigins))
