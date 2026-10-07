import { describe, expect, it } from 'vitest'

import { normalizeBdPhone } from '@/domain/phone'

import {
  duplicateKeys,
  lineTotal,
  monthToExpiryDate,
  subtotal,
  toOpeningItems,
  toReceiveItems,
  validateLine,
  type DraftLine,
} from './lines'

const TODAY = '2026-10-08'

function draft(overrides: Partial<DraftLine> = {}): DraftLine {
  return {
    key: 'k1',
    medicineId: 'm1',
    brandName: 'Napa',
    strength: '500 mg',
    unit: 'tablet',
    batchNo: ' NP2401 ',
    expiryMonth: '2027-03',
    quantity: '100',
    bonus: '',
    unitCost: '0.95',
    mrp: '1.20',
    salePrice: '',
    ...overrides,
  }
}

describe('monthToExpiryDate', () => {
  it('uses the last day of the month, including leap years', () => {
    expect(monthToExpiryDate('2027-03')).toBe('2027-03-31')
    expect(monthToExpiryDate('2028-02')).toBe('2028-02-29')
    expect(monthToExpiryDate('2027-02')).toBe('2027-02-28')
    expect(monthToExpiryDate('2027-13')).toBeNull()
    expect(monthToExpiryDate('')).toBeNull()
  })
})

describe('validateLine', () => {
  it('accepts a complete line and defaults sale price to MRP', () => {
    const r = validateLine(draft(), TODAY)
    expect(r).toEqual({
      ok: true,
      line: {
        medicineId: 'm1',
        batchNo: 'NP2401',
        expiryDate: '2027-03-31',
        quantity: 100,
        bonus: 0,
        unitCostPaisa: 95,
        mrpPaisa: 120,
        salePricePaisa: 120,
      },
    })
  })

  it('rejects expired stock, sale price above MRP and bad numbers', () => {
    const r = validateLine(
      draft({
        expiryMonth: '2026-09',
        salePrice: '1.50',
        quantity: '0',
        bonus: '-1',
        unitCost: '1.234',
      }),
      TODAY,
    )
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.errors).toEqual({
        expiryMonth: 'purchases.err.expired',
        salePrice: 'purchases.err.aboveMrp',
        quantity: 'purchases.err.quantity',
        bonus: 'purchases.err.bonus',
        unitCost: 'purchases.err.money',
      })
    }
  })

  it('requires a batch number', () => {
    const r = validateLine(draft({ batchNo: '  ' }), TODAY)
    expect(r.ok ? null : r.errors.batchNo).toBe('purchases.err.batch')
  })
})

describe('totals', () => {
  it('computes line and invoice totals in paisa without floating point drift', () => {
    expect(lineTotal(draft({ quantity: '3', unitCost: '0.10' }))).toBe(30)
    expect(lineTotal(draft({ quantity: '' }))).toBeNull()
    expect(subtotal([draft(), draft({ key: 'k2', quantity: '10', unitCost: '7.00' })])).toBe(
      9500 + 7000,
    )
  })
})

describe('duplicateKeys', () => {
  it('flags the same medicine and batch twice (case-insensitive)', () => {
    const lines = [
      draft(),
      draft({ key: 'k2', batchNo: 'np2401' }),
      draft({ key: 'k3', batchNo: 'X' }),
    ]
    expect([...duplicateKeys(lines)].sort()).toEqual(['k1', 'k2'])
  })
})

describe('payloads', () => {
  it('maps to receive_goods and add_opening_stock items', () => {
    const r = validateLine(draft({ bonus: '10' }), TODAY)
    if (!r.ok) throw new Error('expected valid')
    expect(toReceiveItems([r.line])[0]).toMatchObject({
      quantity: 100,
      bonus_quantity: 10,
      unit_cost_paisa: 95,
    })
    expect(toOpeningItems([r.line])[0]).toMatchObject({ quantity: 110, cost_paisa: 95 })
  })
})

describe('normalizeBdPhone', () => {
  it('matches the database normaliser', () => {
    expect(normalizeBdPhone('01711-223344')).toBe('+8801711223344')
    expect(normalizeBdPhone('+880 1811 223344')).toBe('+8801811223344')
    expect(normalizeBdPhone('  ')).toBeNull()
    expect(() => normalizeBdPhone('01211223344')).toThrow('invalid_phone')
  })
})
