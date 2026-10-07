import { useQuery } from '@tanstack/react-query'
import { ChevronDown, ChevronRight, ReceiptText } from 'lucide-react'
import { Fragment, useState } from 'react'
import { useTranslation } from 'react-i18next'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table'
import { formatTaka, paisa } from '@/domain/money'
import { useWorkspace } from '@/features/org/org-context'
import { currentLanguage } from '@/i18n'
import { formatDate } from '@/lib/dates'
import { toAppError } from '@/lib/errors'
import { formatNumber } from '@/lib/format'
import { supabase } from '@/lib/supabase'

function ReceiptItems({ receiptId }: { receiptId: string }) {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const items = useQuery({
    queryKey: ['goods-receipt-items', receiptId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('goods_receipt_items')
        .select(
          'id, batch_no, expiry_date, quantity, bonus_quantity, unit_cost_paisa, mrp_paisa, line_total_paisa, medicines(brand_name, strength)',
        )
        .eq('goods_receipt_id', receiptId)
      if (error) throw toAppError(error)
      return data
    },
  })
  if (items.isPending) return <Skeleton className="h-16" />
  return (
    <ul className="grid gap-1 text-xs">
      {(items.data ?? []).map((it) => (
        <li key={it.id} className="flex flex-wrap justify-between gap-2">
          <span>
            <span className="font-medium">{it.medicines.brand_name}</span> {it.medicines.strength} ·{' '}
            <span className="font-mono">{it.batch_no}</span> ·{' '}
            {t('pos.exp', { date: formatDate(it.expiry_date, lng) })}
          </span>
          <span className="tabular text-muted-foreground">
            {formatNumber(it.quantity, lng)}
            {it.bonus_quantity > 0 ? ` + ${formatNumber(it.bonus_quantity, lng)}` : ''} ×{' '}
            {formatTaka(paisa(it.unit_cost_paisa), lng)} ={' '}
            {formatTaka(paisa(it.line_total_paisa), lng)}
          </span>
        </li>
      ))}
    </ul>
  )
}

export function ReceiptHistory() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { branch } = useWorkspace()
  const [open, setOpen] = useState<string | null>(null)

  const receipts = useQuery({
    queryKey: ['goods-receipts', branch.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('goods_receipts')
        .select(
          'id, receipt_no, supplier_invoice_no, business_date, total_paisa, paid_paisa, suppliers(name)',
        )
        .eq('branch_id', branch.id)
        .order('created_at', { ascending: false })
        .limit(100)
      if (error) throw toAppError(error)
      return data
    },
  })

  return (
    <Card>
      <CardContent className="p-0">
        {receipts.isPending ? (
          <Skeleton className="m-5 h-40" />
        ) : (receipts.data ?? []).length === 0 ? (
          <EmptyState icon={ReceiptText} title={t('purchases.noReceipts')} />
        ) : (
          <Table>
            <THead>
              <TR>
                <TH className="w-8" />
                <TH>{t('purchases.receiptNo')}</TH>
                <TH>{t('purchases.supplier')}</TH>
                <TH>{t('purchases.date')}</TH>
                <TH className="text-right">{t('pos.total')}</TH>
                <TH className="text-right">{t('pos.due')}</TH>
              </TR>
            </THead>
            <TBody>
              {(receipts.data ?? []).map((r) => {
                const due = r.total_paisa - r.paid_paisa
                const expanded = open === r.id
                return (
                  <Fragment key={r.id}>
                    <TR
                      className="cursor-pointer"
                      onClick={() => setOpen(expanded ? null : r.id)}
                      aria-expanded={expanded}
                    >
                      <TD>
                        {expanded ? (
                          <ChevronDown className="size-4" aria-hidden />
                        ) : (
                          <ChevronRight className="size-4" aria-hidden />
                        )}
                      </TD>
                      <TD className="font-mono text-xs">
                        {r.receipt_no}
                        {r.supplier_invoice_no ? (
                          <span className="block text-muted-foreground">
                            #{r.supplier_invoice_no}
                          </span>
                        ) : null}
                      </TD>
                      <TD>{r.suppliers.name}</TD>
                      <TD>{formatDate(r.business_date, lng)}</TD>
                      <TD className="tabular text-right">
                        {formatTaka(paisa(r.total_paisa), lng)}
                      </TD>
                      <TD className="text-right">
                        {due > 0 ? (
                          <Badge tone="warning">{formatTaka(paisa(due), lng)}</Badge>
                        ) : (
                          <Badge tone="success">{t('purchases.paidInFull')}</Badge>
                        )}
                      </TD>
                    </TR>
                    {expanded ? (
                      <tr>
                        <td />
                        <td colSpan={5} className="px-4 pb-4">
                          <ReceiptItems receiptId={r.id} />
                        </td>
                      </tr>
                    ) : null}
                  </Fragment>
                )
              })}
            </TBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
