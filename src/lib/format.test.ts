import { describe, expect, it } from 'vitest'

import { compactTaka, formatNumber } from './format'

describe('formatNumber', () => {
  it('uses lakh grouping and Bangla digits', () => {
    expect(formatNumber(1234567)).toBe('12,34,567')
    expect(formatNumber(133, 'bn')).toBe('১৩৩')
  })
})

describe('compactTaka', () => {
  it('keeps adjacent axis ticks distinct', () => {
    expect([150000, 200000, 250000].map((p) => compactTaka(p))).toEqual(['৳1.5k', '৳2k', '৳2.5k'])
    expect(compactTaka(80000)).toBe('৳800')
    expect(compactTaka(12_000_000)).toBe('৳1.2L')
  })
})
