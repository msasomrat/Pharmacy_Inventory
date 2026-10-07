import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect } from 'react'
import { useForm, useWatch } from 'react-hook-form'
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
import { Select } from '@/components/ui/select'
import { useWorkspace } from '@/features/org/org-context'
import { rpc } from '@/lib/api'
import { cn } from '@/lib/cn'
import { errorMessage } from '@/lib/errors'

import {
  DEFAULT_UNIT,
  DOSAGE_FORMS,
  SCHEDULES,
  listNames,
  type DosageForm,
  type DrugSchedule,
  type MedicineRow,
} from './medicines-api'

const BARCODE = /^[0-9A-Za-z-]{4,64}$/

const schema = z.object({
  brandName: z.string().trim().min(1).max(160),
  genericName: z.string().trim().max(200),
  manufacturerName: z.string().trim().max(120),
  dosageForm: z.enum(DOSAGE_FORMS as [DosageForm, ...DosageForm[]]),
  strength: z.string().trim().max(60),
  baseUnitLabel: z.string().trim().min(1).max(30),
  schedule: z.enum(SCHEDULES as [DrugSchedule, ...DrugSchedule[]]),
  rackLocation: z.string().trim().max(40),
  reorderLevel: z
    .string()
    .trim()
    .regex(/^\d{0,6}$/),
  barcodes: z
    .string()
    .trim()
    .refine((v) => splitBarcodes(v).every((b) => BARCODE.test(b)), 'barcode'),
  sku: z.string().trim().max(60),
  loyaltyEligible: z.boolean(),
  isActive: z.boolean(),
  notes: z.string().trim().max(1000),
})
type FormValues = z.infer<typeof schema>

function splitBarcodes(v: string): string[] {
  return v
    .split(/[\s,;]+/)
    .map((b) => b.trim())
    .filter(Boolean)
}

function defaults(m: MedicineRow | null): FormValues {
  return {
    brandName: m?.brandName ?? '',
    genericName: m?.genericName ?? '',
    manufacturerName: m?.manufacturerName ?? '',
    dosageForm: m?.dosageForm ?? 'tablet',
    strength: m?.strength ?? '',
    baseUnitLabel: m?.baseUnitLabel ?? 'tablet',
    schedule: m?.schedule ?? 'otc',
    rackLocation: m?.rackLocation ?? '',
    reorderLevel: m ? String(m.reorderLevel) : '',
    barcodes: m?.barcodes.join(', ') ?? '',
    sku: m?.sku ?? '',
    loyaltyEligible: m?.loyaltyEligible ?? true,
    isActive: m?.isActive ?? true,
    notes: m?.notes ?? '',
  }
}

export function MedicineDialog({
  open,
  onOpenChange,
  medicine,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** null creates a new medicine. */
  medicine: MedicineRow | null
}) {
  const { t } = useTranslation()
  const { org, branch } = useWorkspace()
  const queryClient = useQueryClient()
  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: defaults(medicine),
  })
  const { errors } = form.formState

  useEffect(() => {
    if (open) form.reset(defaults(medicine))
  }, [open, medicine, form])

  const generics = useQuery({
    queryKey: ['generic-names', org.organizationId],
    queryFn: () => listNames('generics', org.organizationId),
    enabled: open,
    staleTime: 60_000,
  })
  const manufacturers = useQuery({
    queryKey: ['manufacturer-names', org.organizationId],
    queryFn: () => listNames('manufacturers', org.organizationId),
    enabled: open,
    staleTime: 60_000,
  })

  const save = useMutation({
    mutationFn: (v: FormValues) =>
      rpc('save_medicine', {
        p_organization_id: org.organizationId,
        ...(medicine ? { p_medicine_id: medicine.id } : {}),
        p_brand_name: v.brandName,
        p_generic_name: v.genericName,
        p_manufacturer_name: v.manufacturerName,
        p_dosage_form: v.dosageForm,
        p_strength: v.strength,
        p_base_unit_label: v.baseUnitLabel,
        p_schedule: v.schedule,
        p_loyalty_eligible: v.loyaltyEligible,
        p_sku: v.sku,
        p_barcodes: splitBarcodes(v.barcodes),
        p_notes: v.notes,
        p_is_active: v.isActive,
        p_branch_id: branch.id,
        p_rack_location: v.rackLocation,
        ...(v.reorderLevel !== '' ? { p_reorder_level: Number(v.reorderLevel) } : {}),
      }),
    onSuccess: async (_id, v) => {
      toast.success(t(medicine ? 'medicines.updated' : 'medicines.created', { name: v.brandName }))
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['medicines'] }),
        queryClient.invalidateQueries({ queryKey: ['generic-names'] }),
        queryClient.invalidateQueries({ queryKey: ['manufacturer-names'] }),
      ])
      onOpenChange(false)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  const dosageForm = useWatch({ control: form.control, name: 'dosageForm' })
  const schedule = useWatch({ control: form.control, name: 'schedule' })
  const invalid = (name: keyof FormValues) => (errors[name] ? true : undefined)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl" closeLabel={t('common.close')}>
        <DialogHeader>
          <DialogTitle>{t(medicine ? 'medicines.edit' : 'medicines.add')}</DialogTitle>
          <DialogDescription>
            {t('medicines.dialogBody', { branch: branch.name })}
          </DialogDescription>
        </DialogHeader>

        <form
          className="grid gap-4 sm:grid-cols-6"
          noValidate
          onSubmit={(e) => void form.handleSubmit((v) => save.mutate(v))(e)}
        >
          <div className="sm:col-span-4">
            <Field
              id="med-brand"
              label={t('medicines.brandName')}
              error={errors.brandName ? t('medicines.required') : undefined}
            >
              <Input
                id="med-brand"
                placeholder="Napa"
                aria-invalid={invalid('brandName')}
                {...form.register('brandName')}
              />
            </Field>
          </div>
          <div className="sm:col-span-2">
            <Field id="med-strength" label={t('medicines.strength')}>
              <Input id="med-strength" placeholder="500 mg" {...form.register('strength')} />
            </Field>
          </div>

          <div className="sm:col-span-3">
            <Field id="med-generic" label={t('medicines.generic')}>
              <Input
                id="med-generic"
                list="med-generic-list"
                placeholder="Paracetamol"
                {...form.register('genericName')}
              />
            </Field>
            <datalist id="med-generic-list">
              {(generics.data ?? []).map((n) => (
                <option key={n} value={n} />
              ))}
            </datalist>
          </div>
          <div className="sm:col-span-3">
            <Field id="med-manufacturer" label={t('medicines.manufacturer')}>
              <Input
                id="med-manufacturer"
                list="med-manufacturer-list"
                placeholder="Beximco"
                {...form.register('manufacturerName')}
              />
            </Field>
            <datalist id="med-manufacturer-list">
              {(manufacturers.data ?? []).map((n) => (
                <option key={n} value={n} />
              ))}
            </datalist>
          </div>

          <div className="sm:col-span-2">
            <Field id="med-form" label={t('medicines.form')}>
              <Select
                id="med-form"
                {...form.register('dosageForm', {
                  onChange: (e: { target: { value: DosageForm } }) => {
                    const unit = DEFAULT_UNIT[e.target.value]
                    if (unit && !form.getFieldState('baseUnitLabel').isDirty) {
                      form.setValue('baseUnitLabel', unit)
                    }
                  },
                })}
              >
                {DOSAGE_FORMS.map((f) => (
                  <option key={f} value={f}>
                    {t(`medicines.forms.${f}`)}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          <div className="sm:col-span-2">
            <Field
              id="med-unit"
              label={t('medicines.unit')}
              hint={t('medicines.unitHint')}
              error={errors.baseUnitLabel ? t('medicines.required') : undefined}
            >
              <Input
                id="med-unit"
                placeholder={DEFAULT_UNIT[dosageForm] ?? 'piece'}
                aria-invalid={invalid('baseUnitLabel')}
                {...form.register('baseUnitLabel')}
              />
            </Field>
          </div>
          <div className="sm:col-span-2">
            <Field id="med-rack" label={t('medicines.rack')} hint={t('medicines.rackHint')}>
              <Input
                id="med-rack"
                placeholder="A-3"
                className="uppercase"
                maxLength={40}
                {...form.register('rackLocation')}
              />
            </Field>
          </div>

          <fieldset className="grid gap-1.5 sm:col-span-4">
            <legend className="mb-1.5 text-sm font-medium">{t('medicines.schedule')}</legend>
            <div className="grid grid-cols-3 gap-1 rounded-lg bg-surface-muted p-1">
              {SCHEDULES.map((s) => (
                <label
                  key={s}
                  className={cn(
                    'cursor-pointer rounded-md px-2 py-1.5 text-center text-sm font-medium transition-colors has-[:focus-visible]:ring-3 has-[:focus-visible]:ring-ring/25',
                    schedule === s
                      ? 'bg-surface text-foreground shadow-sm'
                      : 'text-muted-foreground hover:text-foreground',
                  )}
                >
                  <input
                    type="radio"
                    value={s}
                    className="sr-only"
                    {...form.register('schedule')}
                  />
                  {t(`medicines.schedules.${s}`)}
                </label>
              ))}
            </div>
            <p className="text-xs text-muted-foreground">
              {t(`medicines.scheduleHint.${schedule}`)}
            </p>
          </fieldset>
          <div className="sm:col-span-2">
            <Field
              id="med-reorder"
              label={t('medicines.reorderLevel')}
              hint={t('medicines.reorderHint')}
              error={errors.reorderLevel ? t('medicines.wholeNumber') : undefined}
            >
              <Input
                id="med-reorder"
                inputMode="numeric"
                placeholder="0"
                aria-invalid={invalid('reorderLevel')}
                {...form.register('reorderLevel')}
              />
            </Field>
          </div>

          <div className="sm:col-span-4">
            <Field
              id="med-barcodes"
              label={t('medicines.barcodes')}
              hint={t('medicines.barcodesHint')}
              error={errors.barcodes ? t('errors.invalid_barcode') : undefined}
            >
              <Input
                id="med-barcodes"
                placeholder="8941100500012"
                aria-invalid={invalid('barcodes')}
                {...form.register('barcodes')}
              />
            </Field>
          </div>
          <div className="sm:col-span-2">
            <Field id="med-sku" label={t('medicines.sku')}>
              <Input id="med-sku" {...form.register('sku')} />
            </Field>
          </div>

          <div className="sm:col-span-6">
            <Field id="med-notes" label={t('medicines.notes')}>
              <Input id="med-notes" {...form.register('notes')} />
            </Field>
          </div>

          <div className="flex flex-wrap gap-x-6 gap-y-2 sm:col-span-6">
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                className="size-4 accent-primary"
                {...form.register('loyaltyEligible')}
              />
              {t('medicines.loyaltyEligible')}
            </label>
            {medicine ? (
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  className="size-4 accent-primary"
                  {...form.register('isActive')}
                />
                {t('medicines.active')}
              </label>
            ) : null}
          </div>

          <div className="flex justify-end gap-2 sm:col-span-6">
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
