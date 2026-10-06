import type { DisplayLocale } from '@/domain/money'

/** Integer/decimal formatting with Bangla digits in bn and Bangladeshi (lakh) grouping. */
export function formatNumber(
  n: number,
  locale: DisplayLocale = 'en',
  maxFractionDigits = 0,
): string {
  return new Intl.NumberFormat(locale === 'bn' ? 'bn-BD' : 'en-IN', {
    maximumFractionDigits: maxFractionDigits,
  }).format(n)
}

/** Compact taka for chart axes: ৳800, ৳1.5k, ৳24k, ৳1.2L (lakh). Input is paisa. */
export function compactTaka(paisaAmount: number, locale: DisplayLocale = 'en'): string {
  const taka = paisaAmount / 100
  const abs = Math.abs(taka)
  if (abs >= 100_000) return `৳${formatNumber(taka / 100_000, locale, 1)}L`
  if (abs >= 10_000) return `৳${formatNumber(taka / 1_000, locale, 0)}k`
  if (abs >= 1_000) return `৳${formatNumber(taka / 1_000, locale, 1)}k`
  return `৳${formatNumber(taka, locale, 0)}`
}
