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

test('medicines', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/medicines')
  await page.getByRole('row', { name: /Napa/ }).waitFor()
  await page.getByRole('button', { name: 'Edit Napa' }).click()
  await page.getByRole('dialog').getByLabel('Brand name').waitFor()
  await shot(page, 'medicines')
})

test('purchases', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/purchases')
  await page.getByLabel('Supplier', { exact: true }).selectOption({ label: 'Beximco Distribution' })
  await page.getByLabel('Supplier invoice no.').fill('BX-5600')
  const picker = page.getByRole('combobox', { name: /Add medicine/ })
  for (const [name, batch, qty, cost] of [
    ['napa', 'NP2510', '1000', '0.95'],
    ['seclo', 'SC7731', '300', '5.40'],
  ] as const) {
    await picker.fill(name)
    await picker.press('Enter')
    const label = name === 'napa' ? 'Napa' : 'Seclo'
    await page.getByLabel(`Batch ${label}`, { exact: true }).fill(batch)
    await page.getByLabel(`Expiry ${label}`, { exact: true }).fill('2028-03')
    await page.getByLabel(`Qty ${label}`, { exact: true }).fill(qty)
    await page.getByLabel(`Cost ${label}`, { exact: true }).fill(cost)
  }
  await page.getByLabel('MRP Seclo', { exact: true }).fill('7')
  await page.getByLabel('Paid now').fill('2000')
  await shot(page, 'purchases')
})

test('inventory', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/inventory')
  await page.getByText('Stock on hand').waitFor()
  await shot(page, 'inventory')
})

test('customers', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/customers')
  await page.getByRole('row', { name: /Karim Uddin/ }).waitFor()
  await shot(page, 'customers')
})

test('loyalty enroll card', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/customers')
  await page.getByRole('button', { name: 'Give Salma Begum a loyalty card' }).click()
  await page
    .getByRole('dialog')
    .getByRole('button', { name: /Enroll · collect/ })
    .click()
  await page.getByTestId('card-no').waitFor()
  await shot(page, 'loyalty-card')
})

test('loyalty plans', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/loyalty')
  await page.getByRole('tab', { name: 'Plans' }).click()
  await page.getByRole('region', { name: '3-Month Card' }).waitFor()
  await shot(page, 'loyalty-plans')
})

test('settings staff', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/settings')
  await page.getByRole('row', { name: /Sumi Akter/ }).waitFor()
  await shot(page, 'settings-staff')
})

test('settings access', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/settings')
  await page.getByRole('button', { name: 'Manage Sumi Akter' }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Void a sale').check()
  await dialog.getByLabel('Add and edit customers').uncheck()
  await shot(page, 'settings-access')
})

test('reports', async ({ page }) => {
  await mockBackend(page)
  await page.goto('/reports')
  await page.getByRole('region', { name: 'Totals' }).waitFor()
  await page.getByRole('button', { name: 'Last 7 days' }).click()
  await shot(page, 'reports')
})
