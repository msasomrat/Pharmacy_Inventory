---
status: accepted
date: 2026-10-06
decision-makers:
  - Engineering lead
  - Product owner (pharmacy owner)
consulted:
  - Database design owner
  - Security model owner
informed:
  - All contributors
---

# ADR-0002: Use Supabase (managed PostgreSQL) as the backend platform

## Context and Problem Statement

PIMS needs a backend that stores and protects the pharmacy's business data and exposes it to a browser
application at the counter. The data is strongly relational and the business rules are transactional:

- **Relational structure.** Medicines reference generics, manufacturers, pack definitions and barcodes;
  stock is held in lots (batches) per branch; a sale has lines, lot allocations, payments, ledger
  entries for stock, customer dues (বাকি) and loyalty points, and controlled-drug register entries. The
  [database design](../database/database-design.md) catalogs about 70 tables at full scope.
- **Atomic multi-row writes.** One three-line cash sale writes about 10 to 12 rows across a dozen tables
  ([architecture 19.1](../architecture/architecture.md#191-capacity-estimate)) and must succeed or fail
  as a whole (NFR-REL-001). Stock may never go negative even when four terminals sell the last strip at
  the same moment (FR-INV-005, NFR-REL-002). Invoice numbers must be gapless per branch and fiscal year
  (FR-POS-030).
- **Reporting.** Profit at lot cost, stock value, expiry in 30/60/90 days, slow and fast movers, branch
  comparison, dues and loyalty reports require joins, grouping and window functions over a year of data
  in under 2 seconds (NFR-PERF-004).
- **Isolation.** Data must be isolated per organization (tenant) and per branch for every access path,
  and MFA for Owner and Branch Manager must be enforced by the server, not only by the UI (NFR-SEC-002 to
  NFR-SEC-004).
- **Constraints of the business.** One engineer, no operations staff, and a pilot that must run on free
  tiers (C-09); production for one to three branches should cost about USD 25 to 30 per month
  ([architecture 20.2](../architecture/architecture.md#202-scenarios)). Data is hosted in Singapore, the
  closest suitable region to Dhaka, with a round trip of roughly 50 to 120 ms (SRS OE-05, C-10).
- **Later phases.** Natural-language "ask your data" (M5) needs read-only SQL views under the same
  security rules; a future SaaS offering needs per-tenant export and the option to move a large tenant
  to its own database.

The reference workload is 300 invoices per branch per day, 60 in the peak hour, 3 lines per invoice and
up to 4 terminals per branch (architecture assumption A-04), which grows the database by roughly 250 to
300 MB per branch per year (NFR-SCAL-007).

The question: **which backend platform should hold the data, enforce the rules and serve the API?**

## Decision Drivers

1. **Integrity:** ACID transactions across many rows, plus declarative constraints (foreign keys,
   `CHECK`, `UNIQUE`) as the last line of defence.
2. **Reporting:** joins, aggregation and window functions on the server, without exporting data.
3. **Security close to the data:** tenant and branch isolation and MFA checks that apply to every
   request, whatever client sends it.
4. **Operational burden:** no servers to patch, scale or back up by hand for a one-person team.
5. **Cost:** free for the pilot; predictable and low for the first branches.
6. **Portability:** the ability to leave the vendor with data and business logic intact, which matters
   for a product that may be sold.
7. **Latency:** POS search under 200 ms and sale commit under 500 ms at p95 server time
   (NFR-PERF-001, NFR-PERF-002).
8. **Developer productivity:** a local development stack, migrations, database tests and generated
   TypeScript types.

## Considered Options

1. **Firebase:** Cloud Firestore, Firebase Authentication, Cloud Functions for Firebase and Firebase
   Hosting.
2. **Supabase:** managed PostgreSQL with PostgREST, Supabase Auth, Storage and Edge Functions.
3. **Self-hosted Django and PostgreSQL:** Django with Django REST Framework, `django-otp` for TOTP,
   Gunicorn and Nginx on a virtual private server, with PostgreSQL on the same or a managed instance.

Not shortlisted: AWS Amplify (DynamoDB has the same document-model limits as Firestore and AWS billing
and IAM add complexity), Appwrite and PocketBase (smaller ecosystems; PocketBase uses SQLite with a single
writer), and a custom Node.js API (same operations burden as option 3 with less built in).

## Decision Outcome

Chosen option: **"Supabase"**, because it is the only option that combines the full relational and
transactional power of PostgreSQL (drivers 1 and 2), authorization enforced inside the database through
row level security tied to the authenticated user and MFA level (driver 3), and a managed service with a
usable free tier and a USD 25 per month production plan (drivers 4 and 5), while keeping data and logic
in portable, open-source PostgreSQL (driver 6).

Scope of the decision:

- **Region:** Singapore (`ap-southeast-1`) for production and staging. Local development and CI use the
  Supabase CLI stack in Docker.
- **Plan:** Free for the pilot and staging; Supabase Pro at production launch or when any trigger in
  [architecture section 20.3](../architecture/architecture.md#203-when-to-upgrade-to-supabase-pro) is
  met (the launch-time choice is open issue OI-05). While on Free, the nightly encrypted `pg_dump`
  through GitHub Actions and a health check at least every 5 minutes (so the project is never paused,
  NFR-AVAIL-006) are mandatory.
- **Components used:** PostgreSQL (PostgreSQL 17 at the time of writing; the design requires 15 or
  later), PostgREST for the API, Supabase Auth (email and password, TOTP MFA), Storage (private buckets,
  signed URLs) and Edge Functions only for work that needs secrets or external calls.
- **Lock-in limits:** schema, policies and business logic live in versioned SQL migrations in
  `supabase/migrations/`; no schema change is made through the dashboard in staging or production;
  Supabase-specific surface is limited to `auth.uid()`, `auth.jwt()`, the Auth service, Storage and Edge
  Functions.

The design consequences of this choice are recorded in their own ADRs: business-critical writes as
transactional PostgreSQL functions ([ADR-0007](0007-business-logic-in-transactional-postgres-functions.md)),
pooled multi-tenancy with RLS ([ADR-0006](0006-multi-tenant-organization-branch-model-with-rls.md)), and
the inventory ledger ([ADR-0008](0008-append-only-inventory-ledger-with-fefo.md)).

### Consequences

- Good, because the rules that matter most (non-negative stock, gapless numbers, tenant-safe references,
  immutable ledgers) are enforced by PostgreSQL constraints, locks and triggers that no client can bypass.
- Good, because every report is a SQL query or function next to the data; summary tables and
  materialized views are available when volumes grow.
- Good, because row level security uses the same identity that signs the request (`auth.uid()`, the
  `aal` claim), so isolation holds for PostgREST, RPC, Storage and future clients alike.
- Good, because there is no application server to build, patch or scale, and PostgREST removes
  hand-written CRUD endpoints.
- Good, because the Supabase CLI gives a reproducible local stack, migration tooling, `supabase test db`
  for pgTAP and `supabase gen types` for TypeScript; the stack, `supabase db lint` and the pgTAP suite
  already run in CI.
- Good, because the whole stack is open source and self-hostable, and `pg_dump` produces a standard
  PostgreSQL backup, so an exit path exists (see "Exit plan" below).
- Bad, because the API shape is dictated by PostgREST; multi-step business operations must be written as
  PL/pgSQL functions, which needs SQL expertise and database-level testing (accepted in ADR-0007).
- Bad, because a mistake in a row level security policy or a `SECURITY DEFINER` function can expose data
  (architecture risk R-01); mitigated by pgTAP isolation tests for every role and the platform guard
  tests in `supabase/tests/database/001_platform_guards.test.sql`.
- Bad, because the Free plan has no managed backups, pauses inactive projects after 7 days and allows
  500 MB of database, so production depends on our own backup job and monitoring until it moves to Pro.
- Bad, because production runs in one region without automatic failover at this price; a regional outage
  stops online operations until the offline mode of M4 is delivered (risk R-04).
- Bad, because Supabase Auth is the hardest part to migrate away from (risk R-02): password hashes can be
  exported, but MFA factors and sessions would have to be re-enrolled on another provider.
- Neutral, because hosting in Singapore requires the owner's recorded acceptance and a privacy-notice
  disclosure; if Bangladeshi law later requires local storage of health data, the exit plan applies
  ([security model 13.6](../security/security-model.md#136-bangladesh-legal-context)).

### Exit plan

If Supabase must be left (pricing, reliability, legal or acquisition reasons), the steps are:

1. Restore the latest `pg_dump` into any PostgreSQL 15 or later server (self-hosted Supabase in Docker,
   a managed PostgreSQL service or a Bangladeshi data centre).
2. Run the open-source PostgREST and Supabase Auth (GoTrue) components, or replace Auth with another
   OpenID Connect provider and map its user IDs into `auth.uid()`.
3. Point the static frontend at the new API URL through build-time environment variables.

Business logic, policies and data need no rewrite because they are standard PostgreSQL. This is already
demonstrated: `scripts/db/test-local.sh` applies every migration and runs the pgTAP suite on a plain
PostgreSQL 15 or later cluster, using a small shim (`scripts/db/supabase-shim.sql`) that emulates the
Supabase roles and the `auth` schema. The quarterly restore drill exercises step 1
([runbook](../operations/runbook.md)).

### Confirmation

- CI job "Database lint and pgTAP tests" starts the local Supabase stack, runs `supabase db lint` and
  `supabase test db` on every pull request, including the RLS isolation suite
  ([security model 8.6](../security/security-model.md#86-tenant-and-branch-isolation-tests)).
- The M4 load test at three times the reference peak (NFR-PERF-010) must meet the 200 ms and 500 ms p95
  budgets on the chosen compute size.
- Usage is reviewed weekly against plan quotas, with an alert at 70 percent of database size
  (NFR-SCAL-006).
- The quarterly restore drill restores a production backup into a Supabase project and, using the shim,
  into a plain PostgreSQL server, proving portability.
- Review triggers: Supabase list prices for our configuration more than double; two or more production
  outages longer than one hour in a quarter; a legal requirement to store data in Bangladesh; or a
  measured p95 sale commit above 500 ms that compute upgrades cannot fix.

## Pros and Cons of the Options

### Firebase (Firestore, Auth, Cloud Functions, Hosting)

- Good, because it is mature, backed by Google, available in Singapore (`asia-southeast1`) and has a
  generous free plan (at the time of writing 1 GiB of Firestore storage, 50,000 document reads, 20,000
  writes and 20,000 deletes per day).
- Good, because the client SDKs provide offline persistence and realtime listeners out of the box, which
  is attractive for counter use during internet outages.
- Bad, because Firestore is a document store without joins or `GROUP BY`. Aggregation queries cover
  `count`, `sum` and `average` only, so reports such as profit by branch by month must either read every
  sale document or rely on counters maintained by Cloud Functions. A one-year profit report for one
  branch at the reference workload touches about 110,000 sale documents and 330,000 line documents;
  streaming them to the browser cannot meet the 2-second target (NFR-PERF-004), and pre-aggregating them
  means writing and maintaining a second, eventually consistent data model.
- Bad, because integrity rules must be written in application code: there are no foreign keys, no
  `CHECK` constraints and no unique constraints other than document IDs. "Stock never negative", "phone
  unique per organization" and "sale lines reference medicines of the same tenant" all become code
  paths that can be bypassed by a bug.
- Bad, because server-side business logic needs Cloud Functions, which can only be deployed on the
  pay-as-you-go Blaze plan with a billing account, so the free pilot could not enforce prices on the
  server.
- Bad, because security rules authorize whole documents; hiding a field such as lot cost from a Salesman
  requires splitting it into separate documents and collections.
- Bad, because a single gapless invoice counter document per branch is a hot spot (Firestore documents a
  sustained write rate of about one write per second per document); acceptable for one branch, but it
  constrains organization-wide series in a SaaS future.
- Bad, because data model and queries are proprietary; moving to SQL later means rewriting the data
  layer, and exports come in Firestore's own format.
- Neutral, because Firebase Data Connect (PostgreSQL on Cloud SQL behind a GraphQL layer) narrows the
  SQL gap, but requires a billed Cloud SQL instance after its trial period and does not make PostgreSQL
  row level security and PL/pgSQL the primary model, so it offers no advantage over Supabase for PIMS.

### Supabase (chosen)

- Good, because PostgreSQL provides transactions, constraints, PL/pgSQL, `pg_trgm` for fuzzy medicine
  search, `pg_cron` for scheduled jobs, materialized views and partitioning.
- Good, because row level security integrates with Auth: policies can call helpers that read
  `auth.uid()` and the `aal` claim, so tenant isolation and MFA are enforced per request in the database.
- Good, because the managed service includes Auth with TOTP MFA, Storage with policies, Edge Functions
  for secrets, logs and, on Pro, daily backups and optional point-in-time recovery.
- Good, because cost is USD 0 for the pilot and USD 25 per month on Pro, which includes 8 GB of database
  disk and compute credit covering the Micro instance (architecture 20.1, prices at the time of writing).
- Bad, because the Free plan limits (500 MB database, 1 GB storage, 5 GB egress, pause after a week of
  inactivity) require monitoring and our own backups.
- Bad, because Supabase is a younger company than Google; the open-source stack and standard PostgreSQL
  reduce the impact of vendor failure.

### Self-hosted Django and PostgreSQL

- Good, because it gives full control over hosting location (including a data centre in Bangladesh),
  versions and costs, with no platform lock-in.
- Good, because Django is mature, has a capable ORM and an admin interface, and Python developers are
  available in Bangladesh.
- Good, because the database is still PostgreSQL, so the relational and transactional strengths of
  option 2 are available.
- Bad, because everything Supabase provides must be built and operated: REST API, authentication with
  TOTP MFA, password reset email, rate limiting, file storage with signed URLs, TLS, operating-system
  patching, backups, monitoring and incident response. The initial build adds several weeks before M2,
  and operations take an estimated 4 to 8 hours per month.
- Bad, because a 2 vCPU, 4 GB virtual server in Singapore costs about USD 12 to 25 per month before
  backup storage, similar to Supabase Pro but with the operations labour on top, and a single server is
  a single point of failure.
- Bad, because authorization would live in application code, where one missing tenant filter in one
  query leaks data, unless we also implemented PostgreSQL row level security, which would rebuild what
  Supabase already provides.

## More Information

- [Architecture description](../architecture/architecture.md): sections 5 (containers), 10 (backend),
  19 (scalability path), 20 (cost model) and 22 (risks R-01 to R-04)
- [Database design](../database/database-design.md) and [security model](../security/security-model.md)
- [SRS](../requirements/SRS.md): C-01, C-09, C-10, NFR-REL-001 to NFR-REL-003, NFR-SEC-002 to
  NFR-SEC-004, NFR-PERF-001, NFR-PERF-002, NFR-PERF-004, NFR-SCAL-006, NFR-SCAL-007, NFR-AVAIL-006
- Related decisions: [ADR-0006](0006-multi-tenant-organization-branch-model-with-rls.md),
  [ADR-0007](0007-business-logic-in-transactional-postgres-functions.md),
  [ADR-0008](0008-append-only-inventory-ledger-with-fefo.md)
- Vendor facts (free-tier limits, prices, Cloud Functions plan requirement, Firestore per-document write
  rate) are as published by Supabase and Google in October 2026 and must be re-verified before any
  purchase decision: <https://supabase.com/pricing>, <https://firebase.google.com/pricing>,
  <https://firebase.google.com/docs/firestore/quotas>.
