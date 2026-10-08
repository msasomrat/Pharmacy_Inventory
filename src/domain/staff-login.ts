/**
 * Staff sign in with a username instead of an email address. Supabase Auth needs an email, so a
 * username is stored as the internal address <username>@staff.invalid. The ".invalid" top-level
 * domain is reserved (RFC 2606): these addresses can never receive mail. Owners keep a real email.
 */
export const STAFF_LOGIN_DOMAIN = 'staff.invalid'

const USERNAME = /^[a-z0-9][a-z0-9._-]{2,29}$/

export function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase()
}

/** 3–30 characters: letters, digits, dot, dash or underscore, starting with a letter or digit. */
export function isValidUsername(username: string): boolean {
  return USERNAME.test(username)
}

export function usernameToEmail(username: string): string {
  return `${normalizeUsername(username)}@${STAFF_LOGIN_DOMAIN}`
}

/** What the sign-in form sends to Auth: an email as typed, or a username's internal address. */
export function loginToEmail(input: string): string {
  const value = input.trim().toLowerCase()
  return value.includes('@') ? value : usernameToEmail(value)
}

export function isStaffLogin(email: string | null | undefined): boolean {
  return (email ?? '').toLowerCase().endsWith(`@${STAFF_LOGIN_DOMAIN}`)
}

/** Username for staff sign-ins, the email otherwise. */
export function displayLogin(email: string): string {
  return isStaffLogin(email) ? email.slice(0, -(STAFF_LOGIN_DOMAIN.length + 1)) : email
}
