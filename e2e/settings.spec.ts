import { expect, test } from '@playwright/test'

import { mockBackend } from './support/mock-api'

const SALESMAN_PERMISSIONS = [
  'customers.collect',
  'customers.manage',
  'loyalty.enroll',
  'sales.create',
  'sales.credit',
]

test.describe('owner (aal2): staff and access', () => {
  test('add staff by username creates the invitation and the sign-in, then shows the password', async ({
    page,
  }) => {
    const calls = await mockBackend(page)
    await page.goto('/settings')
    await page.getByRole('button', { name: 'Add staff' }).first().click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Full name').fill('Nila Das')
    await dialog.getByLabel('Username').fill(' Nila.MPR ')
    await dialog.getByLabel('Role').selectOption('salesman')
    const password = await dialog.getByLabel('Temporary password').inputValue()
    expect(password).toMatch(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{12}$/)
    await dialog.getByRole('button', { name: 'Add staff' }).click()

    await expect(dialog.getByText('A sign-in was created. Username: nila.mpr.')).toBeVisible()
    await expect(dialog.getByTestId('new-username')).toHaveText('nila.mpr')
    await expect(dialog.getByTestId('temp-password')).toHaveText(password)
    expect(calls.find((c) => c.fn === 'add_member')?.body).toEqual({
      p_organization_id: '11111111-1111-4111-8111-111111111111',
      p_email: 'nila.mpr@staff.invalid',
      p_role: 'salesman',
      p_branch_ids: ['22222222-2222-4222-8222-222222222222'],
    })
    expect(calls.find((c) => c.fn === 'admin-users')?.body).toEqual({
      organization_id: '11111111-1111-4111-8111-111111111111',
      email: 'nila.mpr@staff.invalid',
      password,
      full_name: 'Nila Das',
    })
  })

  test('a username that is already used is refused and its invitation withdrawn', async ({
    page,
  }) => {
    const calls = await mockBackend(page, { adminFunction: 'exists' })
    await page.goto('/settings')
    await page.getByRole('button', { name: 'Add staff' }).first().click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Username').fill('rafiq')
    await dialog.getByRole('button', { name: 'Add staff' }).click()
    await expect(dialog.getByText(/The username rafiq is already used.*rafiq\.mpr/)).toBeVisible()
    expect(calls.find((c) => c.fn === 'revoke_invitation')?.body).toEqual({
      p_invitation_id: 'inv-new',
    })
  })

  test('falls back to manual instructions when the admin function is not deployed', async ({
    page,
  }) => {
    await mockBackend(page, { adminFunction: false })
    await page.goto('/settings')
    await page.getByRole('button', { name: 'Add staff' }).first().click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Username').fill('acc')
    await dialog.getByLabel('Role').selectOption('accountant')
    await expect(dialog.getByText('This role works in every branch.')).toBeVisible()
    await dialog.getByRole('button', { name: 'Add staff' }).click()
    await expect(
      dialog.getByText(/Supabase → Authentication → Add user.*acc@staff\.invalid/),
    ).toBeVisible()
  })

  test('rejects a bad username or a weak temporary password', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/settings')
    await page.getByRole('button', { name: 'Add staff' }).first().click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Username').fill('ab')
    await dialog.getByLabel('Temporary password').fill('password')
    await dialog.getByRole('button', { name: 'Add staff' }).click()
    await expect(dialog.getByText(/Use 3–30 small letters/)).toBeVisible()
    await expect(dialog.getByText(/Use 10\+ characters/)).toBeVisible()
    expect(calls.some((c) => c.fn === 'add_member')).toBe(false)
  })

  test('the owner resets a staff password', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/settings')
    await expect(
      page.getByRole('row', { name: /Sumi Akter/ }).getByText('sumi', { exact: true }),
    ).toBeVisible()
    await page.getByRole('button', { name: 'Manage Sumi Akter' }).click()
    const dialog = page.getByRole('dialog')
    await dialog.getByRole('button', { name: 'Reset password' }).click()
    const shown = dialog.getByTestId('reset-password')
    await expect(shown).toHaveText(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{12}$/)
    expect(calls.find((c) => c.fn === 'admin-users')?.body).toEqual({
      action: 'reset_password',
      organization_id: '11111111-1111-4111-8111-111111111111',
      user_id: '55555555-5555-4555-8555-555555555555',
      password: await shown.textContent(),
    })
  })

  test('per-person access: grant and revoke individual permissions', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/settings')
    await expect(page.getByRole('row', { name: /Rafiq Hasan/ }).getByText('Custom')).toBeVisible()
    await page.getByRole('button', { name: 'Manage Sumi Akter' }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog.getByLabel('Sell at the counter (POS)')).toBeChecked()
    await dialog.getByLabel('Void a sale').check()
    await dialog.getByLabel('Add and edit customers').uncheck()
    // Two-factor sign-in is for owners only: extra permissions do not change how staff sign in.
    await expect(dialog.getByText(/two-factor/i)).toHaveCount(0)

    // Purchases shows supplier prices, so cost visibility comes with it.
    await dialog.getByLabel('See purchases and supplier prices').check()
    await expect(dialog.getByLabel('See cost and profit')).toBeChecked()
    await dialog.getByLabel('See purchases and supplier prices').uncheck()
    await dialog.getByLabel('See cost and profit').uncheck()

    await dialog.getByRole('button', { name: 'Save access' }).click()
    await expect(page.getByText('Access for Sumi Akter saved')).toBeVisible()
    expect(calls.find((c) => c.fn === 'set_member_permissions')?.body).toEqual({
      p_membership_id: 'mb-sales',
      p_overrides: { 'sales.void': true, 'customers.manage': false },
    })
    expect(calls.some((c) => c.fn === 'update_member')).toBe(false)
  })

  test('changing the role starts from the new role template and updates the member', async ({
    page,
  }) => {
    const calls = await mockBackend(page)
    await page.goto('/settings')
    await page.getByRole('button', { name: 'Manage Rafiq Hasan' }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog.getByLabel('Receive goods from suppliers')).not.toBeChecked()
    await dialog.getByLabel('Role').selectOption('accountant')
    await expect(dialog.getByLabel('Sell at the counter (POS)')).not.toBeChecked()
    await dialog.getByRole('button', { name: 'Save access' }).click()
    await expect(page.getByText('Access for Rafiq Hasan saved')).toBeVisible()
    expect(calls.find((c) => c.fn === 'update_member')?.body).toEqual({
      p_membership_id: 'mb-manager',
      p_role: 'accountant',
      p_is_active: true,
      p_branch_ids: [],
    })
    expect(calls.find((c) => c.fn === 'set_member_permissions')?.body).toEqual({
      p_membership_id: 'mb-manager',
      p_overrides: {},
    })
  })

  test('owners cannot open their own access and pending invitations can be revoked', async ({
    page,
  }) => {
    const calls = await mockBackend(page)
    await page.goto('/settings')
    await expect(page.getByRole('button', { name: 'Manage Rahima' })).toBeDisabled()
    await page.getByRole('row', { name: /late/ }).getByRole('button', { name: 'Revoke' }).click()
    await expect.poll(() => calls.some((c) => c.fn === 'revoke_invitation')).toBe(true)
  })
})

test.describe('owner (aal2): branches and pharmacy', () => {
  test('add a branch', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/settings')
    await page.getByRole('tab', { name: 'Branches' }).click()
    await expect(page.getByRole('row', { name: /Dhanmondi/ })).toBeVisible()
    await page.getByRole('button', { name: 'Add branch' }).click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Branch name').fill('Mirpur 10')
    await dialog.getByLabel('Branch code').fill('mir')
    await dialog.getByLabel('Mobile').fill('01811-000002')
    await dialog.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByText('Mirpur 10 saved')).toBeVisible()
    expect(calls.find((c) => c.fn === 'create_branch')?.body).toEqual({
      p_organization_id: '11111111-1111-4111-8111-111111111111',
      p_code: 'MIR',
      p_name: 'Mirpur 10',
      p_phone: '01811-000002',
    })
  })

  test('pharmacy rules are saved as basis points', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/settings')
    await page.getByRole('tab', { name: 'Pharmacy' }).click()
    await expect(page.getByLabel('Max discount: salesperson')).toHaveValue('5')
    await page.getByLabel('Max discount: salesperson').fill('7.5')
    await page.getByLabel('Return window').fill('10')
    await page.getByLabel('Require prescription details for Rx medicines').check()
    await page.getByRole('button', { name: 'Save settings' }).click()
    await expect(page.getByText('Settings saved')).toBeVisible()
    expect(calls.find((c) => c.fn === 'PATCH organization_settings')?.body).toMatchObject({
      salesman_max_discount_bp: 750,
      manager_max_discount_bp: 1500,
      return_window_days: 10,
      require_prescription_for_rx: true,
    })
  })
})

test.describe('salesperson: screens follow permissions', () => {
  test('a salesperson sees only selling screens', async ({ page }) => {
    await mockBackend(page, { role: 'salesman', permissions: SALESMAN_PERMISSIONS })
    await page.goto('/pos')
    // isVisible() does not wait, so let the page render first; phones keep the menu in a drawer.
    await page.getByRole('heading', { level: 1 }).waitFor()
    const menu = page.getByRole('button', { name: 'Open menu' })
    if (await menu.isVisible()) await menu.click()
    const nav = page.getByRole('navigation', { name: 'Main' }).filter({ visible: true })
    await expect(nav.getByRole('link', { name: 'Point of sale' })).toBeVisible()
    await expect(nav.getByRole('link', { name: 'Purchases' })).toHaveCount(0)
    await expect(nav.getByRole('link', { name: 'Reports' })).toHaveCount(0)
    await expect(nav.getByRole('link', { name: 'Settings' })).toHaveCount(0)
  })

  test('granting reports to a salesperson shows the Reports screen', async ({ page }) => {
    await mockBackend(page, {
      role: 'salesman',
      permissions: [...SALESMAN_PERMISSIONS, 'reports.view'],
    })
    await page.goto('/')
    // isVisible() does not wait, so let the page render first; phones keep the menu in a drawer.
    await page.getByRole('heading', { level: 1 }).waitFor()
    const menu = page.getByRole('button', { name: 'Open menu' })
    if (await menu.isVisible()) await menu.click()
    const nav = page.getByRole('navigation', { name: 'Main' }).filter({ visible: true })
    await expect(nav.getByRole('link', { name: 'Reports' })).toBeVisible()
    await expect(nav.getByRole('link', { name: 'Purchases' })).toHaveCount(0)
  })
})
