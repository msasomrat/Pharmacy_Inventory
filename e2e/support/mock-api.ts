import type { Page, Route } from '@playwright/test'

/**
 * Deterministic in-browser backend for UI tests: a signed-in owner (aal2) and canned responses for
 * the PostgREST endpoints and RPCs the screens use. Database behaviour itself is covered by pgTAP.
 */
export const SUPABASE_URL = 'http://127.0.0.1:54321'
const ORG = '11111111-1111-4111-8111-111111111111'
const BRANCH = '22222222-2222-4222-8222-222222222222'
const USER = '33333333-3333-4333-8333-333333333333'

function base64url(value: object): string {
  return Buffer.from(JSON.stringify(value)).toString('base64url')
}

export function fakeSession(aal: 'aal1' | 'aal2' = 'aal2') {
  const exp = Math.floor(Date.now() / 1000) + 3600 * 24
  const token = `${base64url({ alg: 'HS256', typ: 'JWT' })}.${base64url({
    sub: USER,
    role: 'authenticated',
    aal,
    amr: [
      { method: 'password', timestamp: exp - 10 },
      ...(aal === 'aal2' ? [{ method: 'totp', timestamp: exp - 5 }] : []),
    ],
    exp,
    email: 'rahima@shefa.example',
  })}.c2lnbmF0dXJl`
  return {
    access_token: token,
    token_type: 'bearer',
    expires_in: 3600 * 24,
    expires_at: exp,
    refresh_token: 'refresh',
    user: {
      id: USER,
      aud: 'authenticated',
      role: 'authenticated',
      email: 'rahima@shefa.example',
      app_metadata: {},
      user_metadata: { full_name: 'Rahima' },
      created_at: '2026-01-01T00:00:00Z',
      factors: [
        {
          id: 'f1',
          factor_type: 'totp',
          status: 'verified',
          created_at: '2026-01-01T00:00:00Z',
          updated_at: '2026-01-01T00:00:00Z',
        },
      ],
    },
  }
}

function dayOffset(days: number): string {
  const d = new Date(Date.now() + 6 * 3600_000) // Asia/Dhaka business date
  d.setUTCDate(d.getUTCDate() + days)
  return d.toISOString().slice(0, 10)
}

const SALES = [
  182400, 205300, 171900, 228700, 241200, 199800, 263500, 251100, 238900, 274600, 289300, 266200,
  301800, 318450,
]

export const MEDICINES = [
  {
    medicine_id: 'm-napa',
    brand_name: 'Napa',
    generic_name: 'Paracetamol',
    manufacturer_name: 'Beximco',
    dosage_form: 'tablet',
    strength: '500 mg',
    schedule: 'otc',
    base_unit_label: 'tablet',
    stock_quantity: 840,
    sale_price_paisa: 120,
    nearest_expiry: dayOffset(210),
  },
  {
    medicine_id: 'm-napa-extra',
    brand_name: 'Napa Extra',
    generic_name: 'Paracetamol + Caffeine',
    manufacturer_name: 'Beximco',
    dosage_form: 'tablet',
    strength: '500/65 mg',
    schedule: 'otc',
    base_unit_label: 'tablet',
    stock_quantity: 320,
    sale_price_paisa: 250,
    nearest_expiry: dayOffset(150),
  },
  {
    medicine_id: 'm-seclo',
    brand_name: 'Seclo',
    generic_name: 'Omeprazole',
    manufacturer_name: 'Square',
    dosage_form: 'capsule',
    strength: '20 mg',
    schedule: 'rx',
    base_unit_label: 'capsule',
    stock_quantity: 410,
    sale_price_paisa: 700,
    nearest_expiry: dayOffset(400),
  },
  {
    medicine_id: 'm-sedil',
    brand_name: 'Sedil',
    generic_name: 'Diazepam',
    manufacturer_name: 'Square',
    dosage_form: 'tablet',
    strength: '5 mg',
    schedule: 'controlled',
    base_unit_label: 'tablet',
    stock_quantity: 60,
    sale_price_paisa: 300,
    nearest_expiry: dayOffset(300),
  },
  {
    medicine_id: 'm-ace',
    brand_name: 'Ace',
    generic_name: 'Paracetamol',
    manufacturer_name: 'Square',
    dosage_form: 'tablet',
    strength: '500 mg',
    schedule: 'otc',
    base_unit_label: 'tablet',
    stock_quantity: 0,
    sale_price_paisa: 120,
    nearest_expiry: null,
  },
]

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) })

export async function mockBackend(
  page: Page,
  options: { signedIn?: boolean; aal?: 'aal1' | 'aal2' } = {},
) {
  const { signedIn = true, aal = 'aal2' } = options
  if (signedIn) {
    await page.addInitScript((session) => {
      window.localStorage.setItem('sb-127-auth-token', JSON.stringify(session))
    }, fakeSession(aal))
  }

  await page.route(`${SUPABASE_URL}/auth/v1/**`, (route) => json(route, fakeSession(aal).user))
  await page.route(`${SUPABASE_URL}/rest/v1/memberships*`, (route) =>
    json(route, [
      { organization_id: ORG, role: 'owner', organizations: { name: 'Shefa Pharmacy' } },
    ]),
  )
  await page.route(`${SUPABASE_URL}/rest/v1/branches*`, (route) =>
    json(route, [
      { id: BRANCH, organization_id: ORG, code: 'MPR', name: 'Mohammadpur' },
      {
        id: '44444444-4444-4444-8444-444444444444',
        organization_id: ORG,
        code: 'DHN',
        name: 'Dhanmondi',
      },
    ]),
  )
  await page.route(`${SUPABASE_URL}/rest/v1/branch_assignments*`, (route) => json(route, []))

  await page.route(`${SUPABASE_URL}/rest/v1/rpc/**`, async (route) => {
    const fn = new URL(route.request().url()).pathname.split('/').pop() ?? ''
    const body = (route.request().postDataJSON() ?? {}) as Record<string, unknown>
    switch (fn) {
      case 'report_sales_summary':
        return json(
          route,
          SALES.map((net, i) => ({
            branch_id: BRANCH,
            branch_name: 'Mohammadpur',
            business_date: dayOffset(i - 13),
            sales_count: Math.round(net / 2400),
            gross_paisa: Math.round(net * 1.04),
            discount_paisa: Math.round(net * 0.04),
            loyalty_discount_paisa: Math.round(net * 0.01),
            net_sales_paisa: net,
            returns_paisa: 0,
            voided_paisa: 0,
            credit_sales_paisa: 0,
            cost_paisa: Math.round(net * 0.78),
            gross_profit_paisa: Math.round(net * 0.22),
          })),
        )
      case 'report_expiring_stock':
        return json(route, [
          {
            batch_id: 'b1',
            medicine_id: 'm-x',
            brand_name: 'Maxpro 20',
            batch_no: 'MX2401',
            expiry_date: dayOffset(9),
            days_left: 9,
            quantity_on_hand: 42,
            stock_value_mrp_paisa: 29400,
            stock_value_cost_paisa: 23000,
          },
          {
            batch_id: 'b2',
            medicine_id: 'm-y',
            brand_name: 'Fexo 120',
            batch_no: 'FX9921',
            expiry_date: dayOffset(23),
            days_left: 23,
            quantity_on_hand: 60,
            stock_value_mrp_paisa: 54000,
            stock_value_cost_paisa: 41000,
          },
          {
            batch_id: 'b3',
            medicine_id: 'm-z',
            brand_name: 'Ceevit',
            batch_no: 'CV7713',
            expiry_date: dayOffset(51),
            days_left: 51,
            quantity_on_hand: 150,
            stock_value_mrp_paisa: 30000,
            stock_value_cost_paisa: 22000,
          },
        ])
      case 'report_low_stock':
        return json(route, [
          {
            medicine_id: 'm-a',
            brand_name: 'Monas 10',
            generic_name: 'Montelukast',
            reorder_level: 60,
            sellable_quantity: 14,
            rack_location: 'B-3',
          },
          {
            medicine_id: 'm-b',
            brand_name: 'Losectil 20',
            generic_name: 'Omeprazole',
            reorder_level: 100,
            sellable_quantity: 30,
            rack_location: 'A-1',
          },
          {
            medicine_id: 'm-c',
            brand_name: 'Alatrol',
            generic_name: 'Cetirizine',
            reorder_level: 80,
            sellable_quantity: 0,
            rack_location: null,
          },
        ])
      case 'search_medicines': {
        const q = (typeof body.p_query === 'string' ? body.p_query : '').toLowerCase()
        return json(
          route,
          MEDICINES.filter((m) => `${m.brand_name} ${m.generic_name}`.toLowerCase().includes(q)),
        )
      }
      case 'quote_sale':
      case 'create_sale': {
        const items = (body.p_items ?? []) as {
          medicine_id: string
          quantity: number
          discount_bp: number
        }[]
        let gross = 0
        let discount = 0
        for (const it of items) {
          const price =
            MEDICINES.find((m) => m.medicine_id === it.medicine_id)?.sale_price_paisa ?? 0
          gross += price * it.quantity
          discount += Math.round((price * it.quantity * it.discount_bp) / 10000)
        }
        const loyalty = body.p_loyalty_card_no ? Math.round((gross - discount) * 0.05) : 0
        const total = gross - discount - loyalty
        if (fn === 'quote_sale') {
          return json(route, {
            gross_paisa: gross,
            discount_paisa: discount,
            loyalty_discount_paisa: loyalty,
            rounding_paisa: 0,
            total_paisa: total,
            points_earned: Math.floor(total / 10000),
            lines: [],
          })
        }
        const paid = ((body.p_payments ?? []) as { amount_paisa: number }[]).reduce(
          (s, p) => s + p.amount_paisa,
          0,
        )
        return json(route, {
          sale_id: 's1',
          invoice_no: 'MPR-2627-000128',
          total_paisa: total,
          paid_paisa: paid,
          change_paisa: Math.max(paid - total, 0),
          due_paisa: 0,
          points_earned: Math.floor(total / 10000),
          loyalty_discount_paisa: loyalty,
          replayed: false,
        })
      }
      case 'lookup_loyalty':
        return json(route, [
          {
            card_id: 'c1',
            card_no: '8000000011',
            customer_id: 'cu1',
            customer_name: 'Karim Uddin',
            membership_id: 'lm1',
            plan_name: '6-Month Card',
            starts_on: dayOffset(-30),
            ends_on: dayOffset(150),
            discount_bp: 500,
            points_balance: 37,
          },
        ])
      case 'my_invitations':
        return json(route, [])
      default:
        return json(route, { message: `unmocked rpc ${fn}` }, 404)
    }
  })
}
