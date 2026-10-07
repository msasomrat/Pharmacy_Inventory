import type { Database } from '@/lib/database.types'
import { toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

export type DosageForm = Database['public']['Enums']['dosage_form']
export type DrugSchedule = Database['public']['Enums']['drug_schedule']

export const DOSAGE_FORMS: DosageForm[] = [
  'tablet',
  'capsule',
  'syrup',
  'suspension',
  'solution',
  'injection',
  'infusion',
  'drops',
  'cream',
  'ointment',
  'gel',
  'lotion',
  'inhaler',
  'nebuliser_solution',
  'powder',
  'sachet',
  'suppository',
  'spray',
  'patch',
  'device',
  'other',
]

export const SCHEDULES: DrugSchedule[] = ['otc', 'rx', 'controlled']

/** Default stock unit for each dosage form; the user can change it. */
export const DEFAULT_UNIT: Partial<Record<DosageForm, string>> = {
  tablet: 'tablet',
  capsule: 'capsule',
  syrup: 'bottle',
  suspension: 'bottle',
  solution: 'bottle',
  injection: 'ampoule',
  infusion: 'bag',
  drops: 'bottle',
  cream: 'tube',
  ointment: 'tube',
  gel: 'tube',
  lotion: 'bottle',
  inhaler: 'inhaler',
  nebuliser_solution: 'ampoule',
  powder: 'pack',
  sachet: 'sachet',
  suppository: 'piece',
  spray: 'bottle',
  patch: 'patch',
}

export interface MedicineRow {
  id: string
  brandName: string
  genericName: string | null
  manufacturerName: string | null
  dosageForm: DosageForm
  strength: string | null
  baseUnitLabel: string
  schedule: DrugSchedule
  loyaltyEligible: boolean
  sku: string | null
  notes: string | null
  isActive: boolean
  barcodes: string[]
  rackLocation: string | null
  reorderLevel: number
}

export const PAGE_SIZE = 50

/** Removes characters that have meaning inside a PostgREST or() filter or an ilike pattern. */
export function sanitizeSearch(q: string): string {
  return q
    .replace(/[,()*%\\:"']/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 60)
}

export async function listMedicines(params: {
  organizationId: string
  branchId: string
  query: string
  page: number
  includeInactive: boolean
}): Promise<{ rows: MedicineRow[]; total: number }> {
  const q = sanitizeSearch(params.query)
  let request = supabase
    .from('medicines')
    .select(
      'id, brand_name, strength, dosage_form, schedule, base_unit_label, loyalty_eligible, sku, notes, is_active, generics(name), manufacturers(name), medicine_barcodes(barcode, pack_id)',
      { count: 'exact' },
    )
    .eq('organization_id', params.organizationId)
    .order('brand_name')
    .range(params.page * PAGE_SIZE, params.page * PAGE_SIZE + PAGE_SIZE - 1)
  if (!params.includeInactive) request = request.eq('is_active', true)

  if (q.length > 0) {
    const generics = await supabase
      .from('generics')
      .select('id')
      .eq('organization_id', params.organizationId)
      .ilike('name', `%${q}%`)
      .limit(100)
    if (generics.error) throw toAppError(generics.error)
    const filters = [`brand_name.ilike.*${q}*`, `sku.eq.${q}`]
    const ids = generics.data.map((g) => g.id)
    if (ids.length > 0) filters.push(`generic_id.in.(${ids.join(',')})`)
    request = request.or(filters.join(','))
  }

  const { data, error, count } = await request
  if (error) throw toAppError(error)
  const medicineIds = data.map((m) => m.id)

  const settings = new Map<string, { rack: string | null; reorder: number }>()
  if (medicineIds.length > 0) {
    const res = await supabase
      .from('branch_medicine_settings')
      .select('medicine_id, rack_location, reorder_level')
      .eq('branch_id', params.branchId)
      .in('medicine_id', medicineIds)
    if (res.error) throw toAppError(res.error)
    for (const s of res.data) {
      settings.set(s.medicine_id, { rack: s.rack_location, reorder: s.reorder_level })
    }
  }

  return {
    total: count ?? 0,
    rows: data.map((m) => ({
      id: m.id,
      brandName: m.brand_name,
      genericName: m.generics?.name ?? null,
      manufacturerName: m.manufacturers?.name ?? null,
      dosageForm: m.dosage_form,
      strength: m.strength,
      baseUnitLabel: m.base_unit_label,
      schedule: m.schedule,
      loyaltyEligible: m.loyalty_eligible,
      sku: m.sku,
      notes: m.notes,
      isActive: m.is_active,
      barcodes: m.medicine_barcodes.filter((b) => !b.pack_id).map((b) => b.barcode),
      rackLocation: settings.get(m.id)?.rack ?? null,
      reorderLevel: settings.get(m.id)?.reorder ?? 0,
    })),
  }
}

/** Distinct names for the generic / manufacturer suggestion lists. */
export async function listNames(
  table: 'generics' | 'manufacturers',
  organizationId: string,
): Promise<string[]> {
  const { data, error } = await supabase
    .from(table)
    .select('name')
    .eq('organization_id', organizationId)
    .eq('is_active', true)
    .order('name')
    .limit(2000)
  if (error) throw toAppError(error)
  return data.map((r) => r.name)
}
