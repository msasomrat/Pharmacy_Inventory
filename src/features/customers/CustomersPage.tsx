import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, Contact, CreditCard, Pencil, Plus, Search } from 'lucide-react'
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
import { formatTaka, paisa } from '@/domain/money'
import { EnrollDialog, type PickedCustomer } from '@/features/loyalty/EnrollDialog'
import { useWorkspace } from '@/features/org/org-context'
import { currentLanguage } from '@/i18n'
import { formatDate } from '@/lib/dates'
import { formatNumber } from '@/lib/format'

import { CustomerDialog } from './CustomerDialog'
import { displayPhone } from '@/domain/phone'

import { PAGE_SIZE, listCustomers, type CustomerRow } from './customers-api'

function LoyaltyBadge({ row }: { row: CustomerRow }) {
  const { t } = useTranslation()
  const lng = currentLanguage()
  if (!row.membership)
    return <span className="text-sm text-muted-foreground">{t('customers.noCard')}</span>
  return (
    <span className="inline-flex flex-wrap items-center gap-1.5">
      <Badge tone="primary">
        <CreditCard className="size-3" aria-hidden />
        {row.membership.planName}
      </Badge>
      <span className="text-xs text-muted-foreground">
        {t('loyalty.validTill', { date: formatDate(row.membership.endsOn, lng) })}
      </span>
    </span>
  )
}

export function CustomersPage() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { org, can } = useWorkspace()
  const canManage = can('customers.manage')
  const canEnroll = can('loyalty.enroll')
  const [search, setSearch] = useState('')
  const query = useDeferredValue(search)
  const [page, setPage] = useState(0)
  const [editing, setEditing] = useState<CustomerRow | null>(null)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [enrolling, setEnrolling] = useState<PickedCustomer | null>(null)

  const customers = useQuery({
    queryKey: ['customers', org.organizationId, query, page],
    queryFn: () => listCustomers({ organizationId: org.organizationId, query, page }),
    placeholderData: keepPreviousData,
  })
  const total = customers.data?.total ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const rows = customers.data?.rows ?? []

  function openNew() {
    setEditing(null)
    setDialogOpen(true)
  }

  return (
    <>
      <PageHeader
        title={t('nav.customers')}
        description={t('customers.subtitle', { n: formatNumber(total, lng) })}
        actions={
          canManage ? (
            <Button onClick={openNew}>
              <Plus aria-hidden />
              {t('customers.add')}
            </Button>
          ) : null
        }
      />
      <Card>
        <div className="border-b p-4">
          <div className="relative">
            <Search
              aria-hidden
              className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
            />
            <Input
              type="search"
              aria-label={t('customers.search')}
              placeholder={t('customers.search')}
              className="pl-9"
              value={search}
              onChange={(e) => {
                setSearch(e.target.value)
                setPage(0)
              }}
            />
          </div>
        </div>
        <CardContent className="p-0">
          {customers.isPending ? (
            <Skeleton className="m-5 h-48" />
          ) : rows.length === 0 ? (
            <EmptyState
              icon={Contact}
              title={query ? t('customers.noMatch') : t('customers.empty')}
              {...(query ? {} : { description: t('customers.emptyBody') })}
            />
          ) : (
            <Table>
              <THead>
                <TR>
                  <TH>{t('loyalty.customer')}</TH>
                  <TH className="hidden md:table-cell">{t('nav.loyalty')}</TH>
                  <TH className="text-right">{t('customers.due')}</TH>
                  <TH className="w-24" />
                </TR>
              </THead>
              <TBody>
                {rows.map((c) => (
                  <TR key={c.id} className={c.isActive ? undefined : 'opacity-60'}>
                    <TD>
                      <p className="font-medium">
                        {c.name}{' '}
                        {c.isActive ? null : (
                          <Badge className="ml-1">{t('medicines.inactive')}</Badge>
                        )}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {displayPhone(c.phone) || '—'}
                      </p>
                      <div className="mt-1 md:hidden">
                        <LoyaltyBadge row={c} />
                      </div>
                    </TD>
                    <TD className="hidden md:table-cell">
                      <LoyaltyBadge row={c} />
                    </TD>
                    <TD className="tabular text-right">
                      {c.balancePaisa > 0 ? (
                        <span className="font-medium text-warning">
                          {formatTaka(paisa(c.balancePaisa), lng)}
                        </span>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TD>
                    <TD>
                      <div className="flex justify-end gap-1">
                        {canEnroll && c.isActive ? (
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label={t(
                              c.membership ? 'loyalty.renewNamed' : 'loyalty.enrollNamed',
                              { name: c.name },
                            )}
                            onClick={() => setEnrolling({ id: c.id, name: c.name, phone: c.phone })}
                          >
                            <CreditCard aria-hidden />
                          </Button>
                        ) : null}
                        {canManage ? (
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label={t('customers.editNamed', { name: c.name })}
                            onClick={() => {
                              setEditing(c)
                              setDialogOpen(true)
                            }}
                          >
                            <Pencil aria-hidden />
                          </Button>
                        ) : null}
                      </div>
                    </TD>
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
        <CustomerDialog open={dialogOpen} onOpenChange={setDialogOpen} customer={editing} />
      ) : null}
      {canEnroll ? (
        <EnrollDialog
          open={enrolling !== null}
          onOpenChange={(o) => {
            if (!o) setEnrolling(null)
          }}
          customer={enrolling}
        />
      ) : null}
    </>
  )
}
