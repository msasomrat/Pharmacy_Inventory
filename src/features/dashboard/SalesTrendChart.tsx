import { useTranslation } from 'react-i18next'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

import { currentLanguage } from '@/i18n'
import { formatDate, formatShortDate } from '@/lib/dates'
import { compactTaka } from '@/lib/format'
import { formatTaka, paisa } from '@/domain/money'

export interface TrendPoint {
  date: string
  netPaisa: number
}

/** Single series: net sales per day. No legend (the card title names the series); table for AT. */
export function SalesTrendChart({ data }: { data: TrendPoint[] }) {
  const { t } = useTranslation()
  const lng = currentLanguage()
  return (
    <figure className="m-0">
      <div className="h-64 w-full" aria-hidden>
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
            <defs>
              <linearGradient id="trend-fill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--chart-1)" stopOpacity={0.22} />
                <stop offset="100%" stopColor="var(--chart-1)" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid vertical={false} stroke="var(--chart-grid)" />
            <XAxis
              dataKey="date"
              tickLine={false}
              axisLine={false}
              tick={{ fill: 'var(--muted-foreground)', fontSize: 12 }}
              tickFormatter={(d: string) => formatShortDate(d, lng)}
              minTickGap={24}
            />
            <YAxis
              tickLine={false}
              axisLine={false}
              width={52}
              tick={{ fill: 'var(--muted-foreground)', fontSize: 12 }}
              tickFormatter={(v: number) => compactTaka(v, lng)}
            />
            <Tooltip
              cursor={{ stroke: 'var(--muted-foreground)', strokeDasharray: '3 3' }}
              content={({ active, payload }) => {
                const point = payload[0]?.payload as TrendPoint | undefined
                if (!active || !point) return null
                return (
                  <div className="rounded-md border bg-surface px-3 py-2 text-xs shadow-pop">
                    <p className="text-muted-foreground">{formatDate(point.date, lng)}</p>
                    <p className="tabular text-sm font-semibold">
                      {formatTaka(paisa(point.netPaisa), lng)}
                    </p>
                  </div>
                )
              }}
            />
            <Area
              type="monotone"
              dataKey="netPaisa"
              stroke="var(--chart-1)"
              strokeWidth={2}
              fill="url(#trend-fill)"
              activeDot={{ r: 5, stroke: 'var(--surface)', strokeWidth: 2 }}
              isAnimationActive={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
      <table className="sr-only">
        <caption>{t('dashboard.salesTrend')}</caption>
        <tbody>
          {data.map((d) => (
            <tr key={d.date}>
              <th scope="row">{formatDate(d.date, lng)}</th>
              <td>{formatTaka(paisa(d.netPaisa), lng)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </figure>
  )
}
