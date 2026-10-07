import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { z } from 'zod'

import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { isValidBdPhone, normalizeBdPhone } from '@/domain/phone'
import { useWorkspace } from '@/features/org/org-context'
import { errorMessage, toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

const schema = z.object({
  name: z.string().trim().min(2).max(160),
  contactPerson: z.string().trim().max(120),
  phone: z.string().trim().refine(isValidBdPhone),
  address: z.string().trim().max(500),
})
type FormValues = z.infer<typeof schema>

export function SupplierDialog({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  onCreated: (supplierId: string) => void
}) {
  const { t } = useTranslation()
  const { org } = useWorkspace()
  const queryClient = useQueryClient()
  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { name: '', contactPerson: '', phone: '', address: '' },
  })
  const { errors } = form.formState

  useEffect(() => {
    if (open) form.reset()
  }, [open, form])

  const create = useMutation({
    mutationFn: async (v: FormValues) => {
      const { data, error } = await supabase
        .from('suppliers')
        .insert({
          organization_id: org.organizationId,
          name: v.name,
          contact_person: v.contactPerson || null,
          phone: normalizeBdPhone(v.phone),
          address: v.address || null,
        })
        .select('id')
        .single()
      if (error) {
        // 23505 = unique violation on (organization_id, lower(name)).
        if (error.code === '23505') {
          throw toAppError({ message: error.message, details: 'duplicate_supplier' })
        }
        throw toAppError(error)
      }
      return data.id
    },
    onSuccess: async (id, v) => {
      toast.success(t('purchases.supplierCreated', { name: v.name }))
      await queryClient.invalidateQueries({ queryKey: ['suppliers'] })
      onCreated(id)
      onOpenChange(false)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent closeLabel={t('common.close')}>
        <DialogHeader>
          <DialogTitle>{t('purchases.newSupplier')}</DialogTitle>
        </DialogHeader>
        <form
          className="grid gap-4"
          noValidate
          onSubmit={(e) => {
            e.stopPropagation()
            void form.handleSubmit((v) => create.mutate(v))(e)
          }}
        >
          <Field
            id="sup-name"
            label={t('purchases.supplierName')}
            error={errors.name ? t('medicines.required') : undefined}
          >
            <Input
              id="sup-name"
              placeholder="Beximco Pharmaceuticals"
              aria-invalid={errors.name ? true : undefined}
              {...form.register('name')}
            />
          </Field>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field id="sup-contact" label={t('purchases.contactPerson')}>
              <Input id="sup-contact" {...form.register('contactPerson')} />
            </Field>
            <Field
              id="sup-phone"
              label={t('purchases.phone')}
              error={errors.phone ? t('errors.invalid_phone') : undefined}
            >
              <Input
                id="sup-phone"
                inputMode="tel"
                placeholder="01XXXXXXXXX"
                aria-invalid={errors.phone ? true : undefined}
                {...form.register('phone')}
              />
            </Field>
          </div>
          <Field id="sup-address" label={t('purchases.address')}>
            <Input id="sup-address" {...form.register('address')} />
          </Field>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => onOpenChange(false)}>
              {t('common.cancel')}
            </Button>
            <Button type="submit" loading={create.isPending}>
              {t('common.save')}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
