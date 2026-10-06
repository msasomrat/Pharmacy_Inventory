import * as DialogPrimitive from '@radix-ui/react-dialog'
import { Building2, Check, ChevronDown, LogOut, Menu, Search, ShieldCheck } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Outlet } from 'react-router'

import { Logo } from '@/components/brand/logo'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Kbd } from '@/components/ui/kbd'
import { useAuth } from '@/features/auth/auth-context'
import { useOrg } from '@/features/org/org-context'
import { prefs } from '@/lib/storage'

import { CommandPalette } from './CommandPalette'
import { LanguageToggle, ThemeToggle } from './preferences'
import { Sidebar, SidebarNav } from './Sidebar'

function initials(text: string): string {
  return text
    .split(/[\s@._-]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('')
}

function BranchSwitcher() {
  const { t } = useTranslation()
  const { memberships, current, branch, selectOrganization, selectBranch } = useOrg()
  if (!current || !branch) return null
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="secondary"
          size="sm"
          className="max-w-[16rem] gap-2"
          aria-label={t('nav.branch')}
        >
          <Building2 aria-hidden />
          <span className="truncate">
            <span className="hidden sm:inline">{current.organizationName} · </span>
            {branch.name}
          </span>
          <ChevronDown className="opacity-60" aria-hidden />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-64">
        {memberships.map((m) => (
          <div key={m.organizationId}>
            <DropdownMenuLabel>{m.organizationName}</DropdownMenuLabel>
            {m.branches.map((b) => (
              <DropdownMenuItem
                key={b.id}
                onSelect={() => {
                  if (m.organizationId !== current.organizationId)
                    selectOrganization(m.organizationId)
                  selectBranch(b.id)
                }}
              >
                <span className="grid size-6 place-items-center rounded bg-primary-soft text-[10px] font-semibold text-primary-soft-foreground">
                  {b.code}
                </span>
                <span className="flex-1">{b.name}</span>
                {b.id === branch.id ? <Check className="!text-primary" aria-hidden /> : null}
              </DropdownMenuItem>
            ))}
          </div>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function UserMenu() {
  const { t } = useTranslation()
  const { session, aal, signOut } = useAuth()
  const { current } = useOrg()
  const email = session?.user.email ?? ''
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          className="grid size-9 place-items-center rounded-full bg-primary text-xs font-semibold text-primary-foreground ring-offset-2 hover:ring-2 hover:ring-primary/30"
          aria-label={t('nav.account')}
        >
          {initials(email)}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60">
        <DropdownMenuLabel>
          <span className="block truncate text-sm font-medium text-foreground">{email}</span>
          <span className="capitalize">{current?.role}</span>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem disabled>
          <ShieldCheck aria-hidden />
          {t('nav.security')}: {aal.current === 'aal2' ? '✓' : '—'}
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={() => void signOut()}>
          <LogOut aria-hidden />
          {t('nav.signOut')}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

export function AppShell() {
  const { t } = useTranslation()
  const [collapsed, setCollapsed] = useState(() => prefs.get('sidebar') === 'collapsed')
  const [mobileOpen, setMobileOpen] = useState(false)
  const [paletteOpen, setPaletteOpen] = useState(false)

  return (
    <div className="flex min-h-dvh bg-background">
      <a
        href="#main"
        className="sr-only z-50 rounded-md bg-primary px-3 py-2 text-primary-foreground focus:not-sr-only focus:fixed focus:top-2 focus:left-2"
      >
        {t('app.skipToContent')}
      </a>
      <Sidebar
        collapsed={collapsed}
        onToggle={() => {
          setCollapsed((c) => {
            prefs.set('sidebar', c ? null : 'collapsed')
            return !c
          })
        }}
      />

      <DialogPrimitive.Root open={mobileOpen} onOpenChange={setMobileOpen}>
        <DialogPrimitive.Portal>
          <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-black/50 lg:hidden" />
          <DialogPrimitive.Content className="fixed inset-y-0 left-0 z-50 w-72 bg-sidebar p-4 text-sidebar-foreground shadow-pop lg:hidden">
            <DialogPrimitive.Title className="mb-6 px-2">
              <Logo withText className="text-white" />
            </DialogPrimitive.Title>
            <SidebarNav collapsed={false} onNavigate={() => setMobileOpen(false)} />
          </DialogPrimitive.Content>
        </DialogPrimitive.Portal>
      </DialogPrimitive.Root>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex h-16 items-center gap-3 border-b bg-background/85 px-4 backdrop-blur supports-[backdrop-filter]:bg-background/70 sm:px-6">
          <Button
            variant="ghost"
            size="icon"
            className="lg:hidden"
            onClick={() => setMobileOpen(true)}
            aria-label={t('nav.openMenu')}
          >
            <Menu aria-hidden />
          </Button>
          <BranchSwitcher />
          <button
            type="button"
            onClick={() => setPaletteOpen(true)}
            className="ml-auto hidden h-9 w-64 items-center gap-2 rounded-md border bg-surface px-3 text-sm text-muted-foreground shadow-xs hover:bg-surface-muted md:flex"
          >
            <Search className="size-4" aria-hidden />
            <span className="flex-1 text-left">{t('nav.search')}</span>
            <Kbd>Ctrl</Kbd>
            <Kbd>K</Kbd>
          </button>
          <div className="ml-auto flex items-center gap-1 md:ml-0">
            <LanguageToggle />
            <ThemeToggle />
            <UserMenu />
          </div>
        </header>
        <main id="main" className="flex-1 px-4 py-6 sm:px-6 lg:px-8">
          <Outlet />
        </main>
      </div>
      <CommandPalette open={paletteOpen} onOpenChange={setPaletteOpen} />
    </div>
  )
}
