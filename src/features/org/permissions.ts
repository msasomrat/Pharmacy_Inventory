import type { OrgRole } from './org-context'

/**
 * Mirror of app.role_permissions (tenancy migration) for showing or hiding UI only.
 * The database enforces every permission again; never rely on this for security.
 */
const PERMISSIONS = {
  'catalog.manage': ['owner', 'manager'],
  'purchases.view': ['owner', 'manager', 'accountant', 'auditor'],
  'purchases.receive': ['owner', 'manager'],
  'suppliers.manage': ['owner', 'manager'],
  'stock.adjust': ['owner', 'manager'],
} as const satisfies Record<string, readonly OrgRole[]>

export type Permission = keyof typeof PERMISSIONS

export function roleCan(role: OrgRole, permission: Permission): boolean {
  return (PERMISSIONS[permission] as readonly OrgRole[]).includes(role)
}
