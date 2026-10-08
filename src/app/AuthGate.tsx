import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Outlet } from 'react-router'

import { Logo } from '@/components/brand/logo'
import { LoginPage } from '@/features/auth/LoginPage'
import { MfaPage } from '@/features/auth/MfaPage'
import { useAuth } from '@/features/auth/auth-context'
import { OnboardingPage } from '@/features/org/OnboardingPage'
import { useOrg } from '@/features/org/org-context'

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
 * Sign-in -> organization -> app. Two-factor authentication is for owners only: staff sign in with a
 * password. The database hides an owner's organization until the session is TOTP-verified (aal2), so
 * someone with an authenticator and no visible organization is asked for their code, and a new owner
 * sets one up before creating a pharmacy. The database enforces all of this independently.
 */
export function AuthGate() {
  const { status, aal } = useAuth()
  const org = useOrg()
  const [settingUpOwner, setSettingUpOwner] = useState(false)

  if (status === 'loading') return <Splash />
  if (status === 'signed_out') return <LoginPage />
  if (org.loading) return <Splash />

  const hasAuthenticator = aal.next === 'aal2'
  if (org.memberships.length === 0) {
    if (hasAuthenticator && aal.current === 'aal1') return <MfaPage mode="verify" />
    if (settingUpOwner && !hasAuthenticator) {
      return <MfaPage mode="enroll" onBack={() => setSettingUpOwner(false)} />
    }
    return (
      <OnboardingPage
        {...(hasAuthenticator ? {} : { onNeedsAuthenticator: () => setSettingUpOwner(true) })}
      />
    )
  }
  if (!org.current || !org.branch) return <OnboardingPage />
  return <Outlet />
}
