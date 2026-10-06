import { createClient } from '@supabase/supabase-js'

import { parseEnv } from './env'

const env = parseEnv(import.meta.env)

/**
 * Browser Supabase client. It only ever holds the public anon key plus the signed-in user's JWT;
 * all authorization is enforced by Row Level Security and database functions.
 */
export const supabase = createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
})
