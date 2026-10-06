import { describe, expect, it } from 'vitest'

import { parseEnv } from './env'

const valid = {
  VITE_SUPABASE_URL: 'http://127.0.0.1:54321',
  VITE_SUPABASE_ANON_KEY: 'a'.repeat(40),
}

describe('parseEnv', () => {
  it('accepts a valid environment and defaults optional values', () => {
    expect(parseEnv(valid)).toEqual({ ...valid, VITE_SENTRY_DSN: '' })
  })

  it('names the missing variables without echoing their values', () => {
    expect(() => parseEnv({ VITE_SUPABASE_URL: 'not-a-url' })).toThrow(
      /VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY/,
    )
  })
})
