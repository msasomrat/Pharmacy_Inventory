import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CreditCard, Search, UserPlus } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { bpToPercentText, formatTaka, paisa } from '@/domain/money'
import { CustomerDialog } from '@/features/customers/CustomerDialog'
import { displayPhone } from '@/domain/phone'
import { useWorkspace } from '@/features/org/org-context'
import { useDebounced } from '@/hooks/useDebounced'
import { currentLanguage } from '@/i18n'
import { newRequestId, rpc } from '@/lib/api'
import { cn } from '@/lib/cn'
import { formatDate } from '@/lib/dates'
import { errorMessage, toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

import { listPlans } from './loyalty-api'
import { formatCardNo } from './membership'

type PayMethod = 'cash' | 'bkash' | 'nagad' | 'rocket' | 'card'
const METHODS: PayMethod[] = ['cash', 'bkash', 'nagad', 'rocket', 'card']

export interface PickedCustomer {
  id: string
  name: string
  phone: string | null
}

interface EnrollResult {
  card_no: string
  starts_on: string
  ends_on: string
  fee_paisa: number
}

function CustomerSearch({ onPick }: { onPick: (c: PickedCustomer) => void }) {
  const { t } = useTranslation()
  const { org } = useWorkspace()
  const [text, setText] = useState('')
  const q = useDebounced(text.replace(/[,()*%\\:"']/g, ' ').trim(), 200)
  const results = useQuery({
    queryKey: ['customer-search', org.organizationId, q],
    queryFn: async () => {
      const digits = q.replace(/\D/g, '')
      const filters = [`name.ilike.*${q}*`]
      if (digits.length >= 4) filters.push(`phone.ilike.*${digits}*`)
      const { data, error } = await supabase
        .from('customers')
        .select('id, name, phone')
        .eq('organization_id', org.organizationId)
        .eq('is_active', true)
        .or(filters.join(','))
        .order('name')
        .limit(8)
      if (error) throw toAppError(error)
      return data
    },
    enabled: q.length >= 2,
  })
  return (
    <div className="grid gap-2">
      <div className="relative">
        <Search
          aria-hidden
          className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
        />
        <Input
          type="search"
          aria-label={t('loyalty.findCustomer')}
          placeholder={t('loyalty.findCustomer')}
          className="pl-9"
          value={text}
          onChange={(e) => setText(e.target.value)}
        />
      </div>
      {q.length >= 2 ? (
        <ul className="max-h-56 divide-y overflow-y-auto rounded-md border">
          {(results.data ?? []).length === 0 ? (
            <li className="px-3 py-2 text-sm text-muted-foreground">
              {results.isFetching ? t('app.loading') : t('customers.noMatch')}
            </li>
          ) : (
            (results.data ?? []).map((c) => (
              <li key={c.id}>
                <button
                  type="button"
                  className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm hover:bg-surface-muted"
                  onClick={() => onPick(c)}
                >
                  <span className="font-medium">{c.name}</span>
                  <span className="text-muted-foreground">{displayPhone(c.phone)}</span>
                </button>
              </li>
            ))
          )}
        </ul>
      ) : null}
    </div>
  )
}

function EnrollContent({
  initialCustomer,
  onClose,
}: {
  initialCustomer: PickedCustomer | null
  onClose: () => void
}) {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { org, branch } = useWorkspace()
  const queryClient = useQueryClient()
  const [customer, setCustomer] = useState<PickedCustomer | null>(initialCustomer)
  const [planId, setPlanId] = useState('')
  const [method, setMethod] = useState<PayMethod>('cash')
  const [cardNo, setCardNo] = useState('')
  const [requestId] = useState(newRequestId)
  const [result, setResult] = useState<EnrollResult | null>(null)
  const [newCustomerOpen, setNewCustomerOpen] = useState(false)

  const plans = useQuery({
    queryKey: ['loyalty-plans', org.organizationId],
    queryFn: () => listPlans(org.organizationId),
  })
  const activePlans = (plans.data ?? []).filter((p) => p.isActive)
  const plan = activePlans.find((p) => p.id === planId) ?? activePlans[0]

  const enroll = useMutation({
    mutationFn: async () => {
      if (!customer || !plan) throw new Error(t('errors.unknown'))
      return (await rpc('enroll_loyalty', {
        p_customer_id: customer.id,
        p_plan_id: plan.id,
        p_branch_id: branch.id,
        p_client_request_id: requestId,
        p_payment_method: method,
        ...(cardNo.trim() ? { p_card_no: cardNo.replace(/\s/g, '') } : {}),
      })) as unknown as EnrollResult
    },
    onSuccess: async (r) => {
      setResult(r)
      await queryClient.invalidateQueries({ queryKey: ['customers'] })
      await queryClient.invalidateQueries({ queryKey: ['loyalty-members'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const needsPhone = customer !== null && !customer.phone

  return (
    <>
      {result ? (
        <div className="grid gap-4 text-center">
          <DialogHeader className="items-center pr-0">
            <DialogTitle>{t('loyalty.enrolled')}</DialogTitle>
            <DialogDescription>{customer?.name}</DialogDescription>
          </DialogHeader>
          <div className="mx-auto grid w-full max-w-xs gap-3 rounded-2xl bg-gradient-to-br from-primary to-primary-hover p-5 text-left text-primary-foreground shadow-pop">
            <div className="flex items-center justify-between text-sm opacity-90">
              <span>{org.organizationName}</span>
              <CreditCard className="size-5" aria-hidden />
            </div>
            <p className="font-mono text-xl tracking-widest" data-testid="card-no">
              {formatCardNo(result.card_no)}
            </p>
            <p className="text-xs opacity-90">
              {t('loyalty.validTill', { date: formatDate(result.ends_on, lng) })}
            </p>
          </div>
          {result.fee_paisa > 0 ? (
            <p className="text-sm text-muted-foreground">
              {t('loyalty.feeCollected', { fee: formatTaka(paisa(result.fee_paisa), lng) })}
            </p>
          ) : null}
          <Button onClick={onClose}>{t('loyalty.done')}</Button>
        </div>
      ) : (
        <div className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{t('loyalty.enroll')}</DialogTitle>
            <DialogDescription>{t('loyalty.enrollBody')}</DialogDescription>
          </DialogHeader>

          <div className="grid gap-2">
            <p className="text-sm font-medium">{t('loyalty.customer')}</p>
            {customer ? (
              <div className="flex items-center justify-between gap-3 rounded-md border p-3">
                <div>
                  <p className="font-medium">{customer.name}</p>
                  <p className="text-sm text-muted-foreground">
                    {displayPhone(customer.phone) || t('loyalty.noPhone')}
                  </p>
                </div>
                {initialCustomer ? null : (
                  <Button variant="ghost" size="sm" onClick={() => setCustomer(null)}>
                    {t('loyalty.change')}
                  </Button>
                )}
              </div>
            ) : (
              <>
                <CustomerSearch onPick={setCustomer} />
                <Button
                  variant="secondary"
                  size="sm"
                  className="justify-self-start"
                  onClick={() => setNewCustomerOpen(true)}
                >
                  <UserPlus aria-hidden />
                  {t('customers.add')}
                </Button>
              </>
            )}
            {needsPhone ? (
              <p className="text-xs text-danger">{t('errors.phone_required')}</p>
            ) : null}
          </div>

          {plans.isPending ? null : activePlans.length === 0 ? (
            <p className="rounded-md bg-warning-soft p-3 text-sm text-warning">
              {t('loyalty.noActivePlan')}
            </p>
          ) : (
            <fieldset className="grid gap-2">
              <legend className="mb-2 text-sm font-medium">{t('loyalty.plan')}</legend>
              <div className="grid gap-2 sm:grid-cols-2">
                {activePlans.map((p) => (
                  <label
                    key={p.id}
                    className={cn(
                      'cursor-pointer rounded-lg border p-3 transition-colors has-[:focus-visible]:ring-3 has-[:focus-visible]:ring-ring/25',
                      plan?.id === p.id
                        ? 'border-primary bg-primary-soft/50'
                        : 'hover:bg-surface-muted',
                    )}
                  >
                    <input
                      type="radio"
                      name="plan"
                      className="sr-only"
                      checked={plan?.id === p.id}
                      onChange={() => setPlanId(p.id)}
                    />
                    <span className="block font-medium">{p.name}</span>
                    <span className="block text-sm text-muted-foreground">
                      {t('loyalty.planSummary', {
                        fee: formatTaka(paisa(p.feePaisa), lng),
                        discount: bpToPercentText(p.discountBp),
                        months: p.durationMonths,
                      })}
                    </span>
                  </label>
                ))}
              </div>
            </fieldset>
          )}

          <div className="grid gap-4 sm:grid-cols-2">
            {plan && plan.feePaisa > 0 ? (
              <Field id="en-method" label={t('pos.payment')}>
                <Select
                  id="en-method"
                  value={method}
                  onChange={(e) => setMethod(e.target.value as PayMethod)}
                >
                  {METHODS.map((m) => (
                    <option key={m} value={m}>
                      {t(`pos.methods.${m}`)}
                    </option>
                  ))}
                </Select>
              </Field>
            ) : null}
            <Field id="en-card" label={t('loyalty.cardNo')} hint={t('loyalty.cardNoHint')}>
              <Input
                id="en-card"
                inputMode="numeric"
                placeholder={t('loyalty.autoNumber')}
                value={cardNo}
                onChange={(e) => setCardNo(e.target.value)}
              />
            </Field>
          </div>

          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={onClose}>
              {t('common.cancel')}
            </Button>
            <Button
              loading={enroll.isPending}
              disabled={!customer || !plan || needsPhone}
              onClick={() => enroll.mutate()}
            >
              {plan && plan.feePaisa > 0
                ? t('loyalty.enrollPay', { fee: formatTaka(paisa(plan.feePaisa), lng) })
                : t('loyalty.enroll')}
            </Button>
          </div>
        </div>
      )}
      <CustomerDialog
        open={newCustomerOpen}
        onOpenChange={setNewCustomerOpen}
        customer={null}
        onSaved={setCustomer}
      />
    </>
  )
}

export function EnrollDialog({
  open,
  onOpenChange,
  customer,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  customer?: PickedCustomer | null
}) {
  const { t } = useTranslation()
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent closeLabel={t('common.close')}>
        {/* Mounted only while open, so every opening starts with a fresh form and request id. */}
        <EnrollContent initialCustomer={customer ?? null} onClose={() => onOpenChange(false)} />
      </DialogContent>
    </Dialog>
  )
}
