import { cn } from '@/lib/cn'

/** Brand mark: a rounded cross in a pill, legible at 16px. */
export function Logo({ className, withText = false }: { className?: string; withText?: boolean }) {
  return (
    <span className={cn('inline-flex items-center gap-2', className)}>
      <svg viewBox="0 0 32 32" aria-hidden className="size-8 shrink-0">
        <rect width="32" height="32" rx="9" fill="var(--primary)" />
        <path d="M13 8h6v5h5v6h-5v5h-6v-5H8v-6h5z" fill="var(--primary-foreground)" />
      </svg>
      {withText ? (
        <span className="text-base font-semibold tracking-tight">Pharmacy&nbsp;Inventory</span>
      ) : null}
    </span>
  )
}
