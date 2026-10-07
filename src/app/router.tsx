/* eslint-disable react-refresh/only-export-components -- route table module, not a hot-reloaded component */
import { lazy, Suspense, type ReactNode } from 'react'
import { createBrowserRouter } from 'react-router'

import { AppShell } from '@/components/layout/AppShell'
import { ComingSoon } from '@/components/layout/ComingSoon'
import { Skeleton } from '@/components/ui/skeleton'

import { AuthGate } from './AuthGate'
import { RouteError } from './RouteError'

const DashboardPage = lazy(() =>
  import('@/features/dashboard/DashboardPage').then((m) => ({ default: m.DashboardPage })),
)
const PosPage = lazy(() => import('@/features/pos/PosPage').then((m) => ({ default: m.PosPage })))
const MedicinesPage = lazy(() =>
  import('@/features/medicines/MedicinesPage').then((m) => ({ default: m.MedicinesPage })),
)
const PurchasesPage = lazy(() =>
  import('@/features/purchases/PurchasesPage').then((m) => ({ default: m.PurchasesPage })),
)
const InventoryPage = lazy(() =>
  import('@/features/inventory/InventoryPage').then((m) => ({ default: m.InventoryPage })),
)

function page(node: ReactNode) {
  return <Suspense fallback={<Skeleton className="h-96" />}>{node}</Suspense>
}

export const router = createBrowserRouter([
  {
    element: <AuthGate />,
    errorElement: <RouteError />,
    children: [
      {
        element: <AppShell />,
        children: [
          { index: true, element: page(<DashboardPage />) },
          { path: 'pos', element: page(<PosPage />) },
          { path: 'inventory', element: page(<InventoryPage />) },
          { path: 'medicines', element: page(<MedicinesPage />) },
          { path: 'purchases', element: page(<PurchasesPage />) },
          { path: 'customers', element: <ComingSoon titleKey="nav.customers" /> },
          { path: 'loyalty', element: <ComingSoon titleKey="nav.loyalty" /> },
          { path: 'reports', element: <ComingSoon titleKey="nav.reports" /> },
          { path: 'settings', element: <ComingSoon titleKey="nav.settings" /> },
          { path: '*', element: <ComingSoon titleKey="nav.dashboard" /> },
        ],
      },
    ],
  },
])
