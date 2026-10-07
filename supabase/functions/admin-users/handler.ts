/**
 * admin-users: creates the sign-in account for a person the owner has already invited.
 *
 * Security model (least privilege):
 * - The caller's own JWT is used to look up a pending invitation for the email. Invitations are only
 *   visible to members holding users.manage (RLS, owner + MFA by default), so the database decides who
 *   may create accounts. No invitation -> no account.
 * - Only then is the service-role Admin API used, and only to create that one confirmed user. The
 *   person still joins the pharmacy by accepting the invitation with their own session.
 * - The temporary password must meet the project's password policy.
 *
 * Pure request handling lives here so it can be unit-tested without Deno; index.ts wires real clients.
 */

export interface Invitation {
  role: string
}

export interface Deps {
  /** Pending, unexpired invitation for the email in the organization, as seen by the caller (RLS). */
  findInvitation: (
    callerJwt: string,
    organizationId: string,
    email: string,
  ) => Promise<Invitation | null>
  /** Creates a confirmed user; 'exists' when the email already has an account. */
  createUser: (email: string, password: string, fullName: string) => Promise<'created' | 'exists'>
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
  const organizationId = typeof input.organization_id === 'string' ? input.organization_id : ''
  const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : ''
  const password = typeof input.password === 'string' ? input.password : ''
  const fullName = typeof input.full_name === 'string' ? input.full_name.trim().slice(0, 120) : ''

  if (!UUID.test(organizationId)) return reply(400, { code: 'invalid_request' })
  if (!EMAIL.test(email) || email.length > 320) return reply(400, { code: 'invalid_email' })
  const weak = passwordProblem(password)
  if (weak) return reply(400, { code: weak })

  try {
    const invitation = await deps.findInvitation(jwt, organizationId, email)
    if (!invitation) return reply(403, { code: 'no_invitation' })
    const result = await deps.createUser(email, password, fullName)
    return reply(result === 'created' ? 201 : 200, { status: result })
  } catch (e) {
    console.error('admin-users failed', e instanceof Error ? e.message : e)
    return reply(500, { code: 'unknown' })
  }
}
