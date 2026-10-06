# Contributing to PIMS

Thank you for helping build the Pharmacy Inventory Management System (PIMS). This guide gets you from a
fresh machine to a running application and a merged pull request. The target is a working local
environment within 30 minutes (NFR-MAINT-006).

The rules behind this guide are in the [engineering standards](docs/engineering/engineering-standards.md)
and the [testing strategy](docs/engineering/testing-strategy.md). Where this guide and those documents
differ, those documents win.

> **Security issues:** never open a public issue for a vulnerability. Follow [SECURITY.md](SECURITY.md).

## Contents

1. [Before you start](#1-before-you-start)
2. [Prerequisites](#2-prerequisites)
3. [Local setup](#3-local-setup)
4. [Seed accounts](#4-seed-accounts)
5. [Scripts](#5-scripts)
6. [Workflow](#6-workflow)
7. [Commits and pull requests](#7-commits-and-pull-requests)
8. [Database changes](#8-database-changes)
9. [Tests](#9-tests)
10. [Translations and accessibility](#10-translations-and-accessibility)
11. [Troubleshooting](#11-troubleshooting)
12. [Issues, questions and links](#12-issues-questions-and-links)

---

## 1. Before you start

Read, in this order:

1. [Documentation index](docs/README.md) and [glossary](docs/glossary.md) (FEFO, GRN, paisa, বাকি, AAL2).
2. [Engineering standards](docs/engineering/engineering-standards.md), sections 3 to 7 (branching,
   commits, pull requests, review, Definition of Done).
3. The canonical document for the area you will touch:
   [database design](docs/database/database-design.md),
   [architecture](docs/architecture/architecture.md),
   [security model](docs/security/security-model.md) or the [SRS](docs/requirements/SRS.md).

Non-negotiable rules you will meet on day one:

- Money is integer **paisa**; never use floating point for money (`parseFloat` fails lint).
- Prices, totals, stock allocation and permissions are decided by **database functions**, never by
  the browser.
- Every table has **Row Level Security** and isolation tests.
- Every user-facing string exists in **English and Bangla**.
- **No secrets** in the repository or in `VITE_*` variables; every `VITE_*` value ships to the browser.

The repository is private and proprietary (`"license": "UNLICENSED"` in `package.json`); contributions
are accepted from people the Owner has authorized.

---

## 2. Prerequisites

| Tool                 | Version                                                  | Notes                                                                                                                                        |
| -------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Git                  | 2.40 or later                                            | Line endings are normalized to LF by `.gitattributes`                                                                                        |
| Node.js              | 22 LTS, at least 22.12.0                                 | `.nvmrc` says `22`; `engine-strict=true` makes `pnpm install` fail on other versions. With nvm: `nvm install && nvm use`                     |
| pnpm                 | 10.28.0                                                  | Pinned in `package.json` (`packageManager`); enable it with `corepack enable`                                                                |
| Docker               | Docker Desktop (Windows, macOS) or Docker Engine (Linux) | Runs the local Supabase stack. Allow at least 4 GB of memory for Docker (8 GB recommended) and about 10 GB of disk for images                |
| Supabase CLI         | 2.120.x                                                  | Installed as a dev dependency; `pnpm exec supabase --version` works after `pnpm install`. A global install is optional. CI pins 2.120.0      |
| Playwright browsers  | Chromium                                                 | `pnpm exec playwright install --with-deps chromium` (once)                                                                                   |
| Editor               | VS Code recommended                                      | Install the recommended extensions from `.vscode/extensions.json` (ESLint, Prettier, Tailwind CSS, Deno, Supabase); format on save is preset |
| Optional: PostgreSQL | Server binaries 15 or later with pgTAP and `pg_prove`    | Only for `pnpm test:db:local`, the fast database test runner that does not need Docker                                                       |

**Windows:** use WSL 2 with Docker Desktop's WSL integration, and clone the repository inside the Linux
file system (for example `~/code`), not under `/mnt/c`, for acceptable performance.

---

## 3. Local setup

```bash
# 1. Clone
git clone https://github.com/msasomrat/Pharmacy_Inventory.git
cd Pharmacy_Inventory

# 2. Toolchain
nvm install && nvm use          # or install Node 22 another way
corepack enable                 # provides the pinned pnpm 10.28.0

# 3. Dependencies (also installs the Git hooks through Husky)
pnpm install

# 4. Start the local Supabase stack (first run downloads Docker images)
pnpm db:start

# 5. Configure the web app with the local, public values
cp .env.example .env.local
pnpm exec supabase status -o env   # copy API_URL and ANON_KEY into .env.local

# 6. Apply all migrations and load the development seed
pnpm db:reset

# 7. Regenerate database types after any schema change
pnpm gen:types

# 8. Run the app
pnpm dev                        # http://localhost:5173
```

`.env.local` needs only public values:

```dotenv
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=<anon key printed by supabase status>
VITE_SENTRY_DSN=
```

Never put the `service_role` key or any other secret in `.env.local` or any `VITE_*` variable. The
app validates these variables at start-up (`src/lib/env.ts`) and names any that are missing.

Local services:

| Service                      | URL                    |
| ---------------------------- | ---------------------- |
| Web app (Vite)               | http://localhost:5173  |
| Supabase API                 | http://127.0.0.1:54321 |
| PostgreSQL                   | `127.0.0.1:54322`      |
| Supabase Studio              | http://127.0.0.1:54323 |
| Local e-mail inbox (Mailpit) | http://127.0.0.1:54324 |

Verify the setup:

```bash
pnpm check        # lint, format check, typecheck, unit tests
pnpm test:db      # pgTAP database tests, including RLS
pnpm test:e2e     # Playwright end-to-end tests (builds and previews the app)
```

Stop the stack with `pnpm db:stop` when you are done; your local data is kept until the next
`pnpm db:reset`.

---

## 4. Seed accounts

`supabase/seed.sql` (being added in M1, see the
[database design](docs/database/database-design.md) section 19.3) creates two organizations, "Demo
Pharmacy" with branches MPR (Mohammadpur) and DHN (Dhanmondi) and "Other Pharmacy" for isolation
checks, plus one account per role:

| Account                  | Role           | Branches                 |
| ------------------------ | -------------- | ------------------------ |
| `owner@demo.test`        | Owner          | All                      |
| `manager.mpr@demo.test`  | Branch Manager | MPR                      |
| `salesman.mpr@demo.test` | Salesman       | MPR                      |
| `manager.dhn@demo.test`  | Branch Manager | DHN                      |
| `salesman.dhn@demo.test` | Salesman       | DHN                      |
| `accountant@demo.test`   | Accountant     | All (read-only, from M4) |

`PimsLocal-2026` is the shared sign-in phrase of every seed account. It exists only in the local
seed: it is never used on staging or production, and staging accounts are created separately.

Two-factor authentication is not enforced in the local seed (`enforce_mfa = false`), so Owner and
Manager accounts work without an authenticator app. To exercise MFA locally, turn the setting on for
the demo organization and enroll with any TOTP app. Auth e-mails (invitations, password resets)
appear in Mailpit.

---

## 5. Scripts

Existing scripts (`package.json`):

| Script                         | What it does                                                                                                  |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `pnpm dev`                     | Vite dev server on port 5173                                                                                  |
| `pnpm build`                   | Type-checks and builds the production bundle into `dist/`                                                     |
| `pnpm preview`                 | Serves the production build                                                                                   |
| `pnpm lint`                    | ESLint with zero warnings allowed                                                                             |
| `pnpm format` / `format:check` | Prettier write / check                                                                                        |
| `pnpm typecheck`               | TypeScript project build without emitting                                                                     |
| `pnpm test`                    | Vitest unit and component tests, once                                                                         |
| `pnpm test:watch`              | Vitest in watch mode                                                                                          |
| `pnpm test:coverage`           | Vitest with coverage and the enforced thresholds (as CI runs it)                                              |
| `pnpm test:e2e`                | Playwright end-to-end tests against a production build                                                        |
| `pnpm test:db`                 | pgTAP tests through `supabase test db` (authoritative; needs `pnpm db:start`)                                 |
| `pnpm test:db:local`           | Fast pgTAP run on a throwaway PostgreSQL cluster without Docker; `TESTS_DIR`, `SEED=1`, `VERBOSE=1` supported |
| `pnpm db:start` / `db:stop`    | Start or stop the local Supabase stack                                                                        |
| `pnpm db:reset`                | Recreate the local database: all migrations, then `supabase/seed.sql`                                         |
| `pnpm db:lint`                 | `supabase db lint` (plpgsql_check) at warning level                                                           |
| `pnpm db:new-migration <name>` | Create `supabase/migrations/<timestamp>_<name>.sql`                                                           |
| `pnpm gen:types`               | Regenerate `src/lib/database.types.ts` from the local database                                                |
| `pnpm check`                   | `lint`, `format:check`, `typecheck` and `test` in one command; run before every push                          |

Planned scripts (added with the work that needs them; see the
[testing strategy](docs/engineering/testing-strategy.md)):

| Script                  | Purpose                                                    | Milestone |
| ----------------------- | ---------------------------------------------------------- | --------- |
| `pnpm test:integration` | Vitest with supabase-js against the local stack            | M1        |
| `pnpm traceability`     | Requirement traceability report from SRS IDs and test tags | M1        |
| `pnpm i18n:check`       | English and Bangla key-set parity                          | M2        |
| `pnpm test:perf`        | pgbench and k6 performance scenarios                       | M4        |

---

## 6. Workflow

1. **Pick an issue** that meets the Definition of Ready (acceptance criteria in Given/When/Then,
   requirement IDs, milestone). Assign it to yourself.
2. **Branch from the latest `main`** using `<type>/<issue>-<slug>`, where type is `feat`, `fix`,
   `chore` or `docs`:

   ```bash
   git switch main && git pull --rebase
   git switch -c feat/57-pos-barcode-scan
   ```

3. **Work in small commits** (Conventional Commits, checked by the `commit-msg` hook). Rebase on
   `main` at least daily; keep the branch alive for 1 to 2 working days, never more than 5.
4. **Run the checks** before pushing: `pnpm check`, plus `pnpm test:db` and `pnpm gen:types` if SQL
   changed.
5. **Open a draft pull request early**, complete the template, and mark it ready when CI is green.
6. **Address review**, resolve every conversation, and **squash-merge** with a Conventional Commit
   title. The branch is deleted automatically.
7. **Watch staging**: after the merge, `main` deploys to staging; confirm the smoke tests pass and fix
   or revert the same day if anything breaks.
   **Interim rule:** until `deploy.yml` exists (roadmap M1-D9), there is no staging deployment to
   watch; instead run `pnpm db:reset && pnpm test:db` and `pnpm test:e2e` locally on the merged commit
   (Definition of Done item 11, [engineering standards 7.2](docs/engineering/engineering-standards.md#72-definition-of-done-a-change-is-complete)).
   The pull request that adds `deploy.yml` removes this note, the matching rule in engineering
   standards 7.2 and the interim rule in `.github/pull_request_template.md`.

`main` is protected: pull requests only, required checks green, linear history, squash merge only.

---

## 7. Commits and pull requests

**Commit messages** follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<scope>): <imperative subject, lower case, no period, max 72 characters>
```

- Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`, `style`, `revert`.
- Scopes: `app`, `auth`, `catalog`, `inventory`, `purchases`, `sales`, `pos`, `customers`, `loyalty`,
  `transfers`, `reports`, `ai`, `db`, `security`, `ci`, `deps`, `docs`, `i18n`, `ops`
  (`commitlint.config.js`).
- Breaking changes use `!` and a `BREAKING CHANGE:` footer. Reference work with `Refs: #57` and
  `Implements: FR-POS-002`.

Examples:

```text
feat(pos): add items from barcode scans when search has no focus
fix(sales): do not consume an invoice number when a sale fails
test(db): add cross-branch RLS matrix for sale tables
```

**Pull requests:**

- Title: a Conventional Commit header; it becomes the commit on `main`.
- Keep them small: aim for under 400 changed lines excluding generated files and the lockfile.
- Fill in every section of the template; write "Not applicable" rather than deleting a section.
- Link the issue (`Closes #57`) and list requirement IDs (`Implements: FR-POS-002, NFR-USAB-003`).
- Include screenshots in English and Bangla for UI changes, and a rollback plan.
- Changes under `supabase/`, `.github/` and `public/_headers` need a code owner's approval.
- Add an entry under `Unreleased` in `CHANGELOG.md` for user-visible or operational changes.

The full process, the review checklist and the Definition of Done are in the
[engineering standards](docs/engineering/engineering-standards.md) sections 4 to 7.

---

## 8. Database changes

```bash
pnpm db:new-migration add_stock_transfers   # creates supabase/migrations/<timestamp>_add_stock_transfers.sql
# edit the file
pnpm db:reset                               # apply all migrations from scratch plus the seed
pnpm test:db                                # run pgTAP, including RLS and platform guards
pnpm db:lint                                # plpgsql_check
pnpm gen:types                              # regenerate and commit src/lib/database.types.ts
```

Rules (details in [engineering standards](docs/engineering/engineering-standards.md) section 11 and
[database design](docs/database/database-design.md) section 18):

- Migrations are **forward-only**. Never edit a migration that has reached staging or production; write
  a new one.
- Every new table: `organization_id` (and `branch_id` where branch-scoped), RLS enabled, policies per
  operation, explicit grants, indexes on foreign keys, comments, and isolation tests.
- Every function: `set search_path = ''`, schema-qualified names, a permission check first, errors
  through `app.fail(code, message)`, and a full pgTAP suite.
- Every migration file ends with `call app.harden_privileges();`.
- Breaking changes follow **expand, migrate, contract** across releases.
- Update the database design document in the same pull request.

---

## 9. Tests

Write tests at the level where the rule lives ([testing strategy](docs/engineering/testing-strategy.md)):

| You changed                            | Add or update                                                                                                     |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| A calculation in `src/domain`          | Vitest unit tests, with fast-check properties for money (10,000 runs)                                             |
| A component, hook or form              | Vitest with Testing Library, queried by role, driven by keyboard                                                  |
| A table, policy, trigger or constraint | pgTAP in `supabase/tests/database/`, including cross-organization and cross-branch denial                         |
| An RPC                                 | pgTAP: happy path, every error code, denial per role, cross-tenant, idempotent replay, concurrency where relevant |
| A user journey                         | Playwright spec in `e2e/` tagged with the use case (`@UC-06`) and requirement IDs                                 |

- Start test titles and pgTAP descriptions with the requirement ID they verify
  (`'FR-INV-005: concurrent sales cannot drive stock negative'`).
- Never commit `.only` or `.skip`, and never add retries. A flaky test is fixed, not skipped: open an
  issue labelled `flaky-test` as soon as you see one.
- Use synthetic data only: `.test` e-mail addresses, generated phone numbers, never real customer data.

---

## 10. Translations and accessibility

- Add every user-facing string to both `src/i18n/locales/en.json` and `src/i18n/locales/bn.json`, with
  keys prefixed by feature (`pos.cart.total`). If your Bangla needs a native speaker's review, add the
  `i18n-review` label.
- Format money with `formatTaka()`, parse it with `parseTaka()`, and format dates in Asia/Dhaka.
- Use the shadcn/ui and Radix components; every control must work with the keyboard and have a label.
- Check your screen with the keyboard only, at 200 % zoom, and in Bangla before asking for review.

---

## 11. Troubleshooting

| Symptom                                                                  | Fix                                                                                                                                                             |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pnpm install` fails with an engine error                                | Use Node 22.12 or later (`nvm use`) and run `corepack enable`                                                                                                   |
| `pnpm db:start` fails: Docker not running or ports 54321 to 54324 in use | Start Docker; stop other Supabase projects (`pnpm exec supabase stop --all`) or whatever uses the ports                                                         |
| `pnpm db:start` is slow or runs out of memory                            | Give Docker more memory, or start without optional services: `pnpm exec supabase start -x realtime,storage-api,imgproxy,edge-runtime,logflare,vector,supavisor` |
| The app shows "Invalid or missing environment variables"                 | Create `.env.local` from `.env.example` with the values from `pnpm exec supabase status -o env`                                                                 |
| Type errors after pulling `main`                                         | `pnpm install`, `pnpm db:reset`, `pnpm gen:types`                                                                                                               |
| Commit rejected by the `commit-msg` hook                                 | Rewrite the message in Conventional Commits form (section 7)                                                                                                    |
| Git hooks do not run                                                     | Run `pnpm install` again (the `prepare` script installs Husky)                                                                                                  |
| Playwright cannot find a browser                                         | `pnpm exec playwright install --with-deps chromium`                                                                                                             |
| Port 5173 already in use                                                 | Stop the other dev server; the port is fixed (`strictPort`) because Supabase Auth redirects to it                                                               |
| `pnpm test:db:local` cannot find `pg_ctl` or `pg_prove`                  | Install PostgreSQL server binaries and pgTAP, or set `PG_BIN`; otherwise use `pnpm test:db`                                                                     |

---

## 12. Issues, questions and links

- **Bugs:** use the "Bug report" issue template. Do not paste customer names, phone numbers,
  prescriptions, passwords or keys.
- **Features:** use the "Feature request" template with acceptance criteria in Given/When/Then.
- **Security vulnerabilities:** report privately as described in [SECURITY.md](SECURITY.md).
- **Questions:** open a discussion on the issue or pull request you are working on.

| Document                                                           | Use it for                                         |
| ------------------------------------------------------------------ | -------------------------------------------------- |
| [Documentation index](docs/README.md)                              | Everything else                                    |
| [Engineering standards](docs/engineering/engineering-standards.md) | Branching, commits, review, code and SQL standards |
| [Testing strategy](docs/engineering/testing-strategy.md)           | What to test, where, and how CI gates it           |
| [SRS](docs/requirements/SRS.md)                                    | Requirement IDs and acceptance criteria            |
| [Architecture](docs/architecture/architecture.md)                  | Structure, environments, delivery pipeline         |
| [Database design](docs/database/database-design.md)                | Tables, functions, error codes, migration policy   |
| [Security model](docs/security/security-model.md)                  | Roles, permissions, threat model                   |
| [Runbook](docs/operations/runbook.md)                              | Deployments, backups, incidents                    |
| [ADR index](docs/adr/README.md)                                    | Architecture decisions                             |
| [Roadmap](docs/roadmap.md)                                         | Milestones M0 to M5                                |
