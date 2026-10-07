import { FunctionsHttpError } from '@supabase/supabase-js'

import type { OrgRole } from '@/features/org/org-context'
import { ALL_PERMISSIONS, type Permission } from '@/features/org/permissions'
import { rpc } from '@/lib/api'
import { toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

export const ROLES: OrgRole[] = ['manager', 'salesman', 'accountant', 'auditor', 'owner']

/** Owners, accountants and auditors see every branch; managers and salesmen only assigned ones. */
export function roleUsesBranches(role: OrgRole): boolean {
  return role === 'manager' || role === 'salesman'
}

export interface Member {
  membershipId: string
  userId: string
  email: string
  fullName: string | null
  role: OrgRole
  isActive: boolean
  branchIds: string[]
  overrides: Partial<Record<Permission, boolean>>
  lastSignInAt: string | null
}

export async function listMembers(organizationId: string): Promise<Member[]> {
  const rows = await rpc('list_members', { p_organization_id: organizationId })
  return rows.map((m) => ({
    membershipId: m.membership_id,
    userId: m.user_id,
    email: m.email,
    fullName: m.full_name,
    role: m.role,
    isActive: m.is_active,
    branchIds: m.branch_ids,
    overrides: (m.overrides ?? {}) as Partial<Record<Permission, boolean>>,
    lastSignInAt: m.last_sign_in_at,
  }))
}

export interface Invitation {
  id: string
  email: string
  role: OrgRole
  branchIds: string[]
  expiresAt: string
}

export async function listInvitations(organizationId: string): Promise<Invitation[]> {
  const { data, error } = await supabase
    .from('invitations')
    .select('id, email, role, branch_ids, expires_at')
    .eq('organization_id', organizationId)
    .is('accepted_at', null)
    .is('revoked_at', null)
    .order('created_at', { ascending: false })
  if (error) throw toAppError(error)
  return data.map((i) => ({
    id: i.id,
    email: i.email,
    role: i.role,
    branchIds: i.branch_ids,
    expiresAt: i.expires_at,
  }))
}

export function effectiveOf(
  member: Pick<Member, 'role' | 'overrides'>,
  template: Set<Permission>,
): Set<Permission> {
  if (member.role === 'owner') return new Set(ALL_PERMISSIONS)
  const out = new Set(template)
  for (const [p, allowed] of Object.entries(member.overrides) as [Permission, boolean][]) {
    if (allowed) out.add(p)
    else out.delete(p)
  }
  return out
}

/** Random temporary password that satisfies the Auth policy (10+ chars, lower, upper, digit). */
export function generatePassword(length = 12): string {
  const lower = 'abcdefghijkmnpqrstuvwxyz'
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
  const digits = '23456789'
  const all = lower + upper + digits
  const random = new Uint32Array(length)
  crypto.getRandomValues(random)
  const pick = (set: string, n: number) => set.charAt(n % set.length)
  const chars = Array.from(random, (n, i) =>
    i === 0 ? pick(upper, n) : i === 1 ? pick(lower, n) : i === 2 ? pick(digits, n) : pick(all, n),
  )
  // Shuffle so the guaranteed classes are not always first.
  const order = new Uint32Array(length)
  crypto.getRandomValues(order)
  return chars
    .map((c, i) => ({ c, k: order[i] ?? 0 }))
    .sort((a, b) => a.k - b.k)
    .map((x) => x.c)
    .join('')
}

export type LoginResult = 'created' | 'exists' | 'unavailable'

/**
 * Asks the admin-users Edge Function to create the sign-in account for an invited email.
 * 'unavailable' means the function is not deployed or unreachable; the invitation still stands.
 */
export async function createLogin(params: {
  organizationId: string
  email: string
  password: string
  fullName: string
}): Promise<LoginResult> {
  const result = await supabase.functions.invoke<{ status: 'created' | 'exists' }>('admin-users', {
    body: {
      organization_id: params.organizationId,
      email: params.email,
      password: params.password,
      full_name: params.fullName,
    },
  })
  const error: unknown = result.error
  if (!error) return result.data?.status ?? 'created'
  if (error instanceof FunctionsHttpError) {
    const response = error.context as Response
    if (response.status === 404) return 'unavailable'
    let code = 'unknown'
    try {
      code = ((await response.json()) as { code?: string }).code ?? 'unknown'
    } catch {
      // Body was not JSON; keep 'unknown'.
    }
    throw toAppError({ message: code, details: code })
  }
  return 'unavailable'
}
