import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  CreditCard,
  Minus,
  PackageSearch,
  Plus,
  Search,
  ShoppingBasket,
  Stethoscope,
  Trash2,
  X,
} from 'lucide-react'
import {
  useCallback,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
  type KeyboardEvent,
} from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Kbd } from '@/components/ui/kbd'
import { useWorkspace } from '@/features/org/org-context'
import type { Json } from '@/lib/database.types'
import { useDebounced } from '@/hooks/useDebounced'
import { currentLanguage } from '@/i18n'
import { newRequestId, rpc } from '@/lib/api'
import { cn } from '@/lib/cn'
import { businessDate, formatDate } from '@/lib/dates'
import { errorMessage } from '@/lib/errors'
import { formatNumber } from '@/lib/format'
import { formatTaka, paisa, parseTaka, MoneyError } from '@/domain/money'

import { cartReducer, estimate, needsPrescription, toSaleItems, type CartLine } from './cart'
import { ReceiptDialog, type SaleResult } from './ReceiptDialog'

type Method = 'cash' | 'bkash' | 'nagad' | 'card'
const METHODS: Method[] = ['cash', 'bkash', 'nagad', 'card']

interface Quote {
  gross_paisa: number
  discount_paisa: number
  loyalty_discount_paisa: number
  rounding_paisa: number
  total_paisa: number
  points_earned: number
}

interface Member {
  card_no: string
  customer_name: string
  plan_name: string | null
  discount_bp: number | null
  points_balance: number
  membership_id: string | null
}

export function PosPage() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const tk = (p: number) => formatTaka(paisa(p), lng)
  const { org, branch } = useWorkspace()

  const [lines, dispatch] = useReducer(cartReducer, [])
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(0)
  const [method, setMethod] = useState<Method>('cash')
  const [tendered, setTendered] = useState('')
  const [memberInput, setMemberInput] = useState('')
  const [member, setMember] = useState<Member | null>(null)
  const [rx, setRx] = useState({
    patient_name: '',
    doctor_name: '',
    doctor_reg_no: '',
    prescription_date: businessDate(),
  })
  const [completed, setCompleted] = useState<{ sale: SaleResult; lines: CartLine[] } | null>(null)
  const requestId = useRef(newRequestId())
  const searchRef = useRef<HTMLInputElement>(null)

  const queryClient = useQueryClient()
  const term = useDebounced(query.trim(), 150)
  const searchOptions = useCallback(
    (q: string) => ({
      queryKey: ['search_medicines', branch.id, q],
      queryFn: () => rpc('search_medicines', { p_branch_id: branch.id, p_query: q, p_limit: 12 }),
      staleTime: 5_000,
    }),
    [branch.id],
  )
  const results = useQuery({ ...searchOptions(term), enabled: term.length >= 2 })
  const items = useMemo(() => (term.length >= 2 ? (results.data ?? []) : []), [results.data, term])

  const needsRx = needsPrescription(lines)
  const prescription = needsRx ? rx : null
  const quoteKey = useDebounced(
    JSON.stringify({ items: toSaleItems(lines), card: member?.card_no ?? null, rx: prescription }),
    300,
  )
  const quote = useQuery({
    queryKey: ['quote_sale', branch.id, quoteKey],
    queryFn: async () => {
      const q = JSON.parse(quoteKey) as { items: Json; card: string | null; rx: typeof rx | null }
      return (await rpc('quote_sale', {
        p_branch_id: branch.id,
        p_items: q.items,
        ...(q.card ? { p_loyalty_card_no: q.card } : {}),
        ...(q.rx ? { p_prescription: q.rx } : {}),
      })) as unknown as Quote
    },
    enabled: lines.length > 0,
    retry: false,
    placeholderData: (prev) => prev,
  })

  const est = estimate(lines)
  const exact = quote.data && !quote.isPlaceholderData && !quote.isError ? quote.data : null
  const total = exact?.total_paisa ?? est.totalPaisa
  let tenderedPaisa: number | null = null
  try {
    tenderedPaisa = tendered.trim() ? parseTaka(tendered) : null
  } catch (e) {
    if (!(e instanceof MoneyError)) throw e
  }
  const change =
    method === 'cash' && tenderedPaisa !== null ? Math.max(tenderedPaisa - total, 0) : 0

  type SearchRow = (typeof items)[number]
  const addRow = useCallback(
    (r: SearchRow | undefined) => {
      if (!r) return
      if (r.stock_quantity <= 0) {
        toast.error(t('pos.outOfStock'))
        return
      }
      dispatch({
        type: 'add',
        line: {
          medicineId: r.medicine_id,
          name: r.brand_name,
          detail: [r.strength, r.generic_name].filter(Boolean).join(' · '),
          schedule: r.schedule,
          unitPricePaisa: r.sale_price_paisa,
          stock: r.stock_quantity,
        },
      })
      setQuery('')
      setActive(0)
      searchRef.current?.focus()
    },
    [t],
  )

  // Enter must work even before the debounced search returns (barcode scanners type + Enter instantly).
  const addFromSearch = useCallback(async () => {
    const q = query.trim()
    if (q.length < 2) return
    if (q === term && results.data) {
      addRow(results.data[active])
      return
    }
    try {
      const rows = await queryClient.query(searchOptions(q))
      if (rows.length === 0) toast.error(t('pos.noResults'))
      else addRow(rows[0])
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }, [query, term, results.data, active, addRow, queryClient, searchOptions, t])

  const lookup = useMutation({
    mutationFn: () =>
      rpc('lookup_loyalty', {
        p_organization_id: org.organizationId,
        p_card_or_phone: memberInput,
      }),
    onSuccess: (rows) => {
      const m = rows[0]
      if (!m?.membership_id) {
        toast.error(t('errors.loyalty_inactive'))
        setMember(null)
        return
      }
      setMember(m)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const reset = useCallback(() => {
    dispatch({ type: 'clear' })
    setMember(null)
    setMemberInput('')
    setTendered('')
    setMethod('cash')
    setRx({
      patient_name: '',
      doctor_name: '',
      doctor_reg_no: '',
      prescription_date: businessDate(),
    })
    requestId.current = newRequestId()
    searchRef.current?.focus()
  }, [])

  const complete = useMutation({
    mutationFn: () => {
      const amount = method === 'cash' ? (tenderedPaisa ?? total) : total
      return rpc('create_sale', {
        p_branch_id: branch.id,
        p_items: toSaleItems(lines),
        p_payments: [{ method, amount_paisa: amount }],
        p_client_request_id: requestId.current,
        ...(member ? { p_loyalty_card_no: member.card_no } : {}),
        ...(prescription ? { p_prescription: prescription } : {}),
      }) as unknown as Promise<SaleResult>
    },
    onSuccess: (sale) => {
      setCompleted({ sale, lines })
      reset()
    },
    // The same request id is kept, so retrying after a network error can never double-sell.
    onError: (e) => toast.error(errorMessage(e)),
  })

  const canComplete =
    lines.length > 0 &&
    !complete.isPending &&
    (!needsRx ||
      (rx.patient_name.trim().length > 1 &&
        rx.doctor_name.trim().length > 1 &&
        rx.doctor_reg_no.trim().length > 1)) &&
    (method !== 'cash' || tenderedPaisa === null || tenderedPaisa >= total)

  useEffect(() => {
    function onKey(e: globalThis.KeyboardEvent) {
      if (e.key === 'F2') {
        e.preventDefault()
        searchRef.current?.focus()
      } else if (e.key === 'F9') {
        e.preventDefault()
        if (canComplete) complete.mutate()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
    }
  }, [canComplete, complete])

  function onSearchKey(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActive((a) => Math.min(a + 1, Math.max(items.length - 1, 0)))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((a) => Math.max(a - 1, 0))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      void addFromSearch()
    } else if (e.key === 'Escape') {
      setQuery('')
    }
  }

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_440px]">
      {/* Search */}
      <section aria-labelledby="pos-search" className="flex min-w-0 flex-col gap-4">
        <div className="flex items-center justify-between">
          <h1 id="pos-search" className="text-2xl font-semibold tracking-tight">
            {t('pos.title')}
          </h1>
          <p className="hidden items-center gap-2 text-xs text-muted-foreground sm:flex">
            {t('pos.shortcuts')}: <Kbd>F2</Kbd> search <Kbd>↑↓</Kbd> <Kbd>Enter</Kbd> add{' '}
            <Kbd>F9</Kbd> complete
          </p>
        </div>
        <div className="relative">
          <Search
            className="pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-muted-foreground"
            aria-hidden
          />
          <Input
            ref={searchRef}
            // eslint-disable-next-line jsx-a11y/no-autofocus -- the counter screen starts in search, like a barcode scanner
            autoFocus
            value={query}
            onChange={(e) => {
              setQuery(e.target.value)
              setActive(0)
            }}
            onKeyDown={onSearchKey}
            placeholder={t('pos.search')}
            aria-label={t('pos.search')}
            role="combobox"
            aria-expanded={items.length > 0}
            aria-controls="pos-results"
            aria-activedescendant={items[active] ? `pos-result-${active}` : undefined}
            className="h-14 rounded-xl pl-12 text-base shadow-card"
          />
        </div>

        <Card className="min-h-[24rem] overflow-hidden">
          {term.length < 2 ? (
            <EmptyState icon={PackageSearch} title={t('pos.searchHint')} />
          ) : results.isPending ? (
            <div className="space-y-2 p-4">
              {Array.from({ length: 5 }, (_, i) => (
                <div key={i} className="h-14 animate-pulse rounded-md bg-surface-muted" />
              ))}
            </div>
          ) : items.length === 0 ? (
            <EmptyState icon={PackageSearch} title={t('pos.noResults')} />
          ) : (
            <div id="pos-results" role="listbox" aria-label={t('pos.search')} className="divide-y">
              {items.map((r, i) => (
                // Keyboard users drive this list from the search box (aria-activedescendant combobox pattern).
                // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/interactive-supports-focus
                <div
                  key={r.medicine_id}
                  id={`pos-result-${i}`}
                  role="option"
                  aria-selected={i === active}
                  aria-disabled={r.stock_quantity <= 0}
                  onMouseEnter={() => setActive(i)}
                  onClick={() => addRow(r)}
                  className={cn(
                    'flex cursor-pointer items-center gap-4 px-4 py-3 transition-colors',
                    i === active && 'bg-primary-soft/60',
                    r.stock_quantity <= 0 && 'cursor-not-allowed opacity-55',
                  )}
                >
                  <div className="grid size-10 shrink-0 place-items-center rounded-lg bg-surface-muted text-xs font-semibold text-muted-foreground uppercase">
                    {r.dosage_form.slice(0, 3)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="flex items-center gap-2 font-medium">
                      <span className="truncate">{r.brand_name}</span>
                      <span className="text-sm font-normal text-muted-foreground">
                        {r.strength}
                      </span>
                      {r.schedule !== 'otc' ? (
                        <Badge tone={r.schedule === 'controlled' ? 'danger' : 'info'}>
                          {t(`pos.schedule.${r.schedule}`)}
                        </Badge>
                      ) : null}
                    </p>
                    <p className="truncate text-xs text-muted-foreground">
                      {[r.generic_name, r.manufacturer_name].filter(Boolean).join(' · ')}
                      {r.nearest_expiry
                        ? ` · ${t('pos.exp', { date: formatDate(r.nearest_expiry, lng) })}`
                        : ''}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="tabular font-semibold">
                      {r.sale_price_paisa ? tk(r.sale_price_paisa) : '—'}
                    </p>
                    <p
                      className={cn(
                        'text-xs',
                        r.stock_quantity > 0 ? 'text-success' : 'text-danger',
                      )}
                    >
                      {r.stock_quantity > 0
                        ? t('pos.inStock', {
                            count: r.stock_quantity,
                            n: formatNumber(r.stock_quantity, lng),
                          })
                        : t('pos.outOfStock')}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </section>

      {/* Bill */}
      <aside aria-labelledby="pos-cart" className="xl:sticky xl:top-22 xl:self-start">
        <Card className="flex flex-col">
          <div className="flex items-center justify-between border-b px-5 py-4">
            <h2 id="pos-cart" className="flex items-center gap-2 font-semibold">
              <ShoppingBasket className="size-5 text-primary" aria-hidden />
              {t('pos.cart')}
              {lines.length > 0 ? <Badge tone="primary">{lines.length}</Badge> : null}
            </h2>
            {lines.length > 0 ? (
              <Button variant="ghost" size="sm" onClick={reset}>
                {t('pos.clear')}
              </Button>
            ) : null}
          </div>

          <div className="max-h-[38vh] overflow-y-auto">
            {lines.length === 0 ? (
              <EmptyState
                icon={ShoppingBasket}
                title={t('pos.emptyCart')}
                description={t('pos.emptyCartBody')}
              />
            ) : (
              <ul className="divide-y">
                {lines.map((l) => (
                  <li key={l.medicineId} className="grid gap-2 px-5 py-3">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{l.name}</p>
                        <p className="truncate text-xs text-muted-foreground">{l.detail}</p>
                      </div>
                      <button
                        type="button"
                        onClick={() => dispatch({ type: 'remove', medicineId: l.medicineId })}
                        className="rounded p-1 text-muted-foreground hover:bg-danger-soft hover:text-danger"
                        aria-label={t('pos.remove', { name: l.name })}
                      >
                        <Trash2 className="size-4" aria-hidden />
                      </button>
                    </div>
                    <div className="flex items-center gap-3">
                      <div className="flex items-center rounded-md border">
                        <button
                          type="button"
                          className="grid size-8 place-items-center hover:bg-surface-muted"
                          onClick={() =>
                            dispatch({
                              type: 'setQuantity',
                              medicineId: l.medicineId,
                              quantity: l.quantity - 1,
                            })
                          }
                          aria-label={`− ${l.name}`}
                        >
                          <Minus className="size-3.5" aria-hidden />
                        </button>
                        <input
                          className="tabular h-8 w-12 border-x bg-transparent text-center text-sm outline-none"
                          inputMode="numeric"
                          value={l.quantity}
                          aria-label={`${t('pos.qty')} ${l.name}`}
                          onChange={(e) =>
                            dispatch({
                              type: 'setQuantity',
                              medicineId: l.medicineId,
                              quantity: Number(e.target.value),
                            })
                          }
                        />
                        <button
                          type="button"
                          className="grid size-8 place-items-center hover:bg-surface-muted"
                          onClick={() =>
                            dispatch({
                              type: 'setQuantity',
                              medicineId: l.medicineId,
                              quantity: l.quantity + 1,
                            })
                          }
                          aria-label={`+ ${l.name}`}
                        >
                          <Plus className="size-3.5" aria-hidden />
                        </button>
                      </div>
                      <label className="flex items-center gap-1 text-xs text-muted-foreground">
                        {t('pos.discount')}
                        <input
                          className="tabular h-8 w-14 rounded-md border bg-transparent px-2 text-right text-sm text-foreground outline-none focus:border-primary"
                          inputMode="decimal"
                          value={l.discountBp ? l.discountBp / 100 : ''}
                          placeholder="0"
                          onChange={(e) =>
                            dispatch({
                              type: 'setDiscount',
                              medicineId: l.medicineId,
                              discountBp: Number(e.target.value) * 100,
                            })
                          }
                        />
                      </label>
                      <span className="tabular ml-auto text-sm font-medium">
                        {tk(l.unitPricePaisa * l.quantity)}
                      </span>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="grid gap-4 border-t px-5 py-4">
            {/* Loyalty */}
            <div className="grid gap-1.5">
              <label htmlFor="member" className="text-xs font-medium text-muted-foreground">
                {t('pos.customer')}
              </label>
              {member ? (
                <div className="flex items-center justify-between rounded-md bg-primary-soft px-3 py-2 text-sm text-primary-soft-foreground">
                  <div className="flex items-center gap-2">
                    <CreditCard className="size-4" aria-hidden />
                    <div>
                      <p className="font-medium">{member.customer_name}</p>
                      <p className="text-xs">
                        {t('pos.member', {
                          plan: member.plan_name ?? '',
                          discount: (member.discount_bp ?? 0) / 100,
                          points: member.points_balance,
                        })}
                      </p>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => setMember(null)}
                    aria-label="Remove card"
                    className="rounded p-1 hover:bg-primary/10"
                  >
                    <X className="size-4" aria-hidden />
                  </button>
                </div>
              ) : (
                <form
                  className="flex gap-2"
                  onSubmit={(e) => {
                    e.preventDefault()
                    if (memberInput.trim()) lookup.mutate()
                  }}
                >
                  <Input
                    id="member"
                    value={memberInput}
                    onChange={(e) => setMemberInput(e.target.value)}
                    placeholder={t('pos.customerPlaceholder')}
                  />
                  <Button type="submit" variant="secondary" loading={lookup.isPending}>
                    {t('pos.apply')}
                  </Button>
                </form>
              )}
            </div>

            {needsRx ? (
              <fieldset className="grid gap-3 rounded-lg border border-danger/30 bg-danger-soft/40 p-3">
                <legend className="flex items-center gap-2 px-1 text-sm font-medium text-danger">
                  <Stethoscope className="size-4" aria-hidden />
                  {t('pos.prescription')}
                </legend>
                <div className="grid grid-cols-2 gap-2">
                  <Field id="rx-patient" label={t('pos.patientName')}>
                    <Input
                      id="rx-patient"
                      value={rx.patient_name}
                      onChange={(e) => setRx({ ...rx, patient_name: e.target.value })}
                    />
                  </Field>
                  <Field id="rx-doctor" label={t('pos.doctorName')}>
                    <Input
                      id="rx-doctor"
                      value={rx.doctor_name}
                      onChange={(e) => setRx({ ...rx, doctor_name: e.target.value })}
                    />
                  </Field>
                  <Field id="rx-reg" label={t('pos.doctorReg')}>
                    <Input
                      id="rx-reg"
                      value={rx.doctor_reg_no}
                      onChange={(e) => setRx({ ...rx, doctor_reg_no: e.target.value })}
                    />
                  </Field>
                  <Field id="rx-date" label={t('pos.prescriptionDate')}>
                    <Input
                      id="rx-date"
                      type="date"
                      value={rx.prescription_date}
                      max={businessDate()}
                      onChange={(e) => setRx({ ...rx, prescription_date: e.target.value })}
                    />
                  </Field>
                </div>
              </fieldset>
            ) : null}

            {/* Totals */}
            <dl className="tabular grid gap-1.5 text-sm">
              <div className="flex justify-between text-muted-foreground">
                <dt>{t('pos.subtotal')}</dt>
                <dd>{tk(exact?.gross_paisa ?? est.grossPaisa)}</dd>
              </div>
              {(exact?.discount_paisa ?? est.discountPaisa) > 0 ? (
                <div className="flex justify-between text-muted-foreground">
                  <dt>{t('pos.lineDiscounts')}</dt>
                  <dd>−{tk(exact?.discount_paisa ?? est.discountPaisa)}</dd>
                </div>
              ) : null}
              {exact && exact.loyalty_discount_paisa > 0 ? (
                <div className="flex justify-between text-primary">
                  <dt>{t('pos.loyaltyDiscount')}</dt>
                  <dd>−{tk(exact.loyalty_discount_paisa)}</dd>
                </div>
              ) : null}
              <div className="mt-1 flex items-baseline justify-between border-t pt-2">
                <dt className="font-medium">{exact ? t('pos.total') : t('pos.estimated')}</dt>
                <dd className="text-2xl font-semibold tracking-tight">{tk(total)}</dd>
              </div>
              {quote.isError && lines.length > 0 ? (
                <p
                  role="alert"
                  className="rounded-md bg-warning-soft px-2 py-1.5 text-xs text-warning"
                >
                  {errorMessage(quote.error)}
                </p>
              ) : null}
            </dl>

            {/* Payment */}
            <div className="grid gap-2">
              <div
                role="radiogroup"
                aria-label={t('pos.payment')}
                className="grid grid-cols-4 gap-1 rounded-lg bg-surface-muted p-1"
              >
                {METHODS.map((m) => (
                  <button
                    key={m}
                    type="button"
                    role="radio"
                    aria-checked={method === m}
                    onClick={() => setMethod(m)}
                    className={cn(
                      'h-9 rounded-md text-sm font-medium text-muted-foreground transition-colors',
                      method === m && 'bg-surface text-foreground shadow-card',
                    )}
                  >
                    {t(`pos.methods.${m}`)}
                  </button>
                ))}
              </div>
              {method === 'cash' ? (
                <div className="grid grid-cols-2 items-end gap-3">
                  <Field id="tendered" label={t('pos.tendered')}>
                    <Input
                      id="tendered"
                      inputMode="decimal"
                      placeholder={(total / 100).toFixed(0)}
                      value={tendered}
                      onChange={(e) => setTendered(e.target.value)}
                      className="tabular text-right"
                    />
                  </Field>
                  <div className="pb-2 text-right">
                    <p className="text-xs text-muted-foreground">{t('pos.change')}</p>
                    <p className="tabular text-lg font-semibold text-success">{tk(change)}</p>
                  </div>
                </div>
              ) : null}
            </div>

            <Button
              size="lg"
              className="h-14 text-base"
              disabled={!canComplete}
              loading={complete.isPending}
              onClick={() => complete.mutate()}
            >
              {t('pos.complete')} · {tk(total)}
              <Kbd className="ml-1 border-white/30 bg-white/15 text-primary-foreground">F9</Kbd>
            </Button>
            <p className="text-center text-[11px] text-muted-foreground">{t('pos.estimateNote')}</p>
          </div>
        </Card>
      </aside>

      <ReceiptDialog
        sale={completed?.sale ?? null}
        lines={completed?.lines ?? []}
        pharmacy={org.organizationName}
        branch={branch.name}
        onClose={() => {
          setCompleted(null)
          searchRef.current?.focus()
        }}
      />
    </div>
  )
}
