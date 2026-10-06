import { describe, expect, it } from 'vitest'

import { cartReducer, estimate, needsPrescription, toSaleItems, type CartLine } from './cart'

const napa = {
  medicineId: 'napa',
  name: 'Napa',
  detail: '500 mg',
  schedule: 'otc' as const,
  unitPricePaisa: 120,
  stock: 50,
}
const sedil = {
  medicineId: 'sedil',
  name: 'Sedil',
  detail: '5 mg',
  schedule: 'controlled' as const,
  unitPricePaisa: 300,
  stock: 5,
}

describe('cartReducer', () => {
  it('adds a line and increments on repeat add', () => {
    let cart: CartLine[] = cartReducer([], { type: 'add', line: napa })
    cart = cartReducer(cart, { type: 'add', line: napa, quantity: 9 })
    expect(cart).toHaveLength(1)
    expect(cart[0]?.quantity).toBe(10)
  })

  it('never exceeds stock and never goes below one', () => {
    let cart = cartReducer([], { type: 'add', line: sedil, quantity: 99 })
    expect(cart[0]?.quantity).toBe(5)
    cart = cartReducer(cart, { type: 'setQuantity', medicineId: 'sedil', quantity: 0 })
    expect(cart[0]?.quantity).toBe(1)
  })

  it('ignores out-of-stock items', () => {
    expect(cartReducer([], { type: 'add', line: { ...napa, stock: 0 } })).toEqual([])
  })

  it('clamps discounts to 0-100%', () => {
    let cart = cartReducer([], { type: 'add', line: napa })
    cart = cartReducer(cart, { type: 'setDiscount', medicineId: 'napa', discountBp: 20_000 })
    expect(cart[0]?.discountBp).toBe(10_000)
    cart = cartReducer(cart, { type: 'setDiscount', medicineId: 'napa', discountBp: -5 })
    expect(cart[0]?.discountBp).toBe(0)
  })

  it('removes and clears', () => {
    let cart = cartReducer([], { type: 'add', line: napa })
    cart = cartReducer(cart, { type: 'add', line: sedil })
    expect(
      cartReducer(cart, { type: 'remove', medicineId: 'napa' }).map((l) => l.medicineId),
    ).toEqual(['sedil'])
    expect(cartReducer(cart, { type: 'clear' })).toEqual([])
  })
})

describe('estimate', () => {
  it('applies line discounts with half-away-from-zero rounding like the database', () => {
    let cart = cartReducer([], { type: 'add', line: napa, quantity: 10 })
    cart = cartReducer(cart, { type: 'setDiscount', medicineId: 'napa', discountBp: 500 })
    expect(estimate(cart)).toEqual({ grossPaisa: 1200, discountPaisa: 60, totalPaisa: 1140 })
  })
})

describe('helpers', () => {
  it('requires a prescription only for controlled medicines', () => {
    expect(needsPrescription(cartReducer([], { type: 'add', line: napa }))).toBe(false)
    expect(needsPrescription(cartReducer([], { type: 'add', line: sedil }))).toBe(true)
  })

  it('maps lines to the RPC payload', () => {
    expect(toSaleItems(cartReducer([], { type: 'add', line: napa, quantity: 2 }))).toEqual([
      { medicine_id: 'napa', quantity: 2, discount_bp: 0 },
    ])
  })
})
