/**
 * admin-users: sign-in accounts for staff, managed by the owner.
 *
 * Actions:
 * - create (default): creates the sign-in for a person the owner has already invited. Staff sign in
 *   with a username, stored in Auth as the internal address <username>@staff.invalid.
 * - reset_password: sets a new temporary password for a staff sign-in of the caller's pharmacy. Staff
 *   have no email address, so the owner resets forgotten passwords.
 *
 * Security model (least privilege):
 * - The caller's own JWT asks the database first: a pending invitation for the address (create) or
 *   the member in list_members (reset). Both are visible only with users.manage (owner, two-factor),
 *   so the database decides who may act. Nothing visible -> nothing done.
 * - Only then is the service-role Admin API used, for that one account. New accounts are stamped with
 *   app_metadata.staff_org = the organization: the database lets such an account join only that
 *   organization, and a password is reset only for an account stamped with the caller's organization,
 *   never for an owner.
 * - The person still joins the pharmacy by accepting the invitation with their own session.
 * - Passwords must meet the project's password policy.
 *
 * Pure request handling lives here so it can be unit-tested without Deno; index.ts wires real clients.
 */

export interface Invitation {
  role: string
}

export interface Member {
  role: string
}

export interface Deps {
  /** Pending, unexpired invitation for the email in the organization, as seen by the caller (RLS). */
  findInvitation: (
    callerJwt: string,
    organizationId: string,
    email: string,
  ) => Promise<Invitation | null>
  /** Creates a confirmed user stamped with the organization; 'exists' when the address is taken. */
  createUser: (
    email: string,
    password: string,
    fullName: string,
    organizationId: string,
  ) => Promise<'created' | 'exists'>
  /** The member as listed to the caller by list_members (users.manage), or null. */
  findMember: (callerJwt: string, organizationId: string, userId: string) => Promise<Member | null>
  /** app_metadata.staff_org of the account, or null. */
  staffOrgOf: (userId: string) => Promise<string | null>
  setPassword: (userId: string, password: string) => Promise<void>
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

/** Mirrors the Auth password policy: at least 10 characters with lower, upper case letters and digits. */
export function passwordProblem(password: string): string | null {
  if (password.length < 10 || password.length > 72) return 'password_length'
  if (!/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/\d/.test(password))
    return 'password_weak'
  return null
}

function corsHeaders(origin: string | null, allowedOrigins: string[]): Record<string, string> {
  const allow =
    allowedOrigins.includes('*') || (origin !== null && allowedOrigins.includes(origin))
      ? (origin ?? '*')
      : (allowedOrigins[0] ?? '')
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  }
}

export async function handle(
  req: Request,
  deps: Deps,
  allowedOrigins: string[],
): Promise<Response> {
  const cors = corsHeaders(req.headers.get('origin'), allowedOrigins)
  const reply = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return reply(405, { code: 'method_not_allowed' })

  const auth = req.headers.get('authorization') ?? ''
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7).trim() : ''
  if (!jwt) return reply(401, { code: 'not_authenticated' })

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return reply(400, { code: 'invalid_request' })
  }
  const input = (typeof body === 'object' && body !== null ? body : {}) as Record<string, unknown>
  const action = input.action ?? 'create'
  const organizationId = typeof input.organization_id === 'string' ? input.organization_id : ''
  const password = typeof input.password === 'string' ? input.password : ''

  if (!UUID.test(organizationId)) return reply(400, { code: 'invalid_request' })

  if (action === 'reset_password') {
    const userId = typeof input.user_id === 'string' ? input.user_id : ''
    if (!UUID.test(userId)) return reply(400, { code: 'invalid_request' })
    const weak = passwordProblem(password)
    if (weak) return reply(400, { code: weak })
    try {
      const member = await deps.findMember(jwt, organizationId, userId)
      if (!member) return reply(403, { code: 'not_allowed' })
      if (member.role === 'owner') return reply(403, { code: 'owner_password' })
      if ((await deps.staffOrgOf(userId)) !== organizationId)
        return reply(403, { code: 'not_staff_login' })
      await deps.setPassword(userId, password)
      return reply(200, { status: 'reset' })
    } catch (e) {
      console.error('admin-users reset failed', e instanceof Error ? e.message : e)
      return reply(500, { code: 'unknown' })
    }
  }
  if (action !== 'create') return reply(400, { code: 'invalid_request' })

  const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : ''
  const fullName = typeof input.full_name === 'string' ? input.full_name.trim().slice(0, 120) : ''
  if (!EMAIL.test(email) || email.length > 320) return reply(400, { code: 'invalid_email' })
  const weak = passwordProblem(password)
  if (weak) return reply(400, { code: weak })

  try {
    const invitation = await deps.findInvitation(jwt, organizationId, email)
    if (!invitation) return reply(403, { code: 'no_invitation' })
    const result = await deps.createUser(email, password, fullName, organizationId)
    return reply(result === 'created' ? 201 : 200, { status: result })
  } catch (e) {
    console.error('admin-users failed', e instanceof Error ? e.message : e)
    return reply(500, { code: 'unknown' })
  }
}
