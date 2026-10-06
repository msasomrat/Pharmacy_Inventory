import { Languages, Monitor, Moon, Sun } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { useTheme, type ThemeChoice } from '@/app/theme'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

export function LanguageToggle() {
  const { t, i18n } = useTranslation()
  const next = i18n.language === 'bn' ? 'en' : 'bn'
  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={() => void i18n.changeLanguage(next)}
      aria-label={t('app.language')}
      className="font-medium"
    >
      <Languages aria-hidden />
      {next === 'bn' ? 'বাংলা' : 'English'}
    </Button>
  )
}

const THEME_ICON = { light: Sun, dark: Moon, system: Monitor } as const

export function ThemeToggle() {
  const { t } = useTranslation()
  const { theme, setTheme } = useTheme()
  const Icon = THEME_ICON[theme]
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" aria-label={t('app.theme')}>
          <Icon aria-hidden />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {(['light', 'dark', 'system'] as ThemeChoice[]).map((choice) => {
          const ChoiceIcon = THEME_ICON[choice]
          return (
            <DropdownMenuItem
              key={choice}
              onSelect={() => setTheme(choice)}
              aria-current={theme === choice}
            >
              <ChoiceIcon aria-hidden />
              {t(`app.${choice}`)}
            </DropdownMenuItem>
          )
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
