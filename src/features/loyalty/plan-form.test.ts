import { describe, expect, it } from 'vitest'

import { toDraft, validatePlan } from './plan-form'

const plan = {
  id: 'p3',
  name: '3-Month Card',
  durationMonths: 3,
  feePaisa: 0,
  discountBp: 0,
  maxDiscountPerInvoicePaisa: null,
  pointsPer100Taka: 0,
  pointValuePaisa: 0,
  minRedeemPoints: 0,
  isActive: false,
  sortOrder: 1,
}

describe('plan form', () => {
  it('round-trips a plan and converts taka/percent to paisa/basis points', () => {
    const draft = {
      ...toDraft(plan),
      fee: '100',
      discount: '5.5',
      maxDiscount: '50',
      pointsPer100: '1',
      pointValue: '0.50',
      minRedeem: '20',
      isActive: true,
    }
    expect(validatePlan(draft)).toEqual({
      ok: true,
      row: {
        name: '3-Month Card',
        duration_months: 3,
        fee_paisa: 10000,
        discount_bp: 550,
        max_discount_per_invoice_paisa: 5000,
        points_per_100_taka: 1,
        point_value_paisa: 50,
        min_redeem_points: 20,
        is_active: true,
      },
    })
  })

  it('applies the database limits (discount max 50%, 1-36 months)', () => {
    const r = validatePlan({
      ...toDraft(plan),
      discount: '60',
      months: '40',
      name: 'X',
      pointsPer100: '2000',
    })
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.errors).toMatchObject({
        discount: 'loyalty.err.discount',
        months: 'loyalty.err.months',
        name: 'loyalty.err.name',
        pointsPer100: 'loyalty.err.points',
      })
    }
  })

  it('treats an empty max discount as "no cap"', () => {
    const r = validatePlan({ ...toDraft(plan), maxDiscount: '' })
    expect(r.ok && r.row.max_discount_per_invoice_paisa).toBeNull()
  })
})
