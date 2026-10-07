import { businessDate } from '@/lib/dates'
import { toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

export const PAGE_SIZE = 50

export interface Membership {
  id: string
  cardId: string
  cardNo: string
  planName: string
  startsOn: string
  endsOn: string
}

export interface CustomerRow {
  id: string
  name: string
  phone: string | null
  address: string | null
  notes: string | null
  isActive: boolean
  creditLimitPaisa: number
  balancePaisa: number
  /** Current (or upcoming) active loyalty membership, latest end date first. */
  membership: Membership | null
}

/** Removes characters with meaning inside a PostgREST or() filter or an ilike pattern. */
function sanitize(q: string): string {
  return q
    .replace(/[,()*%\\:"']/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 60)
}

export async function activeMemberships(
  customerIds: string[],
  today = businessDate(),
): Promise<Map<string, Membership>> {
  const map = new Map<string, Membership>()
  if (customerIds.length === 0) return map
  const { data, error } = await supabase
    .from('loyalty_memberships')
    .select('id, customer_id, starts_on, ends_on, loyalty_cards(id, card_no), loyalty_plans(name)')
    .in('customer_id', customerIds)
    .eq('status', 'active')
    .gte('ends_on', today)
    .order('ends_on', { ascending: false })
  if (error) throw toAppError(error)
  for (const m of data) {
    if (map.has(m.customer_id)) continue
    map.set(m.customer_id, {
      id: m.id,
      cardId: m.loyalty_cards.id,
      cardNo: m.loyalty_cards.card_no,
      planName: m.loyalty_plans.name,
      startsOn: m.starts_on,
      endsOn: m.ends_on,
    })
  }
  return map
}

export async function listCustomers(params: {
  organizationId: string
  query: string
  page: number
}): Promise<{ rows: CustomerRow[]; total: number }> {
  const q = sanitize(params.query)
  let request = supabase
    .from('customers')
    .select('id, name, phone, address, notes, is_active, credit_limit_paisa', { count: 'exact' })
    .eq('organization_id', params.organizationId)
    .order('name')
    .range(params.page * PAGE_SIZE, params.page * PAGE_SIZE + PAGE_SIZE - 1)
  if (q) {
    const digits = q.replace(/\D/g, '')
    const filters = [`name.ilike.*${q}*`]
    if (digits.length >= 4) filters.push(`phone.ilike.*${digits}*`)
    request = request.or(filters.join(','))
  }
  const { data, error, count } = await request
  if (error) throw toAppError(error)
  const ids = data.map((c) => c.id)

  const [balances, memberships] = await Promise.all([
    ids.length > 0
      ? supabase
          .from('customer_balances')
          .select('customer_id, balance_paisa')
          .in('customer_id', ids)
      : Promise.resolve({ data: [], error: null }),
    activeMemberships(ids),
  ])
  if (balances.error) throw toAppError(balances.error)
  const balanceBy = new Map(balances.data.map((b) => [b.customer_id, b.balance_paisa ?? 0]))

  return {
    total: count ?? 0,
    rows: data.map((c) => ({
      id: c.id,
      name: c.name,
      phone: c.phone,
      address: c.address,
      notes: c.notes,
      isActive: c.is_active,
      creditLimitPaisa: c.credit_limit_paisa,
      balancePaisa: balanceBy.get(c.id) ?? 0,
      membership: memberships.get(c.id) ?? null,
    })),
  }
}
