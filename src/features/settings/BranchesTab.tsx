import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Pencil, Plus, Store } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table'
import { displayPhone, isValidBdPhone, normalizeBdPhone } from '@/domain/phone'
import { useOrg, useWorkspace } from '@/features/org/org-context'
import { rpc } from '@/lib/api'
import { errorMessage, toAppError } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

interface BranchRow {
  id: string
  code: string
  name: string
  address: string | null
  phone: string | null
  isActive: boolean
}

async function listBranches(organizationId: string): Promise<BranchRow[]> {
  const { data, error } = await supabase
    .from('branches')
    .select('id, code, name, address, phone, is_active')
    .eq('organization_id', organizationId)
    .order('is_active', { ascending: false })
    .order('name')
  if (error) throw toAppError(error)
  return data.map((b) => ({
    id: b.id,
    code: b.code,
    name: b.name,
    address: b.address,
    phone: b.phone,
    isActive: b.is_active,
  }))
}

function BranchForm({ branch, onDone }: { branch: BranchRow | null; onDone: () => void }) {
  const { t } = useTranslation()
  const { org } = useWorkspace()
  const { refetch } = useOrg()
  const queryClient = useQueryClient()
  const [name, setName] = useState(branch?.name ?? '')
  const [code, setCode] = useState(branch?.code ?? '')
  const [address, setAddress] = useState(branch?.address ?? '')
  const [phone, setPhone] = useState(displayPhone(branch?.phone ?? null))
  const [isActive, setIsActive] = useState(branch?.isActive ?? true)
  const [showErrors, setShowErrors] = useState(false)
  const errors = {
    name: name.trim().length < 2,
    code: !branch && !/^[A-Za-z0-9]{2,6}$/.test(code.trim()),
    phone: !isValidBdPhone(phone),
  }

  const save = useMutation({
    mutationFn: async () => {
      if (branch) {
        const { error } = await supabase
          .from('branches')
          .update({
            name: name.trim(),
            address: address.trim() || null,
            phone: normalizeBdPhone(phone),
            is_active: isActive,
          })
          .eq('id', branch.id)
        if (error) throw toAppError(error)
      } else {
        await rpc('create_branch', {
          p_organization_id: org.organizationId,
          p_code: code.trim().toUpperCase(),
          p_name: name.trim(),
          ...(address.trim() ? { p_address: address.trim() } : {}),
          ...(phone.trim() ? { p_phone: phone.trim() } : {}),
        })
      }
    },
    onSuccess: async () => {
      toast.success(t('settings.branchSaved', { name: name.trim() }))
      await queryClient.invalidateQueries({ queryKey: ['branches-admin'] })
      await refetch()
      onDone()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <div className="grid gap-4">
      <DialogHeader>
        <DialogTitle>{t(branch ? 'settings.editBranch' : 'settings.addBranch')}</DialogTitle>
        <DialogDescription>{t('settings.branchBody')}</DialogDescription>
      </DialogHeader>
      <div className="grid gap-4 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <Field
            id="br-name"
            label={t('settings.branchName')}
            error={showErrors && errors.name ? t('medicines.required') : undefined}
          >
            <Input id="br-name" value={name} onChange={(e) => setName(e.target.value)} />
          </Field>
        </div>
        <Field
          id="br-code"
          label={t('onboarding.branchCode')}
          hint={branch ? t('settings.codeFixed') : t('onboarding.branchCodeHint')}
          error={showErrors && errors.code ? t('settings.codeInvalid') : undefined}
        >
          <Input
            id="br-code"
            className="uppercase"
            maxLength={6}
            disabled={branch !== null}
            value={code}
            onChange={(e) => setCode(e.target.value)}
          />
        </Field>
        <div className="sm:col-span-2">
          <Field id="br-address" label={t('purchases.address')}>
            <Input id="br-address" value={address} onChange={(e) => setAddress(e.target.value)} />
          </Field>
        </div>
        <Field
          id="br-phone"
          label={t('purchases.phone')}
          error={showErrors && errors.phone ? t('errors.invalid_phone') : undefined}
        >
          <Input
            id="br-phone"
            inputMode="tel"
            placeholder="01XXXXXXXXX"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
        </Field>
      </div>
      {branch ? (
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            className="size-4 accent-primary"
            checked={isActive}
            onChange={(e) => setIsActive(e.target.checked)}
          />
          {t('settings.branchOpen')}
        </label>
      ) : null}
      <div className="flex justify-end gap-2">
        <Button variant="secondary" onClick={onDone}>
          {t('common.cancel')}
        </Button>
        <Button
          loading={save.isPending}
          onClick={() => {
            setShowErrors(true)
            if (!errors.name && !errors.code && !errors.phone) save.mutate()
          }}
        >
          {t('common.save')}
        </Button>
      </div>
    </div>
  )
}

export function BranchesTab() {
  const { t } = useTranslation()
  const { org } = useWorkspace()
  const [editing, setEditing] = useState<BranchRow | null | undefined>(undefined)
  const branches = useQuery({
    queryKey: ['branches-admin', org.organizationId],
    queryFn: () => listBranches(org.organizationId),
  })

  return (
    <Card>
      <CardHeader className="flex-row flex-wrap items-center justify-between gap-3">
        <CardTitle className="flex items-center gap-2">
          <Store className="size-4 text-primary" aria-hidden />
          {t('settings.tabs.branches')}
        </CardTitle>
        <Button onClick={() => setEditing(null)}>
          <Plus aria-hidden />
          {t('settings.addBranch')}
        </Button>
      </CardHeader>
      <CardContent className="p-0">
        {branches.isPending ? (
          <Skeleton className="m-5 h-32" />
        ) : (
          <Table>
            <THead>
              <TR>
                <TH>{t('settings.branchName')}</TH>
                <TH className="hidden sm:table-cell">{t('purchases.address')}</TH>
                <TH className="hidden md:table-cell">{t('purchases.phone')}</TH>
                <TH className="w-12" />
              </TR>
            </THead>
            <TBody>
              {(branches.data ?? []).map((b) => (
                <TR key={b.id} className={b.isActive ? undefined : 'opacity-60'}>
                  <TD>
                    <p className="flex items-center gap-2 font-medium">
                      {b.name} <Badge className="font-mono">{b.code}</Badge>
                      {b.isActive ? null : <Badge tone="danger">{t('settings.closed')}</Badge>}
                    </p>
                  </TD>
                  <TD className="hidden text-sm sm:table-cell">{b.address ?? '—'}</TD>
                  <TD className="hidden text-sm md:table-cell">{displayPhone(b.phone) || '—'}</TD>
                  <TD>
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label={t('settings.editNamed', { name: b.name })}
                      onClick={() => setEditing(b)}
                    >
                      <Pencil aria-hidden />
                    </Button>
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        )}
      </CardContent>
      <Dialog
        open={editing !== undefined}
        onOpenChange={(o) => {
          if (!o) setEditing(undefined)
        }}
      >
        <DialogContent closeLabel={t('common.close')}>
          {editing !== undefined ? (
            <BranchForm branch={editing} onDone={() => setEditing(undefined)} />
          ) : null}
        </DialogContent>
      </Dialog>
    </Card>
  )
}
