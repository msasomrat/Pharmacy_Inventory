import { expect, test } from '@playwright/test'

import { mockBackend } from './support/mock-api'

const SALESMAN_PERMISSIONS = [
  'customers.collect',
  'customers.manage',
  'loyalty.enroll',
  'sales.create',
  'sales.credit',
]

test.describe('two-factor sign-in is for owners only', () => {
  test('a salesperson with only a password session goes straight to the app', async ({ page }) => {
    await mockBackend(page, { role: 'salesman', aal: 'aal1', permissions: SALESMAN_PERMISSIONS })
    await page.goto('/pos')
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Two-factor authentication' })).toHaveCount(0)
  })

  test('a manager with only a password session goes straight to the app', async ({ page }) => {
    await mockBackend(page, { role: 'manager', aal: 'aal1' })
    await page.goto('/')
    await expect(
      page.getByRole('heading', { name: /Good (morning|afternoon|evening)/ }),
    ).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Two-factor authentication' })).toHaveCount(0)
  })

  test('an owner must enter the authenticator code before seeing the pharmacy', async ({
    page,
  }) => {
    await mockBackend(page, { role: 'owner', aal: 'aal1' })
    await page.goto('/')
    await expect(page.getByRole('heading', { name: 'Two-factor authentication' })).toBeVisible()
    await expect(page.getByLabel('Code')).toBeVisible()
    await expect(page.getByText("Today's sales")).toHaveCount(0)
  })
})
