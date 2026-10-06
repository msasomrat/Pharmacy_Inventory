import { percentOf, paisa, type BasisPoints, type Paisa } from '@/domain/money'

export type Schedule = 'otc' | 'rx' | 'controlled'

export interface CartLine {
  medicineId: string
  name: string
  detail: string
  schedule: Schedule
  /** FEFO price of the next sellable batch, used only until the server quote arrives. */
  unitPricePaisa: number
  stock: number
  quantity: number
  discountBp: BasisPoints
}

export type CartAction =
  | { type: 'add'; line: Omit<CartLine, 'quantity' | 'discountBp'>; quantity?: number }
  | { type: 'setQuantity'; medicineId: string; quantity: number }
  | { type: 'setDiscount'; medicineId: string; discountBp: number }
  | { type: 'remove'; medicineId: string }
  | { type: 'clear' }

const clampQty = (q: number, stock: number) =>
  Math.max(1, Math.min(Math.trunc(q) || 1, Math.max(stock, 1)))

export function cartReducer(lines: CartLine[], action: CartAction): CartLine[] {
  switch (action.type) {
    case 'add': {
      const existing = lines.find((l) => l.medicineId === action.line.medicineId)
      const add = action.quantity ?? 1
      if (existing) {
        return lines.map((l) =>
          l.medicineId === existing.medicineId
            ? { ...l, quantity: clampQty(l.quantity + add, l.stock) }
            : l,
        )
      }
      if (action.line.stock <= 0) return lines
      return [
        ...lines,
        { ...action.line, quantity: clampQty(add, action.line.stock), discountBp: 0 },
      ]
    }
    case 'setQuantity':
      return lines.map((l) =>
        l.medicineId === action.medicineId
          ? { ...l, quantity: clampQty(action.quantity, l.stock) }
          : l,
      )
    case 'setDiscount':
      return lines.map((l) =>
        l.medicineId === action.medicineId
          ? { ...l, discountBp: Math.max(0, Math.min(10_000, Math.round(action.discountBp))) }
          : l,
      )
    case 'remove':
      return lines.filter((l) => l.medicineId !== action.medicineId)
    case 'clear':
      return []
  }
}

export interface Estimate {
  grossPaisa: Paisa
  discountPaisa: Paisa
  totalPaisa: Paisa
}

/** Local estimate (single FEFO price per line). The server quote replaces it as soon as it arrives. */
export function estimate(lines: CartLine[]): Estimate {
  let gross = 0
  let discount = 0
  for (const l of lines) {
    const lineGross = l.unitPricePaisa * l.quantity
    gross += lineGross
    discount += percentOf(paisa(lineGross), l.discountBp)
  }
  return {
    grossPaisa: paisa(gross),
    discountPaisa: paisa(discount),
    totalPaisa: paisa(gross - discount),
  }
}

export function needsPrescription(lines: CartLine[]): boolean {
  return lines.some((l) => l.schedule === 'controlled')
}

/** Payload for create_sale / quote_sale. Percent input is converted to basis points. */
export function toSaleItems(
  lines: CartLine[],
): { medicine_id: string; quantity: number; discount_bp: number }[] {
  return lines.map((l) => ({
    medicine_id: l.medicineId,
    quantity: l.quantity,
    discount_bp: l.discountBp,
  }))
}
