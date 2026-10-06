import {
  BarChart3,
  Boxes,
  Contact,
  CreditCard,
  LayoutDashboard,
  Pill,
  Settings,
  ShoppingCart,
  Truck,
  type LucideIcon,
} from 'lucide-react'

import type { OrgRole } from '@/features/org/org-context'

export interface NavItem {
  to: string
  key: string
  icon: LucideIcon
  roles: OrgRole[]
  shortcut?: string
}

export interface NavSection {
  key: string
  items: NavItem[]
}

const ALL: OrgRole[] = ['owner', 'manager', 'salesman', 'accountant', 'auditor']
const STAFF: OrgRole[] = ['owner', 'manager', 'salesman']
const MANAGEMENT: OrgRole[] = ['owner', 'manager', 'accountant', 'auditor']

/** Navigation visible per role. The UI only hides links; the database enforces every permission. */
export const NAV: NavSection[] = [
  {
    key: 'sell',
    items: [
      { to: '/', key: 'dashboard', icon: LayoutDashboard, roles: ALL, shortcut: 'G D' },
      { to: '/pos', key: 'pos', icon: ShoppingCart, roles: STAFF, shortcut: 'F2' },
    ],
  },
  {
    key: 'stock',
    items: [
      { to: '/inventory', key: 'inventory', icon: Boxes, roles: ALL },
      { to: '/medicines', key: 'medicines', icon: Pill, roles: ALL },
      { to: '/purchases', key: 'purchases', icon: Truck, roles: MANAGEMENT },
    ],
  },
  {
    key: 'people',
    items: [
      { to: '/customers', key: 'customers', icon: Contact, roles: ALL },
      { to: '/loyalty', key: 'loyalty', icon: CreditCard, roles: ALL },
    ],
  },
  {
    key: 'insights',
    items: [
      { to: '/reports', key: 'reports', icon: BarChart3, roles: MANAGEMENT },
      { to: '/settings', key: 'settings', icon: Settings, roles: ['owner'] },
    ],
  },
]

export function navFor(role: OrgRole | undefined): NavSection[] {
  if (!role) return []
  return NAV.map((s) => ({ ...s, items: s.items.filter((i) => i.roles.includes(role)) })).filter(
    (s) => s.items.length > 0,
  )
}
