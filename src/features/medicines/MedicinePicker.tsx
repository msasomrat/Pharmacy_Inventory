import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Search } from 'lucide-react'
import { useCallback, useId, useState, type KeyboardEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'

import { Input } from '@/components/ui/input'
import { useWorkspace } from '@/features/org/org-context'
import { useDebounced } from '@/hooks/useDebounced'
import { rpc } from '@/lib/api'
import { cn } from '@/lib/cn'
import { errorMessage } from '@/lib/errors'
import type { Database } from '@/lib/database.types'

export type MedicineHit = Database['public']['Functions']['search_medicines']['Returns'][number]

/** Search-as-you-type medicine combobox (brand, generic or barcode). Enter picks the highlighted hit. */
export function MedicinePicker({
  onPick,
  label,
  placeholder,
}: {
  onPick: (hit: MedicineHit) => void
  label: string
  placeholder: string
}) {
  const { t } = useTranslation()
  const { branch } = useWorkspace()
  const listId = useId()
  const [text, setText] = useState('')
  const [active, setActive] = useState(0)
  const [open, setOpen] = useState(false)
  const query = useDebounced(text.trim(), 150)
  const queryClient = useQueryClient()

  const searchOptions = useCallback(
    (q: string) => ({
      queryKey: ['search_medicines', branch.id, q, 12],
      queryFn: () => rpc('search_medicines', { p_branch_id: branch.id, p_query: q, p_limit: 12 }),
      staleTime: 10_000,
    }),
    [branch.id],
  )
  const results = useQuery({ ...searchOptions(query), enabled: query.length >= 2 })
  const hits = query.length >= 2 ? (results.data ?? []) : []

  function pick(hit: MedicineHit | undefined) {
    if (!hit) return
    onPick(hit)
    setText('')
    setActive(0)
    setOpen(false)
  }

  // Enter must work before the debounced search returns (barcode scanners type + Enter instantly).
  async function pickFromInput() {
    const q = text.trim()
    if (q.length < 2) return
    if (q === query && results.data) {
      pick(results.data[active])
      return
    }
    try {
      const rows = await queryClient.query(searchOptions(q))
      if (rows.length === 0) toast.error(t('pos.noResults'))
      else pick(rows[0])
    } catch (err) {
      toast.error(errorMessage(err))
    }
  }

  function onKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActive((i) => Math.min(i + 1, hits.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((i) => Math.max(i - 1, 0))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      void pickFromInput()
    } else if (e.key === 'Escape') {
      setOpen(false)
    }
  }

  const expanded = open && query.length >= 2

  return (
    <div className="relative">
      <Search
        aria-hidden
        className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
      />
      <Input
        role="combobox"
        aria-label={label}
        aria-expanded={expanded}
        aria-controls={listId}
        aria-autocomplete="list"
        {...(expanded && hits[active] ? { 'aria-activedescendant': `${listId}-${active}` } : {})}
        placeholder={placeholder}
        className="pl-9"
        value={text}
        onChange={(e) => {
          setText(e.target.value)
          setActive(0)
          setOpen(true)
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
        onKeyDown={onKeyDown}
      />
      {expanded ? (
        <div
          id={listId}
          role="listbox"
          className="absolute z-30 mt-1 max-h-80 w-full overflow-y-auto rounded-lg border bg-surface p-1 shadow-pop"
        >
          {hits.length === 0 ? (
            <p className="px-3 py-2 text-sm text-muted-foreground">
              {results.isFetching ? t('app.loading') : t('pos.noResults')}
            </p>
          ) : (
            hits.map((h, i) => (
              // Keyboard users drive this list from the input (aria-activedescendant combobox pattern).
              // eslint-disable-next-line jsx-a11y/interactive-supports-focus
              <div
                key={h.medicine_id}
                id={`${listId}-${i}`}
                role="option"
                aria-selected={i === active}
                onMouseEnter={() => setActive(i)}
                onMouseDown={(e) => {
                  e.preventDefault()
                  pick(h)
                }}
                className={cn(
                  'flex cursor-pointer items-center justify-between gap-3 rounded-md px-3 py-2 text-sm',
                  i === active && 'bg-primary-soft/60',
                )}
              >
                <span className="min-w-0">
                  <span className="font-medium">{h.brand_name}</span>{' '}
                  <span className="text-muted-foreground">{h.strength}</span>
                  <span className="block truncate text-xs text-muted-foreground">
                    {[h.generic_name, h.manufacturer_name].filter(Boolean).join(' · ')}
                  </span>
                </span>
                {h.rack_location ? (
                  <span className="shrink-0 rounded bg-surface-muted px-1.5 py-0.5 font-mono text-xs">
                    {h.rack_location}
                  </span>
                ) : null}
              </div>
            ))
          )}
        </div>
      ) : null}
    </div>
  )
}
