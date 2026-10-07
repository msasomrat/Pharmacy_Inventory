/* eslint-disable react-refresh/only-export-components -- route table module, not a hot-reloaded component */
import { lazy, Suspense, type ReactNode } from 'react'
import { createBrowserRouter } from 'react-router'

import { AppShell } from '@/components/layout/AppShell'
import { ComingSoon } from '@/components/layout/ComingSoon'
import { Skeleton } from '@/components/ui/skeleton'

import { AuthGate } from './AuthGate'
import { RouteError } from './RouteError'
import { pageModules } from './routes'

const DashboardPage = lazy(() => pageModules['/']().then((m) => ({ default: m.DashboardPage })))
const PosPage = lazy(() => pageModules['/pos']().then((m) => ({ default: m.PosPage })))
const MedicinesPage = lazy(() =>
  pageModules['/medicines']().then((m) => ({ default: m.MedicinesPage })),
)
const PurchasesPage = lazy(() =>
  pageModules['/purchases']().then((m) => ({ default: m.PurchasesPage })),
)
const CustomersPage = lazy(() =>
  pageModules['/customers']().then((m) => ({ default: m.CustomersPage })),
)
const LoyaltyPage = lazy(() => pageModules['/loyalty']().then((m) => ({ default: m.LoyaltyPage })))
const ReportsPage = lazy(() => pageModules['/reports']().then((m) => ({ default: m.ReportsPage })))
const SettingsPage = lazy(() =>
  pageModules['/settings']().then((m) => ({ default: m.SettingsPage })),
)
const InventoryPage = lazy(() =>
  pageModules['/inventory']().then((m) => ({ default: m.InventoryPage })),
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
          { path: 'customers', element: page(<CustomersPage />) },
          { path: 'loyalty', element: page(<LoyaltyPage />) },
          { path: 'reports', element: page(<ReportsPage />) },
          { path: 'settings', element: page(<SettingsPage />) },
          { path: '*', element: <ComingSoon titleKey="nav.dashboard" /> },
        ],
      },
    ],
  },
])
