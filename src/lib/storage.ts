/** localStorage wrapper that never throws (private mode, blocked storage). Non-sensitive prefs only. */
export const prefs = {
  get(key: string): string | null {
    try {
      return window.localStorage.getItem(`pims:${key}`)
    } catch {
      return null
    }
  },
  set(key: string, value: string | null): void {
    try {
      if (value === null) window.localStorage.removeItem(`pims:${key}`)
      else window.localStorage.setItem(`pims:${key}`, value)
    } catch {
      // Preference persistence is best-effort.
    }
  },
}
