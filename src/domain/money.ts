/**
 * Money helpers. All amounts are integer paisa (1 BDT = 100 paisa) — see ADR-0005.
 *
 * The database is the single authority for prices, discounts and totals. These helpers are used
 * for input parsing, display and client-side previews only; the server recomputes everything.
 */

declare const paisaBrand: unique symbol
export type Paisa = number & { readonly [paisaBrand]: true }

/** Largest magnitude we accept, so intermediate products stay exact in IEEE-754 doubles. */
export const MAX_PAISA = 1_000_000_000_000 // 10 billion taka

/** Basis points: 1% = 100 bp, 100% = 10_000 bp. Percentages are never stored as floats. */
export type BasisPoints = number

export class MoneyError extends Error {
  override name = 'MoneyError'
}

export function paisa(value: number): Paisa {
  if (!Number.isSafeInteger(value)) {
    throw new MoneyError(`Paisa must be a safe integer, got ${String(value)}`)
  }
  if (Math.abs(value) > MAX_PAISA) {
    throw new MoneyError(`Amount out of range: ${value}`)
  }
  return value as Paisa
}

const AMOUNT_PATTERN = /^(-)?(\d{1,11})(?:\.(\d{1,2}))?$/

/**
 * Parses a user-entered taka amount ("1250", "1,250.5", "12.50") into paisa without using
 * floating point. Rejects more than two decimal places instead of silently rounding.
 */
export function parseTaka(input: string): Paisa {
  const normalized = input.trim().replace(/[,\s৳]/g, '')
  const match = AMOUNT_PATTERN.exec(normalized)
  if (!match) {
    throw new MoneyError(`Invalid amount: "${input}"`)
  }
  const [, sign, whole = '0', fraction = ''] = match
  const value = Number(whole) * 100 + Number(fraction.padEnd(2, '0'))
  return paisa(sign ? -value : value)
}

export function addPaisa(...amounts: Paisa[]): Paisa {
  return paisa(amounts.reduce<number>((sum, amount) => sum + amount, 0))
}

export function multiplyPaisa(amount: Paisa, quantity: number): Paisa {
  if (!Number.isSafeInteger(quantity)) {
    throw new MoneyError(`Quantity must be an integer, got ${String(quantity)}`)
  }
  return paisa(amount * quantity)
}

/**
 * Returns `amount * bp / 10_000`, rounded half away from zero to the nearest paisa.
 * This mirrors the database rounding rule (ROUND() on NUMERIC, which rounds half away from zero).
 */
export function percentOf(amount: Paisa, bp: BasisPoints): Paisa {
  if (!Number.isInteger(bp) || bp < 0 || bp > 10_000) {
    throw new MoneyError(`Basis points must be an integer in [0, 10000], got ${String(bp)}`)
  }
  const product = Math.abs(amount) * bp
  const rounded = Math.floor((product + 5_000) / 10_000)
  return paisa(amount < 0 ? -rounded : rounded)
}

export type DisplayLocale = 'en' | 'bn'

const BANGLA_DIGITS = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'] as const

function toBanglaDigits(text: string): string {
  return text.replace(/\d/g, (digit) => BANGLA_DIGITS[Number(digit)] ?? digit)
}

/**
 * Formats paisa as Bangladeshi taka with lakh/crore grouping, e.g. 123456789 -> "৳12,34,567.89".
 * Uses integer arithmetic only.
 */
export function formatTaka(amount: Paisa, locale: DisplayLocale = 'en'): string {
  const negative = amount < 0
  const absolute = Math.abs(amount)
  const taka = Math.trunc(absolute / 100)
  const fraction = String(absolute % 100).padStart(2, '0')
  const grouped = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 }).format(taka)
  const text = `${negative ? '-' : ''}৳${grouped}.${fraction}`
  return locale === 'bn' ? toBanglaDigits(text) : text
}
