/// <reference types="vitest/config" />
import { fileURLToPath, URL } from 'node:url'

import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    target: 'es2022',
    sourcemap: true,
    rolldownOptions: {
      output: {
        // Stable vendor chunks: a deploy that only changes app code leaves these cached in browsers
        // (Cloudflare serves /assets/* as immutable). Charts stay with the dashboard's lazy chunk.
        codeSplitting: {
          groups: [
            {
              name: 'react',
              test: /node_modules[\\/](react|react-dom|scheduler|react-router)[\\/]/,
              priority: 30,
            },
            { name: 'supabase', test: /node_modules[\\/]@supabase[\\/]/, priority: 20 },
            {
              name: 'ui',
              test: /node_modules[\\/](@radix-ui|@floating-ui|sonner|lucide-react|@tanstack|i18next|react-i18next)[\\/]/,
              priority: 10,
            },
          ],
        },
      },
    },
  },
  test: {
    environment: 'jsdom',
    globals: false,
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    restoreMocks: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      include: ['src/**/*.{ts,tsx}'],
      exclude: [
        'src/**/*.test.{ts,tsx}',
        'src/test/**',
        'src/main.tsx',
        'src/lib/database.types.ts',
      ],
      thresholds: {
        'src/domain/**': { lines: 90, functions: 90, branches: 85, statements: 90 },
      },
    },
  },
})
