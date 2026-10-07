import { MoneyError, parseTaka, type Paisa } from '@/domain/money'

/**
 * Draft line of a goods receipt or opening-stock load, kept as the raw strings the user typed so the
 * form never loses input. All quantities are in the medicine's base unit (tablet, bottle...), all
 * prices per base unit. The database validates and recomputes everything again.
 */
export interface DraftLine {
  key: string
  medicineId: string
  brandName: string
  strength: string | null
  unit: string
  batchNo: string
  /** YYYY-MM as typed in a month input; stock expires on the last day of that month. */
  expiryMonth: string
  quantity: string
  bonus: string
  unitCost: string
  mrp: string
  salePrice: string
}

export type LineField =
  'batchNo' | 'expiryMonth' | 'quantity' | 'bonus' | 'unitCost' | 'mrp' | 'salePrice'
export type LineErrors = Partial<Record<LineField, string>>

export interface ValidLine {
  medicineId: string
  batchNo: string
  expiryDate: string
  quantity: number
  bonus: number
  unitCostPaisa: Paisa
  mrpPaisa: Paisa
  salePricePaisa: Paisa
}

/** "2027-03" -> "2027-03-31" (last day of the month, the convention for printed expiry dates). */
export function monthToExpiryDate(month: string): string | null {
  const m = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(month)
  if (!m) return null
  const year = Number(m[1])
  const monthIndex = Number(m[2])
  const lastDay = new Date(Date.UTC(year, monthIndex, 0)).getUTCDate()
  return `${m[1]}-${m[2]}-${String(lastDay).padStart(2, '0')}`
}

function parseCount(value: string, allowZero: boolean): number | null {
  const v = value.trim()
  if (v === '') return allowZero ? 0 : null
  if (!/^\d{1,7}$/.test(v)) return null
  const n = Number(v)
  return n > 0 || allowZero ? n : null
}

function parseMoney(value: string): Paisa | null {
  try {
    return parseTaka(value)
  } catch (e) {
    if (e instanceof MoneyError) return null
    throw e
  }
}

/**
 * Validates one line against the same rules as app.validate_batch_input. `today` is the business date
 * (YYYY-MM-DD); stock must expire after it. Returns error keys (i18n) or a typed line.
 */
export function validateLine(
  line: DraftLine,
  today: string,
): { ok: true; line: ValidLine } | { ok: false; errors: LineErrors } {
  const errors: LineErrors = {}
  const batchNo = line.batchNo.trim()
  if (batchNo === '' || batchNo.length > 60) errors.batchNo = 'purchases.err.batch'

  const expiryDate = monthToExpiryDate(line.expiryMonth)
  if (!expiryDate) errors.expiryMonth = 'purchases.err.expiry'
  else if (expiryDate <= today) errors.expiryMonth = 'purchases.err.expired'

  const quantity = parseCount(line.quantity, false)
  if (quantity === null) errors.quantity = 'purchases.err.quantity'
  const bonus = parseCount(line.bonus, true)
  if (bonus === null) errors.bonus = 'purchases.err.bonus'

  const unitCost = parseMoney(line.unitCost)
  if (unitCost === null || unitCost < 0) errors.unitCost = 'purchases.err.money'
  const mrp = parseMoney(line.mrp)
  if (mrp === null || mrp <= 0) errors.mrp = 'purchases.err.money'
  const salePrice = line.salePrice.trim() === '' ? mrp : parseMoney(line.salePrice)
  if (salePrice === null || salePrice <= 0) errors.salePrice = 'purchases.err.money'
  else if (mrp !== null && salePrice > mrp) errors.salePrice = 'purchases.err.aboveMrp'

  if (
    Object.keys(errors).length > 0 ||
    expiryDate === null ||
    quantity === null ||
    bonus === null ||
    unitCost === null ||
    mrp === null ||
    salePrice === null
  ) {
    return { ok: false, errors }
  }
  return {
    ok: true,
    line: {
      medicineId: line.medicineId,
      batchNo,
      expiryDate,
      quantity,
      bonus,
      unitCostPaisa: unitCost,
      mrpPaisa: mrp,
      salePricePaisa: salePrice,
    },
  }
}

/** Line cost (paid quantity x unit cost) in paisa, or null while the line is incomplete. */
export function lineTotal(line: DraftLine): number | null {
  const quantity = parseCount(line.quantity, false)
  const cost = parseMoney(line.unitCost)
  if (quantity === null || cost === null) return null
  return quantity * cost
}

export function subtotal(lines: DraftLine[]): number {
  return lines.reduce((sum, l) => sum + (lineTotal(l) ?? 0), 0)
}

/** Duplicate medicine + batch pairs are rejected by receive_goods; flag them in the form first. */
export function duplicateKeys(lines: DraftLine[]): Set<string> {
  const seen = new Map<string, string>()
  const dupes = new Set<string>()
  for (const l of lines) {
    const id = `${l.medicineId}|${l.batchNo.trim().toLowerCase()}`
    if (l.batchNo.trim() === '') continue
    const first = seen.get(id)
    if (first) {
      dupes.add(first)
      dupes.add(l.key)
    } else seen.set(id, l.key)
  }
  return dupes
}

export function toReceiveItems(lines: ValidLine[]) {
  return lines.map((l) => ({
    medicine_id: l.medicineId,
    batch_no: l.batchNo,
    expiry_date: l.expiryDate,
    quantity: l.quantity,
    bonus_quantity: l.bonus,
    unit_cost_paisa: l.unitCostPaisa,
    mrp_paisa: l.mrpPaisa,
    sale_price_paisa: l.salePricePaisa,
  }))
}

/** Opening stock has no bonus: bonus units are simply part of the counted quantity. */
export function toOpeningItems(lines: ValidLine[]) {
  return lines.map((l) => ({
    medicine_id: l.medicineId,
    batch_no: l.batchNo,
    expiry_date: l.expiryDate,
    quantity: l.quantity + l.bonus,
    cost_paisa: l.unitCostPaisa,
    mrp_paisa: l.mrpPaisa,
    sale_price_paisa: l.salePricePaisa,
  }))
}
