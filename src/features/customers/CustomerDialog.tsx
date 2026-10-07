import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { z } from 'zod'

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
import { MoneyError, parseTaka } from '@/domain/money'
import { isValidBdPhone, normalizeBdPhone } from '@/domain/phone'
import { useWorkspace } from '@/features/org/org-context'
import { rpc } from '@/lib/api'
import { errorMessage, toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

import { displayPhone } from '@/domain/phone'

import type { CustomerRow } from './customers-api'

function isMoney(v: string): boolean {
  if (v.trim() === '') return true
  try {
    return parseTaka(v) >= 0
  } catch (e) {
    if (e instanceof MoneyError) return false
    throw e
  }
}

const schema = z.object({
  name: z.string().trim().min(1).max(120),
  phone: z.string().trim().refine(isValidBdPhone),
  address: z.string().trim().max(500),
  notes: z.string().trim().max(1000),
  creditLimit: z.string().trim().refine(isMoney),
  isActive: z.boolean(),
})
type FormValues = z.infer<typeof schema>

function defaults(c: CustomerRow | null): FormValues {
  return {
    name: c?.name ?? '',
    phone: displayPhone(c?.phone ?? null),
    address: c?.address ?? '',
    notes: c?.notes ?? '',
    creditLimit: c && c.creditLimitPaisa > 0 ? (c.creditLimitPaisa / 100).toFixed(2) : '',
    isActive: c?.isActive ?? true,
  }
}

/** Unique phone per organization (customers_org_phone_key) maps to a friendly message. */
function mapError(error: { code: string; message: string; details: string }) {
  return error.code === '23505'
    ? toAppError({ message: error.message, details: 'duplicate_phone' })
    : toAppError(error)
}

export function CustomerDialog({
  open,
  onOpenChange,
  customer,
  onSaved,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** null creates a new customer. */
  customer: CustomerRow | null
  onSaved?: (customer: { id: string; name: string; phone: string | null }) => void
}) {
  const { t } = useTranslation()
  const { org, can } = useWorkspace()
  const queryClient = useQueryClient()
  const canSetCredit = (org.role === 'owner' || org.role === 'manager') && can('customers.manage')
  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: defaults(customer),
  })
  const { errors } = form.formState

  useEffect(() => {
    if (open) form.reset(defaults(customer))
  }, [open, customer, form])

  const save = useMutation({
    mutationFn: async (v: FormValues) => {
      const fields = {
        name: v.name,
        phone: normalizeBdPhone(v.phone),
        address: v.address || null,
        notes: v.notes || null,
      }
      let id: string
      if (customer) {
        const { error } = await supabase
          .from('customers')
          .update({ ...fields, is_active: v.isActive })
          .eq('id', customer.id)
        if (error) throw mapError(error)
        id = customer.id
      } else {
        const { data, error } = await supabase
          .from('customers')
          .insert({ organization_id: org.organizationId, ...fields })
          .select('id')
          .single()
        if (error) throw mapError(error)
        id = data.id
      }
      const limit = v.creditLimit ? parseTaka(v.creditLimit) : 0
      if (canSetCredit && limit !== (customer?.creditLimitPaisa ?? 0)) {
        await rpc('set_customer_credit_limit', { p_customer_id: id, p_credit_limit_paisa: limit })
      }
      return { id, name: fields.name, phone: fields.phone }
    },
    onSuccess: async (saved) => {
      toast.success(t(customer ? 'customers.updated' : 'customers.created', { name: saved.name }))
      await queryClient.invalidateQueries({ queryKey: ['customers'] })
      onSaved?.(saved)
      onOpenChange(false)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent closeLabel={t('common.close')}>
        <DialogHeader>
          <DialogTitle>{t(customer ? 'customers.edit' : 'customers.add')}</DialogTitle>
          <DialogDescription>{t('customers.dialogBody')}</DialogDescription>
        </DialogHeader>
        <form
          className="grid gap-4 sm:grid-cols-2"
          noValidate
          onSubmit={(e) => {
            e.stopPropagation()
            void form.handleSubmit((v) => save.mutate(v))(e)
          }}
        >
          <Field
            id="cu-name"
            label={t('customers.name')}
            error={errors.name ? t('medicines.required') : undefined}
          >
            <Input
              id="cu-name"
              aria-invalid={errors.name ? true : undefined}
              {...form.register('name')}
            />
          </Field>
          <Field
            id="cu-phone"
            label={t('purchases.phone')}
            hint={t('customers.phoneHint')}
            error={errors.phone ? t('errors.invalid_phone') : undefined}
          >
            <Input
              id="cu-phone"
              inputMode="tel"
              placeholder="01XXXXXXXXX"
              aria-invalid={errors.phone ? true : undefined}
              {...form.register('phone')}
            />
          </Field>
          <div className="sm:col-span-2">
            <Field id="cu-address" label={t('purchases.address')}>
              <Input id="cu-address" {...form.register('address')} />
            </Field>
          </div>
          {canSetCredit ? (
            <Field
              id="cu-credit"
              label={t('customers.creditLimit')}
              hint={t('customers.creditHint')}
              error={errors.creditLimit ? t('purchases.err.money') : undefined}
            >
              <Input
                id="cu-credit"
                inputMode="decimal"
                placeholder="0"
                aria-invalid={errors.creditLimit ? true : undefined}
                {...form.register('creditLimit')}
              />
            </Field>
          ) : null}
          <div className={canSetCredit ? undefined : 'sm:col-span-2'}>
            <Field id="cu-notes" label={t('medicines.notes')}>
              <Input id="cu-notes" {...form.register('notes')} />
            </Field>
          </div>
          {customer ? (
            <label className="flex items-center gap-2 text-sm sm:col-span-2">
              <input
                type="checkbox"
                className="size-4 accent-primary"
                {...form.register('isActive')}
              />
              {t('customers.active')}
            </label>
          ) : null}
          <div className="flex justify-end gap-2 sm:col-span-2">
            <Button type="button" variant="secondary" onClick={() => onOpenChange(false)}>
              {t('common.cancel')}
            </Button>
            <Button type="submit" loading={save.isPending}>
              {t('common.save')}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
