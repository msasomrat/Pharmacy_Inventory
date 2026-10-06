import type { AuthMFAGetAuthenticatorAssuranceLevelResponse, Session } from '@supabase/supabase-js'
import { useQueryClient } from '@tanstack/react-query'
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'

import { supabase } from '@/lib/supabase'

type Aal = 'aal1' | 'aal2'

export interface AuthContextValue {
  status: 'loading' | 'signed_out' | 'signed_in'
  session: Session | null
  /** Current assurance level and the highest level the user can reach (aal2 = has a TOTP factor). */
  aal: { current: Aal; next: Aal }
  refreshAal: () => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

function toAal(level: string | null | undefined): Aal {
  return level === 'aal2' ? 'aal2' : 'aal1'
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient()
  const [session, setSession] = useState<Session | null>(null)
  const [status, setStatus] = useState<AuthContextValue['status']>('loading')
  const [aal, setAal] = useState<AuthContextValue['aal']>({ current: 'aal1', next: 'aal1' })

  const refreshAal = useCallback(async () => {
    const res: AuthMFAGetAuthenticatorAssuranceLevelResponse =
      await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
    if (res.data) {
      setAal({ current: toAal(res.data.currentLevel), next: toAal(res.data.nextLevel) })
    }
  }, [])

  useEffect(() => {
    let active = true
    // Status stays 'loading' until the assurance level is known, so the UI never flashes the
    // two-factor enrolment screen (which would start an enrolment) for users who already have one.
    const { data: sub } = supabase.auth.onAuthStateChange((event, next) => {
      setSession(next)
      if (event === 'SIGNED_OUT') queryClient.clear() // never leak one user's cached data to the next
      if (!next) {
        setStatus('signed_out')
        return
      }
      // Defer: calling supabase.auth inside this callback can deadlock the auth lock.
      window.setTimeout(() => {
        refreshAal().then(
          () => {
            if (active) setStatus('signed_in')
          },
          async () => {
            // A corrupted or forged stored session: drop it locally rather than guess the user's MFA state.
            await supabase.auth.signOut({ scope: 'local' })
            if (active) setStatus('signed_out')
          },
        )
      }, 0)
    })
    return () => {
      active = false
      sub.subscription.unsubscribe()
    }
  }, [queryClient, refreshAal])

  const signOut = useCallback(async () => {
    await supabase.auth.signOut()
  }, [])

  const value = useMemo(
    () => ({ status, session, aal, refreshAal, signOut }),
    [status, session, aal, refreshAal, signOut],
  )
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider')
  return ctx
}
