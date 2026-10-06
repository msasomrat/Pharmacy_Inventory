import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

import bn from './locales/bn.json'
import en from './locales/en.json'

export const SUPPORTED_LANGUAGES = ['en', 'bn'] as const
export type Language = (typeof SUPPORTED_LANGUAGES)[number]

void i18n.use(initReactI18next).init({
  resources: { en: { translation: en }, bn: { translation: bn } },
  lng: 'en',
  fallbackLng: 'en',
  supportedLngs: SUPPORTED_LANGUAGES,
  interpolation: { escapeValue: false }, // React already escapes output.
  returnNull: false,
})

export default i18n
