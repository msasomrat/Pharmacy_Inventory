import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, Pencil, Pill, Plus, Search } from 'lucide-react'
import { useDeferredValue, useState } from 'react'
import { useTranslation } from 'react-i18next'

import { PageHeader } from '@/components/layout/PageHeader'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table'
import { useWorkspace } from '@/features/org/org-context'
import { roleCan } from '@/features/org/permissions'
import { currentLanguage } from '@/i18n'
import { formatNumber } from '@/lib/format'

import { MedicineDialog } from './MedicineDialog'
import { PAGE_SIZE, listMedicines, type MedicineRow } from './medicines-api'

export function MedicinesPage() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { org, branch } = useWorkspace()
  const canManage = roleCan(org.role, 'catalog.manage')
  const [search, setSearch] = useState('')
  const query = useDeferredValue(search)
  const [page, setPage] = useState(0)
  const [showInactive, setShowInactive] = useState(false)
  const [editing, setEditing] = useState<MedicineRow | null>(null)
  const [dialogOpen, setDialogOpen] = useState(false)

  const medicines = useQuery({
    queryKey: ['medicines', org.organizationId, branch.id, query, page, showInactive],
    queryFn: () =>
      listMedicines({
        organizationId: org.organizationId,
        branchId: branch.id,
        query,
        page,
        includeInactive: showInactive,
      }),
    placeholderData: keepPreviousData,
  })

  const total = medicines.data?.total ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const rows = medicines.data?.rows ?? []

  function openNew() {
    setEditing(null)
    setDialogOpen(true)
  }

  return (
    <>
      <PageHeader
        title={t('medicines.title')}
        description={t('medicines.subtitle', { n: formatNumber(total, lng) })}
        actions={
          canManage ? (
            <Button onClick={openNew}>
              <Plus aria-hidden />
              {t('medicines.add')}
            </Button>
          ) : null
        }
      />

      <Card>
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <div className="relative min-w-60 flex-1">
            <Search
              aria-hidden
              className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
            />
            <Input
              type="search"
              aria-label={t('medicines.search')}
              placeholder={t('medicines.search')}
              className="pl-9"
              value={search}
              onChange={(e) => {
                setSearch(e.target.value)
                setPage(0)
              }}
            />
          </div>
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            <input
              type="checkbox"
              className="size-4 accent-primary"
              checked={showInactive}
              onChange={(e) => {
                setShowInactive(e.target.checked)
                setPage(0)
              }}
            />
            {t('medicines.showInactive')}
          </label>
        </div>

        <CardContent className="p-0">
          {medicines.isPending ? (
            <Skeleton className="m-5 h-64" />
          ) : rows.length === 0 ? (
            <EmptyState
              icon={Pill}
              title={query ? t('medicines.noMatch') : t('medicines.empty')}
              {...(query ? {} : { description: t('medicines.emptyBody') })}
              {...(canManage && !query
                ? {
                    action: (
                      <Button onClick={openNew}>
                        <Plus aria-hidden />
                        {t('medicines.addFirst')}
                      </Button>
                    ),
                  }
                : {})}
            />
          ) : (
            <Table>
              <THead>
                <TR>
                  <TH>{t('medicines.medicine')}</TH>
                  <TH>{t('medicines.form')}</TH>
                  <TH>{t('medicines.rack')}</TH>
                  <TH className="text-right">{t('medicines.reorderLevel')}</TH>
                  <TH>{t('medicines.barcodes')}</TH>
                  {canManage ? <TH className="w-12" /> : null}
                </TR>
              </THead>
              <TBody>
                {rows.map((m) => (
                  <TR key={m.id} className={m.isActive ? undefined : 'opacity-60'}>
                    <TD>
                      <p className="flex flex-wrap items-center gap-2 font-medium">
                        {m.brandName}
                        {m.strength ? (
                          <span className="text-sm font-normal text-muted-foreground">
                            {m.strength}
                          </span>
                        ) : null}
                        {m.schedule !== 'otc' ? (
                          <Badge tone={m.schedule === 'controlled' ? 'danger' : 'info'}>
                            {t(`medicines.schedules.${m.schedule}`)}
                          </Badge>
                        ) : null}
                        {m.isActive ? null : <Badge>{t('medicines.inactive')}</Badge>}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {[m.genericName, m.manufacturerName].filter(Boolean).join(' · ') || '—'}
                      </p>
                    </TD>
                    <TD>
                      <p>{t(`medicines.forms.${m.dosageForm}`)}</p>
                      <p className="text-xs text-muted-foreground">
                        {t('medicines.perUnit', { unit: m.baseUnitLabel })}
                      </p>
                    </TD>
                    <TD>
                      {m.rackLocation ? (
                        <Badge tone="primary" className="font-mono">
                          {m.rackLocation}
                        </Badge>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TD>
                    <TD className="tabular text-right">
                      {m.reorderLevel > 0 ? formatNumber(m.reorderLevel, lng) : '—'}
                    </TD>
                    <TD className="max-w-40 truncate font-mono text-xs text-muted-foreground">
                      {m.barcodes.join(', ') || '—'}
                    </TD>
                    {canManage ? (
                      <TD>
                        <Button
                          variant="ghost"
                          size="icon"
                          aria-label={t('medicines.editNamed', { name: m.brandName })}
                          onClick={() => {
                            setEditing(m)
                            setDialogOpen(true)
                          }}
                        >
                          <Pencil aria-hidden />
                        </Button>
                      </TD>
                    ) : null}
                  </TR>
                ))}
              </TBody>
            </Table>
          )}
        </CardContent>

        {pages > 1 ? (
          <div className="flex items-center justify-between border-t px-4 py-3 text-sm text-muted-foreground">
            <span>
              {t('common.pageOf', {
                page: formatNumber(page + 1, lng),
                pages: formatNumber(pages, lng),
              })}
            </span>
            <div className="flex gap-2">
              <Button
                variant="secondary"
                size="sm"
                disabled={page === 0}
                onClick={() => setPage((p) => p - 1)}
              >
                <ChevronLeft aria-hidden />
                {t('common.previous')}
              </Button>
              <Button
                variant="secondary"
                size="sm"
                disabled={page + 1 >= pages}
                onClick={() => setPage((p) => p + 1)}
              >
                {t('common.next')}
                <ChevronRight aria-hidden />
              </Button>
            </div>
          </div>
        ) : null}
      </Card>

      {canManage ? (
        <MedicineDialog open={dialogOpen} onOpenChange={setDialogOpen} medicine={editing} />
      ) : null}
    </>
  )
}
