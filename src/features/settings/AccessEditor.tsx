import { RotateCcw } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { Button } from '@/components/ui/button'
import type { OrgRole } from '@/features/org/org-context'
import {
  PERMISSION_GROUPS,
  roleTemplate,
  withDependencies,
  type Permission,
} from '@/features/org/permissions'

/** Checklist of what one member may do, starting from their role template. */
export function AccessEditor({
  role,
  value,
  onChange,
}: {
  role: OrgRole
  value: Set<Permission>
  onChange: (next: Set<Permission>) => void
}) {
  const { t } = useTranslation()
  const template = roleTemplate(role)
  const customised = [...new Set([...template, ...value])].some(
    (p) => template.has(p) !== value.has(p),
  )

  if (role === 'owner') {
    return <p className="rounded-md bg-surface-muted p-3 text-sm">{t('settings.ownerAll')}</p>
  }

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">{t('settings.accessHint')}</p>
        {customised ? (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => onChange(new Set(template))}
          >
            <RotateCcw aria-hidden />
            {t('settings.resetToRole')}
          </Button>
        ) : null}
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        {PERMISSION_GROUPS.map((group) => (
          <fieldset key={group.key} className="grid content-start gap-1 rounded-lg border p-3">
            <legend className="px-1 text-sm font-semibold">
              {t(`settings.groups.${group.key}`)}
            </legend>
            {group.permissions.map((p) => {
              const changed = template.has(p) !== value.has(p)
              return (
                <label
                  key={p}
                  className="flex cursor-pointer items-start gap-2 rounded-md px-1 py-1 text-sm hover:bg-surface-muted"
                >
                  <input
                    type="checkbox"
                    className="mt-0.5 size-4 accent-primary"
                    checked={value.has(p)}
                    onChange={(e) => onChange(withDependencies(value, p, e.target.checked))}
                  />
                  <span>
                    <span className="font-medium">{t(`settings.perms.${p}`)}</span>
                    {changed ? (
                      <span className="ml-1.5 rounded bg-warning-soft px-1 text-[11px] text-warning">
                        {t('settings.custom')}
                      </span>
                    ) : null}
                  </span>
                </label>
              )
            })}
          </fieldset>
        ))}
      </div>
    </div>
  )
}
