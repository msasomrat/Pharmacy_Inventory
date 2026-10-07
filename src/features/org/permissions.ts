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
  'customers.manage': ['owner', 'manager', 'salesman'],
  // set_customer_credit_limit additionally requires the owner or manager role.
  'customers.credit_limit': ['owner', 'manager'],
  'loyalty.enroll': ['owner', 'manager', 'salesman'],
  'loyalty.cancel': ['owner', 'manager'],
  'loyalty.manage_plans': ['owner'],
  'org.settings.manage': ['owner'],
} as const satisfies Record<string, readonly OrgRole[]>

export type Permission = keyof typeof PERMISSIONS

export function roleCan(role: OrgRole, permission: Permission): boolean {
  return (PERMISSIONS[permission] as readonly OrgRole[]).includes(role)
}
