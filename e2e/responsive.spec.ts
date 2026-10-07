import { expect, test } from '@playwright/test'

import { mockBackend } from './support/mock-api'

// Every screen must fit a small phone without sideways page scrolling (wide tables scroll inside
// their card or collapse into cards). Runs once, at the narrowest common width.
test.use({ viewport: { width: 360, height: 780 } })

const PAGES = [
  '/',
  '/pos',
  '/inventory',
  '/medicines',
  '/purchases',
  '/customers',
  '/loyalty',
] as const

for (const path of PAGES) {
  test(`${path} fits a 360px phone`, async ({ page }, info) => {
    test.skip(info.project.name !== 'chromium', 'viewport is fixed here; one browser is enough')
    await mockBackend(page)
    await page.goto(path)
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
    if (path === '/purchases') {
      const picker = page.getByRole('combobox', { name: /Add medicine/ })
      await picker.fill('napa')
      await picker.press('Enter')
      await expect(page.getByLabel('Batch Napa', { exact: true })).toBeVisible()
    }
    await page.waitForLoadState('networkidle')
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    )
    expect(overflow, 'page must not scroll sideways').toBeLessThanOrEqual(0)
  })
}
