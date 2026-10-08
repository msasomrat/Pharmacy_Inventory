import { describe, expect, it } from 'vitest'

import {
  displayLogin,
  isStaffLogin,
  isValidUsername,
  loginToEmail,
  normalizeUsername,
  usernameToEmail,
} from './staff-login'

describe('staff usernames', () => {
  it('accepts simple usernames and rejects the rest', () => {
    for (const ok of ['rafiq', 'sumi.mpr', 'nila_2', 'a1-b2', '123']) {
      expect(isValidUsername(ok)).toBe(true)
    }
    for (const bad of ['ab', '.rafiq', 'rafiq hasan', 'rafiq@x', 'Rafiq', 'a'.repeat(31), '']) {
      expect(isValidUsername(bad)).toBe(false)
    }
    expect(isValidUsername(normalizeUsername('  Rafiq '))).toBe(true)
  })

  it('maps usernames to internal sign-in addresses and back', () => {
    expect(usernameToEmail(' Rafiq ')).toBe('rafiq@staff.invalid')
    expect(isStaffLogin('rafiq@staff.invalid')).toBe(true)
    expect(isStaffLogin('owner@gmail.com')).toBe(false)
    expect(isStaffLogin(null)).toBe(false)
    expect(displayLogin('rafiq@staff.invalid')).toBe('rafiq')
    expect(displayLogin('owner@gmail.com')).toBe('owner@gmail.com')
  })

  it('signs in with a username or an email', () => {
    expect(loginToEmail(' Sumi ')).toBe('sumi@staff.invalid')
    expect(loginToEmail(' Owner@Gmail.com ')).toBe('owner@gmail.com')
  })
})
