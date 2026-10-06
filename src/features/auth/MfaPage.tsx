import { ShieldCheck } from 'lucide-react'
import { useEffect, useState, type SyntheticEvent } from 'react'
import { useTranslation } from 'react-i18next'

import { Logo } from '@/components/brand/logo'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { supabase } from '@/lib/supabase'

import { useAuth } from './auth-context'

interface Enrollment {
  factorId: string
  qrCode: string
  secret: string
}

/**
 * Verifies an existing TOTP factor (mode="verify") or enrols a new one (mode="enroll").
 * Salespeople may skip enrolment; owner/manager data stays locked by the database until aal2.
 */
export function MfaPage({ mode, onSkip }: { mode: 'verify' | 'enroll'; onSkip?: () => void }) {
  const { t } = useTranslation()
  const { refreshAal, signOut } = useAuth()
  const [factorId, setFactorId] = useState<string | null>(null)
  const [enrollment, setEnrollment] = useState<Enrollment | null>(null)
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let cancelled = false
    async function prepare() {
      if (mode === 'verify') {
        const { data } = await supabase.auth.mfa.listFactors()
        if (!cancelled) setFactorId(data?.totp[0]?.id ?? null)
        return
      }
      const { data, error: enrollError } = await supabase.auth.mfa.enroll({ factorType: 'totp' })
      if (cancelled) return
      if (enrollError) {
        setError(enrollError.message)
        return
      }
      setEnrollment({ factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret })
      setFactorId(data.id)
    }
    void prepare()
    return () => {
      cancelled = true
    }
  }, [mode])

  async function submit(event: SyntheticEvent) {
    event.preventDefault()
    if (!factorId) return
    setBusy(true)
    setError(null)
    const { error: verifyError } = await supabase.auth.mfa.challengeAndVerify({
      factorId,
      code: code.trim(),
    })
    setBusy(false)
    if (verifyError) {
      setError(t('auth.codeInvalid'))
      return
    }
    await refreshAal()
  }

  return (
    <main className="grid min-h-dvh place-items-center bg-background p-6">
      <Card className="w-full max-w-md">
        <CardHeader className="items-center text-center">
          <Logo />
          <div className="mt-2 grid size-12 place-items-center rounded-full bg-primary-soft text-primary-soft-foreground">
            <ShieldCheck className="size-6" aria-hidden />
          </div>
          <CardTitle className="text-xl">{t('auth.mfaTitle')}</CardTitle>
          <CardDescription>
            {mode === 'verify' ? t('auth.mfaVerifyBody') : t('auth.mfaEnrollBody')}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-5">
          {enrollment ? (
            <div className="grid justify-items-center gap-3">
              <img
                src={enrollment.qrCode}
                alt=""
                className="size-44 rounded-lg border bg-white p-2"
              />
              <details className="w-full text-center text-sm">
                <summary className="cursor-pointer text-muted-foreground">
                  {t('auth.mfaSecret')}
                </summary>
                <code className="mt-2 block rounded-md bg-surface-muted p-2 font-mono text-xs break-all">
                  {enrollment.secret}
                </code>
              </details>
            </div>
          ) : null}
          <form className="grid gap-4" onSubmit={(e) => void submit(e)}>
            <Field id="otp" label={t('auth.code')} error={error ?? undefined}>
              <Input
                id="otp"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                // Single-purpose screen: the code field is the only task, so focus it.
                // eslint-disable-next-line jsx-a11y/no-autofocus
                autoFocus
                className="text-center font-mono text-lg tracking-[0.5em]"
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
                aria-invalid={Boolean(error)}
              />
            </Field>
            <Button
              type="submit"
              size="lg"
              loading={busy}
              disabled={code.length !== 6 || !factorId}
            >
              {t('auth.verify')}
            </Button>
          </form>
          {mode === 'enroll' && onSkip ? (
            <div className="grid gap-1 text-center">
              <Button variant="link" onClick={onSkip}>
                {t('auth.skip')}
              </Button>
              <p className="text-xs text-muted-foreground">{t('auth.skipHint')}</p>
            </div>
          ) : null}
          <Button variant="ghost" size="sm" onClick={() => void signOut()}>
            {t('nav.signOut')}
          </Button>
        </CardContent>
      </Card>
    </main>
  )
}
