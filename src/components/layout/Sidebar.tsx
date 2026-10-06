import { ChevronsLeft, ChevronsRight } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { NavLink } from 'react-router'

import { Logo } from '@/components/brand/logo'
import { Tooltip } from '@/components/ui/tooltip'
import { cn } from '@/lib/cn'
import { useOrg } from '@/features/org/org-context'

import { navFor } from './nav'

export function SidebarNav({
  collapsed,
  onNavigate,
}: {
  collapsed: boolean
  onNavigate?: () => void
}) {
  const { t } = useTranslation()
  const { current } = useOrg()
  return (
    <nav aria-label="Main" className="flex flex-col gap-6">
      {navFor(current?.role).map((section) => (
        <div key={section.key} className="flex flex-col gap-1">
          {collapsed ? null : (
            <p className="px-3 pb-1 text-[11px] font-semibold tracking-wider text-sidebar-muted uppercase">
              {t(`nav.sections.${section.key}`)}
            </p>
          )}
          {section.items.map((item) => {
            const link = (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === '/'}
                onClick={onNavigate}
                className={({ isActive }) =>
                  cn(
                    'group relative flex h-10 items-center gap-3 rounded-md px-3 text-sm font-medium text-sidebar-muted transition-colors hover:bg-sidebar-active hover:text-sidebar-foreground',
                    isActive && 'bg-sidebar-active text-white',
                    collapsed && 'justify-center px-0',
                  )
                }
              >
                {({ isActive }) => (
                  <>
                    {isActive ? (
                      <span
                        aria-hidden
                        className="absolute top-2 bottom-2 left-0 w-0.5 rounded-full bg-primary"
                      />
                    ) : null}
                    <item.icon
                      className={cn('size-[18px] shrink-0', isActive && 'text-primary')}
                      aria-hidden
                    />
                    {collapsed ? (
                      <span className="sr-only">{t(`nav.${item.key}`)}</span>
                    ) : (
                      t(`nav.${item.key}`)
                    )}
                  </>
                )}
              </NavLink>
            )
            return collapsed ? (
              <Tooltip key={item.to} content={t(`nav.${item.key}`)}>
                {link}
              </Tooltip>
            ) : (
              link
            )
          })}
        </div>
      ))}
    </nav>
  )
}

export function Sidebar({ collapsed, onToggle }: { collapsed: boolean; onToggle: () => void }) {
  const { t } = useTranslation()
  return (
    <aside
      className={cn(
        'sticky top-0 hidden h-dvh shrink-0 flex-col border-r border-white/5 bg-sidebar px-3 py-4 text-sidebar-foreground transition-[width] duration-200 lg:flex',
        collapsed ? 'w-[68px]' : 'w-64',
      )}
    >
      <div className={cn('mb-6 flex items-center px-2', collapsed && 'justify-center px-0')}>
        <Logo withText={!collapsed} className="text-white" />
      </div>
      <div className="flex-1 overflow-y-auto">
        <SidebarNav collapsed={collapsed} />
      </div>
      <button
        type="button"
        onClick={onToggle}
        className={cn(
          'mt-4 flex h-9 items-center gap-2 rounded-md px-3 text-sm text-sidebar-muted hover:bg-sidebar-active hover:text-sidebar-foreground',
          collapsed && 'justify-center px-0',
        )}
        aria-label={collapsed ? t('nav.expand') : t('nav.collapse')}
      >
        {collapsed ? (
          <ChevronsRight className="size-4" aria-hidden />
        ) : (
          <ChevronsLeft className="size-4" aria-hidden />
        )}
        {collapsed ? null : t('nav.collapse')}
      </button>
    </aside>
  )
}
