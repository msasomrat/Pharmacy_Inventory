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

import type { Permission } from '@/features/org/permissions'

export interface NavItem {
  to: string
  key: string
  icon: LucideIcon
  /** Shown when the user holds any of these permissions; omitted = every member. */
  anyOf?: Permission[]
  shortcut?: string
}

export interface NavSection {
  key: string
  items: NavItem[]
}

/** Navigation visible per permission. The UI only hides links; the database enforces every permission. */
export const NAV: NavSection[] = [
  {
    key: 'sell',
    items: [
      { to: '/', key: 'dashboard', icon: LayoutDashboard, shortcut: 'G D' },
      { to: '/pos', key: 'pos', icon: ShoppingCart, anyOf: ['sales.create'], shortcut: 'F2' },
    ],
  },
  {
    key: 'stock',
    items: [
      { to: '/inventory', key: 'inventory', icon: Boxes },
      { to: '/medicines', key: 'medicines', icon: Pill },
      { to: '/purchases', key: 'purchases', icon: Truck, anyOf: ['purchases.view'] },
    ],
  },
  {
    key: 'people',
    items: [
      { to: '/customers', key: 'customers', icon: Contact },
      { to: '/loyalty', key: 'loyalty', icon: CreditCard },
    ],
  },
  {
    key: 'insights',
    items: [
      { to: '/reports', key: 'reports', icon: BarChart3, anyOf: ['reports.view'] },
      {
        to: '/settings',
        key: 'settings',
        icon: Settings,
        anyOf: ['users.manage', 'branches.manage', 'org.settings.manage'],
      },
    ],
  },
]

export function navFor(can: (permission: Permission) => boolean): NavSection[] {
  return NAV.map((s) => ({
    ...s,
    items: s.items.filter((i) => !i.anyOf || i.anyOf.some((p) => can(p))),
  })).filter((s) => s.items.length > 0)
}
