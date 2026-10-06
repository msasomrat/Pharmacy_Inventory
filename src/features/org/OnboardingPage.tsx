import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Building2, MailOpen } from 'lucide-react'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { z } from 'zod'

import { Logo } from '@/components/brand/logo'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { rpc } from '@/lib/api'
import { errorMessage } from '@/lib/errors'
import { useAuth } from '@/features/auth/auth-context'

import { useOrg } from './org-context'

const schema = z.object({
  name: z.string().trim().min(2).max(120),
  branchName: z.string().trim().min(2).max(120),
  branchCode: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9]{2,6}$/),
})
type FormValues = z.infer<typeof schema>

export function OnboardingPage() {
  const { t } = useTranslation()
  const { signOut } = useAuth()
  const { refetch } = useOrg()
  const invitations = useQuery({
    queryKey: ['my-invitations'],
    queryFn: () => rpc('my_invitations', {}),
  })
  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { name: '', branchName: '', branchCode: '' },
  })

  const create = useMutation({
    mutationFn: (v: FormValues) =>
      rpc('create_organization', {
        p_name: v.name,
        p_branch_name: v.branchName,
        p_branch_code: v.branchCode.toUpperCase(),
      }),
    onSuccess: () => void refetch(),
    onError: (e) => toast.error(errorMessage(e)),
  })
  const accept = useMutation({
    mutationFn: (id: string) => rpc('accept_invitation', { p_invitation_id: id }),
    onSuccess: () => void refetch(),
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <main className="min-h-dvh bg-background px-6 py-10">
      <div className="mx-auto grid max-w-2xl gap-6">
        <div className="flex items-center justify-between">
          <Logo withText />
          <Button variant="ghost" size="sm" onClick={() => void signOut()}>
            {t('nav.signOut')}
          </Button>
        </div>

        {invitations.data && invitations.data.length > 0 ? (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <MailOpen className="size-5 text-primary" aria-hidden />
                {t('onboarding.invitations')}
              </CardTitle>
            </CardHeader>
            <CardContent className="grid gap-2">
              {invitations.data.map((inv) => (
                <div
                  key={inv.invitation_id}
                  className="flex items-center justify-between rounded-md border p-3"
                >
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{inv.organization_name}</span>
                    <Badge tone="primary">{inv.role}</Badge>
                  </div>
                  <Button
                    size="sm"
                    loading={accept.isPending}
                    onClick={() => accept.mutate(inv.invitation_id)}
                  >
                    {t('onboarding.accept')}
                  </Button>
                </div>
              ))}
            </CardContent>
          </Card>
        ) : null}

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-xl">
              <Building2 className="size-5 text-primary" aria-hidden />
              {t('onboarding.title')}
            </CardTitle>
            <CardDescription>{t('onboarding.body')}</CardDescription>
          </CardHeader>
          <CardContent>
            <form
              className="grid gap-4 sm:grid-cols-2"
              onSubmit={(e) => void form.handleSubmit((v) => create.mutate(v))(e)}
              noValidate
            >
              <div className="sm:col-span-2">
                <Field id="org-name" label={t('onboarding.pharmacyName')}>
                  <Input id="org-name" placeholder="Shefa Pharmacy" {...form.register('name')} />
                </Field>
              </div>
              <Field id="branch-name" label={t('onboarding.branchName')}>
                <Input
                  id="branch-name"
                  placeholder="Mohammadpur"
                  {...form.register('branchName')}
                />
              </Field>
              <Field
                id="branch-code"
                label={t('onboarding.branchCode')}
                hint={t('onboarding.branchCodeHint')}
              >
                <Input
                  id="branch-code"
                  placeholder="MPR"
                  className="uppercase"
                  maxLength={6}
                  {...form.register('branchCode')}
                />
              </Field>
              <div className="sm:col-span-2">
                <Button type="submit" size="lg" className="w-full" loading={create.isPending}>
                  {t('onboarding.create')}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>

        <p className="text-center text-sm text-muted-foreground">
          <strong>{t('onboarding.noAccess')}.</strong> {t('onboarding.noAccessBody')}
        </p>
      </div>
    </main>
  )
}
