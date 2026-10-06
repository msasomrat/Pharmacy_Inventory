import { Hammer } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { Card } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/empty-state'

import { PageHeader } from './PageHeader'

export function ComingSoon({ titleKey }: { titleKey: string }) {
  const { t } = useTranslation()
  return (
    <>
      <PageHeader title={t(titleKey)} />
      <Card>
        <EmptyState
          icon={Hammer}
          title={t('comingSoon.title')}
          description={t('comingSoon.body')}
        />
      </Card>
    </>
  )
}
