import { expect, test } from '@playwright/test'

import { mockBackend } from './support/mock-api'

test.describe('owner (aal2): customers and loyalty', () => {
  test('customers list shows loyalty status and dues; adding a customer normalises the phone', async ({
    page,
  }) => {
    const calls = await mockBackend(page)
    await page.goto('/customers')
    const karim = page.getByRole('row', { name: /Karim Uddin/ })
    await expect(karim.getByText('6-Month Card').filter({ visible: true })).toBeVisible()
    await expect(karim.getByText('৳350.00')).toBeVisible()
    await expect(
      page
        .getByRole('row', { name: /Rahim Mia/ })
        .getByText('No card')
        .first(),
    ).toBeAttached()

    await page.getByRole('button', { name: 'Add customer' }).click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Customer name').fill('Nasima Akter')
    await dialog.getByLabel('Mobile').fill('01911-223344')
    await dialog.getByLabel('Credit limit (বাকি)').fill('2000')
    await dialog.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByText('Nasima Akter added')).toBeVisible()
    expect(calls.find((c) => c.fn === 'POST customers')?.body).toMatchObject({
      name: 'Nasima Akter',
      phone: '+8801911223344',
    })
    expect(calls.find((c) => c.fn === 'set_customer_credit_limit')?.body).toMatchObject({
      p_customer_id: 'customers-new',
      p_credit_limit_paisa: 200000,
    })
  })

  test('customer form rejects an invalid mobile number', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/customers')
    await page.getByRole('button', { name: 'Add customer' }).click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Customer name').fill('Test')
    await dialog.getByLabel('Mobile').fill('01211223344')
    await dialog.getByRole('button', { name: 'Save' }).click()
    await expect(dialog.getByText(/valid Bangladeshi mobile number/)).toBeVisible()
    expect(calls.some((c) => c.fn === 'POST customers')).toBe(false)
  })

  test('enroll a customer: only offered plans, fee shown, card number displayed', async ({
    page,
  }) => {
    const calls = await mockBackend(page)
    await page.goto('/customers')
    await page.getByRole('button', { name: 'Give Salma Begum a loyalty card' }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog.getByText('3-Month Card')).toBeVisible()
    await expect(dialog.getByText('6-Month Card')).toHaveCount(0)
    await dialog.getByRole('button', { name: 'Enroll · collect ৳100.00' }).click()
    await expect(dialog.getByTestId('card-no')).toHaveText('8000 0000 29')
    expect(calls.find((c) => c.fn === 'enroll_loyalty')?.body).toMatchObject({
      p_customer_id: 'cu3',
      p_plan_id: 'pl3',
      p_payment_method: 'cash',
    })
  })

  test('members: filters, search and cancel with a reason', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/loyalty')
    await expect(page.getByRole('row', { name: /Karim Uddin/ })).toBeVisible()
    await expect(page.getByRole('row', { name: /Rahim Mia/ })).toHaveCount(0)
    await page.getByRole('button', { name: /^Expired/ }).click()
    await expect(page.getByRole('row', { name: /Rahim Mia/ })).toBeVisible()

    await page.getByRole('button', { name: /^Active/ }).click()
    await page.getByRole('button', { name: "Cancel Karim Uddin's membership" }).click()
    const dialog = page.getByRole('dialog')
    const confirm = dialog.getByRole('button', { name: 'Cancel membership' })
    await expect(confirm).toBeDisabled()
    await dialog.getByLabel('Reason').fill('Customer moved away')
    await confirm.click()
    await expect(page.getByText('Membership cancelled')).toBeVisible()
    expect(calls.find((c) => c.fn === 'cancel_loyalty_membership')?.body).toEqual({
      p_membership_id: 'lm1',
      p_reason: 'Customer moved away',
    })
  })

  test('plans: owner sets fee, discount and points in taka and percent', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/loyalty')
    await page.getByRole('tab', { name: 'Plans' }).click()
    const card = page.getByRole('region', { name: '6-Month Card' })
    await card.getByLabel('Card fee').fill('180')
    await card.getByLabel('Discount', { exact: true }).fill('60')
    await card.getByRole('button', { name: 'Save' }).click()
    await expect(card.getByText('0 to 50')).toBeVisible()
    expect(calls.some((c) => c.fn === 'PATCH loyalty_plans')).toBe(false)

    await card.getByLabel('Discount', { exact: true }).fill('7.5')
    await card.getByLabel('Points per ৳100').fill('2')
    await card.getByLabel('Offer this plan to customers').check()
    await card.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByText('6-Month Card saved')).toBeVisible()
    expect(calls.find((c) => c.fn === 'PATCH loyalty_plans')?.body).toMatchObject({
      fee_paisa: 18000,
      discount_bp: 750,
      points_per_100_taka: 2,
      is_active: true,
      max_discount_per_invoice_paisa: null,
    })
  })
})
