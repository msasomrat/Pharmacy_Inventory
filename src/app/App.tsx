import { useTranslation } from 'react-i18next'

import { SUPPORTED_LANGUAGES, type Language } from '@/i18n'

const LANGUAGE_LABELS: Record<Language, string> = { en: 'English', bn: 'বাংলা' }

export function App() {
  const { t, i18n } = useTranslation()

  return (
    <main className="mx-auto flex min-h-dvh max-w-2xl flex-col justify-center gap-4 p-6">
      <h1 className="text-3xl font-semibold text-brand-700">{t('app.name')}</h1>
      <p className="text-lg">{t('app.tagline')}</p>
      <p className="text-sm opacity-80">{t('app.status')}</p>
      <label className="flex items-center gap-2 text-sm">
        {t('app.language')}
        <select
          className="rounded border px-2 py-1"
          value={i18n.language}
          onChange={(event) => void i18n.changeLanguage(event.target.value)}
        >
          {SUPPORTED_LANGUAGES.map((lng) => (
            <option key={lng} value={lng}>
              {LANGUAGE_LABELS[lng]}
            </option>
          ))}
        </select>
      </label>
    </main>
  )
}
