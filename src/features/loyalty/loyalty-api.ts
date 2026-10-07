import { toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

export interface Plan {
  id: string
  name: string
  durationMonths: number
  feePaisa: number
  discountBp: number
  maxDiscountPerInvoicePaisa: number | null
  pointsPer100Taka: number
  pointValuePaisa: number
  minRedeemPoints: number
  isActive: boolean
  sortOrder: number
}

export async function listPlans(organizationId: string): Promise<Plan[]> {
  const { data, error } = await supabase
    .from('loyalty_plans')
    .select(
      'id, name, duration_months, fee_paisa, discount_bp, max_discount_per_invoice_paisa, points_per_100_taka, point_value_paisa, min_redeem_points, is_active, sort_order',
    )
    .eq('organization_id', organizationId)
    .order('sort_order')
    .order('duration_months')
  if (error) throw toAppError(error)
  return data.map((p) => ({
    id: p.id,
    name: p.name,
    durationMonths: p.duration_months,
    feePaisa: p.fee_paisa,
    discountBp: p.discount_bp,
    maxDiscountPerInvoicePaisa: p.max_discount_per_invoice_paisa,
    pointsPer100Taka: p.points_per_100_taka,
    pointValuePaisa: p.point_value_paisa,
    minRedeemPoints: p.min_redeem_points,
    isActive: p.is_active,
    sortOrder: p.sort_order,
  }))
}

export async function loyaltyEnabled(organizationId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from('organization_settings')
    .select('loyalty_enabled')
    .eq('organization_id', organizationId)
    .single()
  if (error) throw toAppError(error)
  return data.loyalty_enabled
}
