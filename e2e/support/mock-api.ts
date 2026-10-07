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
    rack_location: 'A-3',
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

/** PostgREST list response with the Content-Range header that count: 'exact' reads. */
const list = (route: Route, rows: unknown[]) =>
  route.fulfill({
    status: 200,
    contentType: 'application/json',
    headers: {
      'content-range': `0-${Math.max(rows.length - 1, 0)}/${rows.length}`,
      'access-control-expose-headers': 'content-range',
    },
    body: JSON.stringify(rows),
  })

export const CATALOG = [
  {
    id: 'm-napa',
    brand_name: 'Napa',
    strength: '500 mg',
    dosage_form: 'tablet',
    schedule: 'otc',
    base_unit_label: 'tablet',
    loyalty_eligible: true,
    sku: null,
    notes: null,
    is_active: true,
    generics: { name: 'Paracetamol' },
    manufacturers: { name: 'Beximco' },
    medicine_barcodes: [{ barcode: '8941100500012', pack_id: null }],
  },
  {
    id: 'm-seclo',
    brand_name: 'Seclo',
    strength: '20 mg',
    dosage_form: 'capsule',
    schedule: 'rx',
    base_unit_label: 'capsule',
    loyalty_eligible: true,
    sku: null,
    notes: null,
    is_active: true,
    generics: { name: 'Omeprazole' },
    manufacturers: { name: 'Square' },
    medicine_barcodes: [],
  },
]

export const CUSTOMERS = [
  {
    id: 'cu1',
    name: 'Karim Uddin',
    phone: '+8801811223344',
    address: null,
    notes: null,
    is_active: true,
    credit_limit_paisa: 500000,
  },
  {
    id: 'cu2',
    name: 'Rahim Mia',
    phone: '+8801711000000',
    address: null,
    notes: null,
    is_active: true,
    credit_limit_paisa: 0,
  },
  {
    id: 'cu3',
    name: 'Salma Begum',
    phone: '+8801911000111',
    address: 'Mohammadpur',
    notes: null,
    is_active: true,
    credit_limit_paisa: 0,
  },
]

const PLANS = [
  {
    id: 'pl3',
    name: '3-Month Card',
    duration_months: 3,
    fee_paisa: 10000,
    discount_bp: 500,
    max_discount_per_invoice_paisa: null,
    points_per_100_taka: 1,
    point_value_paisa: 100,
    min_redeem_points: 20,
    is_active: true,
    sort_order: 1,
  },
  {
    id: 'pl6',
    name: '6-Month Card',
    duration_months: 6,
    fee_paisa: 0,
    discount_bp: 0,
    max_discount_per_invoice_paisa: null,
    points_per_100_taka: 0,
    point_value_paisa: 0,
    min_redeem_points: 0,
    is_active: false,
    sort_order: 2,
  },
]

const MEMBERSHIPS = [
  {
    id: 'lm1',
    status: 'active',
    starts_on: dayOffset(-30),
    ends_on: dayOffset(150),
    customer_id: 'cu1',
    customers: { name: 'Karim Uddin', phone: '+8801811223344' },
    loyalty_cards: { id: 'c1', card_no: '8000000011', is_active: true },
    loyalty_plans: { name: '6-Month Card' },
  },
  {
    id: 'lm2',
    status: 'active',
    starts_on: dayOffset(-120),
    ends_on: dayOffset(-30),
    customer_id: 'cu2',
    customers: { name: 'Rahim Mia', phone: '+8801711000000' },
    loyalty_cards: { id: 'c2', card_no: '8000000045', is_active: true },
    loyalty_plans: { name: '3-Month Card' },
  },
]

/** Every RPC call the UI makes, for assertions on what was sent to the server. */
export interface RpcCall {
  fn: string
  body: Record<string, unknown>
}

export async function mockBackend(
  page: Page,
  options: { signedIn?: boolean; aal?: 'aal1' | 'aal2' } = {},
): Promise<RpcCall[]> {
  const { signedIn = true, aal = 'aal2' } = options
  const calls: RpcCall[] = []
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
  await page.route(`${SUPABASE_URL}/rest/v1/medicines*`, (route) => list(route, CATALOG))
  await page.route(`${SUPABASE_URL}/rest/v1/generics*`, (route) =>
    json(route, [
      { id: 'g1', name: 'Paracetamol' },
      { id: 'g2', name: 'Omeprazole' },
    ]),
  )
  await page.route(`${SUPABASE_URL}/rest/v1/manufacturers*`, (route) =>
    json(route, [{ name: 'Beximco' }, { name: 'Square' }]),
  )
  await page.route(`${SUPABASE_URL}/rest/v1/branch_medicine_settings*`, (route) =>
    json(route, [{ medicine_id: 'm-napa', rack_location: 'A-3', reorder_level: 50 }]),
  )
  await page.route(`${SUPABASE_URL}/rest/v1/suppliers*`, (route) =>
    route.request().method() === 'POST'
      ? json(route, { id: 'sup-new' }, 201)
      : json(route, [{ id: 'sup-1', name: 'Beximco Distribution' }]),
  )
  await page.route(`${SUPABASE_URL}/rest/v1/goods_receipts*`, (route) =>
    json(route, [
      {
        id: 'gr-1',
        receipt_no: 'MPR-G2627-000007',
        supplier_invoice_no: 'BX-5521',
        business_date: dayOffset(-2),
        total_paisa: 950000,
        paid_paisa: 500000,
        suppliers: { name: 'Beximco Distribution' },
      },
    ]),
  )
  await page.route(`${SUPABASE_URL}/rest/v1/goods_receipt_items*`, (route) =>
    json(route, [
      {
        id: 'gri-1',
        batch_no: 'NP2401',
        expiry_date: dayOffset(400),
        quantity: 1000,
        bonus_quantity: 50,
        unit_cost_paisa: 95,
        mrp_paisa: 120,
        line_total_paisa: 95000,
        medicines: { brand_name: 'Napa', strength: '500 mg' },
      },
    ]),
  )
  await page.route(`${SUPABASE_URL}/rest/v1/batches*`, (route) =>
    json(route, [
      {
        medicine_id: 'm-napa',
        expiry_date: dayOffset(20),
        quantity_on_hand: 40,
        sale_price_paisa: 120,
        received_at: '2026-01-01T00:00:00Z',
        medicines: { brand_name: 'Napa', strength: '500 mg', base_unit_label: 'tablet' },
      },
      {
        medicine_id: 'm-napa',
        expiry_date: dayOffset(300),
        quantity_on_hand: 800,
        sale_price_paisa: 120,
        received_at: '2026-02-01T00:00:00Z',
        medicines: { brand_name: 'Napa', strength: '500 mg', base_unit_label: 'tablet' },
      },
      {
        medicine_id: 'm-seclo',
        expiry_date: dayOffset(400),
        quantity_on_hand: 410,
        sale_price_paisa: 700,
        received_at: '2026-02-01T00:00:00Z',
        medicines: { brand_name: 'Seclo', strength: '20 mg', base_unit_label: 'capsule' },
      },
    ]),
  )

  // Writes to tables are recorded as calls named "<METHOD> <table>" for assertions.
  const writable = (table: string, rows: (url: URL) => unknown[], single?: unknown) =>
    page.route(`${SUPABASE_URL}/rest/v1/${table}*`, async (route) => {
      const request = route.request()
      const url = new URL(request.url())
      if (request.method() === 'GET') {
        return single !== undefined ? json(route, single) : list(route, rows(url))
      }
      calls.push({
        fn: `${request.method()} ${table}`,
        body: (request.postDataJSON() ?? {}) as Record<string, unknown>,
      })
      if (request.method() === 'POST') return json(route, { id: `${table}-new` }, 201)
      return route.fulfill({ status: 204, body: '' })
    })
  await writable('customers', () => CUSTOMERS)
  await page.route(`${SUPABASE_URL}/rest/v1/customer_balances*`, (route) =>
    json(route, [{ customer_id: 'cu1', balance_paisa: 35000 }]),
  )
  await writable('loyalty_memberships', (url) =>
    // The customers page asks only for current memberships (ends_on >= today).
    url.search.includes('ends_on=gte')
      ? MEMBERSHIPS.filter((m) => m.ends_on >= dayOffset(0))
      : MEMBERSHIPS,
  )
  await writable('loyalty_plans', () => PLANS)
  await writable('organization_settings', () => [], { loyalty_enabled: true })

  await page.route(`${SUPABASE_URL}/rest/v1/rpc/**`, async (route) => {
    const fn = new URL(route.request().url()).pathname.split('/').pop() ?? ''
    const body = (route.request().postDataJSON() ?? {}) as Record<string, unknown>
    calls.push({ fn, body })
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
      case 'save_medicine':
        return json(route, 'm-new')
      case 'receive_goods':
        return json(route, {
          goods_receipt_id: 'gr-2',
          receipt_no: 'MPR-G2627-000008',
          total_paisa: 9500,
          replayed: false,
        })
      case 'enroll_loyalty':
        return json(route, {
          membership_id: 'lm-new',
          card_no: '8000000029',
          starts_on: dayOffset(0),
          ends_on: dayOffset(90),
          fee_paisa: 10000,
          replayed: false,
        })
      case 'cancel_loyalty_membership':
      case 'set_customer_credit_limit':
        return route.fulfill({ status: 204, body: '' })
      case 'replace_loyalty_card':
        return json(route, '8000000037')
      case 'add_opening_stock':
        return json(route, ((body.p_items ?? []) as unknown[]).length)
      default:
        return json(route, { message: `unmocked rpc ${fn}` }, 404)
    }
  })
  return calls
}
