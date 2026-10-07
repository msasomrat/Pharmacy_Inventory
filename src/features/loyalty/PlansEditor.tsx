import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { useWorkspace } from '@/features/org/org-context'
import { roleCan } from '@/features/org/permissions'
import { errorMessage, toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

import { listPlans, loyaltyEnabled, type Plan } from './loyalty-api'
import { toDraft, validatePlan, type Draft, type DraftErrors } from './plan-form'

function PlanCard({ plan, canEdit }: { plan: Plan; canEdit: boolean }) {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [draft, setDraft] = useState<Draft>(() => toDraft(plan))
  const [errors, setErrors] = useState<DraftErrors>({})
  const set = (k: keyof Draft) => (e: { target: { value: string } }) =>
    setDraft((d) => ({ ...d, [k]: e.target.value }))
  const id = (k: string) => `plan-${plan.id}-${k}`

  const save = useMutation({
    mutationFn: async () => {
      const v = validatePlan(draft)
      if (!v.ok) {
        setErrors(v.errors)
        throw new Error(t('loyalty.err.fix'))
      }
      setErrors({})
      const { error } = await supabase.from('loyalty_plans').update(v.row).eq('id', plan.id)
      if (error) throw toAppError(error)
    },
    onSuccess: async () => {
      toast.success(t('loyalty.planSaved', { name: draft.name }))
      await queryClient.invalidateQueries({ queryKey: ['loyalty-plans'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const field = (
    k: keyof Draft,
    label: string,
    opts: { hint?: string; inputMode?: 'numeric' | 'decimal'; suffix?: string } = {},
  ) => (
    <Field
      id={id(k)}
      label={label}
      error={errors[k] ? t(errors[k]) : undefined}
      {...(opts.hint ? { hint: opts.hint } : {})}
    >
      <div className="relative">
        <Input
          id={id(k)}
          value={draft[k] as string}
          onChange={set(k)}
          disabled={!canEdit}
          aria-invalid={errors[k] ? true : undefined}
          {...(opts.inputMode ? { inputMode: opts.inputMode } : {})}
          className={opts.suffix ? 'pr-10' : undefined}
        />
        {opts.suffix ? (
          <span className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-sm text-muted-foreground">
            {opts.suffix}
          </span>
        ) : null}
      </div>
    </Field>
  )

  return (
    <Card role="region" aria-labelledby={id('title')}>
      <CardHeader className="flex-row items-center justify-between gap-3">
        <CardTitle id={id('title')}>{plan.name}</CardTitle>
        <Badge tone={plan.isActive ? 'success' : 'neutral'}>
          {t(plan.isActive ? 'loyalty.planOn' : 'loyalty.planOff')}
        </Badge>
      </CardHeader>
      <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div className="sm:col-span-2">{field('name', t('loyalty.planName'))}</div>
        {field('months', t('loyalty.months'), { inputMode: 'numeric' })}
        {field('fee', t('loyalty.fee'), { inputMode: 'decimal', suffix: '৳' })}
        {field('discount', t('loyalty.discount'), {
          inputMode: 'decimal',
          suffix: '%',
          hint: t('loyalty.discountHint'),
        })}
        {field('maxDiscount', t('loyalty.maxDiscount'), {
          inputMode: 'decimal',
          suffix: '৳',
          hint: t('loyalty.optional'),
        })}
        {field('pointsPer100', t('loyalty.pointsPer100'), {
          inputMode: 'numeric',
          hint: t('loyalty.pointsHint'),
        })}
        {field('pointValue', t('loyalty.pointValue'), { inputMode: 'decimal', suffix: '৳' })}
        {field('minRedeem', t('loyalty.minRedeem'), { inputMode: 'numeric' })}
        <label className="flex items-center gap-2 self-end pb-2 text-sm lg:col-span-2">
          <input
            type="checkbox"
            className="size-4 accent-primary"
            checked={draft.isActive}
            disabled={!canEdit}
            onChange={(e) => setDraft((d) => ({ ...d, isActive: e.target.checked }))}
          />
          {t('loyalty.offerPlan')}
        </label>
        {canEdit ? (
          <div className="flex items-end justify-end sm:col-span-2 lg:col-span-1">
            <Button loading={save.isPending} onClick={() => save.mutate()}>
              {t('common.save')}
            </Button>
          </div>
        ) : null}
      </CardContent>
    </Card>
  )
}

export function PlansEditor() {
  const { t } = useTranslation()
  const { org } = useWorkspace()
  const queryClient = useQueryClient()
  const canEdit = roleCan(org.role, 'loyalty.manage_plans')
  const canToggle = roleCan(org.role, 'org.settings.manage')
  const plans = useQuery({
    queryKey: ['loyalty-plans', org.organizationId],
    queryFn: () => listPlans(org.organizationId),
  })
  const enabled = useQuery({
    queryKey: ['loyalty-enabled', org.organizationId],
    queryFn: () => loyaltyEnabled(org.organizationId),
  })

  const toggle = useMutation({
    mutationFn: async (on: boolean) => {
      const { error } = await supabase
        .from('organization_settings')
        .update({ loyalty_enabled: on })
        .eq('organization_id', org.organizationId)
      if (error) throw toAppError(error)
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['loyalty-enabled'] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  const addPlan = useMutation({
    mutationFn: async () => {
      const n = (plans.data?.length ?? 0) + 1
      const { error } = await supabase.from('loyalty_plans').insert({
        organization_id: org.organizationId,
        name: t('loyalty.newPlanName', { n }),
        duration_months: 12,
        sort_order: n,
      })
      if (error) throw toAppError(error)
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['loyalty-plans'] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <div className="grid gap-6">
      <Card>
        <CardContent className="flex flex-wrap items-center justify-between gap-4 pt-5">
          <div className="max-w-xl space-y-1">
            <p className="font-medium">{t('loyalty.programme')}</p>
            <p className="text-sm text-muted-foreground">{t('loyalty.programmeBody')}</p>
          </div>
          <label className="flex items-center gap-2 text-sm font-medium">
            <input
              type="checkbox"
              className="size-5 accent-primary"
              checked={enabled.data ?? false}
              disabled={!canToggle || enabled.isPending || toggle.isPending}
              onChange={(e) => toggle.mutate(e.target.checked)}
            />
            {t('loyalty.programmeOn')}
          </label>
        </CardContent>
      </Card>
      {plans.isPending ? (
        <Skeleton className="h-48" />
      ) : (
        (plans.data ?? []).map((p) => (
          <PlanCard
            key={`${p.id}-${p.feePaisa}-${p.discountBp}-${p.isActive}`}
            plan={p}
            canEdit={canEdit}
          />
        ))
      )}
      {canEdit ? (
        <Button
          variant="secondary"
          className="justify-self-start"
          loading={addPlan.isPending}
          onClick={() => addPlan.mutate()}
        >
          <Plus aria-hidden />
          {t('loyalty.addPlan')}
        </Button>
      ) : (
        <p className="text-sm text-muted-foreground">{t('loyalty.ownerOnly')}</p>
      )}
    </div>
  )
}
