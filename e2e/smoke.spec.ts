import { expect, test } from '@playwright/test'

test('home page loads and is switchable to Bangla', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Pharmacy Inventory' })).toBeVisible()
  await page.getByRole('combobox', { name: 'Language' }).selectOption('bn')
  await expect(page.getByRole('heading', { name: 'ফার্মেসি ইনভেন্টরি' })).toBeVisible()
})
