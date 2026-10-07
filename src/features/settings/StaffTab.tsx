import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Copy, KeyRound, MailX, ShieldCheck, UserPlus, Users } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { EmptyState } from '@/components/ui/empty-state'
import { Field } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table'
import { useAuth } from '@/features/auth/auth-context'
import type { OrgRole } from '@/features/org/org-context'
import { useWorkspace } from '@/features/org/org-context'
import { overridesFor, roleTemplate, type Permission } from '@/features/org/permissions'
import { currentLanguage } from '@/i18n'
import { rpc } from '@/lib/api'
import { formatDate } from '@/lib/dates'
import { errorMessage } from '@/lib/errors'

import { AccessEditor } from './AccessEditor'
import {
  ROLES,
  createLogin,
  effectiveOf,
  generatePassword,
  listInvitations,
  listMembers,
  roleUsesBranches,
  type LoginResult,
  type Member,
} from './settings-api'

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/
const STRONG = (p: string) => p.length >= 10 && /[a-z]/.test(p) && /[A-Z]/.test(p) && /\d/.test(p)

function BranchPicker({ value, onChange }: { value: string[]; onChange: (ids: string[]) => void }) {
  const { t } = useTranslation()
  const { org } = useWorkspace()
  return (
    <fieldset className="grid gap-1.5">
      <legend className="mb-1.5 text-sm font-medium">{t('settings.branches')}</legend>
      <div className="flex flex-wrap gap-2">
        {org.branches.map((b) => (
          <label
            key={b.id}
            className="flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm"
          >
            <input
              type="checkbox"
              className="size-4 accent-primary"
              checked={value.includes(b.id)}
              onChange={(e) =>
                onChange(e.target.checked ? [...value, b.id] : value.filter((id) => id !== b.id))
              }
            />
            {b.name}
          </label>
        ))}
      </div>
    </fieldset>
  )
}

function RoleSelect({
  id,
  value,
  onChange,
}: {
  id: string
  value: OrgRole
  onChange: (r: OrgRole) => void
}) {
  const { t } = useTranslation()
  return (
    <Field id={id} label={t('settings.role')} hint={t(`settings.roleHints.${value}`)}>
      <Select id={id} value={value} onChange={(e) => onChange(e.target.value as OrgRole)}>
        {ROLES.map((r) => (
          <option key={r} value={r}>
            {t(`settings.roles.${r}`)}
          </option>
        ))}
      </Select>
    </Field>
  )
}

function AddStaffDialog({
  open,
  onOpenChange,
}: {
  open: boolean
  onOpenChange: (o: boolean) => void
}) {
  const { t } = useTranslation()
  const { org, branch } = useWorkspace()
  const queryClient = useQueryClient()
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [role, setRole] = useState<OrgRole>('salesman')
  const [branchIds, setBranchIds] = useState<string[]>([branch.id])
  const [password, setPassword] = useState(() => generatePassword())
  const [showErrors, setShowErrors] = useState(false)
  const [done, setDone] = useState<{ email: string; password: string; login: LoginResult } | null>(
    null,
  )

  const errors = {
    email: !EMAIL.test(email.trim()),
    password: !STRONG(password),
    branches: roleUsesBranches(role) && branchIds.length === 0,
  }

  const add = useMutation({
    mutationFn: async () => {
      const cleanEmail = email.trim().toLowerCase()
      await rpc('add_member', {
        p_organization_id: org.organizationId,
        p_email: cleanEmail,
        p_role: role,
        p_branch_ids: roleUsesBranches(role) ? branchIds : [],
      })
      const login = await createLogin({
        organizationId: org.organizationId,
        email: cleanEmail,
        password,
        fullName: fullName.trim(),
      })
      return { email: cleanEmail, password, login }
    },
    onSuccess: async (r) => {
      setDone(r)
      await queryClient.invalidateQueries({ queryKey: ['invitations'] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  function submit() {
    setShowErrors(true)
    if (errors.email || errors.password || errors.branches) return
    add.mutate()
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-xl" closeLabel={t('common.close')}>
        {done ? (
          <div className="grid gap-4">
            <DialogHeader>
              <DialogTitle>{t('settings.staffAdded')}</DialogTitle>
              <DialogDescription>
                {t(
                  done.login === 'created'
                    ? 'settings.loginCreated'
                    : done.login === 'exists'
                      ? 'settings.loginExists'
                      : 'settings.loginUnavailable',
                  { email: done.email },
                )}
              </DialogDescription>
            </DialogHeader>
            {done.login === 'created' ? (
              <div className="grid gap-2 rounded-lg border bg-surface-muted/60 p-4 text-sm">
                <p>
                  <span className="text-muted-foreground">{t('settings.email')}:</span>{' '}
                  <span className="font-medium">{done.email}</span>
                </p>
                <p className="flex items-center gap-2">
                  <span className="text-muted-foreground">{t('settings.tempPassword')}:</span>{' '}
                  <span className="font-mono font-medium" data-testid="temp-password">
                    {done.password}
                  </span>
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={t('settings.copy')}
                    onClick={() =>
                      void navigator.clipboard.writeText(`${done.email}\n${done.password}`)
                    }
                  >
                    <Copy aria-hidden />
                  </Button>
                </p>
                <p className="text-xs text-muted-foreground">{t('settings.handOver')}</p>
              </div>
            ) : null}
            <ol className="list-decimal space-y-1 pl-5 text-sm text-muted-foreground">
              <li>{t('settings.next1')}</li>
              <li>{t('settings.next2')}</li>
              <li>{t('settings.next3')}</li>
            </ol>
            <Button onClick={() => onOpenChange(false)}>{t('loyalty.done')}</Button>
          </div>
        ) : (
          <div className="grid gap-4">
            <DialogHeader>
              <DialogTitle>{t('settings.addStaff')}</DialogTitle>
              <DialogDescription>{t('settings.addStaffBody')}</DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field id="st-name" label={t('settings.fullName')}>
                <Input
                  id="st-name"
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                />
              </Field>
              <Field
                id="st-email"
                label={t('settings.email')}
                error={showErrors && errors.email ? t('errors.invalid_email') : undefined}
              >
                <Input
                  id="st-email"
                  type="email"
                  autoComplete="off"
                  value={email}
                  aria-invalid={showErrors && errors.email ? true : undefined}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </Field>
              <RoleSelect id="st-role" value={role} onChange={setRole} />
              <Field
                id="st-password"
                label={t('settings.tempPassword')}
                hint={t('settings.passwordHint')}
                error={showErrors && errors.password ? t('settings.passwordWeak') : undefined}
              >
                <div className="flex gap-2">
                  <Input
                    id="st-password"
                    className="font-mono"
                    autoComplete="new-password"
                    value={password}
                    aria-invalid={showErrors && errors.password ? true : undefined}
                    onChange={(e) => setPassword(e.target.value)}
                  />
                  <Button
                    type="button"
                    variant="secondary"
                    size="icon"
                    className="size-10 shrink-0"
                    aria-label={t('settings.generate')}
                    onClick={() => setPassword(generatePassword())}
                  >
                    <KeyRound aria-hidden />
                  </Button>
                </div>
              </Field>
            </div>
            {roleUsesBranches(role) ? (
              <div>
                <BranchPicker value={branchIds} onChange={setBranchIds} />
                {showErrors && errors.branches ? (
                  <p className="mt-1 text-xs text-danger">{t('settings.pickBranch')}</p>
                ) : null}
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">{t('settings.allBranches')}</p>
            )}
            <p className="text-xs text-muted-foreground">{t('settings.fineTuneLater')}</p>
            <div className="flex justify-end gap-2">
              <Button variant="secondary" onClick={() => onOpenChange(false)}>
                {t('common.cancel')}
              </Button>
              <Button loading={add.isPending} onClick={submit}>
                <UserPlus aria-hidden />
                {t('settings.addStaff')}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}

function MemberDialog({ member, onClose }: { member: Member; onClose: () => void }) {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [role, setRole] = useState<OrgRole>(member.role)
  const [isActive, setIsActive] = useState(member.isActive)
  const [branchIds, setBranchIds] = useState<string[]>(member.branchIds)
  const [access, setAccess] = useState<Set<Permission>>(() =>
    effectiveOf(member, roleTemplate(member.role)),
  )

  function changeRole(next: OrgRole) {
    setRole(next)
    // A new role starts from its template (the server clears overrides on a role change too).
    setAccess(effectiveOf({ role: next, overrides: {} }, roleTemplate(next)))
  }

  const save = useMutation({
    mutationFn: async () => {
      const branches = roleUsesBranches(role) ? branchIds : []
      const changedBasics =
        role !== member.role ||
        isActive !== member.isActive ||
        branches.slice().sort().join() !== member.branchIds.slice().sort().join()
      if (changedBasics) {
        await rpc('update_member', {
          p_membership_id: member.membershipId,
          p_role: role,
          p_is_active: isActive,
          p_branch_ids: branches,
        })
      }
      if (role !== 'owner') {
        await rpc('set_member_permissions', {
          p_membership_id: member.membershipId,
          p_overrides: overridesFor(role, access),
        })
      }
    },
    onSuccess: async () => {
      toast.success(t('settings.accessSaved', { name: member.fullName ?? member.email }))
      await queryClient.invalidateQueries({ queryKey: ['members'] })
      await queryClient.invalidateQueries({ queryKey: ['my-permissions'] })
      onClose()
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <div className="grid gap-4">
      <DialogHeader>
        <DialogTitle>{member.fullName ?? member.email}</DialogTitle>
        <DialogDescription>{member.email}</DialogDescription>
      </DialogHeader>
      <div className="grid gap-4 sm:grid-cols-2">
        <RoleSelect id="mb-role" value={role} onChange={changeRole} />
        <label className="flex items-center gap-2 self-center text-sm">
          <input
            type="checkbox"
            className="size-4 accent-primary"
            checked={isActive}
            onChange={(e) => setIsActive(e.target.checked)}
          />
          {t('settings.canSignIn')}
        </label>
      </div>
      {roleUsesBranches(role) ? (
        <BranchPicker value={branchIds} onChange={setBranchIds} />
      ) : (
        <p className="text-sm text-muted-foreground">{t('settings.allBranches')}</p>
      )}
      <AccessEditor role={role} value={access} onChange={setAccess} />
      <div className="flex justify-end gap-2">
        <Button variant="secondary" onClick={onClose}>
          {t('common.cancel')}
        </Button>
        <Button loading={save.isPending} onClick={() => save.mutate()}>
          <ShieldCheck aria-hidden />
          {t('settings.saveAccess')}
        </Button>
      </div>
    </div>
  )
}

export function StaffTab() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { org } = useWorkspace()
  const { session } = useAuth()
  const queryClient = useQueryClient()
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<Member | null>(null)

  const members = useQuery({
    queryKey: ['members', org.organizationId],
    queryFn: () => listMembers(org.organizationId),
  })
  const invitations = useQuery({
    queryKey: ['invitations', org.organizationId],
    queryFn: () => listInvitations(org.organizationId),
  })
  const branchName = (id: string) => org.branches.find((b) => b.id === id)?.name ?? '—'

  const revoke = useMutation({
    mutationFn: (id: string) => rpc('revoke_invitation', { p_invitation_id: id }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['invitations'] }),
    onError: (e) => toast.error(errorMessage(e)),
  })

  return (
    <div className="grid min-w-0 grid-cols-1 gap-6">
      <Card>
        <CardHeader className="flex-row flex-wrap items-center justify-between gap-3">
          <CardTitle className="flex items-center gap-2">
            <Users className="size-4 text-primary" aria-hidden />
            {t('settings.staff')}
          </CardTitle>
          <Button onClick={() => setAdding(true)}>
            <UserPlus aria-hidden />
            {t('settings.addStaff')}
          </Button>
        </CardHeader>
        <CardContent className="p-0">
          {members.isPending ? (
            <Skeleton className="m-5 h-40" />
          ) : (
            <Table>
              <THead>
                <TR>
                  <TH>{t('settings.person')}</TH>
                  <TH>{t('settings.role')}</TH>
                  <TH className="hidden md:table-cell">{t('settings.branches')}</TH>
                  <TH className="hidden lg:table-cell">{t('settings.lastSignIn')}</TH>
                  <TH className="w-28" />
                </TR>
              </THead>
              <TBody>
                {(members.data ?? []).map((m) => {
                  const custom = Object.keys(m.overrides).length > 0
                  const self = m.userId === session?.user.id
                  return (
                    <TR key={m.membershipId} className={m.isActive ? undefined : 'opacity-60'}>
                      <TD>
                        <p className="font-medium">{m.fullName ?? m.email}</p>
                        <p className="text-xs text-muted-foreground">{m.email}</p>
                      </TD>
                      <TD>
                        <span className="flex flex-wrap gap-1.5">
                          <Badge tone={m.role === 'owner' ? 'primary' : 'neutral'}>
                            {t(`settings.roles.${m.role}`)}
                          </Badge>
                          {custom ? <Badge tone="warning">{t('settings.custom')}</Badge> : null}
                          {m.isActive ? null : (
                            <Badge tone="danger">{t('settings.disabled')}</Badge>
                          )}
                        </span>
                      </TD>
                      <TD className="hidden text-sm md:table-cell">
                        {roleUsesBranches(m.role)
                          ? m.branchIds.map(branchName).join(', ') || '—'
                          : t('settings.all')}
                      </TD>
                      <TD className="hidden text-sm text-muted-foreground lg:table-cell">
                        {m.lastSignInAt
                          ? formatDate(m.lastSignInAt.slice(0, 10), lng)
                          : t('settings.never')}
                      </TD>
                      <TD className="text-right">
                        <Button
                          variant="secondary"
                          size="sm"
                          disabled={self}
                          title={self ? t('settings.notSelf') : undefined}
                          aria-label={t('settings.manageNamed', { name: m.fullName ?? m.email })}
                          onClick={() => setEditing(m)}
                        >
                          {t('settings.manage')}
                        </Button>
                      </TD>
                    </TR>
                  )
                })}
              </TBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('settings.pending')}</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {(invitations.data ?? []).length === 0 ? (
            <EmptyState icon={MailX} title={t('settings.noPending')} />
          ) : (
            <Table>
              <TBody>
                {(invitations.data ?? []).map((i) => (
                  <TR key={i.id}>
                    <TD>
                      <p className="font-medium">{i.email}</p>
                      <p className="text-xs text-muted-foreground">
                        {t('settings.expires', { date: formatDate(i.expiresAt.slice(0, 10), lng) })}
                      </p>
                    </TD>
                    <TD>
                      <Badge>{t(`settings.roles.${i.role}`)}</Badge>
                    </TD>
                    <TD className="text-right">
                      <Button
                        variant="ghost"
                        size="sm"
                        loading={revoke.isPending && revoke.variables === i.id}
                        onClick={() => revoke.mutate(i.id)}
                      >
                        {t('settings.revoke')}
                      </Button>
                    </TD>
                  </TR>
                ))}
              </TBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {adding ? <AddStaffDialog open={adding} onOpenChange={setAdding} /> : null}
      <Dialog
        open={editing !== null}
        onOpenChange={(o) => {
          if (!o) setEditing(null)
        }}
      >
        <DialogContent className="max-w-3xl" closeLabel={t('common.close')}>
          {editing ? <MemberDialog member={editing} onClose={() => setEditing(null)} /> : null}
        </DialogContent>
      </Dialog>
    </div>
  )
}
