import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { AlertTriangle, BarChart3, Boxes, Download, PackageMinus } from 'lucide-react'
import { useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'

import { PageHeader } from '@/components/layout/PageHeader'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table'
import { formatTaka, paisa } from '@/domain/money'
import { useWorkspace } from '@/features/org/org-context'
import { currentLanguage } from '@/i18n'
import { rpc } from '@/lib/api'
import { cn } from '@/lib/cn'
import { downloadCsv, toCsv } from '@/lib/csv'
import { addDays, businessDate, formatDate } from '@/lib/dates'
import { formatNumber } from '@/lib/format'

import { aggregateSales, presetRange, type Preset } from './report-math'

type Tab = 'sales' | 'stock' | 'expiry' | 'low'
const PRESETS: Preset[] = ['today', 'yesterday', 'last7', 'thisMonth', 'lastMonth', 'custom']

function Stat({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone?: 'danger' | 'success'
}) {
  return (
    <Card className="p-4">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p
        className={cn(
          'tabular mt-1 text-xl font-semibold tracking-tight',
          tone === 'danger' && 'text-danger',
          tone === 'success' && 'text-success',
        )}
      >
        {value}
      </p>
    </Card>
  )
}

function BranchSelect({
  id,
  value,
  onChange,
  allowAll,
}: {
  id: string
  value: string
  onChange: (v: string) => void
  allowAll?: boolean
}) {
  const { t } = useTranslation()
  const { org } = useWorkspace()
  return (
    <Field id={id} label={t('nav.branch')}>
      <Select id={id} value={value} onChange={(e) => onChange(e.target.value)}>
        {allowAll ? <option value="">{t('reports.allBranches')}</option> : null}
        {org.branches.map((b) => (
          <option key={b.id} value={b.id}>
            {b.name}
          </option>
        ))}
      </Select>
    </Field>
  )
}

function SalesReport() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { org, can } = useWorkspace()
  const today = businessDate()
  const [preset, setPreset] = useState<Preset>('last7')
  const [custom, setCustom] = useState({ from: addDays(today, -6), to: today })
  const [branchId, setBranchId] = useState('')
  const range = preset === 'custom' ? custom : presetRange(preset, today)
  const validRange = range.from <= range.to

  const report = useQuery({
    queryKey: ['report_sales_summary', org.organizationId, range.from, range.to, branchId],
    queryFn: () =>
      rpc('report_sales_summary', {
        p_organization_id: org.organizationId,
        p_from: range.from,
        p_to: range.to,
        ...(branchId ? { p_branch_id: branchId } : {}),
      }),
    enabled: validRange,
    placeholderData: keepPreviousData,
  })
  const rows = report.data ?? []
  const agg = useMemo(() => aggregateSales(report.data ?? []), [report.data])
  const showCost = agg.totals.profitPaisa !== null
  const tk = (p: number | null) => (p === null ? '—' : formatTaka(paisa(p), lng))

  function exportCsv() {
    const header = [
      'date',
      'branch',
      'bills',
      'gross',
      'discount',
      'loyalty_discount',
      'returns',
      'net_sales',
      'credit_sales',
    ]
    if (showCost) header.push('cost', 'gross_profit')
    const body = rows.map((r) => {
      const line: (string | number | null)[] = [
        r.business_date,
        r.branch_name,
        r.sales_count,
        r.gross_paisa / 100,
        r.discount_paisa / 100,
        r.loyalty_discount_paisa / 100,
        r.returns_paisa / 100,
        r.net_sales_paisa / 100,
        r.credit_sales_paisa / 100,
      ]
      if (showCost)
        line.push(
          (r.cost_paisa as number | null) === null ? null : r.cost_paisa / 100,
          (r.gross_profit_paisa as number | null) === null ? null : r.gross_profit_paisa / 100,
        )
      return line
    })
    downloadCsv(`sales_${range.from}_${range.to}.csv`, toCsv(header, body))
  }

  return (
    <div className="grid min-w-0 grid-cols-1 gap-6">
      <Card>
        <CardContent className="flex flex-wrap items-end gap-4 pt-5">
          <div
            role="group"
            aria-label={t('reports.period')}
            className="flex flex-wrap gap-1 rounded-lg bg-surface-muted p-1"
          >
            {PRESETS.map((p) => (
              <button
                key={p}
                type="button"
                aria-pressed={preset === p}
                onClick={() => setPreset(p)}
                className={cn(
                  'rounded-md px-3 py-1.5 text-sm font-medium transition-colors',
                  preset === p
                    ? 'bg-surface text-foreground shadow-sm'
                    : 'text-muted-foreground hover:text-foreground',
                )}
              >
                {t(`reports.presets.${p}`)}
              </button>
            ))}
          </div>
          {preset === 'custom' ? (
            <>
              <Field id="rp-from" label={t('reports.from')}>
                <Input
                  id="rp-from"
                  type="date"
                  max={today}
                  value={custom.from}
                  onChange={(e) => setCustom((c) => ({ ...c, from: e.target.value }))}
                />
              </Field>
              <Field
                id="rp-to"
                label={t('reports.to')}
                error={validRange ? undefined : t('reports.badRange')}
              >
                <Input
                  id="rp-to"
                  type="date"
                  max={today}
                  value={custom.to}
                  onChange={(e) => setCustom((c) => ({ ...c, to: e.target.value }))}
                />
              </Field>
            </>
          ) : (
            <p className="pb-2 text-sm text-muted-foreground">
              {formatDate(range.from, lng)} – {formatDate(range.to, lng)}
            </p>
          )}
          <div className="min-w-44">
            <BranchSelect id="rp-branch" value={branchId} onChange={setBranchId} allowAll />
          </div>
          {can('data.export') ? (
            <Button
              variant="secondary"
              className="ml-auto"
              disabled={rows.length === 0}
              onClick={exportCsv}
            >
              <Download aria-hidden />
              {t('reports.exportCsv')}
            </Button>
          ) : null}
        </CardContent>
      </Card>

      <section aria-label={t('reports.totals')} className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label={t('reports.netSales')} value={tk(agg.totals.netPaisa)} />
        <Stat label={t('reports.bills')} value={formatNumber(agg.totals.bills, lng)} />
        <Stat label={t('reports.discounts')} value={tk(agg.totals.discountPaisa)} />
        {showCost ? (
          <Stat
            label={t('reports.grossProfit')}
            value={tk(agg.totals.profitPaisa)}
            tone={(agg.totals.profitPaisa ?? 0) < 0 ? 'danger' : 'success'}
          />
        ) : (
          <Stat label={t('reports.returns')} value={tk(agg.totals.returnsPaisa)} />
        )}
      </section>

      <Card>
        <CardHeader>
          <CardTitle>{t('reports.byDay')}</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {report.isPending ? (
            <Skeleton className="m-5 h-40" />
          ) : agg.byDay.length === 0 ? (
            <EmptyState icon={BarChart3} title={t('reports.noSales')} />
          ) : (
            <Table>
              <THead>
                <TR>
                  <TH>{t('purchases.date')}</TH>
                  <TH className="text-right">{t('reports.bills')}</TH>
                  <TH className="hidden text-right sm:table-cell">{t('reports.discounts')}</TH>
                  <TH className="hidden text-right md:table-cell">{t('reports.returns')}</TH>
                  <TH className="text-right">{t('reports.netSales')}</TH>
                  {showCost ? (
                    <TH className="hidden text-right sm:table-cell">{t('reports.grossProfit')}</TH>
                  ) : null}
                </TR>
              </THead>
              <TBody>
                {agg.byDay.map((d) => (
                  <TR key={d.date}>
                    <TD>{formatDate(d.date, lng)}</TD>
                    <TD className="tabular text-right">{formatNumber(d.bills, lng)}</TD>
                    <TD className="tabular hidden text-right sm:table-cell">
                      {tk(d.discountPaisa)}
                    </TD>
                    <TD className="tabular hidden text-right md:table-cell">
                      {tk(d.returnsPaisa)}
                    </TD>
                    <TD className="tabular text-right font-medium">{tk(d.netPaisa)}</TD>
                    {showCost ? (
                      <TD className="tabular hidden text-right sm:table-cell">
                        {tk(d.profitPaisa)}
                      </TD>
                    ) : null}
                  </TR>
                ))}
              </TBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {!branchId && agg.byBranch.length > 1 ? (
        <Card>
          <CardHeader>
            <CardTitle>{t('reports.byBranch')}</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <Table>
              <TBody>
                {agg.byBranch.map((b) => (
                  <TR key={b.branchId}>
                    <TD className="font-medium">{b.branchName}</TD>
                    <TD className="tabular text-right">{formatNumber(b.bills, lng)}</TD>
                    <TD className="tabular text-right font-medium">{tk(b.netPaisa)}</TD>
                    {showCost ? (
                      <TD className="tabular hidden text-right sm:table-cell">
                        {tk(b.profitPaisa)}
                      </TD>
                    ) : null}
                  </TR>
                ))}
              </TBody>
            </Table>
          </CardContent>
        </Card>
      ) : null}
    </div>
  )
}

function StockValueReport() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { org } = useWorkspace()
  const value = useQuery({
    queryKey: ['report_stock_value', org.organizationId],
    queryFn: () => rpc('report_stock_value', { p_organization_id: org.organizationId }),
  })
  const rows = value.data ?? []
  const showCost = rows.some((r) => (r.value_cost_paisa as number | null) !== null)
  const sum = (k: 'units' | 'value_mrp_paisa' | 'value_cost_paisa' | 'expired_units') =>
    rows.reduce((s, r) => s + ((r[k] as number | null) ?? 0), 0)
  return (
    <Card>
      <CardContent className="p-0">
        {value.isPending ? (
          <Skeleton className="m-5 h-32" />
        ) : (
          <Table>
            <THead>
              <TR>
                <TH>{t('nav.branch')}</TH>
                <TH className="hidden text-right sm:table-cell">{t('reports.skus')}</TH>
                <TH className="text-right">{t('reports.units')}</TH>
                <TH className="text-right">{t('inventory.valueMrp')}</TH>
                {showCost ? (
                  <TH className="hidden text-right sm:table-cell">{t('reports.valueCost')}</TH>
                ) : null}
                <TH className="hidden text-right md:table-cell">{t('reports.expiredUnits')}</TH>
              </TR>
            </THead>
            <TBody>
              {rows.map((r) => (
                <TR key={r.branch_id}>
                  <TD className="font-medium">{r.branch_name}</TD>
                  <TD className="tabular hidden text-right sm:table-cell">
                    {formatNumber(r.sku_count, lng)}
                  </TD>
                  <TD className="tabular text-right">{formatNumber(r.units, lng)}</TD>
                  <TD className="tabular text-right">
                    {formatTaka(paisa(r.value_mrp_paisa), lng)}
                  </TD>
                  {showCost ? (
                    <TD className="tabular hidden text-right sm:table-cell">
                      {formatTaka(paisa(r.value_cost_paisa), lng)}
                    </TD>
                  ) : null}
                  <TD className="tabular hidden text-right md:table-cell">
                    {r.expired_units > 0 ? (
                      <Badge tone="danger">{formatNumber(r.expired_units, lng)}</Badge>
                    ) : (
                      '—'
                    )}
                  </TD>
                </TR>
              ))}
              {rows.length > 1 ? (
                <TR className="font-semibold">
                  <TD>{t('reports.total')}</TD>
                  <TD className="hidden sm:table-cell" />
                  <TD className="tabular text-right">{formatNumber(sum('units'), lng)}</TD>
                  <TD className="tabular text-right">
                    {formatTaka(paisa(sum('value_mrp_paisa')), lng)}
                  </TD>
                  {showCost ? (
                    <TD className="tabular hidden text-right sm:table-cell">
                      {formatTaka(paisa(sum('value_cost_paisa')), lng)}
                    </TD>
                  ) : null}
                  <TD className="tabular hidden text-right md:table-cell">
                    {formatNumber(sum('expired_units'), lng)}
                  </TD>
                </TR>
              ) : null}
            </TBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}

function ExpiryReport() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { branch, can } = useWorkspace()
  const [branchId, setBranchId] = useState(branch.id)
  const [days, setDays] = useState('90')
  const expiring = useQuery({
    queryKey: ['report_expiring_stock', branchId, Number(days)],
    queryFn: () => rpc('report_expiring_stock', { p_branch_id: branchId, p_days: Number(days) }),
  })
  const rows = expiring.data ?? []
  return (
    <Card>
      <CardContent className="flex flex-wrap items-end gap-4 border-b pt-5 pb-4">
        <div className="min-w-44">
          <BranchSelect id="ex-branch" value={branchId} onChange={setBranchId} />
        </div>
        <Field id="ex-days" label={t('reports.within')}>
          <Select id="ex-days" value={days} onChange={(e) => setDays(e.target.value)}>
            {['30', '60', '90', '180', '365'].map((d) => (
              <option key={d} value={d}>
                {t('reports.daysN', { n: formatNumber(Number(d), lng) })}
              </option>
            ))}
          </Select>
        </Field>
        {can('data.export') ? (
          <button
            type="button"
            className="ml-auto inline-flex h-10 items-center gap-2 rounded-md border px-4 text-sm font-medium shadow-sm hover:bg-surface-muted disabled:opacity-50"
            disabled={rows.length === 0}
            onClick={() =>
              downloadCsv(
                `expiring_${days}d.csv`,
                toCsv(
                  ['medicine', 'batch', 'expiry', 'days_left', 'quantity', 'value_mrp'],
                  rows.map((r) => [
                    r.brand_name,
                    r.batch_no,
                    r.expiry_date,
                    r.days_left,
                    r.quantity_on_hand,
                    r.stock_value_mrp_paisa / 100,
                  ]),
                ),
              )
            }
          >
            <Download className="size-4" aria-hidden />
            {t('reports.exportCsv')}
          </button>
        ) : null}
      </CardContent>
      <CardContent className="p-0">
        {expiring.isPending ? (
          <Skeleton className="m-5 h-32" />
        ) : rows.length === 0 ? (
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
              {rows.map((r) => (
                <TR key={r.batch_id}>
                  <TD className="font-medium">{r.brand_name}</TD>
                  <TD className="hidden font-mono text-xs sm:table-cell">{r.batch_no}</TD>
                  <TD>
                    <span className="mr-2">{formatDate(r.expiry_date, lng)}</span>
                    <Badge
                      tone={r.days_left <= 0 ? 'danger' : r.days_left <= 30 ? 'warning' : 'neutral'}
                    >
                      {t('dashboard.daysLeft', {
                        count: r.days_left,
                        n: formatNumber(r.days_left, lng),
                      })}
                    </Badge>
                  </TD>
                  <TD className="tabular text-right">{formatNumber(r.quantity_on_hand, lng)}</TD>
                  <TD className="tabular hidden text-right sm:table-cell">
                    {formatTaka(paisa(r.stock_value_mrp_paisa), lng)}
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}

function LowStockReport() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { branch } = useWorkspace()
  const [branchId, setBranchId] = useState(branch.id)
  const low = useQuery({
    queryKey: ['report_low_stock', branchId],
    queryFn: () => rpc('report_low_stock', { p_branch_id: branchId }),
  })
  const rows = low.data ?? []
  return (
    <Card>
      <CardContent className="border-b pt-5 pb-4">
        <div className="max-w-xs">
          <BranchSelect id="low-branch" value={branchId} onChange={setBranchId} />
        </div>
      </CardContent>
      <CardContent className="p-0">
        {low.isPending ? (
          <Skeleton className="m-5 h-32" />
        ) : rows.length === 0 ? (
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
              {rows.map((m) => (
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
  )
}

export function ReportsPage() {
  const { t } = useTranslation()
  const { can } = useWorkspace()
  const [tab, setTab] = useState<Tab>('sales')
  if (!can('reports.view')) {
    return (
      <>
        <PageHeader title={t('nav.reports')} />
        <Card>
          <EmptyState icon={Boxes} title={t('reports.noAccess')} />
        </Card>
      </>
    )
  }
  return (
    <>
      <PageHeader title={t('nav.reports')} description={t('reports.subtitle')} />
      <div
        role="tablist"
        aria-label={t('nav.reports')}
        className="mb-6 inline-flex flex-wrap gap-1 rounded-lg bg-surface-muted p-1"
      >
        {(['sales', 'stock', 'expiry', 'low'] as const).map((id) => (
          <button
            key={id}
            role="tab"
            type="button"
            aria-selected={tab === id}
            aria-controls={`reports-${id}`}
            onClick={() => setTab(id)}
            className={cn(
              'rounded-md px-4 py-1.5 text-sm font-medium transition-colors',
              tab === id
                ? 'bg-surface text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            )}
          >
            {t(`reports.tabs.${id}`)}
          </button>
        ))}
      </div>
      <div role="tabpanel" id={`reports-${tab}`}>
        {tab === 'sales' ? (
          <SalesReport />
        ) : tab === 'stock' ? (
          <StockValueReport />
        ) : tab === 'expiry' ? (
          <ExpiryReport />
        ) : (
          <LowStockReport />
        )}
      </div>
    </>
  )
}
