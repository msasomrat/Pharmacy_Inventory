/**
 * Normalises a Bangladeshi mobile number to +8801XXXXXXXXX, mirroring app.normalize_bd_phone().
 * Returns null for blank input and throws for anything that is not a valid mobile number.
 */
export function normalizeBdPhone(input: string): string | null {
  if (input.trim() === '') return null
  const digits = input.replace(/\D/g, '')
  if (/^8801[3-9]\d{8}$/.test(digits)) return `+${digits}`
  if (/^01[3-9]\d{8}$/.test(digits)) return `+88${digits}`
  throw new Error('invalid_phone')
}

export function isValidBdPhone(input: string): boolean {
  try {
    normalizeBdPhone(input)
    return true
  } catch {
    return false
  }
}

/** "+8801711223344" -> "01711-223344" for display. */
export function displayPhone(phone: string | null): string {
  if (!phone) return ''
  const local = phone.replace(/^\+88/, '')
  return local.length === 11 ? `${local.slice(0, 5)}-${local.slice(5)}` : local
}
