import { bpToPercentText, MoneyError, parsePercentBp, parseTaka } from '@/domain/money'

import type { Plan } from './loyalty-api'

/** Raw form values of a loyalty plan, kept as typed strings. */
export interface Draft {
  name: string
  months: string
  fee: string
  discount: string
  maxDiscount: string
  pointsPer100: string
  pointValue: string
  minRedeem: string
  isActive: boolean
}

const taka = (p: number) => (p / 100).toFixed(2).replace(/\.00$/, '')

export function toDraft(p: Plan): Draft {
  return {
    name: p.name,
    months: String(p.durationMonths),
    fee: taka(p.feePaisa),
    discount: bpToPercentText(p.discountBp),
    maxDiscount: p.maxDiscountPerInvoicePaisa ? taka(p.maxDiscountPerInvoicePaisa) : '',
    pointsPer100: String(p.pointsPer100Taka),
    pointValue: taka(p.pointValuePaisa),
    minRedeem: String(p.minRedeemPoints),
    isActive: p.isActive,
  }
}

export type DraftErrors = Partial<Record<keyof Draft, string>>

function intIn(v: string, min: number, max: number): number | null {
  if (!/^\d{1,6}$/.test(v.trim())) return null
  const n = Number(v)
  return n >= min && n <= max ? n : null
}

function moneyOrNull(v: string): number | null {
  try {
    return parseTaka(v)
  } catch (e) {
    if (e instanceof MoneyError) return null
    throw e
  }
}

/** Validates against the loyalty_plans check constraints and returns the row to save. */
export function validatePlan(d: Draft) {
  const errors: DraftErrors = {}
  const name = d.name.trim()
  if (name.length < 2 || name.length > 60) errors.name = 'loyalty.err.name'
  const months = intIn(d.months, 1, 36)
  if (months === null) errors.months = 'loyalty.err.months'
  const fee = moneyOrNull(d.fee || '0')
  if (fee === null || fee < 0) errors.fee = 'purchases.err.money'
  let discount: number | null = null
  try {
    discount = parsePercentBp(d.discount || '0')
  } catch (e) {
    if (!(e instanceof MoneyError)) throw e
  }
  if (discount === null || discount > 5000) errors.discount = 'loyalty.err.discount'
  const maxDiscount = d.maxDiscount.trim() === '' ? null : moneyOrNull(d.maxDiscount)
  if (d.maxDiscount.trim() !== '' && (maxDiscount === null || maxDiscount <= 0))
    errors.maxDiscount = 'purchases.err.money'
  const points = intIn(d.pointsPer100 || '0', 0, 1000)
  if (points === null) errors.pointsPer100 = 'loyalty.err.points'
  const pointValue = moneyOrNull(d.pointValue || '0')
  if (pointValue === null || pointValue < 0 || pointValue > 100000)
    errors.pointValue = 'purchases.err.money'
  const minRedeem = intIn(d.minRedeem || '0', 0, 1_000_000)
  if (minRedeem === null) errors.minRedeem = 'medicines.wholeNumber'
  if (
    Object.keys(errors).length > 0 ||
    months === null ||
    fee === null ||
    discount === null ||
    points === null ||
    pointValue === null ||
    minRedeem === null
  ) {
    return { ok: false as const, errors }
  }
  return {
    ok: true as const,
    row: {
      name,
      duration_months: months,
      fee_paisa: fee,
      discount_bp: discount,
      max_discount_per_invoice_paisa: maxDiscount,
      points_per_100_taka: points,
      point_value_paisa: pointValue,
      min_redeem_points: minRedeem,
      is_active: d.isActive,
    },
  }
}
