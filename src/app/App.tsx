import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router'
import { Toaster } from 'sonner'

import { TooltipProvider } from '@/components/ui/tooltip'
import { AuthProvider } from '@/features/auth/auth-context'
import { OrgProvider } from '@/features/org/org-context'

import { router } from './router'
import { ThemeProvider, useTheme } from './theme'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, retry: 1, refetchOnWindowFocus: false },
    mutations: { retry: 0 }, // Never blindly retry writes; sales use idempotency keys instead.
  },
})

function ThemedToaster() {
  const { resolved } = useTheme()
  return <Toaster theme={resolved} richColors position="top-right" closeButton />
}

export function App() {
  return (
    <ThemeProvider>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <OrgProvider>
            <TooltipProvider>
              <RouterProvider router={router} />
              <ThemedToaster />
            </TooltipProvider>
          </OrgProvider>
        </AuthProvider>
      </QueryClientProvider>
    </ThemeProvider>
  )
}
