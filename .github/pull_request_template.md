<!--
Pull request template. Structure and rules: docs/engineering/engineering-standards.md sections 5.3
(template contents) and 7.2 (Definition of Done). Fill in every section; write "Not applicable" in a
section that does not apply instead of deleting it. The title is a Conventional Commit header.
-->

## Summary

<!-- What changes and why, in two to five sentences. -->

## Requirements

<!--
List requirement IDs from docs/requirements/SRS.md so the traceability report (SRS section 4.2)
picks them up. Use "Implements:" for requirements this change satisfies and "Affects:" for
requirements whose behaviour or tests change. Write "None" on a line that has no IDs.
-->

Implements: <!-- e.g. FR-POS-030, NFR-REL-004 -->

Affects: <!-- e.g. FR-INV-005 -->

Closes #<!-- issue number -->

## Type of change

- [ ] Feature
- [ ] Bug fix
- [ ] Database migration
- [ ] Security
- [ ] Refactor or chore
- [ ] Documentation

## How it was tested

<!--
Test levels added or changed (unit, pgTAP, integration, E2E) with the test titles that carry
requirement IDs; manual checks performed; evidence for anything not automated.
-->

- Unit (Vitest):
- Database (pgTAP, including RLS isolation for every new table and the full set for every new or changed RPC):
- Integration:
- E2E (Playwright):
- Manual checks:

## Database changes

<!--
Migration file names; new tables, policies, grants and functions; expand-migrate-contract phase;
backfill size and duration; lock impact. Confirm: every new table has organization_id (and
branch_id where branch-scoped), RLS enabled with policies per operation and explicit grants; every
new function uses `set search_path = ''`, schema-qualified names and a permission check first;
`pnpm gen:types` output is committed. See engineering standards section 11.8.
-->

- Migrations:
- Tables, policies, grants, functions:
- Expand, migrate, contract phase:
- Backfill size and duration; lock impact:

## Security and privacy impact

<!--
Authorization changes, new personal data, new secrets or endpoints. No secrets and no service_role
key in client code. State whether the threat model in docs/security/security-model.md section 5 was
updated, or that no threat changed (NFR-SEC-014).
-->

- Authorization changes:
- New personal data:
- New secrets or endpoints:
- Threat model: <!-- updated (sections ...) / no threat changed -->

## Screenshots or recordings

<!--
For UI changes: English and Bangla, desktop and the narrowest supported width; keyboard flow for POS
changes.
-->

## Rollback plan

<!--
How to undo in production: frontend rollback, function redeploy or a corrective migration (never a
down migration).
-->

## Checklist

<!-- Definition of Done, engineering standards section 7.2. Tick every applicable item; mark an item
that does not apply with "Not applicable" and the reason. -->

- [ ] 1. Acceptance criteria are met and demonstrated (test, screenshot or recording in the pull request).
- [ ] 2. Code follows the engineering standards; `pnpm check` passes; no new lint suppressions without a justification comment.
- [ ] 3. Tests are added at every level required by the testing strategy; every new table has RLS isolation tests and every new or changed RPC has the full pgTAP set; test titles carry requirement IDs.
- [ ] 4. Coverage thresholds hold; no test is skipped, focused or marked flaky.
- [ ] 5. Migrations are forward-only, linted, applied from scratch in CI, and generated types are committed.
- [ ] 6. User-facing text exists in English and Bangla; screens pass keyboard and axe checks.
- [ ] 7. Security review items of section 6.2 are satisfied; the threat model is updated where required.
- [ ] 8. Documentation is updated in the same pull request: database design (schema or RPC change), security model (permission change), architecture or ADR (structural decision), runbook (operational change), SRS (requirement change via its change control).
- [ ] 9. A CHANGELOG entry is added under `Unreleased` for user-visible or operational changes.
- [ ] 10. All required CI checks are green, review is approved, the pull request is squash-merged with a Conventional Commit title, and the branch is deleted.
- [ ] 11. The staging deployment succeeded and its smoke tests passed. **Interim rule:** until `deploy.yml` exists (roadmap M1-D9, target 2026-11-26), item 11 is replaced by: `pnpm db:reset && pnpm test:db` and `pnpm test:e2e` pass locally on the merged commit.
- [ ] Docs/ADR/threat model updated if behaviour or architecture changed (summary of items 7 and 8; required by ADR-0001).
