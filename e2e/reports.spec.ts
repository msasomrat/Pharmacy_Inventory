import { readFileSync } from 'node:fs'

import { expect, test } from '@playwright/test'

import { mockBackend } from './support/mock-api'

test.describe('owner (aal2): reports', () => {
  test('sales report: totals, period presets and CSV export', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/reports')
    const totals = page.getByRole('region', { name: 'Totals' })
    await expect(totals.getByText('Net sales')).toBeVisible()
    await expect(totals.getByText('Gross profit')).toBeVisible()

    await page.getByRole('button', { name: 'This month' }).click()
    await expect
      .poll(() =>
        calls.some((c) => c.fn === 'report_sales_summary' && String(c.body.p_from).endsWith('-01')),
      )
      .toBe(true)

    const download = page.waitForEvent('download')
    await page.getByRole('button', { name: 'Export CSV' }).click()
    const file = await download
    expect(file.suggestedFilename()).toMatch(/^sales_\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}\.csv$/)
    const path = await file.path()
    const csv = readFileSync(path, 'utf8')
    expect(csv.split('\r\n')[0]).toBe(
      '﻿date,branch,bills,gross,discount,loyalty_discount,returns,net_sales,credit_sales,cost,gross_profit',
    )
  })

  test('stock value by branch', async ({ page }) => {
    await mockBackend(page)
    await page.goto('/reports')
    await page.getByRole('tab', { name: 'Stock value' }).click()
    const row = page.getByRole('row', { name: /Mohammadpur/ })
    await expect(row.getByText('৳15,23,400.00')).toBeVisible()
  })

  test('without the export permission there is no CSV button', async ({ page }) => {
    await mockBackend(page, {
      role: 'manager',
      permissions: ['reports.view', 'reports.view_cost', 'sales.create'],
    })
    await page.goto('/reports')
    await expect(page.getByRole('region', { name: 'Totals' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Export CSV' })).toHaveCount(0)
  })
})
