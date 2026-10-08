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

test.describe('staff sign in with a username', () => {
  test('the sign-in form turns a username into the internal sign-in address', async ({ page }) => {
    const calls = await mockBackend(page, { signedIn: false })
    await page.goto('/')
    await page.getByLabel('Username or email').fill(' Sumi ')
    await page.getByLabel('Password').fill('Temp-Pass123')
    await page.getByRole('button', { name: 'Sign in' }).click()
    await expect
      .poll(() => calls.find((c) => c.fn.startsWith('POST auth/token'))?.body)
      .toMatchObject({ email: 'sumi@staff.invalid', password: 'Temp-Pass123' })
  })

  test('owners still sign in with their email', async ({ page }) => {
    const calls = await mockBackend(page, { signedIn: false })
    await page.goto('/')
    await page.getByLabel('Username or email').fill('Rahima@Shefa.example')
    await page.getByLabel('Password').fill('Owner-Pass123')
    await page.getByRole('button', { name: 'Sign in' }).click()
    await expect
      .poll(() => calls.find((c) => c.fn.startsWith('POST auth/token'))?.body)
      .toMatchObject({ email: 'rahima@shefa.example' })
  })

  test('a new staff member joins the pharmacy automatically at first sign-in', async ({ page }) => {
    const calls = await mockBackend(page, {
      role: 'salesman',
      aal: 'aal1',
      permissions: SALESMAN_PERMISSIONS,
      email: 'sumi@staff.invalid',
      joined: false,
      myInvitations: [
        { invitation_id: 'inv-1', organization_name: 'Shefa Pharmacy', role: 'salesman' },
      ],
    })
    await page.goto('/pos')
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
    expect(calls.find((c) => c.fn === 'accept_invitation')?.body).toEqual({
      p_invitation_id: 'inv-1',
    })
    await expect(page.getByText('Set up your pharmacy')).toHaveCount(0)
  })

  test('staff change their temporary password from the account menu', async ({ page }) => {
    const calls = await mockBackend(page, {
      role: 'salesman',
      aal: 'aal1',
      permissions: SALESMAN_PERMISSIONS,
      email: 'sumi@staff.invalid',
    })
    await page.goto('/pos')
    await page.getByRole('button', { name: 'Account' }).click()
    await expect(page.getByRole('menu').getByText('sumi', { exact: true })).toBeVisible()
    await page.getByRole('menuitem', { name: 'Change password' }).click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('New password', { exact: true }).fill('Mine-Pass2026')
    await dialog.getByLabel('Repeat new password').fill('Mine-Pass2026')
    await dialog.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByText('Password changed')).toBeVisible()
    expect(calls.find((c) => c.fn === 'PUT auth/user')?.body).toMatchObject({
      password: 'Mine-Pass2026',
    })
  })
})
