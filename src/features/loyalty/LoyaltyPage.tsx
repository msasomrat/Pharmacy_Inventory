import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Ban, CreditCard, RefreshCw, Replace, Search, UserPlus } from 'lucide-react'
import { useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { PageHeader } from '@/components/layout/PageHeader'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
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
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table'
import { displayPhone } from '@/domain/phone'
import { useWorkspace } from '@/features/org/org-context'
import { currentLanguage } from '@/i18n'
import { rpc } from '@/lib/api'
import { cn } from '@/lib/cn'
import { businessDate, formatDate } from '@/lib/dates'
import { errorMessage, toAppError } from '@/lib/errors'
import { formatNumber } from '@/lib/format'
import { supabase } from '@/lib/supabase'

import { EnrollDialog, type PickedCustomer } from './EnrollDialog'
import { formatCardNo, membershipState, type MembershipState } from './membership'
import { PlansEditor } from './PlansEditor'

type Filter = 'all' | 'active' | 'expiring' | 'expired'
const FILTERS: Filter[] = ['active', 'expiring', 'expired', 'all']

interface MemberRow {
  id: string
  state: MembershipState
  startsOn: string
  endsOn: string
  customer: PickedCustomer
  cardId: string
  cardNo: string
  cardActive: boolean
  planName: string
}

const STATE_TONE: Record<MembershipState, 'success' | 'warning' | 'info' | 'neutral' | 'danger'> = {
  active: 'success',
  expiring: 'warning',
  upcoming: 'info',
  expired: 'neutral',
  cancelled: 'danger',
}

async function fetchMembers(organizationId: string, today: string): Promise<MemberRow[]> {
  const { data, error } = await supabase
    .from('loyalty_memberships')
    .select(
      'id, status, starts_on, ends_on, customer_id, customers(name, phone), loyalty_cards(id, card_no, is_active), loyalty_plans(name)',
    )
    .eq('organization_id', organizationId)
    .order('ends_on', { ascending: false })
    .limit(1000)
  if (error) throw toAppError(error)
  return data.map((m) => ({
    id: m.id,
    state: membershipState({ status: m.status, startsOn: m.starts_on, endsOn: m.ends_on }, today),
    startsOn: m.starts_on,
    endsOn: m.ends_on,
    customer: { id: m.customer_id, name: m.customers.name, phone: m.customers.phone },
    cardId: m.loyalty_cards.id,
    cardNo: m.loyalty_cards.card_no,
    cardActive: m.loyalty_cards.is_active,
    planName: m.loyalty_plans.name,
  }))
}

function ReasonDialog({
  open,
  onOpenChange,
  title,
  description,
  withCardNo,
  confirmLabel,
  onConfirm,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description: string
  withCardNo?: boolean
  confirmLabel: string
  onConfirm: (reason: string, cardNo: string) => Promise<unknown>
}) {
  const { t } = useTranslation()
  const [reason, setReason] = useState('')
  const [cardNo, setCardNo] = useState('')
  const run = useMutation({
    mutationFn: () => onConfirm(reason.trim(), cardNo.replace(/\s/g, '')),
    onSuccess: () => {
      setReason('')
      setCardNo('')
      onOpenChange(false)
    },
    onError: (e) => toast.error(errorMessage(e)),
  })
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent closeLabel={t('common.close')}>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        <Field id="reason" label={t('loyalty.reason')}>
          <Input
            id="reason"
            maxLength={200}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
        </Field>
        {withCardNo ? (
          <Field id="new-card" label={t('loyalty.newCardNo')} hint={t('loyalty.cardNoHint')}>
            <Input
              id="new-card"
              inputMode="numeric"
              placeholder={t('loyalty.autoNumber')}
              value={cardNo}
              onChange={(e) => setCardNo(e.target.value)}
            />
          </Field>
        ) : null}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            {t('common.cancel')}
          </Button>
          <Button
            variant={withCardNo ? 'primary' : 'danger'}
            disabled={reason.trim().length < 3}
            loading={run.isPending}
            onClick={() => run.mutate()}
          >
            {confirmLabel}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function MembersTab() {
  const { t } = useTranslation()
  const lng = currentLanguage()
  const { org, can } = useWorkspace()
  const queryClient = useQueryClient()
  const today = businessDate()
  const canEnroll = can('loyalty.enroll')
  const canCancel = can('loyalty.cancel')
  const [filter, setFilter] = useState<Filter>('active')
  const [text, setText] = useState('')
  const [enrolling, setEnrolling] = useState<PickedCustomer | null | undefined>(undefined)
  const [cancelling, setCancelling] = useState<MemberRow | null>(null)
  const [replacing, setReplacing] = useState<MemberRow | null>(null)

  const members = useQuery({
    queryKey: ['loyalty-members', org.organizationId, today],
    queryFn: () => fetchMembers(org.organizationId, today),
  })

  const counts = useMemo(() => {
    const all = members.data ?? []
    return {
      active: all.filter(
        (m) => m.state === 'active' || m.state === 'expiring' || m.state === 'upcoming',
      ).length,
      expiring: all.filter((m) => m.state === 'expiring').length,
      expired: all.filter((m) => m.state === 'expired').length,
      all: all.length,
    }
  }, [members.data])

  const rows = useMemo(() => {
    const q = text.trim().toLowerCase()
    const digits = q.replace(/\D/g, '')
    return (members.data ?? []).filter((m) => {
      const inFilter =
        filter === 'all' ||
        (filter === 'active' &&
          (m.state === 'active' || m.state === 'expiring' || m.state === 'upcoming')) ||
        m.state === filter
      if (!inFilter) return false
      if (!q) return true
      return (
        m.customer.name.toLowerCase().includes(q) ||
        (digits.length >= 3 &&
          ((m.customer.phone ?? '').includes(digits) || m.cardNo.includes(digits)))
      )
    })
  }, [members.data, filter, text])

  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ['loyalty-members'] }),
      queryClient.invalidateQueries({ queryKey: ['customers'] }),
    ])

  return (
    <>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div
          role="group"
          aria-label={t('loyalty.filter')}
          className="flex flex-wrap gap-1 rounded-lg bg-surface-muted p-1"
        >
          {FILTERS.map((f) => (
            <button
              key={f}
              type="button"
              aria-pressed={filter === f}
              onClick={() => setFilter(f)}
              className={cn(
                'rounded-md px-3 py-1.5 text-sm font-medium transition-colors',
                filter === f
                  ? 'bg-surface text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground',
              )}
            >
              {t(`loyalty.filters.${f}`)}{' '}
              <span className="tabular text-xs opacity-70">{formatNumber(counts[f], lng)}</span>
            </button>
          ))}
        </div>
        <div className="relative min-w-52 flex-1">
          <Search
            aria-hidden
            className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
          />
          <Input
            type="search"
            aria-label={t('loyalty.searchMembers')}
            placeholder={t('loyalty.searchMembers')}
            className="pl-9"
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
        </div>
        {canEnroll ? (
          <Button onClick={() => setEnrolling(null)}>
            <UserPlus aria-hidden />
            {t('loyalty.enroll')}
          </Button>
        ) : null}
      </div>

      <Card>
        <CardContent className="p-0">
          {members.isPending ? (
            <Skeleton className="m-5 h-48" />
          ) : rows.length === 0 ? (
            <EmptyState
              icon={CreditCard}
              title={t('loyalty.noMembers')}
              {...((members.data ?? []).length === 0
                ? { description: t('loyalty.noMembersBody') }
                : {})}
            />
          ) : (
            <Table>
              <THead>
                <TR>
                  <TH>{t('loyalty.customer')}</TH>
                  <TH className="hidden sm:table-cell">{t('loyalty.cardNo')}</TH>
                  <TH className="hidden md:table-cell">{t('loyalty.plan')}</TH>
                  <TH>{t('loyalty.validity')}</TH>
                  <TH className="w-28" />
                </TR>
              </THead>
              <TBody>
                {rows.map((m) => (
                  <TR key={m.id}>
                    <TD>
                      <p className="font-medium">{m.customer.name}</p>
                      <p className="text-xs text-muted-foreground">
                        {displayPhone(m.customer.phone)}
                      </p>
                      <p className="font-mono text-xs text-muted-foreground sm:hidden">
                        {formatCardNo(m.cardNo)}
                      </p>
                    </TD>
                    <TD className="hidden font-mono text-sm sm:table-cell">
                      {formatCardNo(m.cardNo)}
                      {m.cardActive ? null : (
                        <Badge className="ml-2">{t('loyalty.cardReplaced')}</Badge>
                      )}
                    </TD>
                    <TD className="hidden md:table-cell">{m.planName}</TD>
                    <TD>
                      <Badge tone={STATE_TONE[m.state]}>{t(`loyalty.states.${m.state}`)}</Badge>
                      <p className="mt-1 text-xs text-muted-foreground">
                        {formatDate(m.startsOn, lng)} – {formatDate(m.endsOn, lng)}
                      </p>
                    </TD>
                    <TD>
                      <div className="flex justify-end gap-1">
                        {canEnroll &&
                        m.state !== 'cancelled' &&
                        m.state !== 'upcoming' &&
                        m.cardActive ? (
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label={t('loyalty.renewNamed', { name: m.customer.name })}
                            onClick={() => setEnrolling(m.customer)}
                          >
                            <RefreshCw aria-hidden />
                          </Button>
                        ) : null}
                        {canCancel &&
                        m.cardActive &&
                        m.state !== 'cancelled' &&
                        m.state !== 'expired' ? (
                          <>
                            <Button
                              variant="ghost"
                              size="icon"
                              aria-label={t('loyalty.replaceNamed', { name: m.customer.name })}
                              onClick={() => setReplacing(m)}
                            >
                              <Replace aria-hidden />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              aria-label={t('loyalty.cancelNamed', { name: m.customer.name })}
                              onClick={() => setCancelling(m)}
                            >
                              <Ban aria-hidden />
                            </Button>
                          </>
                        ) : null}
                      </div>
                    </TD>
                  </TR>
                ))}
              </TBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {canEnroll ? (
        <EnrollDialog
          open={enrolling !== undefined}
          onOpenChange={(o) => {
            if (!o) setEnrolling(undefined)
          }}
          customer={enrolling ?? null}
        />
      ) : null}
      {canCancel ? (
        <>
          <ReasonDialog
            open={cancelling !== null}
            onOpenChange={(o) => {
              if (!o) setCancelling(null)
            }}
            title={t('loyalty.cancelTitle')}
            description={t('loyalty.cancelBody', { name: cancelling?.customer.name ?? '' })}
            confirmLabel={t('loyalty.cancelConfirm')}
            onConfirm={async (reason) => {
              if (!cancelling) return
              await rpc('cancel_loyalty_membership', {
                p_membership_id: cancelling.id,
                p_reason: reason,
              })
              toast.success(t('loyalty.cancelled'))
              await refresh()
            }}
          />
          <ReasonDialog
            open={replacing !== null}
            onOpenChange={(o) => {
              if (!o) setReplacing(null)
            }}
            title={t('loyalty.replaceTitle')}
            description={t('loyalty.replaceBody', { name: replacing?.customer.name ?? '' })}
            withCardNo
            confirmLabel={t('loyalty.replaceConfirm')}
            onConfirm={async (reason, cardNo) => {
              if (!replacing) return
              const newNo = await rpc('replace_loyalty_card', {
                p_card_id: replacing.cardId,
                p_reason: reason,
                ...(cardNo ? { p_new_card_no: cardNo } : {}),
              })
              toast.success(t('loyalty.replacedToast', { no: formatCardNo(newNo) }))
              await refresh()
            }}
          />
        </>
      ) : null}
    </>
  )
}

type Tab = 'members' | 'plans'

export function LoyaltyPage() {
  const { t } = useTranslation()
  const [tab, setTab] = useState<Tab>('members')
  return (
    <>
      <PageHeader title={t('nav.loyalty')} description={t('loyalty.subtitle')} />
      <div
        role="tablist"
        aria-label={t('nav.loyalty')}
        className="mb-6 inline-flex gap-1 rounded-lg bg-surface-muted p-1"
      >
        {(['members', 'plans'] as const).map((id) => (
          <button
            key={id}
            role="tab"
            type="button"
            aria-selected={tab === id}
            aria-controls={`loyalty-${id}`}
            onClick={() => setTab(id)}
            className={cn(
              'rounded-md px-4 py-1.5 text-sm font-medium transition-colors',
              tab === id
                ? 'bg-surface text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            )}
          >
            {t(`loyalty.tabs.${id}`)}
          </button>
        ))}
      </div>
      <div role="tabpanel" id={`loyalty-${tab}`}>
        {tab === 'members' ? <MembersTab /> : <PlansEditor />}
      </div>
    </>
  )
}
