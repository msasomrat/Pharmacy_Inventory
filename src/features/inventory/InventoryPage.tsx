import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, PackageMinus } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { PageHeader } from '@/components/layout/PageHeader'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table'
import { useWorkspace } from '@/features/org/org-context'
import { currentLanguage } from '@/i18n'
import { rpc } from '@/lib/api'
import { formatDate } from '@/lib/dates'
import { formatNumber } from '@/lib/format'
import { formatTaka, paisa } from '@/domain/money'

import { StockOnHand } from './StockOnHand'

export function InventoryPage() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { branch } = useWorkspace()
  const expiring = useQuery({
    queryKey: ['report_expiring_stock', branch.id, 90],
    queryFn: () => rpc('report_expiring_stock', { p_branch_id: branch.id, p_days: 90 }),
  })
  const low = useQuery({
    queryKey: ['report_low_stock', branch.id],
    queryFn: () => rpc('report_low_stock', { p_branch_id: branch.id }),
  })

  return (
    <>
      <PageHeader
        title={t('inventory.title')}
        description={t('inventory.subtitle', { branch: branch.name })}
      />
      <div className="grid min-w-0 grid-cols-1 gap-6">
        <StockOnHand />
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <AlertTriangle className="size-4 text-warning" aria-hidden />
              {t('dashboard.expiring')}
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            {expiring.isPending ? (
              <Skeleton className="m-5 h-40" />
            ) : (expiring.data ?? []).length === 0 ? (
              <EmptyState icon={AlertTriangle} title={t('dashboard.noExpiring')} />
            ) : (
              <Table>
                <THead>
                  <TR>
                    <TH>{t('inventory.medicine')}</TH>
                    <TH className="hidden sm:table-cell">{t('inventory.batch')}</TH>
                    <TH>{t('inventory.expiry')}</TH>
                    <TH className="text-right">{t('inventory.onHand')}</TH>
                    <TH className="hidden text-right sm:table-cell">{t('inventory.valueMrp')}</TH>
                  </TR>
                </THead>
                <TBody>
                  {(expiring.data ?? []).map((b) => (
                    <TR key={b.batch_id}>
                      <TD className="font-medium">{b.brand_name}</TD>
                      <TD className="hidden font-mono text-xs sm:table-cell">{b.batch_no}</TD>
                      <TD>
                        <span className="mr-2">{formatDate(b.expiry_date, lng)}</span>
                        <Badge
                          tone={
                            b.days_left <= 0 ? 'danger' : b.days_left <= 30 ? 'warning' : 'neutral'
                          }
                        >
                          {t('dashboard.daysLeft', {
                            count: b.days_left,
                            n: formatNumber(b.days_left, lng),
                          })}
                        </Badge>
                      </TD>
                      <TD className="tabular text-right">
                        {formatNumber(b.quantity_on_hand, lng)}
                      </TD>
                      <TD className="tabular hidden text-right sm:table-cell">
                        {formatTaka(paisa(b.stock_value_mrp_paisa), lng)}
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <PackageMinus className="size-4 text-danger" aria-hidden />
              {t('dashboard.lowStock')}
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            {low.isPending ? (
              <Skeleton className="m-5 h-24" />
            ) : (low.data ?? []).length === 0 ? (
              <EmptyState icon={PackageMinus} title={t('dashboard.noLowStock')} />
            ) : (
              <Table>
                <THead>
                  <TR>
                    <TH>{t('inventory.medicine')}</TH>
                    <TH className="hidden sm:table-cell">{t('inventory.rack')}</TH>
                    <TH className="text-right">{t('inventory.sellable')}</TH>
                    <TH className="text-right">{t('inventory.reorderLevel')}</TH>
                  </TR>
                </THead>
                <TBody>
                  {(low.data ?? []).map((m) => (
                    <TR key={m.medicine_id}>
                      <TD>
                        <p className="font-medium">{m.brand_name}</p>
                        <p className="text-xs text-muted-foreground">{m.generic_name}</p>
                      </TD>
                      <TD className="hidden sm:table-cell">
                        {(m.rack_location as string | null) ?? '—'}
                      </TD>
                      <TD className="tabular text-right font-semibold text-danger">
                        {formatNumber(m.sellable_quantity, lng)}
                      </TD>
                      <TD className="tabular text-right">{formatNumber(m.reorder_level, lng)}</TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  )
}
