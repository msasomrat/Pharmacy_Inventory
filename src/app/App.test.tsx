import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'

import '@/i18n'

import { App } from './App'

describe('App', () => {
  it('renders the product name and switches to Bangla', async () => {
    render(<App />)
    expect(screen.getByRole('heading', { name: 'Pharmacy Inventory' })).toBeInTheDocument()

    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Language' }), 'bn')

    expect(screen.getByRole('heading', { name: 'ফার্মেসি ইনভেন্টরি' })).toBeInTheDocument()
  })
})
