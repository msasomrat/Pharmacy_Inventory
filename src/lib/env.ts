import { z } from 'zod'

/**
 * Validated, typed access to build-time environment variables.
 * Everything here ships to the browser — never add secrets (service_role keys, API keys).
 */
const envSchema = z.object({
  VITE_SUPABASE_URL: z.url(),
  VITE_SUPABASE_ANON_KEY: z.string().min(20),
  VITE_SENTRY_DSN: z.union([z.url(), z.literal('')]).default(''),
})

export type Env = z.infer<typeof envSchema>

export function parseEnv(source: Record<string, unknown>): Env {
  const result = envSchema.safeParse(source)
  if (!result.success) {
    const fields = result.error.issues.map((issue) => issue.path.join('.')).join(', ')
    throw new Error(`Invalid or missing environment variables: ${fields}. See .env.example.`)
  }
  return result.data
}
