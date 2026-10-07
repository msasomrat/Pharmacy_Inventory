import { expect, test } from '@playwright/test'

import { mockBackend } from './support/mock-api'

function monthsAhead(n: number): string {
  const d = new Date()
  d.setUTCDate(1)
  d.setUTCMonth(d.getUTCMonth() + n)
  return d.toISOString().slice(0, 7)
}

test.describe('owner (aal2): catalog and stock', () => {
  test('medicines list shows rack location; adding a medicine saves rack for the branch', async ({
    page,
  }) => {
    const calls = await mockBackend(page)
    await page.goto('/medicines')
    await expect(page.getByText('2 medicines in your catalog')).toBeVisible()
    const napa = page.getByRole('row', { name: /Napa/ })
    await expect(napa.getByText('A-3')).toBeVisible()
    await expect(napa.getByText('Paracetamol · Beximco')).toBeVisible()

    await page.getByRole('button', { name: 'Add medicine' }).first().click()
    const dialog = page.getByRole('dialog')
    await dialog.getByLabel('Brand name').fill('Fexo')
    await dialog.getByLabel('Strength').fill('120 mg')
    await dialog.getByLabel('Generic name').fill('Fexofenadine')
    await dialog.getByLabel('Rack / shelf').fill('b-2')
    await dialog.getByLabel('Reorder level').fill('30')
    await dialog.getByText('Prescription (Rx)').click()
    await dialog.getByRole('button', { name: 'Save' }).click()

    await expect(page.getByText('Fexo added')).toBeVisible()
    const save = calls.find((c) => c.fn === 'save_medicine')
    expect(save?.body).toMatchObject({
      p_brand_name: 'Fexo',
      p_generic_name: 'Fexofenadine',
      p_dosage_form: 'tablet',
      p_base_unit_label: 'tablet',
      p_schedule: 'rx',
      p_rack_location: 'b-2',
      p_reorder_level: 30,
      p_branch_id: '22222222-2222-4222-8222-222222222222',
    })
    expect(save?.body).not.toHaveProperty('p_medicine_id')
  })

  test('medicine form rejects a malformed barcode before calling the server', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/medicines')
    await page.getByRole('button', { name: 'Edit Napa' }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog.getByLabel('Brand name')).toHaveValue('Napa')
    await dialog.getByLabel('Barcodes').fill('ab')
    await dialog.getByRole('button', { name: 'Save' }).click()
    await expect(dialog.getByText('Barcodes are 4–64 letters, digits or dashes.')).toBeVisible()
    expect(calls.some((c) => c.fn === 'save_medicine')).toBe(false)
  })

  test('receive goods: validates lines, then posts an idempotent receipt', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/purchases')
    await page
      .getByLabel('Supplier', { exact: true })
      .selectOption({ label: 'Beximco Distribution' })
    await page.getByLabel('Supplier invoice no.').fill('BX-5600')

    const picker = page.getByRole('combobox', { name: /Add medicine/ })
    await picker.fill('napa')
    await expect(page.getByRole('option', { name: /Napa Extra/ })).toBeVisible()
    await picker.press('Enter')
    await expect(page.getByLabel('MRP Napa', { exact: true })).toHaveValue('1.20')

    // Incomplete line: nothing is sent.
    await page.getByRole('button', { name: 'Save goods receipt' }).click()
    await expect(page.getByText('Required').first()).toBeVisible()
    expect(calls.some((c) => c.fn === 'receive_goods')).toBe(false)

    await page.getByLabel('Batch Napa', { exact: true }).fill('NP2510')
    await page.getByLabel('Expiry Napa', { exact: true }).fill(monthsAhead(18))
    await page.getByLabel('Qty Napa', { exact: true }).fill('100')
    await page.getByLabel('Bonus Napa', { exact: true }).fill('5')
    await page.getByLabel('Cost Napa', { exact: true }).fill('0.95')
    await expect(page.getByRole('cell', { name: '৳95.00' })).toBeVisible()
    await page.getByLabel('Paid now').fill('50')
    await page.getByRole('button', { name: 'Save goods receipt' }).click()

    await expect(page.getByText('Goods receipt MPR-G2627-000008 saved')).toBeVisible()
    const receive = calls.find((c) => c.fn === 'receive_goods')
    expect(receive?.body).toMatchObject({
      p_supplier_id: 'sup-1',
      p_supplier_invoice_no: 'BX-5600',
      p_paid_paisa: 5000,
      p_discount_paisa: 0,
      p_payment_method: 'cash',
      p_items: [
        {
          medicine_id: 'm-napa',
          batch_no: 'NP2510',
          quantity: 100,
          bonus_quantity: 5,
          unit_cost_paisa: 95,
          mrp_paisa: 120,
          sale_price_paisa: 120,
        },
      ],
    })
    expect(receive?.body.p_client_request_id).toMatch(/^[0-9a-f-]{36}$/)
    // The form is cleared for the next invoice.
    await expect(page.getByText('No items yet')).toBeVisible()
  })

  test('opening stock tab posts add_opening_stock', async ({ page }) => {
    const calls = await mockBackend(page)
    await page.goto('/purchases')
    await page.getByRole('tab', { name: 'Opening stock' }).click()
    const picker = page.getByRole('combobox', { name: /Add medicine/ })
    await picker.fill('seclo')
    await picker.press('Enter')
    await page.getByLabel('Batch Seclo', { exact: true }).fill('SC77')
    await page.getByLabel('Expiry Seclo', { exact: true }).fill(monthsAhead(10))
    await page.getByLabel('Qty Seclo', { exact: true }).fill('60')
    await page.getByLabel('Cost Seclo', { exact: true }).fill('5.50')
    await page.getByLabel('MRP Seclo', { exact: true }).fill('7')
    await page.getByRole('button', { name: 'Save opening stock' }).click()
    await expect(page.getByText('Opening stock saved (1 batches)')).toBeVisible()
    expect(calls.find((c) => c.fn === 'add_opening_stock')?.body).toMatchObject({
      p_items: [
        { medicine_id: 'm-seclo', batch_no: 'SC77', quantity: 60, cost_paisa: 550, mrp_paisa: 700 },
      ],
    })
  })

  test('purchase history lists receipts and expands items', async ({ page }) => {
    await mockBackend(page)
    await page.goto('/purchases')
    await page.getByRole('tab', { name: 'History' }).click()
    await expect(page.getByText('MPR-G2627-000007')).toBeVisible()
    await expect(page.getByText('৳4,500.00')).toBeVisible()
    await page.getByText('MPR-G2627-000007').click()
    await expect(page.getByText('NP2401')).toBeVisible()
  })

  test('inventory shows stock on hand per medicine with rack and nearest expiry', async ({
    page,
  }) => {
    await mockBackend(page)
    await page.goto('/inventory')
    const napa = page.getByRole('row', { name: /Napa/ }).first()
    await expect(napa.getByText('A-3')).toBeVisible()
    await expect(napa.getByText('840')).toBeVisible()
    await expect(napa.getByText('2 batches')).toBeVisible()
  })

  test('POS search shows where the medicine is shelved', async ({ page }) => {
    await mockBackend(page)
    await page.goto('/pos')
    await page.getByRole('combobox', { name: /Search medicine/ }).fill('napa')
    await expect(
      page.getByRole('option', { name: /Napa 500 mg/ }).getByText('Rack A-3'),
    ).toBeVisible()
  })
})
