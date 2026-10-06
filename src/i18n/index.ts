import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

import { prefs } from '@/lib/storage'

import bn from './locales/bn.json'
import en from './locales/en.json'

export const SUPPORTED_LANGUAGES = ['en', 'bn'] as const
export type Language = (typeof SUPPORTED_LANGUAGES)[number]

const saved = prefs.get('lang')

void i18n.use(initReactI18next).init({
  resources: { en: { translation: en }, bn: { translation: bn } },
  lng: saved === 'bn' ? 'bn' : 'en',
  fallbackLng: 'en',
  supportedLngs: SUPPORTED_LANGUAGES,
  interpolation: { escapeValue: false }, // React already escapes output.
  returnNull: false,
})

function syncDocument(lng: string) {
  if (typeof document !== 'undefined') document.documentElement.lang = lng
}
syncDocument(i18n.language)
i18n.on('languageChanged', (lng) => {
  syncDocument(lng)
  prefs.set('lang', lng)
})

export function currentLanguage(): Language {
  return i18n.language === 'bn' ? 'bn' : 'en'
}

export default i18n
