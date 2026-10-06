export default {
  '*.{ts,tsx}': ['eslint --max-warnings=0 --no-warn-ignored --fix', 'prettier --write'],
  '*.{js,json,md,yml,yaml,css,html}': ['prettier --write'],
}
