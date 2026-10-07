/** "8000000011" -> "8000 0000 11" for printing and reading aloud. */
export function formatCardNo(cardNo: string): string {
  return cardNo.replace(/(\d{4})(?=\d)/g, '$1 ')
}

export type MembershipState = 'active' | 'expiring' | 'upcoming' | 'expired' | 'cancelled'

export function membershipState(
  m: { status: string; startsOn: string; endsOn: string },
  today: string,
  expiringDays = 14,
): MembershipState {
  if (m.status === 'cancelled') return 'cancelled'
  if (m.endsOn < today) return 'expired'
  if (m.startsOn > today) return 'upcoming'
  const days = (Date.parse(`${m.endsOn}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / 86_400_000
  return days <= expiringDays ? 'expiring' : 'active'
}
