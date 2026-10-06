import fc from 'fast-check'
import { describe, expect, it } from 'vitest'

import {
  MAX_PAISA,
  MoneyError,
  addPaisa,
  formatTaka,
  multiplyPaisa,
  paisa,
  parseTaka,
  percentOf,
} from './money'

describe('paisa', () => {
  it('accepts safe integers in range', () => {
    expect(paisa(0)).toBe(0)
    expect(paisa(-150)).toBe(-150)
  })

  it.each([1.5, Number.NaN, Number.POSITIVE_INFINITY, MAX_PAISA + 1])('rejects %s', (value) => {
    expect(() => paisa(value)).toThrow(MoneyError)
  })
})

describe('parseTaka', () => {
  it.each([
    ['0', 0],
    ['12', 1200],
    ['12.5', 1250],
    ['12.05', 1205],
    ['1,250.50', 125050],
    ['৳ 1,00,000', 10000000],
    ['-3.10', -310],
  ])('parses "%s" to %i paisa', (input, expected) => {
    expect(parseTaka(input)).toBe(expected)
  })

  it.each(['', 'abc', '1.234', '1.2.3', '12a', '--1'])('rejects "%s"', (input) => {
    expect(() => parseTaka(input)).toThrow(MoneyError)
  })

  it('round-trips with formatTaka for any amount', () => {
    fc.assert(
      fc.property(fc.integer({ min: -MAX_PAISA, max: MAX_PAISA }), (value) => {
        expect(parseTaka(formatTaka(paisa(value)))).toBe(value)
      }),
    )
  })
})

describe('arithmetic', () => {
  it('adds and multiplies exactly', () => {
    expect(addPaisa(paisa(10), paisa(20), paisa(-5))).toBe(25)
    expect(multiplyPaisa(paisa(1050), 3)).toBe(3150)
  })

  it('rejects fractional quantities', () => {
    expect(() => multiplyPaisa(paisa(100), 1.5)).toThrow(MoneyError)
  })
})

describe('percentOf', () => {
  it.each([
    [10000, 500, 500], // 5% of 100 taka
    [1250, 500, 63], // 62.5 paisa rounds half away from zero
    [1249, 500, 62],
    [-1250, 500, -63],
    [999, 10000, 999],
    [999, 0, 0],
  ])('%i paisa at %i bp = %i', (amount, bp, expected) => {
    expect(percentOf(paisa(amount), bp)).toBe(expected)
  })

  it.each([-1, 10001, 2.5])('rejects %s basis points', (bp) => {
    expect(() => percentOf(paisa(100), bp)).toThrow(MoneyError)
  })

  it('never exceeds the original amount and is monotonic in bp', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: MAX_PAISA }),
        fc.integer({ min: 0, max: 9_999 }),
        (amount, bp) => {
          const a = percentOf(paisa(amount), bp)
          const b = percentOf(paisa(amount), bp + 1)
          expect(a).toBeLessThanOrEqual(amount)
          expect(b).toBeGreaterThanOrEqual(a)
        },
      ),
    )
  })
})

describe('formatTaka', () => {
  it('uses Bangladeshi lakh grouping', () => {
    expect(formatTaka(paisa(123456789))).toBe('৳12,34,567.89')
    expect(formatTaka(paisa(5))).toBe('৳0.05')
    expect(formatTaka(paisa(-100000))).toBe('-৳1,000.00')
  })

  it('renders Bangla digits', () => {
    expect(formatTaka(paisa(123456), 'bn')).toBe('৳১,২৩৪.৫৬')
  })
})
