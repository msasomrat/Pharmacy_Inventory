import { CheckCircle2, Printer, Plus } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { currentLanguage } from '@/i18n'
import { formatTaka, paisa } from '@/domain/money'

import type { CartLine } from './cart'

export interface SaleResult {
  invoice_no: string
  total_paisa: number
  paid_paisa: number
  change_paisa: number
  due_paisa: number
  points_earned: number
}

export function ReceiptDialog({
  sale,
  lines,
  pharmacy,
  branch,
  onClose,
}: {
  sale: SaleResult | null
  lines: CartLine[]
  pharmacy: string
  branch: string
  onClose: () => void
}) {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const tk = (p: number) => formatTaka(paisa(p), lng)
  return (
    <Dialog open={sale !== null} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-md">
        {sale ? (
          <>
            <DialogHeader className="items-center text-center">
              <div className="grid size-12 place-items-center rounded-full bg-success-soft text-success">
                <CheckCircle2 className="size-6" aria-hidden />
              </div>
              <DialogTitle>{t('pos.success')}</DialogTitle>
              <DialogDescription>
                {t('pos.invoice')}{' '}
                <span className="font-mono font-medium text-foreground">{sale.invoice_no}</span>
              </DialogDescription>
            </DialogHeader>

            <dl className="tabular grid grid-cols-2 gap-y-2 rounded-lg bg-surface-muted p-4 text-sm">
              <dt className="text-muted-foreground">{t('pos.total')}</dt>
              <dd className="text-right text-lg font-semibold">{tk(sale.total_paisa)}</dd>
              <dt className="text-muted-foreground">{t('pos.paid')}</dt>
              <dd className="text-right">{tk(sale.paid_paisa)}</dd>
              {sale.change_paisa > 0 ? (
                <>
                  <dt className="text-muted-foreground">{t('pos.change')}</dt>
                  <dd className="text-right font-semibold text-success">{tk(sale.change_paisa)}</dd>
                </>
              ) : null}
              {sale.due_paisa > 0 ? (
                <>
                  <dt className="text-muted-foreground">{t('pos.due')}</dt>
                  <dd className="text-right font-semibold text-danger">{tk(sale.due_paisa)}</dd>
                </>
              ) : null}
              {sale.points_earned > 0 ? (
                <>
                  <dt className="text-muted-foreground">{t('pos.pointsEarned')}</dt>
                  <dd className="text-right">+{sale.points_earned}</dd>
                </>
              ) : null}
            </dl>

            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" onClick={() => window.print()}>
                <Printer aria-hidden />
                {t('pos.print')}
              </Button>
              {/* eslint-disable-next-line jsx-a11y/no-autofocus -- Enter starts the next sale at the counter */}
              <Button onClick={onClose} autoFocus>
                <Plus aria-hidden />
                {t('pos.newSale')}
              </Button>
            </div>

            {/* 80 mm thermal receipt, visible only when printing */}
            <div className="print-receipt hidden font-mono text-[11px] leading-tight print:block">
              <p className="text-center text-sm font-bold">{pharmacy}</p>
              <p className="text-center">{branch}</p>
              <p className="text-center">{sale.invoice_no}</p>
              <p className="text-center">
                {new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' })}
              </p>
              <hr className="my-1 border-dashed border-black" />
              {lines.map((l) => (
                <div key={l.medicineId} className="flex justify-between gap-2">
                  <span className="truncate">
                    {l.name} x{l.quantity}
                  </span>
                </div>
              ))}
              <hr className="my-1 border-dashed border-black" />
              <p className="flex justify-between font-bold">
                <span>{t('pos.total')}</span>
                <span>{tk(sale.total_paisa)}</span>
              </p>
              <p className="flex justify-between">
                <span>{t('pos.paid')}</span>
                <span>{tk(sale.paid_paisa)}</span>
              </p>
              {sale.change_paisa > 0 ? (
                <p className="flex justify-between">
                  <span>{t('pos.change')}</span>
                  <span>{tk(sale.change_paisa)}</span>
                </p>
              ) : null}
              <p className="mt-2 text-center">{t('pos.thanks')}</p>
            </div>
          </>
        ) : null}
      </DialogContent>
    </Dialog>
  )
}
