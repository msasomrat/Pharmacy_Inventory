import type { Database } from './database.types'
import { toAppError } from './errors'
import { supabase } from './supabase'

type Fns = Database['public']['Functions']

/** Typed RPC call that throws AppError with a translated message on failure. */
export async function rpc<N extends keyof Fns>(
  name: N,
  args: Fns[N]['Args'],
): Promise<Fns[N]['Returns']> {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw toAppError(error)
  return data
}

export function newRequestId(): string {
  return crypto.randomUUID()
}
