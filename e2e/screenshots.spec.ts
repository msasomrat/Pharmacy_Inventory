import { test, type Page } from '@playwright/test'

import { mockBackend } from './support/mock-api'

// Design review screenshots (docs/screenshots). Run with: SCREENSHOTS=1 pnpm test:e2e --project=chromium screenshots
test.skip(!process.env.SCREENSHOTS, 'screenshots are generated on demand')
test.use({ viewport: { width: 1440, height: 900 } })

async function shot(page: Page, name: string) {
  await page.waitForTimeout(400)
  await page.screenshot({ path: `docs/screenshots/${name}.png` })
}

async function setPrefs(page: Page, prefs: Record<string, string>) {
  await page.addInitScript((p) => {
    for (const [k, v] of Object.entries(p)) window.localStorage.setItem(`pims:${k}`, v)
  }, prefs)
}

test('login', async ({ page }) => {
  await mockBackend(page, { signedIn: false })
  await page.goto('/')
  await shot(page, 'login')
})

test('dashboard light', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/')
  await page.getByText('Maxpro 20').waitFor()
  await shot(page, 'dashboard-light')
})

test('dashboard dark bangla', async ({ page }) => {
  await setPrefs(page, { theme: 'dark', lang: 'bn' })
  await mockBackend(page)
  await page.goto('/')
  await page.getByText('Maxpro 20').waitFor()
  await shot(page, 'dashboard-dark-bn')
})

test('pos', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/pos')
  const search = page.getByRole('combobox', { name: /Search medicine/ })
  await search.fill('seclo')
  await search.press('Enter')
  await search.fill('napa')
  await search.press('Enter')
  await page.getByRole('textbox', { name: 'Qty Napa' }).fill('10')
  await page.getByPlaceholder('Card number or mobile').fill('01811223344')
  await page.getByRole('button', { name: 'Apply' }).click()
  await page.getByLabel('Amount received').fill('50')
  await search.fill('pa')
  await page.getByRole('option', { name: /Napa Extra/ }).waitFor()
  await shot(page, 'pos')
})

test('mobile dashboard', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await mockBackend(page)
  await page.goto('/')
  await page.getByText('Maxpro 20').waitFor()
  await page.screenshot({ path: 'docs/screenshots/mobile-dashboard.png', fullPage: true })
})
