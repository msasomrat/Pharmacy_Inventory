import i18n from '@/i18n'

/**
 * Database business errors carry a stable machine code in DETAIL (see app.fail). We translate the
 * code when we have a message for it and fall back to the server message otherwise.
 */
export class AppError extends Error {
  override name = 'AppError'
  constructor(
    readonly code: string,
    message: string,
    readonly hint?: string,
  ) {
    super(message)
  }
}

interface PostgrestLikeError {
  message: string
  details?: string | null
  hint?: string | null
  code?: string
}

export function toAppError(error: PostgrestLikeError): AppError {
  const code =
    error.details && /^[a-z_]+$/.test(error.details) ? error.details : (error.code ?? 'unknown')
  const key = `errors.${code}`
  const message = i18n.exists(key) ? i18n.t(key) : error.message
  return new AppError(code, message, error.hint ?? undefined)
}

export function errorMessage(error: unknown): string {
  if (error instanceof AppError) return error.message
  if (error instanceof Error) return error.message
  return i18n.t('errors.unknown')
}
