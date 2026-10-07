/**
 * Lazily loaded page modules. Each page is its own chunk; prefetchRoute() warms a chunk when the user
 * points at a link (or when the browser is idle) so navigation feels instant without a big first load.
 */
export const pageModules = {
  '/': () => import('@/features/dashboard/DashboardPage'),
  '/pos': () => import('@/features/pos/PosPage'),
  '/inventory': () => import('@/features/inventory/InventoryPage'),
  '/medicines': () => import('@/features/medicines/MedicinesPage'),
  '/purchases': () => import('@/features/purchases/PurchasesPage'),
  '/customers': () => import('@/features/customers/CustomersPage'),
  '/loyalty': () => import('@/features/loyalty/LoyaltyPage'),
  '/reports': () => import('@/features/reports/ReportsPage'),
  '/settings': () => import('@/features/settings/SettingsPage'),
} as const

export type PagePath = keyof typeof pageModules

const warmed = new Set<string>()

export function prefetchRoute(path: string): void {
  if (warmed.has(path) || !(path in pageModules)) return
  warmed.add(path)
  // A failed prefetch is harmless: the route loads (and reports errors) on navigation.
  pageModules[path as PagePath]().catch(() => warmed.delete(path))
}

/** Warms the pages a pharmacy uses most once the first screen has rendered. */
export function prefetchCommonRoutes(): void {
  const run = () => {
    for (const path of ['/pos', '/inventory', '/medicines']) prefetchRoute(path)
  }
  if ('requestIdleCallback' in window) window.requestIdleCallback(run, { timeout: 4000 })
  else setTimeout(run, 2000)
}
