import { useQuery } from '@tanstack/react-query'
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'

import type { Database } from '@/lib/database.types'
import { toAppError } from '@/lib/errors'
import { prefs } from '@/lib/storage'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/features/auth/auth-context'

import { roleCan, type Permission } from './permissions'

export type OrgRole = Database['public']['Enums']['org_role']

export interface Branch {
  id: string
  code: string
  name: string
}

export interface Membership {
  organizationId: string
  organizationName: string
  role: OrgRole
  branches: Branch[]
}

interface OrgContextValue {
  loading: boolean
  memberships: Membership[]
  current: Membership | null
  branch: Branch | null
  selectOrganization: (organizationId: string) => void
  selectBranch: (branchId: string) => void
  refetch: () => Promise<unknown>
  /** Effective permission of the signed-in user in the current organization (role + overrides). */
  can: (permission: Permission) => boolean
}

const OrgContext = createContext<OrgContextValue | null>(null)
const ALL_BRANCH_ROLES: OrgRole[] = ['owner', 'accountant', 'auditor']

async function fetchMemberships(userId: string): Promise<Membership[]> {
  const [members, branches, assignments] = await Promise.all([
    supabase
      .from('memberships')
      .select('organization_id, role, organizations(name)')
      .eq('user_id', userId)
      .eq('is_active', true),
    supabase
      .from('branches')
      .select('id, organization_id, code, name')
      .eq('is_active', true)
      .order('name'),
    supabase.from('branch_assignments').select('branch_id').eq('user_id', userId),
  ])
  for (const res of [members, branches, assignments]) {
    if (res.error) throw toAppError(res.error)
  }
  const assigned = new Set((assignments.data ?? []).map((a) => a.branch_id))
  return (members.data ?? []).map((m) => ({
    organizationId: m.organization_id,
    organizationName: m.organizations.name,
    role: m.role,
    branches: (branches.data ?? [])
      .filter((b) => b.organization_id === m.organization_id)
      .filter((b) => ALL_BRANCH_ROLES.includes(m.role) || assigned.has(b.id))
      .map(({ id, code, name }) => ({ id, code, name })),
  }))
}

export function OrgProvider({ children }: { children: ReactNode }) {
  const { session, aal } = useAuth()
  const userId = session?.user.id
  const [orgId, setOrgId] = useState<string | null>(() => prefs.get('org'))
  const [branchId, setBranchId] = useState<string | null>(() => prefs.get('branch'))

  const query = useQuery({
    queryKey: ['memberships', userId, aal.current],
    queryFn: () => fetchMemberships(userId ?? ''),
    enabled: Boolean(userId),
  })

  const memberships = useMemo(() => query.data ?? [], [query.data])
  const current = memberships.find((m) => m.organizationId === orgId) ?? memberships[0] ?? null

  // Server truth (includes per-member overrides); the role template covers the first render.
  const permissions = useQuery({
    queryKey: ['my-permissions', current?.organizationId, aal.current],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('my_permissions', {
        p_organization_id: current?.organizationId ?? '',
      })
      if (error) throw toAppError(error)
      return new Set(data)
    },
    enabled: Boolean(current),
    staleTime: 60_000,
  })
  const role = current?.role
  const granted = permissions.data
  const can = useCallback(
    (permission: Permission) =>
      granted ? granted.has(permission) : role ? roleCan(role, permission) : false,
    [granted, role],
  )
  const branch = current?.branches.find((b) => b.id === branchId) ?? current?.branches[0] ?? null

  const selectOrganization = useCallback((id: string) => {
    setOrgId(id)
    prefs.set('org', id)
    setBranchId(null)
    prefs.set('branch', null)
  }, [])
  const selectBranch = useCallback((id: string) => {
    setBranchId(id)
    prefs.set('branch', id)
  }, [])

  const value = useMemo(
    () => ({
      loading: query.isPending && Boolean(userId),
      memberships,
      current,
      branch,
      selectOrganization,
      selectBranch,
      refetch: query.refetch,
      can,
    }),
    [
      query.isPending,
      query.refetch,
      userId,
      memberships,
      current,
      branch,
      selectOrganization,
      selectBranch,
      can,
    ],
  )
  return <OrgContext.Provider value={value}>{children}</OrgContext.Provider>
}

export function useOrg(): OrgContextValue {
  const ctx = useContext(OrgContext)
  if (!ctx) throw new Error('useOrg must be used inside OrgProvider')
  return ctx
}

/** Requires a selected organization and branch (inside the app shell). */
export function useWorkspace(): {
  org: Membership
  branch: Branch
  can: (permission: Permission) => boolean
} {
  const { current, branch, can } = useOrg()
  if (!current || !branch) throw new Error('No organization/branch selected')
  return { org: current, branch, can }
}
