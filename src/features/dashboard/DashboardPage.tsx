import { useQuery } from '@tanstack/react-query'
import {
  AlertTriangle,
  ArrowDownRight,
  ArrowRight,
  ArrowUpRight,
  PackageMinus,
  Receipt,
  ShoppingCart,
  TrendingUp,
  Wallet,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router'

import { PageHeader } from '@/components/layout/PageHeader'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { Skeleton } from '@/components/ui/skeleton'
import { useAuth } from '@/features/auth/auth-context'
import { useWorkspace } from '@/features/org/org-context'
import { currentLanguage } from '@/i18n'
import { rpc } from '@/lib/api'
import { addDays, businessDate, formatDate } from '@/lib/dates'
import { formatNumber } from '@/lib/format'
import { formatTaka, paisa } from '@/domain/money'

import { SalesTrendChart, type TrendPoint } from './SalesTrendChart'

const EXPIRY_DAYS = 60

function Kpi({
  label,
  value,
  delta,
  icon: Icon,
  muted,
}: {
  label: string
  value: string
  delta?: number | null
  icon: LucideIcon
  muted?: string
}) {
  const { t } = useTranslation()
  return (
    <Card className="p-5">
      <div className="flex items-start justify-between">
        <p className="text-sm text-muted-foreground">{label}</p>
        <span className="grid size-9 place-items-center rounded-lg bg-primary-soft text-primary-soft-foreground">
          <Icon className="size-[18px]" aria-hidden />
        </span>
      </div>
      <p className="tabular mt-2 text-2xl font-semibold tracking-tight">{muted ?? value}</p>
      {delta !== undefined && delta !== null && Number.isFinite(delta) ? (
        <p
          className={`mt-1 flex items-center gap-1 text-xs ${
            Math.abs(delta) < 0.5
              ? 'text-muted-foreground'
              : delta > 0
                ? 'text-success'
                : 'text-danger'
          }`}
        >
          {Math.abs(delta) < 0.5 ? (
            <ArrowRight className="size-3.5" aria-hidden />
          ) : delta > 0 ? (
            <ArrowUpRight className="size-3.5" aria-hidden />
          ) : (
            <ArrowDownRight className="size-3.5" aria-hidden />
          )}
          <span className="tabular font-medium">
            {formatNumber(Math.abs(delta), currentLanguage())}%
          </span>
          <span className="text-muted-foreground">{t('dashboard.vsYesterday')}</span>
        </p>
      ) : (
        <p className="mt-1 text-xs text-transparent select-none">.</p>
      )}
    </Card>
  )
}

function pct(today: number, yesterday: number): number | null {
  return yesterday > 0 ? ((today - yesterday) / yesterday) * 100 : null
}

function dayPart(): 'morning' | 'afternoon' | 'evening' {
  const h = Number(
    new Intl.DateTimeFormat('en-GB', {
      hour: 'numeric',
      hour12: false,
      timeZone: 'Asia/Dhaka',
    }).format(new Date()),
  )
  return h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening'
}

export function DashboardPage() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { session } = useAuth()
  const { org, branch } = useWorkspace()
  const today = businessDate()
  const from = addDays(today, -13)

  const summary = useQuery({
    queryKey: ['report_sales_summary', org.organizationId, branch.id, from, today],
    queryFn: () =>
      rpc('report_sales_summary', {
        p_organization_id: org.organizationId,
        p_from: from,
        p_to: today,
        p_branch_id: branch.id,
      }),
  })
  const expiring = useQuery({
    queryKey: ['report_expiring_stock', branch.id, EXPIRY_DAYS],
    queryFn: () => rpc('report_expiring_stock', { p_branch_id: branch.id, p_days: EXPIRY_DAYS }),
  })
  const lowStock = useQuery({
    queryKey: ['report_low_stock', branch.id],
    queryFn: () => rpc('report_low_stock', { p_branch_id: branch.id }),
  })

  const rows = summary.data ?? []
  const byDate = new Map(rows.map((r) => [r.business_date, r]))
  const trend: TrendPoint[] = Array.from({ length: 14 }, (_, i) => {
    const date = addDays(from, i)
    return { date, netPaisa: byDate.get(date)?.net_sales_paisa ?? 0 }
  })
  const td = byDate.get(today)
  const yd = byDate.get(addDays(today, -1))
  const todayNet = td?.net_sales_paisa ?? 0
  const todayCount = td?.sales_count ?? 0
  const avg = todayCount > 0 ? Math.round(todayNet / todayCount) : 0
  const yAvg = yd && yd.sales_count > 0 ? yd.net_sales_paisa / yd.sales_count : 0
  // Cost/profit columns are NULL for roles without reports.view_cost (generated types omit nullability).
  const profitVisible =
    rows.length === 0 || rows.some((r) => (r.gross_profit_paisa as number | null) !== null)
  const name =
    (session?.user.user_metadata['full_name'] as string | undefined) ??
    session?.user.email?.split('@')[0] ??
    ''

  return (
    <>
      <PageHeader
        title={t('dashboard.greeting', { part: t(`dashboard.${dayPart()}`), name })}
        description={t('dashboard.subtitle', { branch: branch.name })}
        actions={
          <Button asChild>
            <Link to="/pos">
              <ShoppingCart aria-hidden />
              {t('dashboard.newSale')}
            </Link>
          </Button>
        }
      />

      <section aria-label="KPIs" className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {summary.isPending ? (
          Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-[126px] rounded-lg" />)
        ) : (
          <>
            <Kpi
              label={t('dashboard.todaySales')}
              icon={Wallet}
              value={formatTaka(paisa(todayNet), lng)}
              delta={pct(todayNet, yd?.net_sales_paisa ?? 0)}
            />
            <Kpi
              label={t('dashboard.transactions')}
              icon={Receipt}
              value={formatNumber(todayCount, lng)}
              delta={pct(todayCount, yd?.sales_count ?? 0)}
            />
            <Kpi
              label={t('dashboard.avgBasket')}
              icon={ShoppingCart}
              value={formatTaka(paisa(avg), lng)}
              delta={pct(avg, yAvg)}
            />
            <Kpi
              label={t('dashboard.grossProfit')}
              icon={TrendingUp}
              value={formatTaka(
                paisa((td?.gross_profit_paisa as number | null | undefined) ?? 0),
                lng,
              )}
              {...(profitVisible ? {} : { muted: t('dashboard.hidden') })}
            />
          </>
        )}
      </section>

      <div className="mt-6 grid gap-6 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle>{t('dashboard.salesTrend')}</CardTitle>
            <CardDescription>{t('dashboard.salesTrendBody')}</CardDescription>
          </CardHeader>
          <CardContent>
            {summary.isPending ? <Skeleton className="h-64" /> : <SalesTrendChart data={trend} />}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <AlertTriangle className="size-4 text-warning" aria-hidden />
              {t('dashboard.expiring')}
            </CardTitle>
            <CardDescription>
              {t('dashboard.expiringBody', { days: formatNumber(EXPIRY_DAYS, lng) })}
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-2">
            {expiring.isPending ? (
              <Skeleton className="h-40" />
            ) : (expiring.data ?? []).length === 0 ? (
              <EmptyState icon={AlertTriangle} title={t('dashboard.noExpiring')} />
            ) : (
              (expiring.data ?? []).slice(0, 6).map((b) => (
                <div
                  key={b.batch_id}
                  className="flex items-center justify-between gap-3 rounded-md border px-3 py-2"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{b.brand_name}</p>
                    <p className="text-xs text-muted-foreground">
                      {b.batch_no} · {formatDate(b.expiry_date, lng)} ·{' '}
                      {t('dashboard.units', {
                        count: b.quantity_on_hand,
                        n: formatNumber(b.quantity_on_hand, lng),
                      })}
                    </p>
                  </div>
                  <Badge
                    tone={b.days_left <= 0 ? 'danger' : b.days_left <= 30 ? 'warning' : 'neutral'}
                  >
                    {t('dashboard.daysLeft', {
                      count: b.days_left,
                      n: formatNumber(b.days_left, lng),
                    })}
                  </Badge>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <PackageMinus className="size-4 text-danger" aria-hidden />
            {t('dashboard.lowStock')}
          </CardTitle>
          <CardDescription>{t('dashboard.lowStockBody')}</CardDescription>
        </CardHeader>
        <CardContent>
          {lowStock.isPending ? (
            <Skeleton className="h-24" />
          ) : (lowStock.data ?? []).length === 0 ? (
            <EmptyState icon={PackageMinus} title={t('dashboard.noLowStock')} />
          ) : (
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {(lowStock.data ?? []).map((m) => (
                <div
                  key={m.medicine_id}
                  className="flex items-center justify-between rounded-md border px-3 py-2"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{m.brand_name}</p>
                    <p className="truncate text-xs text-muted-foreground">{m.generic_name}</p>
                  </div>
                  <span className="tabular text-sm">
                    <span className="font-semibold text-danger">
                      {formatNumber(m.sellable_quantity, lng)}
                    </span>
                    <span className="text-muted-foreground">
                      {' '}
                      / {formatNumber(m.reorder_level, lng)}
                    </span>
                  </span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </>
  )
}
