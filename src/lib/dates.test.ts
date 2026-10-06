import { describe, expect, it } from 'vitest'

import { addDays, businessDate } from './dates'

describe('businessDate', () => {
  it('uses Asia/Dhaka (UTC+6) so late-evening UTC is already the next day', () => {
    expect(businessDate(new Date('2026-10-06T18:30:00Z'))).toBe('2026-10-07')
    expect(businessDate(new Date('2026-10-06T17:59:00Z'))).toBe('2026-10-06')
  })
})

describe('addDays', () => {
  it('crosses month and year boundaries', () => {
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28')
  })
})
