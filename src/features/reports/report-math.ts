import { addDays } from '@/lib/dates'

export type Preset = 'today' | 'yesterday' | 'last7' | 'thisMonth' | 'lastMonth' | 'custom'

/** Date range (YYYY-MM-DD, inclusive) for a preset relative to the business date. */
export function presetRange(
  preset: Exclude<Preset, 'custom'>,
  today: string,
): { from: string; to: string } {
  const monthStart = `${today.slice(0, 7)}-01`
  switch (preset) {
    case 'today':
      return { from: today, to: today }
    case 'yesterday': {
      const y = addDays(today, -1)
      return { from: y, to: y }
    }
    case 'last7':
      return { from: addDays(today, -6), to: today }
    case 'thisMonth':
      return { from: monthStart, to: today }
    case 'lastMonth': {
      const end = addDays(monthStart, -1)
      return { from: `${end.slice(0, 7)}-01`, to: end }
    }
  }
}

export interface SalesRow {
  branch_id: string
  branch_name: string
  business_date: string
  sales_count: number
  discount_paisa: number
  loyalty_discount_paisa: number
  net_sales_paisa: number
  returns_paisa: number
  gross_profit_paisa: number | null
}

interface Totals {
  bills: number
  netPaisa: number
  discountPaisa: number
  returnsPaisa: number
  /** null when the user may not see cost and profit. */
  profitPaisa: number | null
}

function add(t: Totals, r: SalesRow): Totals {
  const profit = r.gross_profit_paisa
  return {
    bills: t.bills + r.sales_count,
    netPaisa: t.netPaisa + r.net_sales_paisa,
    discountPaisa: t.discountPaisa + r.discount_paisa + r.loyalty_discount_paisa,
    returnsPaisa: t.returnsPaisa + r.returns_paisa,
    profitPaisa: t.profitPaisa === null || profit === null ? null : t.profitPaisa + profit,
  }
}

const zero = (withProfit: boolean): Totals => ({
  bills: 0,
  netPaisa: 0,
  discountPaisa: 0,
  returnsPaisa: 0,
  profitPaisa: withProfit ? 0 : null,
})

/** Totals, per-day (all selected branches combined, newest first) and per-branch figures. */
export function aggregateSales(rows: SalesRow[]) {
  const withProfit = rows.length > 0 && rows.every((r) => r.gross_profit_paisa !== null)
  const days = new Map<string, Totals>()
  const branches = new Map<string, Totals & { branchName: string }>()
  let totals = zero(withProfit)
  for (const r of rows) {
    totals = add(totals, r)
    days.set(r.business_date, add(days.get(r.business_date) ?? zero(withProfit), r))
    const b = branches.get(r.branch_id)
    branches.set(r.branch_id, { ...add(b ?? zero(withProfit), r), branchName: r.branch_name })
  }
  return {
    totals,
    byDay: [...days.entries()]
      .map(([date, t]) => ({ date, ...t }))
      .sort((a, b) => b.date.localeCompare(a.date)),
    byBranch: [...branches.entries()]
      .map(([branchId, t]) => ({ branchId, ...t }))
      .sort((a, b) => b.netPaisa - a.netPaisa),
  }
}
