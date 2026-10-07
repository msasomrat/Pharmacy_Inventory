import * as DialogPrimitive from '@radix-ui/react-dialog'
import { Command } from 'cmdk'
import { Search } from 'lucide-react'
import { useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { useNavigate } from 'react-router'

import { useOrg } from '@/features/org/org-context'

import { navFor } from './nav'

export function CommandPalette({
  open,
  onOpenChange,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { current, can } = useOrg()
  const sections = current ? navFor(can) : []

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        onOpenChange(!open)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
    }
  }, [open, onOpenChange])

  return (
    <DialogPrimitive.Root open={open} onOpenChange={onOpenChange}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/40 backdrop-blur-[2px]" />
        <DialogPrimitive.Content className="fixed top-[15vh] left-1/2 z-50 w-[calc(100%-2rem)] max-w-xl -translate-x-1/2 overflow-hidden rounded-xl border bg-surface shadow-pop">
          <DialogPrimitive.Title className="sr-only">{t('nav.search')}</DialogPrimitive.Title>
          <Command label={t('nav.search')}>
            <div className="flex items-center gap-2 border-b px-4">
              <Search className="size-4 text-muted-foreground" aria-hidden />
              <Command.Input
                // eslint-disable-next-line jsx-a11y/no-autofocus -- a command palette exists to be typed into
                autoFocus
                placeholder={t('nav.search')}
                className="h-12 flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
              />
            </div>
            <Command.List className="max-h-80 overflow-y-auto p-2">
              <Command.Empty className="p-6 text-center text-sm text-muted-foreground">
                —
              </Command.Empty>
              {sections.map((section) => (
                <Command.Group
                  key={section.key}
                  heading={t(`nav.sections.${section.key}`)}
                  className="[&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:py-1.5 [&_[cmdk-group-heading]]:text-xs [&_[cmdk-group-heading]]:text-muted-foreground"
                >
                  {section.items.map((item) => (
                    <Command.Item
                      key={item.to}
                      value={`${t(`nav.${item.key}`)} ${item.key}`}
                      onSelect={() => {
                        onOpenChange(false)
                        void navigate(item.to)
                      }}
                      className="flex cursor-pointer items-center gap-3 rounded-md px-2 py-2 text-sm data-[selected=true]:bg-surface-muted"
                    >
                      <item.icon className="size-4 text-muted-foreground" aria-hidden />
                      {t(`nav.${item.key}`)}
                    </Command.Item>
                  ))}
                </Command.Group>
              ))}
            </Command.List>
          </Command>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  )
}
