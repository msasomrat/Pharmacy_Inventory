import { AlertOctagon, RotateCw } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { isRouteErrorResponse, useRouteError } from 'react-router'

import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'

/** Friendly error screen; technical details are never shown to staff (they go to monitoring). */
export function RouteError() {
  const { t } = useTranslation()
  const error = useRouteError()
  if (!isRouteErrorResponse(error)) console.error(error)
  return (
    <main className="grid min-h-dvh place-items-center bg-background p-6">
      <Card className="flex max-w-md flex-col items-center gap-4 p-8 text-center">
        <div className="grid size-12 place-items-center rounded-full bg-danger-soft text-danger">
          <AlertOctagon className="size-6" aria-hidden />
        </div>
        <h1 className="text-lg font-semibold">{t('errors.unknown')}</h1>
        <Button onClick={() => window.location.reload()}>
          <RotateCw aria-hidden />
          {t('errors.reload')}
        </Button>
      </Card>
    </main>
  )
}
