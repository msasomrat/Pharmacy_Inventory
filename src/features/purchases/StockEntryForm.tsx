import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { PackagePlus, Plus, Trash2 } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { formatTaka, MoneyError, paisa, parseTaka } from '@/domain/money'
import { MedicinePicker, type MedicineHit } from '@/features/medicines/MedicinePicker'
import { useWorkspace } from '@/features/org/org-context'
import { roleCan } from '@/features/org/permissions'
import { currentLanguage } from '@/i18n'
import { newRequestId, rpc } from '@/lib/api'
import { cn } from '@/lib/cn'
import { businessDate } from '@/lib/dates'
import { errorMessage, toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

import {
  duplicateKeys,
  lineTotal,
  subtotal,
  toOpeningItems,
  toReceiveItems,
  validateLine,
  type DraftLine,
  type LineErrors,
  type LineField,
  type ValidLine,
} from './lines'
import { SupplierDialog } from './SupplierDialog'

type Mode = 'receive' | 'opening'

/** One grid template for the header and every line on tablets/desktops; lines stack as cards on phones. */
const LINE_GRID =
  'md:grid-cols-[minmax(9rem,1fr)_7.5rem_9rem_5.5rem_5rem_6rem_6rem_6rem_6.5rem_2.5rem] md:gap-x-2'
type PayMethod = 'cash' | 'bkash' | 'nagad' | 'rocket' | 'card' | 'bank_transfer'
const PAY_METHODS: PayMethod[] = ['cash', 'bkash', 'nagad', 'rocket', 'card', 'bank_transfer']

function draftKey(mode: Mode, branchId: string) {
  return `pims.draft.${mode}.${branchId}`
}

function loadDraft(mode: Mode, branchId: string): DraftLine[] {
  try {
    const raw = window.localStorage.getItem(draftKey(mode, branchId))
    const parsed: unknown = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? (parsed as DraftLine[]) : []
  } catch {
    return []
  }
}

function saveDraft(mode: Mode, branchId: string, lines: DraftLine[]) {
  try {
    if (lines.length === 0) window.localStorage.removeItem(draftKey(mode, branchId))
    else window.localStorage.setItem(draftKey(mode, branchId), JSON.stringify(lines))
  } catch {
    // Storage can be unavailable (private mode); the draft simply is not kept.
  }
}

function moneyOrZero(value: string): number | null {
  if (value.trim() === '') return 0
  try {
    return parseTaka(value)
  } catch (e) {
    if (e instanceof MoneyError) return null
    throw e
  }
}

function toTakaInput(p: number | null | undefined): string {
  return p ? (p / 100).toFixed(2) : ''
}

export function StockEntryForm({ mode }: { mode: Mode }) {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { org, branch } = useWorkspace()
  const queryClient = useQueryClient()
  const canManageSuppliers = roleCan(org.role, 'suppliers.manage')
  const today = businessDate()

  const [lines, setLines] = useState<DraftLine[]>(() => loadDraft(mode, branch.id))
  const [showErrors, setShowErrors] = useState(false)
  const [requestId, setRequestId] = useState(newRequestId)
  const [supplierId, setSupplierId] = useState('')
  const [supplierOpen, setSupplierOpen] = useState(false)
  const [invoiceNo, setInvoiceNo] = useState('')
  const [invoiceDate, setInvoiceDate] = useState('')
  const [discount, setDiscount] = useState('')
  const [paid, setPaid] = useState('')
  const [method, setMethod] = useState<PayMethod>('cash')
  const [note, setNote] = useState('')

  useEffect(() => saveDraft(mode, branch.id, lines), [mode, branch.id, lines])

  const suppliers = useQuery({
    queryKey: ['suppliers', org.organizationId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('suppliers')
        .select('id, name')
        .eq('organization_id', org.organizationId)
        .eq('is_active', true)
        .order('name')
      if (error) throw toAppError(error)
      return data
    },
    enabled: mode === 'receive',
  })

  const validation = useMemo(() => {
    const results = lines.map((l) => validateLine(l, today))
    const dupes = duplicateKeys(lines)
    return { results, dupes }
  }, [lines, today])

  const sub = subtotal(lines)
  const discountPaisa = moneyOrZero(discount)
  const total = discountPaisa === null ? null : sub - discountPaisa
  const paidPaisa = moneyOrZero(paid)

  const headerErrors = {
    supplier: mode === 'receive' && !supplierId,
    discount: discountPaisa === null || discountPaisa < 0 || discountPaisa > sub,
    paid: paidPaisa === null || paidPaisa < 0 || (total !== null && paidPaisa > total),
    invoiceDate: invoiceDate !== '' && invoiceDate > today,
  }

  function addLine(hit: MedicineHit) {
    setLines((prev) => [
      ...prev,
      {
        key: crypto.randomUUID(),
        medicineId: hit.medicine_id,
        brandName: hit.brand_name,
        strength: hit.strength,
        unit: hit.base_unit_label,
        batchNo: '',
        expiryMonth: '',
        quantity: '',
        bonus: '',
        unitCost: '',
        mrp: toTakaInput(hit.sale_price_paisa),
        salePrice: '',
      },
    ])
  }

  function update(key: string, field: LineField, value: string) {
    setLines((prev) => prev.map((l) => (l.key === key ? { ...l, [field]: value } : l)))
  }

  function reset() {
    setLines([])
    setShowErrors(false)
    setRequestId(newRequestId())
    setInvoiceNo('')
    setInvoiceDate('')
    setDiscount('')
    setPaid('')
    setNote('')
  }

  const submit = useMutation({
    mutationFn: async (valid: ValidLine[]) => {
      if (mode === 'opening') {
        const count = await rpc('add_opening_stock', {
          p_branch_id: branch.id,
          p_items: toOpeningItems(valid),
          p_client_request_id: requestId,
        })
        return t('purchases.openingSaved', { n: count })
      }
      const res = (await rpc('receive_goods', {
        p_branch_id: branch.id,
        p_supplier_id: supplierId,
        p_items: toReceiveItems(valid),
        p_client_request_id: requestId,
        ...(invoiceNo.trim() ? { p_supplier_invoice_no: invoiceNo.trim() } : {}),
        ...(invoiceDate ? { p_supplier_invoice_date: invoiceDate } : {}),
        p_discount_paisa: discountPaisa ?? 0,
        p_paid_paisa: paidPaisa ?? 0,
        p_payment_method: method,
        ...(note.trim() ? { p_note: note.trim() } : {}),
      })) as { receipt_no: string; total_paisa: number }
      return t('purchases.received', {
        no: res.receipt_no,
        total: formatTaka(paisa(res.total_paisa), lng),
      })
    },
    onSuccess: async (message) => {
      toast.success(message)
      reset()
      await Promise.all(
        [
          'goods-receipts',
          'search_medicines',
          'stock',
          'report_low_stock',
          'report_expiring_stock',
        ].map((k) => queryClient.invalidateQueries({ queryKey: [k] })),
      )
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  function onSubmit() {
    setShowErrors(true)
    const valid: ValidLine[] = []
    for (const r of validation.results) {
      if (!r.ok) return
      valid.push(r.line)
    }
    if (valid.length === 0 || validation.dupes.size > 0) return
    if (
      mode === 'receive' &&
      (headerErrors.supplier ||
        headerErrors.discount ||
        headerErrors.paid ||
        headerErrors.invoiceDate)
    )
      return
    submit.mutate(valid)
  }

  const errorsFor = (i: number): LineErrors => {
    const r = validation.results[i]
    return showErrors && r && !r.ok ? r.errors : {}
  }

  const cell = (
    line: DraftLine,
    i: number,
    field: LineField,
    opts: {
      label: string
      className?: string
      type?: string
      inputMode?: 'numeric' | 'decimal'
      placeholder?: string
    },
  ) => {
    const err = errorsFor(i)[field]
    return (
      <div className="min-w-0">
        <span
          aria-hidden
          className="mb-1 block text-xs font-medium text-muted-foreground md:hidden"
        >
          {opts.label}
        </span>
        <Input
          aria-label={`${opts.label} ${line.brandName}`}
          type={opts.type ?? 'text'}
          inputMode={opts.inputMode}
          placeholder={opts.placeholder}
          value={line[field]}
          onChange={(e) => update(line.key, field, e.target.value)}
          aria-invalid={err ? true : undefined}
          title={err ? t(err) : undefined}
          className={cn('h-9 px-2', opts.className)}
        />
        {err ? <p className="mt-0.5 text-[11px] leading-tight text-danger">{t(err)}</p> : null}
      </div>
    )
  }

  return (
    <div className="grid min-w-0 grid-cols-1 gap-6">
      {mode === 'receive' ? (
        <Card>
          <CardContent className="grid gap-4 pt-5 sm:grid-cols-3">
            <Field
              id="gr-supplier"
              label={t('purchases.supplier')}
              error={showErrors && headerErrors.supplier ? t('purchases.err.supplier') : undefined}
            >
              <div className="flex gap-2">
                <div className="flex-1">
                  <Select
                    id="gr-supplier"
                    value={supplierId}
                    onChange={(e) => setSupplierId(e.target.value)}
                    aria-invalid={showErrors && headerErrors.supplier ? true : undefined}
                  >
                    <option value="">{t('purchases.chooseSupplier')}</option>
                    {(suppliers.data ?? []).map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.name}
                      </option>
                    ))}
                  </Select>
                </div>
                {canManageSuppliers ? (
                  <Button
                    type="button"
                    variant="secondary"
                    size="icon"
                    className="size-10"
                    aria-label={t('purchases.newSupplier')}
                    onClick={() => setSupplierOpen(true)}
                  >
                    <Plus aria-hidden />
                  </Button>
                ) : null}
              </div>
            </Field>
            <Field id="gr-invoice" label={t('purchases.invoiceNo')}>
              <Input
                id="gr-invoice"
                value={invoiceNo}
                maxLength={60}
                onChange={(e) => setInvoiceNo(e.target.value)}
              />
            </Field>
            <Field
              id="gr-date"
              label={t('purchases.invoiceDate')}
              error={headerErrors.invoiceDate ? t('purchases.err.futureDate') : undefined}
            >
              <Input
                id="gr-date"
                type="date"
                max={today}
                value={invoiceDate}
                onChange={(e) => setInvoiceDate(e.target.value)}
              />
            </Field>
          </CardContent>
        </Card>
      ) : null}

      <Card className="min-w-0">
        <CardHeader className="gap-3">
          <CardTitle>
            {t(mode === 'receive' ? 'purchases.items' : 'purchases.openingItems')}
          </CardTitle>
          <MedicinePicker
            label={t('purchases.addMedicine')}
            placeholder={t('purchases.addMedicine')}
            onPick={addLine}
          />
        </CardHeader>
        <CardContent className="p-0">
          {lines.length === 0 ? (
            <EmptyState
              icon={PackagePlus}
              title={t('purchases.noItems')}
              description={t(
                mode === 'receive' ? 'purchases.noItemsBody' : 'purchases.openingBody',
              )}
            />
          ) : (
            <div className="overflow-x-auto">
              <div className="text-sm md:min-w-[960px]">
                <div
                  aria-hidden
                  className={cn(
                    LINE_GRID,
                    'hidden border-b bg-surface-muted/60 px-3 py-2 text-xs font-medium tracking-wide text-muted-foreground uppercase md:grid',
                  )}
                >
                  <span>{t('inventory.medicine')}</span>
                  <span>{t('purchases.batchNo')}</span>
                  <span>{t('purchases.expiry')}</span>
                  <span>{t('purchases.qty')}</span>
                  <span>{t(mode === 'receive' ? 'purchases.bonus' : 'purchases.extra')}</span>
                  <span>{t('purchases.unitCost')}</span>
                  <span>{t('purchases.mrp')}</span>
                  <span>{t('purchases.salePrice')}</span>
                  <span className="text-right">{t('purchases.lineTotal')}</span>
                  <span />
                </div>
                <ul className="divide-y">
                  {lines.map((line, i) => {
                    const lt = lineTotal(line)
                    const dupe = showErrors && validation.dupes.has(line.key)
                    return (
                      <li
                        key={line.key}
                        className={cn(
                          LINE_GRID,
                          'grid grid-cols-2 items-start gap-x-3 gap-y-3 px-4 py-4 sm:grid-cols-3 md:gap-y-0 md:px-3 md:py-2',
                          dupe && 'bg-danger-soft/40',
                        )}
                      >
                        <div className="col-span-2 flex items-start justify-between gap-2 sm:col-span-3 md:col-span-1 md:block">
                          <div>
                            <p className="font-medium">
                              {line.brandName}{' '}
                              <span className="font-normal text-muted-foreground">
                                {line.strength}
                              </span>
                            </p>
                            <p className="text-xs text-muted-foreground">
                              {t('purchases.perUnit', { unit: line.unit })}
                            </p>
                            {dupe ? (
                              <p className="text-xs text-danger">{t('purchases.err.duplicate')}</p>
                            ) : null}
                          </div>
                          <span className="tabular shrink-0 font-semibold md:hidden">
                            {lt === null ? '—' : formatTaka(paisa(lt), lng)}
                          </span>
                        </div>
                        {cell(line, i, 'batchNo', {
                          label: t('purchases.batchNo'),
                          className: 'font-mono uppercase',
                        })}
                        {cell(line, i, 'expiryMonth', {
                          label: t('purchases.expiry'),
                          type: 'month',
                        })}
                        {cell(line, i, 'quantity', {
                          label: t('purchases.qty'),
                          inputMode: 'numeric',
                        })}
                        {cell(line, i, 'bonus', {
                          label: t(mode === 'receive' ? 'purchases.bonus' : 'purchases.extra'),
                          inputMode: 'numeric',
                          placeholder: '0',
                        })}
                        {cell(line, i, 'unitCost', {
                          label: t('purchases.unitCost'),
                          inputMode: 'decimal',
                        })}
                        {cell(line, i, 'mrp', { label: t('purchases.mrp'), inputMode: 'decimal' })}
                        {cell(line, i, 'salePrice', {
                          label: t('purchases.salePrice'),
                          inputMode: 'decimal',
                          placeholder: line.mrp || '',
                        })}
                        <span className="tabular hidden pt-2 text-right md:block">
                          {lt === null ? '—' : formatTaka(paisa(lt), lng)}
                        </span>
                        <div className="flex items-end justify-end self-stretch md:block">
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label={t('pos.remove', { name: line.brandName })}
                            onClick={() =>
                              setLines((prev) => prev.filter((l) => l.key !== line.key))
                            }
                          >
                            <Trash2 aria-hidden />
                          </Button>
                        </div>
                      </li>
                    )
                  })}
                </ul>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {lines.length > 0 ? (
        <Card>
          <CardContent className="grid gap-4 pt-5 md:grid-cols-[1fr_20rem]">
            <div className="grid content-start gap-4 sm:grid-cols-2">
              {mode === 'receive' ? (
                <>
                  <Field
                    id="gr-discount"
                    label={t('purchases.discount')}
                    error={headerErrors.discount ? t('purchases.err.discount') : undefined}
                  >
                    <Input
                      id="gr-discount"
                      inputMode="decimal"
                      placeholder="0"
                      value={discount}
                      onChange={(e) => setDiscount(e.target.value)}
                    />
                  </Field>
                  <Field
                    id="gr-paid"
                    label={t('purchases.paidNow')}
                    hint={t('purchases.paidHint')}
                    error={headerErrors.paid ? t('purchases.err.paid') : undefined}
                  >
                    <Input
                      id="gr-paid"
                      inputMode="decimal"
                      placeholder="0"
                      value={paid}
                      onChange={(e) => setPaid(e.target.value)}
                    />
                  </Field>
                  <Field id="gr-method" label={t('pos.payment')}>
                    <Select
                      id="gr-method"
                      value={method}
                      onChange={(e) => setMethod(e.target.value as PayMethod)}
                    >
                      {PAY_METHODS.map((m) => (
                        <option key={m} value={m}>
                          {t(`pos.methods.${m}`)}
                        </option>
                      ))}
                    </Select>
                  </Field>
                  <Field id="gr-note" label={t('medicines.notes')}>
                    <Input
                      id="gr-note"
                      maxLength={500}
                      value={note}
                      onChange={(e) => setNote(e.target.value)}
                    />
                  </Field>
                </>
              ) : (
                <p className="text-sm text-muted-foreground sm:col-span-2">
                  {t('purchases.openingNote')}
                </p>
              )}
            </div>
            <div className="grid content-start gap-2 rounded-lg bg-surface-muted/60 p-4 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">{t('purchases.lines')}</span>
                <span className="tabular">{lines.length}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">{t('pos.subtotal')}</span>
                <span className="tabular">{formatTaka(paisa(sub), lng)}</span>
              </div>
              {mode === 'receive' ? (
                <>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">{t('purchases.discount')}</span>
                    <span className="tabular">−{formatTaka(paisa(discountPaisa ?? 0), lng)}</span>
                  </div>
                  <div className="flex justify-between border-t pt-2 text-base font-semibold">
                    <span>{t('pos.total')}</span>
                    <span className="tabular">{formatTaka(paisa(total ?? sub), lng)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">{t('purchases.dueToSupplier')}</span>
                    <span className="tabular">
                      {formatTaka(paisa(Math.max((total ?? sub) - (paidPaisa ?? 0), 0)), lng)}
                    </span>
                  </div>
                </>
              ) : null}
              <Button className="mt-2" size="lg" loading={submit.isPending} onClick={onSubmit}>
                {t(mode === 'receive' ? 'purchases.saveReceipt' : 'purchases.saveOpening')}
              </Button>
              <Button variant="ghost" size="sm" onClick={reset} disabled={submit.isPending}>
                {t('purchases.discard')}
              </Button>
            </div>
          </CardContent>
        </Card>
      ) : null}

      {mode === 'receive' && canManageSuppliers ? (
        <SupplierDialog
          open={supplierOpen}
          onOpenChange={setSupplierOpen}
          onCreated={setSupplierId}
        />
      ) : null}
    </div>
  )
}
