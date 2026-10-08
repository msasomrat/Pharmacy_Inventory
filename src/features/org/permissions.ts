import type { OrgRole } from './org-context'

/**
 * Role templates, mirroring app.role_permissions (tenancy migration). The app asks the server for the
 * signed-in user's effective permissions (my_permissions, which includes per-member overrides); this
 * table is only the fallback while that answer loads and the template shown in Settings.
 * The database enforces every permission again; never rely on this for security.
 */
export const ROLE_TEMPLATES = {
  'org.settings.manage': ['owner'],
  'branches.manage': ['owner'],
  'users.manage': ['owner'],
  'catalog.manage': ['owner', 'manager'],
  'pricing.manage': ['owner', 'manager'],
  'purchases.view': ['owner', 'manager', 'accountant', 'auditor'],
  'purchases.receive': ['owner', 'manager'],
  'purchases.return': ['owner', 'manager'],
  'suppliers.manage': ['owner', 'manager'],
  'suppliers.pay': ['owner', 'manager', 'accountant'],
  'stock.adjust': ['owner', 'manager'],
  'sales.create': ['owner', 'manager', 'salesman'],
  'sales.credit': ['owner', 'manager', 'salesman'],
  'sales.void': ['owner', 'manager'],
  'sales.return': ['owner', 'manager'],
  'customers.manage': ['owner', 'manager', 'salesman'],
  'customers.collect': ['owner', 'manager', 'salesman', 'accountant'],
  'loyalty.manage_plans': ['owner'],
  'loyalty.enroll': ['owner', 'manager', 'salesman'],
  'loyalty.cancel': ['owner', 'manager'],
  'reports.view': ['owner', 'manager', 'accountant', 'auditor'],
  'reports.view_cost': ['owner', 'manager', 'accountant', 'auditor'],
  'controlled.register.view': ['owner', 'manager', 'auditor'],
  'audit.view': ['owner', 'auditor'],
  'data.export': ['owner', 'accountant'],
} as const satisfies Record<string, readonly OrgRole[]>

export type Permission = keyof typeof ROLE_TEMPLATES

export const ALL_PERMISSIONS = Object.keys(ROLE_TEMPLATES) as Permission[]

/** Reserved for owners: cannot be granted to anyone else (app.permissions.grantable = false). */
export const OWNER_ONLY: readonly Permission[] = [
  'users.manage',
  'branches.manage',
  'org.settings.manage',
]

export function roleCan(role: OrgRole, permission: Permission): boolean {
  return (ROLE_TEMPLATES[permission] as readonly OrgRole[]).includes(role)
}

export function roleTemplate(role: OrgRole): Set<Permission> {
  return new Set(ALL_PERMISSIONS.filter((p) => roleCan(role, p)))
}

/** Sections of the access editor in Settings, in display order. */
export const PERMISSION_GROUPS: { key: string; permissions: Permission[] }[] = [
  { key: 'sales', permissions: ['sales.create', 'sales.credit', 'sales.void', 'sales.return'] },
  { key: 'stock', permissions: ['catalog.manage', 'pricing.manage', 'stock.adjust'] },
  {
    key: 'purchases',
    permissions: [
      'purchases.view',
      'purchases.receive',
      'purchases.return',
      'suppliers.manage',
      'suppliers.pay',
    ],
  },
  { key: 'customers', permissions: ['customers.manage', 'customers.collect'] },
  { key: 'loyalty', permissions: ['loyalty.enroll', 'loyalty.cancel', 'loyalty.manage_plans'] },
  {
    key: 'reports',
    permissions: [
      'reports.view',
      'reports.view_cost',
      'data.export',
      'controlled.register.view',
      'audit.view',
    ],
  },
]

/** Mirrors set_member_permissions: viewing purchases shows supplier prices, so it needs cost visibility. */
export function withDependencies(
  effective: Set<Permission>,
  changed: Permission,
  on: boolean,
): Set<Permission> {
  const next = new Set(effective)
  if (on) next.add(changed)
  else next.delete(changed)
  if (changed === 'purchases.view' && on) next.add('reports.view_cost')
  if (changed === 'reports.view_cost' && !on) next.delete('purchases.view')
  return next
}

/** Overrides to send: every grantable permission whose effective value differs from the role template. */
export function overridesFor(role: OrgRole, effective: Set<Permission>): Record<string, boolean> {
  const template = roleTemplate(role)
  const out: Record<string, boolean> = {}
  for (const p of ALL_PERMISSIONS) {
    if (OWNER_ONLY.includes(p)) continue
    if (template.has(p) !== effective.has(p)) out[p] = effective.has(p)
  }
  return out
}
