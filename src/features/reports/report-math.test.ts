import { describe, expect, it } from 'vitest'

import { aggregateSales, presetRange, type SalesRow } from './report-math'

describe('presetRange', () => {
  it('computes ranges relative to the business date', () => {
    expect(presetRange('today', '2026-10-08')).toEqual({ from: '2026-10-08', to: '2026-10-08' })
    expect(presetRange('yesterday', '2026-10-01')).toEqual({ from: '2026-09-30', to: '2026-09-30' })
    expect(presetRange('last7', '2026-10-08')).toEqual({ from: '2026-10-02', to: '2026-10-08' })
    expect(presetRange('thisMonth', '2026-10-08')).toEqual({ from: '2026-10-01', to: '2026-10-08' })
    expect(presetRange('lastMonth', '2026-03-15')).toEqual({ from: '2026-02-01', to: '2026-02-28' })
    expect(presetRange('lastMonth', '2026-01-05')).toEqual({ from: '2025-12-01', to: '2025-12-31' })
  })
})

const row = (o: Partial<SalesRow>): SalesRow => ({
  branch_id: 'b1',
  branch_name: 'Mohammadpur',
  business_date: '2026-10-08',
  sales_count: 10,
  discount_paisa: 100,
  loyalty_discount_paisa: 50,
  net_sales_paisa: 10000,
  returns_paisa: 0,
  gross_profit_paisa: 2000,
  ...o,
})

describe('aggregateSales', () => {
  it('sums totals, combines branches per day and ranks branches', () => {
    const r = aggregateSales([
      row({}),
      row({
        branch_id: 'b2',
        branch_name: 'Dhanmondi',
        net_sales_paisa: 30000,
        gross_profit_paisa: 5000,
      }),
      row({
        business_date: '2026-10-07',
        net_sales_paisa: 5000,
        returns_paisa: 200,
        gross_profit_paisa: -100,
      }),
    ])
    expect(r.totals).toEqual({
      bills: 30,
      netPaisa: 45000,
      discountPaisa: 450,
      returnsPaisa: 200,
      profitPaisa: 6900,
    })
    expect(r.byDay.map((d) => [d.date, d.netPaisa])).toEqual([
      ['2026-10-08', 40000],
      ['2026-10-07', 5000],
    ])
    expect(r.byBranch.map((b) => b.branchName)).toEqual(['Dhanmondi', 'Mohammadpur'])
  })

  it('hides profit when the server withholds cost', () => {
    const r = aggregateSales([row({ gross_profit_paisa: null })])
    expect(r.totals.profitPaisa).toBeNull()
    expect(r.byDay[0]?.profitPaisa).toBeNull()
  })
})
