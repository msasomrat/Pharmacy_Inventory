import { Lock } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'

import { PageHeader } from '@/components/layout/PageHeader'
import { Card } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'
import { useWorkspace } from '@/features/org/org-context'
import { cn } from '@/lib/cn'

import { BranchesTab } from './BranchesTab'
import { PharmacyTab } from './PharmacyTab'
import { StaffTab } from './StaffTab'

type Tab = 'staff' | 'branches' | 'pharmacy'

export function SettingsPage() {
  const { t } = useTranslation()
  const { can } = useWorkspace()
  const tabs: Tab[] = [
    ...(can('users.manage') ? (['staff'] as const) : []),
    ...(can('branches.manage') ? (['branches'] as const) : []),
    ...(can('org.settings.manage') ? (['pharmacy'] as const) : []),
  ]
  const [selected, setSelected] = useState<Tab | null>(null)
  const tab = selected && tabs.includes(selected) ? selected : tabs[0]

  if (!tab) {
    return (
      <>
        <PageHeader title={t('nav.settings')} />
        <Card>
          <EmptyState icon={Lock} title={t('settings.noAccess')} />
        </Card>
      </>
    )
  }

  return (
    <>
      <PageHeader title={t('nav.settings')} description={t('settings.subtitle')} />
      <div
        role="tablist"
        aria-label={t('nav.settings')}
        className="mb-6 inline-flex gap-1 rounded-lg bg-surface-muted p-1"
      >
        {tabs.map((id) => (
          <button
            key={id}
            role="tab"
            type="button"
            aria-selected={tab === id}
            aria-controls={`settings-${id}`}
            onClick={() => setSelected(id)}
            className={cn(
              'rounded-md px-4 py-1.5 text-sm font-medium transition-colors',
              tab === id
                ? 'bg-surface text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            )}
          >
            {t(`settings.tabs.${id}`)}
          </button>
        ))}
      </div>
      <div role="tabpanel" id={`settings-${tab}`}>
        {tab === 'staff' ? <StaffTab /> : tab === 'branches' ? <BranchesTab /> : <PharmacyTab />}
      </div>
    </>
  )
}
