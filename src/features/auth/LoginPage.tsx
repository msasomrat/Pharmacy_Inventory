import { zodResolver } from '@hookform/resolvers/zod'
import { CheckCircle2, ShieldCheck } from 'lucide-react'
import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'
import { z } from 'zod'

import { Logo } from '@/components/brand/logo'
import { LanguageToggle, ThemeToggle } from '@/components/layout/preferences'
import { Button } from '@/components/ui/button'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { loginToEmail } from '@/domain/staff-login'
import { supabase } from '@/lib/supabase'

// Staff type their username, owners their email (staff usernames map to internal addresses).
const schema = z.object({
  login: z.string().trim().min(1).max(320),
  password: z.string().min(1),
})
type FormValues = z.infer<typeof schema>

export function LoginPage() {
  const { t } = useTranslation()
  const [error, setError] = useState<string | null>(null)
  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { login: '', password: '' },
  })
  const points = t('auth.heroPoints', { returnObjects: true }) as string[]

  const onSubmit = form.handleSubmit(async (values) => {
    setError(null)
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: loginToEmail(values.login),
      password: values.password,
    })
    if (signInError) setError(t('auth.invalid'))
  })

  return (
    <div className="grid min-h-dvh lg:grid-cols-[1.1fr_1fr]">
      <aside className="relative hidden overflow-hidden bg-sidebar p-12 text-sidebar-foreground lg:flex lg:flex-col lg:justify-between">
        <div
          aria-hidden
          className="pointer-events-none absolute -top-40 -right-40 size-[32rem] rounded-full bg-primary/25 blur-3xl"
        />
        <div
          aria-hidden
          className="pointer-events-none absolute -bottom-48 -left-24 size-[28rem] rounded-full bg-info/20 blur-3xl"
        />
        <Logo withText className="relative text-white" />
        <div className="relative max-w-md space-y-6">
          <h1 className="text-4xl leading-tight font-semibold tracking-tight text-white">
            {t('auth.heroTitle')}
          </h1>
          <p className="text-lg text-sidebar-muted">{t('auth.heroBody')}</p>
          <ul className="space-y-3">
            {points.map((point) => (
              <li key={point} className="flex items-start gap-3">
                <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden />
                <span>{point}</span>
              </li>
            ))}
          </ul>
        </div>
        <p className="relative flex items-center gap-2 text-sm text-sidebar-muted">
          <ShieldCheck className="size-4" aria-hidden />
          {t('auth.trust')}
        </p>
      </aside>

      <main className="flex flex-col p-6 sm:p-10">
        <div className="flex items-center justify-between">
          <Logo className="lg:invisible" />
          <div className="flex items-center gap-1">
            <LanguageToggle />
            <ThemeToggle />
          </div>
        </div>
        <div className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-8 py-10">
          <div className="space-y-2">
            <h2 className="text-2xl font-semibold tracking-tight">{t('auth.welcome')}</h2>
            <p className="text-sm text-muted-foreground">{t('auth.signInHint')}</p>
          </div>
          <form className="grid gap-4" onSubmit={(e) => void onSubmit(e)} noValidate>
            <Field
              id="login"
              label={t('auth.loginId')}
              error={form.formState.errors.login ? t('auth.invalid') : undefined}
            >
              <Input
                id="login"
                autoComplete="username"
                autoCapitalize="none"
                autoCorrect="off"
                spellCheck={false}
                // eslint-disable-next-line jsx-a11y/no-autofocus -- sign-in is the only task on this page
                autoFocus
                aria-invalid={Boolean(form.formState.errors.login)}
                {...form.register('login')}
              />
            </Field>
            <Field id="password" label={t('auth.password')}>
              <Input
                id="password"
                type="password"
                autoComplete="current-password"
                {...form.register('password')}
              />
            </Field>
            {error ? (
              <p role="alert" className="rounded-md bg-danger-soft px-3 py-2 text-sm text-danger">
                {error}
              </p>
            ) : null}
            <Button type="submit" size="lg" loading={form.formState.isSubmitting}>
              {t('auth.signIn')}
            </Button>
          </form>
        </div>
      </main>
    </div>
  )
}
