import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Outlet } from 'react-router'

import { Logo } from '@/components/brand/logo'
import { LoginPage } from '@/features/auth/LoginPage'
import { MfaPage } from '@/features/auth/MfaPage'
import { useAuth } from '@/features/auth/auth-context'
import { OnboardingPage } from '@/features/org/OnboardingPage'
import { useOrg } from '@/features/org/org-context'
import { prefs } from '@/lib/storage'

function Splash() {
  const { t } = useTranslation()
  return (
    <div className="grid min-h-dvh place-items-center" role="status" aria-live="polite">
      <div className="flex flex-col items-center gap-3 text-muted-foreground">
        <Logo className="animate-pulse" />
        <span className="text-sm">{t('app.loading')}</span>
      </div>
    </div>
  )
}

/**
 * Sign-in -> two-factor (verify if enrolled, otherwise offer enrolment) -> organization -> app.
 * The database enforces MFA independently; this only guides the user.
 */
export function AuthGate() {
  const { status, aal } = useAuth()
  const org = useOrg()
  const [skippedEnroll, setSkippedEnroll] = useState(() => prefs.get('mfa-skip') === '1')

  if (status === 'loading') return <Splash />
  if (status === 'signed_out') return <LoginPage />
  if (aal.next === 'aal2' && aal.current === 'aal1') return <MfaPage mode="verify" />
  if (org.loading) return <Splash />

  const needsEnroll = aal.next === 'aal1'
  if (needsEnroll && (!skippedEnroll || org.memberships.length === 0)) {
    return (
      <MfaPage
        mode="enroll"
        onSkip={() => {
          prefs.set('mfa-skip', '1')
          setSkippedEnroll(true)
        }}
      />
    )
  }
  if (!org.current || !org.branch) return <OnboardingPage />
  return <Outlet />
}
