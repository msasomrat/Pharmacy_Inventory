## Summary

<!-- What does this change and why? Link the requirement IDs (e.g. FR-POS-003) and issue. -->

## Type of change

- [ ] Feature
- [ ] Bug fix
- [ ] Database migration
- [ ] Security
- [ ] Refactor / chore
- [ ] Documentation

## Checklist (Definition of Done — see docs/engineering/engineering-standards.md)

- [ ] Tests added/updated (unit, pgTAP incl. RLS for every new table/function, E2E for critical flows)
- [ ] New tables have RLS enabled with policies and isolation tests
- [ ] New SQL functions use `SET search_path = ''` and explicit permission checks
- [ ] No secrets, no service_role key in client code; no `dangerouslySetInnerHTML`
- [ ] Money handled as integer paisa; business dates in Asia/Dhaka
- [ ] UI strings translated (en + bn); keyboard and screen-reader accessible
- [ ] Migration is forward-only and safe on existing data (expand → migrate → contract)
- [ ] Docs/ADR/threat model updated if behaviour or architecture changed
- [ ] `pnpm check` passes locally

## Screenshots / evidence

## Rollback plan

<!-- How do we undo this if it misbehaves in production? -->
