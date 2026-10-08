import { useMutation } from '@tanstack/react-query'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { errorMessage } from '@/lib/errors'
import { supabase } from '@/lib/supabase'

const STRONG = (p: string) => p.length >= 10 && /[a-z]/.test(p) && /[A-Z]/.test(p) && /\d/.test(p)

/** Signed-in user replaces their password (staff replace the temporary one from the owner). */
export function ChangePasswordDialog({
  open,
  onOpenChange,
}: {
  open: boolean
  onOpenChange: (o: boolean) => void
}) {
  const { t } = useTranslation()
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [showErrors, setShowErrors] = useState(false)
  const weak = !STRONG(password)
  const mismatch = password !== confirm

  const save = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.auth.updateUser({ password })
      // Auth errors (e.g. same as the old password, policy) carry a readable message.
      if (error) throw new Error(error.message)
    },
    onSuccess: () => {
      toast.success(t('account.saved'))
      onOpenChange(false)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  function submit() {
    setShowErrors(true)
    if (weak || mismatch) return
    save.mutate()
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md" closeLabel={t('common.close')}>
        <DialogHeader>
          <DialogTitle>{t('account.title')}</DialogTitle>
          <DialogDescription>{t('settings.passwordHint')}</DialogDescription>
        </DialogHeader>
        <form
          className="grid gap-4"
          onSubmit={(e) => {
            e.preventDefault()
            submit()
          }}
          noValidate
        >
          <Field
            id="pw-new"
            label={t('account.new')}
            error={showErrors && weak ? t('settings.passwordWeak') : undefined}
          >
            <Input
              id="pw-new"
              type="password"
              autoComplete="new-password"
              value={password}
              aria-invalid={showErrors && weak ? true : undefined}
              onChange={(e) => setPassword(e.target.value)}
            />
          </Field>
          <Field
            id="pw-confirm"
            label={t('account.confirm')}
            error={showErrors && !weak && mismatch ? t('account.mismatch') : undefined}
          >
            <Input
              id="pw-confirm"
              type="password"
              autoComplete="new-password"
              value={confirm}
              aria-invalid={showErrors && !weak && mismatch ? true : undefined}
              onChange={(e) => setConfirm(e.target.value)}
            />
          </Field>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => onOpenChange(false)}>
              {t('common.cancel')}
            </Button>
            <Button type="submit" loading={save.isPending}>
              {t('common.save')}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
