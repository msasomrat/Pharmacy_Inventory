import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import { bpToPercentText, MoneyError, parsePercentBp } from '@/domain/money'
import { useOrg, useWorkspace } from '@/features/org/org-context'
import { errorMessage, toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

interface Values {
  name: string
  salesmanDiscount: string
  managerDiscount: string
  vat: string
  returnDays: string
  voidHours: string
  blockDays: string
  alertDays: string
  rxNeeded: boolean
  rounding: 'none' | 'nearest_taka'
}

async function load(organizationId: string): Promise<Values> {
  const [org, settings] = await Promise.all([
    supabase.from('organizations').select('name').eq('id', organizationId).single(),
    supabase
      .from('organization_settings')
      .select(
        'salesman_max_discount_bp, manager_max_discount_bp, vat_bp, return_window_days, void_window_hours, near_expiry_block_days, expiry_alert_days, require_prescription_for_rx, cash_rounding',
      )
      .eq('organization_id', organizationId)
      .single(),
  ])
  if (org.error) throw toAppError(org.error)
  if (settings.error) throw toAppError(settings.error)
  const s = settings.data
  return {
    name: org.data.name,
    salesmanDiscount: bpToPercentText(s.salesman_max_discount_bp),
    managerDiscount: bpToPercentText(s.manager_max_discount_bp),
    vat: bpToPercentText(s.vat_bp),
    returnDays: String(s.return_window_days),
    voidHours: String(s.void_window_hours),
    blockDays: String(s.near_expiry_block_days),
    alertDays: String(s.expiry_alert_days),
    rxNeeded: s.require_prescription_for_rx,
    rounding: s.cash_rounding,
  }
}

function pct(v: string, max: number): number | null {
  try {
    const bp = parsePercentBp(v)
    return bp <= max ? bp : null
  } catch (e) {
    if (e instanceof MoneyError) return null
    throw e
  }
}

function int(v: string, min: number, max: number): number | null {
  if (!/^\d{1,4}$/.test(v.trim())) return null
  const n = Number(v)
  return n >= min && n <= max ? n : null
}

function Form({ initial }: { initial: Values }) {
  const { t } = useTranslation()
  const { org } = useWorkspace()
  const { refetch } = useOrg()
  const queryClient = useQueryClient()
  const [v, setV] = useState(initial)
  const set = (k: keyof Values) => (e: { target: { value: string } }) =>
    setV((x) => ({ ...x, [k]: e.target.value }))

  const parsed = {
    name: v.name.trim().length >= 2 && v.name.trim().length <= 120 ? v.name.trim() : null,
    salesman: pct(v.salesmanDiscount, 10_000),
    manager: pct(v.managerDiscount, 10_000),
    vat: pct(v.vat, 5000),
    returnDays: int(v.returnDays, 0, 90),
    voidHours: int(v.voidHours, 0, 168),
    blockDays: int(v.blockDays, 0, 365),
    alertDays: int(v.alertDays, 1, 730),
  }
  const invalid = Object.values(parsed).some((x) => x === null)

  const save = useMutation({
    mutationFn: async () => {
      if (invalid) throw new Error(t('loyalty.err.fix'))
      const [a, b] = await Promise.all([
        supabase
          .from('organizations')
          .update({ name: parsed.name ?? '' })
          .eq('id', org.organizationId),
        supabase
          .from('organization_settings')
          .update({
            salesman_max_discount_bp: parsed.salesman ?? 0,
            manager_max_discount_bp: parsed.manager ?? 0,
            vat_bp: parsed.vat ?? 0,
            return_window_days: parsed.returnDays ?? 0,
            void_window_hours: parsed.voidHours ?? 0,
            near_expiry_block_days: parsed.blockDays ?? 0,
            expiry_alert_days: parsed.alertDays ?? 90,
            require_prescription_for_rx: v.rxNeeded,
            cash_rounding: v.rounding,
          })
          .eq('organization_id', org.organizationId),
      ])
      if (a.error) throw toAppError(a.error)
      if (b.error) throw toAppError(b.error)
    },
    onSuccess: async () => {
      toast.success(t('settings.saved'))
      await queryClient.invalidateQueries({ queryKey: ['pharmacy-settings'] })
      await refetch()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const num = (k: keyof Values, label: string, hint: string, ok: boolean, suffix?: string) => (
    <Field
      id={`ph-${k}`}
      label={label}
      hint={hint}
      error={ok ? undefined : t('settings.outOfRange')}
    >
      <div className="relative">
        <Input
          id={`ph-${k}`}
          inputMode="decimal"
          value={v[k] as string}
          onChange={set(k)}
          aria-invalid={ok ? undefined : true}
          className={suffix ? 'pr-12' : undefined}
        />
        {suffix ? (
          <span className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-sm text-muted-foreground">
            {suffix}
          </span>
        ) : null}
      </div>
    </Field>
  )

  return (
    <div className="grid min-w-0 grid-cols-1 gap-6">
      <Card>
        <CardHeader>
          <CardTitle>{t('settings.general')}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <Field
            id="ph-name"
            label={t('onboarding.pharmacyName')}
            error={parsed.name ? undefined : t('medicines.required')}
          >
            <Input id="ph-name" value={v.name} onChange={set('name')} />
          </Field>
          {num('vat', t('settings.vat'), t('settings.vatHint'), parsed.vat !== null, '%')}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t('settings.selling')}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {num(
            'salesmanDiscount',
            t('settings.salesmanDiscount'),
            t('settings.discountHint'),
            parsed.salesman !== null,
            '%',
          )}
          {num(
            'managerDiscount',
            t('settings.managerDiscount'),
            t('settings.discountHint'),
            parsed.manager !== null,
            '%',
          )}
          <Field id="ph-rounding" label={t('settings.rounding')}>
            <Select
              id="ph-rounding"
              value={v.rounding}
              onChange={(e) =>
                setV((x) => ({ ...x, rounding: e.target.value as Values['rounding'] }))
              }
            >
              <option value="none">{t('settings.roundingNone')}</option>
              <option value="nearest_taka">{t('settings.roundingTaka')}</option>
            </Select>
          </Field>
          {num(
            'returnDays',
            t('settings.returnDays'),
            t('settings.returnHint'),
            parsed.returnDays !== null,
            t('settings.days'),
          )}
          {num(
            'voidHours',
            t('settings.voidHours'),
            t('settings.voidHint'),
            parsed.voidHours !== null,
            t('settings.hours'),
          )}
          <label className="flex items-center gap-2 self-end pb-2 text-sm">
            <input
              type="checkbox"
              className="size-4 accent-primary"
              checked={v.rxNeeded}
              onChange={(e) => setV((x) => ({ ...x, rxNeeded: e.target.checked }))}
            />
            {t('settings.rxNeeded')}
          </label>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t('settings.expiry')}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          {num(
            'blockDays',
            t('settings.blockDays'),
            t('settings.blockHint'),
            parsed.blockDays !== null,
            t('settings.days'),
          )}
          {num(
            'alertDays',
            t('settings.alertDays'),
            t('settings.alertHint'),
            parsed.alertDays !== null,
            t('settings.days'),
          )}
        </CardContent>
      </Card>
      <div className="flex justify-end">
        <Button size="lg" loading={save.isPending} disabled={invalid} onClick={() => save.mutate()}>
          {t('settings.saveSettings')}
        </Button>
      </div>
    </div>
  )
}

export function PharmacyTab() {
  const { org } = useWorkspace()
  const values = useQuery({
    queryKey: ['pharmacy-settings', org.organizationId],
    queryFn: () => load(org.organizationId),
  })
  if (!values.data) return <Skeleton className="h-96" />
  return <Form initial={values.data} />
}
