import { expect, test } from '@playwright/test'

import { mockBackend } from './support/mock-api'

test.describe('signed out', () => {
  test('shows the sign-in page and switches to Bangla', async ({ page }) => {
    await mockBackend(page, { signedIn: false })
    await page.goto('/')
    await expect(page.getByRole('heading', { name: 'Welcome back' })).toBeVisible()
    await page.getByRole('button', { name: 'Language' }).click()
    await expect(page.getByRole('heading', { name: 'আবার স্বাগতম' })).toBeVisible()
    await expect(page.locator('html')).toHaveAttribute('lang', 'bn')
  })
})

test.describe('owner (aal2)', () => {
  test.beforeEach(async ({ page }) => {
    await mockBackend(page)
  })

  test('dashboard shows KPIs, trend chart and alerts', async ({ page }) => {
    await page.goto('/')
    await expect(
      page.getByRole('heading', { name: /Good (morning|afternoon|evening), Rahima/ }),
    ).toBeVisible()
    await expect(page.getByText("Today's sales")).toBeVisible()
    await expect(page.getByRole('region', { name: 'KPIs' }).getByText('৳3,184.50')).toBeVisible()
    await expect(page.getByText('Maxpro 20')).toBeVisible()
    await expect(page.getByText('Monas 10')).toBeVisible()
  })

  test('POS: search, add with keyboard, loyalty, exact quote, complete sale', async ({ page }) => {
    await page.goto('/pos')
    const search = page.getByRole('combobox', { name: /Search medicine/ })
    await search.fill('napa')
    await expect(page.getByRole('option', { name: /Napa Extra/ })).toBeVisible()
    await search.press('Enter')
    await expect(page.getByRole('textbox', { name: 'Qty Napa' })).toHaveValue('1')
    await page.getByRole('textbox', { name: 'Qty Napa' }).fill('10')

    await page.getByPlaceholder('Card number or mobile').fill('01811223344')
    await page.getByRole('button', { name: 'Apply' }).click()
    await expect(page.getByText('Karim Uddin')).toBeVisible()
    // 10 x 1.20 = 12.00, 5% loyalty = 0.60 -> 11.40 (server quote)
    await expect(page.getByRole('button', { name: /Complete sale · ৳11\.40/ })).toBeVisible()

    await page.getByLabel('Amount received').fill('20')
    await expect(page.getByText('৳8.60')).toBeVisible()
    await page.keyboard.press('F9')
    await expect(page.getByRole('heading', { name: 'Sale completed' })).toBeVisible()
    await expect(page.getByRole('dialog').getByText('MPR-2627-000128').first()).toBeVisible()
  })

  test('POS: barcode-scanner style typing + instant Enter adds the item', async ({ page }) => {
    await page.goto('/pos')
    const search = page.getByRole('combobox', { name: /Search medicine/ })
    await search.pressSequentially('seclo', { delay: 0 })
    await search.press('Enter')
    await expect(page.getByRole('textbox', { name: 'Qty Seclo' })).toHaveValue('1')
  })

  test('POS asks for a prescription for controlled medicines', async ({ page }) => {
    await page.goto('/pos')
    await page.getByRole('combobox', { name: /Search medicine/ }).fill('sedil')
    await page.getByRole('option', { name: /Sedil/ }).click()
    await expect(page.getByText('Prescription required')).toBeVisible()
    await expect(page.getByRole('button', { name: /Complete sale/ })).toBeDisabled()
  })
})
