import { Lock } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'

import { PageHeader } from '@/components/layout/PageHeader'
import { Card } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { useWorkspace } from '@/features/org/org-context'
import { roleCan } from '@/features/org/permissions'
import { cn } from '@/lib/cn'

import { ReceiptHistory } from './ReceiptHistory'
import { StockEntryForm } from './StockEntryForm'

type Tab = 'receive' | 'opening' | 'history'

export function PurchasesPage() {
  const { t } = useTranslation()
  const { org, branch } = useWorkspace()
  const canView = roleCan(org.role, 'purchases.view')
  const tabs: Tab[] = [
    ...(roleCan(org.role, 'purchases.receive') ? (['receive'] as const) : []),
    ...(roleCan(org.role, 'stock.adjust') ? (['opening'] as const) : []),
    'history',
  ]
  const [tab, setTab] = useState<Tab>(tabs[0] ?? 'history')

  if (!canView) {
    return (
      <>
        <PageHeader title={t('nav.purchases')} />
        <Card>
          <EmptyState
            icon={Lock}
            title={t('purchases.noAccess')}
            description={t('purchases.noAccessBody')}
          />
        </Card>
      </>
    )
  }

  return (
    <>
      <PageHeader
        title={t('nav.purchases')}
        description={t('purchases.subtitle', { branch: branch.name })}
      />
      <div
        role="tablist"
        aria-label={t('nav.purchases')}
        className="mb-6 inline-flex gap-1 rounded-lg bg-surface-muted p-1"
      >
        {tabs.map((id) => (
          <button
            key={id}
            role="tab"
            type="button"
            aria-selected={tab === id}
            aria-controls={`purchases-${id}`}
            onClick={() => setTab(id)}
            className={cn(
              'rounded-md px-4 py-1.5 text-sm font-medium transition-colors',
              tab === id
                ? 'bg-surface text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            )}
          >
            {t(`purchases.tabs.${id}`)}
          </button>
        ))}
      </div>
      <div role="tabpanel" id={`purchases-${tab}`}>
        {tab === 'history' ? (
          <ReceiptHistory />
        ) : (
          <StockEntryForm key={`${tab}-${branch.id}`} mode={tab} />
        )}
      </div>
    </>
  )
}
