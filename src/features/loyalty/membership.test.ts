import { describe, expect, it } from 'vitest'

import { displayPhone } from '@/domain/phone'

import { formatCardNo, membershipState } from './membership'

describe('membershipState', () => {
  const today = '2026-10-08'
  it('classifies memberships for badges and filters', () => {
    expect(
      membershipState({ status: 'active', startsOn: '2026-09-01', endsOn: '2027-02-28' }, today),
    ).toBe('active')
    expect(
      membershipState({ status: 'active', startsOn: '2026-07-01', endsOn: '2026-10-20' }, today),
    ).toBe('expiring')
    expect(
      membershipState({ status: 'active', startsOn: '2026-07-01', endsOn: '2026-10-08' }, today),
    ).toBe('expiring')
    expect(
      membershipState({ status: 'active', startsOn: '2026-04-01', endsOn: '2026-10-07' }, today),
    ).toBe('expired')
    expect(
      membershipState({ status: 'active', startsOn: '2027-03-01', endsOn: '2027-08-31' }, today),
    ).toBe('upcoming')
    expect(
      membershipState({ status: 'cancelled', startsOn: '2026-09-01', endsOn: '2027-02-28' }, today),
    ).toBe('cancelled')
  })
})

describe('formatting', () => {
  it('groups card numbers and shows local phone numbers', () => {
    expect(formatCardNo('8000000011')).toBe('8000 0000 11')
    expect(formatCardNo('1234567890123456')).toBe('1234 5678 9012 3456')
    expect(displayPhone('+8801711223344')).toBe('01711-223344')
    expect(displayPhone(null)).toBe('')
  })
})
