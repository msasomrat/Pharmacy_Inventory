import { useQuery } from '@tanstack/react-query'
import { Boxes, Search } from 'lucide-react'
import { useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table'
import { formatTaka, paisa } from '@/domain/money'
import { useWorkspace } from '@/features/org/org-context'
import { currentLanguage } from '@/i18n'
import { businessDate, formatDate } from '@/lib/dates'
import { toAppError } from '@/lib/errors'
import { formatNumber } from '@/lib/format'
import { supabase } from '@/lib/supabase'

const LIMIT = 1000

interface StockRow {
  medicineId: string
  brandName: string
  strength: string | null
  unit: string
  rack: string | null
  quantity: number
  batches: number
  nearestExpiry: string
  salePricePaisa: number
}

async function fetchStock(branchId: string): Promise<StockRow[]> {
  const [batches, settings] = await Promise.all([
    supabase
      .from('batches')
      .select(
        'medicine_id, expiry_date, quantity_on_hand, sale_price_paisa, received_at, medicines(brand_name, strength, base_unit_label)',
      )
      .eq('branch_id', branchId)
      .eq('is_depleted', false)
      .order('expiry_date')
      .order('received_at')
      .limit(LIMIT),
    supabase
      .from('branch_medicine_settings')
      .select('medicine_id, rack_location')
      .eq('branch_id', branchId),
  ])
  if (batches.error) throw toAppError(batches.error)
  if (settings.error) throw toAppError(settings.error)
  const racks = new Map(settings.data.map((s) => [s.medicine_id, s.rack_location]))

  // Batches arrive in FEFO order, so the first batch seen per medicine is the one sold next.
  const byMedicine = new Map<string, StockRow>()
  for (const b of batches.data) {
    const row = byMedicine.get(b.medicine_id)
    if (row) {
      row.quantity += b.quantity_on_hand
      row.batches += 1
    } else {
      byMedicine.set(b.medicine_id, {
        medicineId: b.medicine_id,
        brandName: b.medicines.brand_name,
        strength: b.medicines.strength,
        unit: b.medicines.base_unit_label,
        rack: racks.get(b.medicine_id) ?? null,
        quantity: b.quantity_on_hand,
        batches: 1,
        nearestExpiry: b.expiry_date,
        salePricePaisa: b.sale_price_paisa,
      })
    }
  }
  return [...byMedicine.values()].sort((a, b) => a.brandName.localeCompare(b.brandName))
}

export function StockOnHand() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { branch } = useWorkspace()
  const [filter, setFilter] = useState('')
  const today = businessDate()
  const stock = useQuery({ queryKey: ['stock', branch.id], queryFn: () => fetchStock(branch.id) })

  const rows = useMemo(() => {
    const q = filter.trim().toLowerCase()
    const all = stock.data ?? []
    return q ? all.filter((r) => `${r.brandName} ${r.rack ?? ''}`.toLowerCase().includes(q)) : all
  }, [stock.data, filter])

  return (
    <Card>
      <CardHeader className="flex-row flex-wrap items-center justify-between gap-3">
        <CardTitle className="flex items-center gap-2">
          <Boxes className="size-4 text-primary" aria-hidden />
          {t('inventory.stockOnHand')}
          <Badge>{formatNumber(stock.data?.length ?? 0, lng)}</Badge>
        </CardTitle>
        <div className="relative w-full sm:w-64">
          <Search
            aria-hidden
            className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
          />
          <Input
            type="search"
            aria-label={t('inventory.filter')}
            placeholder={t('inventory.filter')}
            className="h-9 pl-9"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          />
        </div>
      </CardHeader>
      <CardContent className="p-0">
        {stock.isPending ? (
          <Skeleton className="m-5 h-40" />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={Boxes}
            title={filter ? t('medicines.noMatch') : t('inventory.noStock')}
            {...(filter ? {} : { description: t('inventory.noStockBody') })}
          />
        ) : (
          <Table>
            <THead>
              <TR>
                <TH>{t('inventory.medicine')}</TH>
                <TH>{t('inventory.rack')}</TH>
                <TH className="text-right">{t('inventory.onHand')}</TH>
                <TH>{t('inventory.nextExpiry')}</TH>
                <TH className="text-right">{t('inventory.price')}</TH>
              </TR>
            </THead>
            <TBody>
              {rows.map((r) => {
                const days = Math.round(
                  (Date.parse(`${r.nearestExpiry}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) /
                    86_400_000,
                )
                return (
                  <TR key={r.medicineId}>
                    <TD>
                      <p className="font-medium">
                        {r.brandName}{' '}
                        <span className="font-normal text-muted-foreground">{r.strength}</span>
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {t('inventory.batches', {
                          count: r.batches,
                          n: formatNumber(r.batches, lng),
                        })}
                      </p>
                    </TD>
                    <TD>
                      {r.rack ? (
                        <Badge tone="primary" className="font-mono">
                          {r.rack}
                        </Badge>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TD>
                    <TD className="tabular text-right font-medium">
                      {formatNumber(r.quantity, lng)}{' '}
                      <span className="text-xs font-normal text-muted-foreground">{r.unit}</span>
                    </TD>
                    <TD>
                      <span className="mr-2">{formatDate(r.nearestExpiry, lng)}</span>
                      {days <= 90 ? (
                        <Badge tone={days <= 30 ? 'danger' : 'warning'}>
                          {t('dashboard.daysLeft', { count: days, n: formatNumber(days, lng) })}
                        </Badge>
                      ) : null}
                    </TD>
                    <TD className="tabular text-right">
                      {formatTaka(paisa(r.salePricePaisa), lng)}
                    </TD>
                  </TR>
                )
              })}
            </TBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
