---
status: accepted
date: 2026-10-06
decision-makers:
  - Engineering lead
consulted:
  - Product owner (pharmacy owner)
  - Security model owner
informed:
  - All contributors
---

# ADR-0003: Build the client as a React, TypeScript and Vite single-page application

## Context and Problem Statement

The PIMS user interface is an internal business application, not a public website. Every screen is
behind sign-in; there is nothing for search engines to index. Its users are:

- **Salesmen at the counter** working keyboard-first on Windows PCs with Chrome or Edge, a USB barcode
  scanner in keyboard-wedge mode and a thermal receipt printer (architecture assumptions A-01 to A-03).
  A trained Salesman must complete a three-item cash sale in a median of 30 seconds by barcode
  (NFR-USAB-004), so interactions must feel instant.
- **Branch Managers and the Owner** on PCs and Android phones, using inventory, purchasing and report
  screens in English or Bangla.

Requirements that shape the client:

- Installable Progressive Web App now, and **offline sales in M4**: the application shell must load and
  the POS must keep selling without a network connection, queueing sales for replay (NFR-AVAIL-004).
- Performance budgets on 4G: Largest Contentful Paint under 2.5 seconds for sign-in and POS
  (NFR-PERF-003), Interaction to Next Paint under 200 ms (NFR-PERF-005), at most 250 KB of gzipped
  JavaScript for the shell plus POS (NFR-PERF-007).
- The backend is Supabase ([ADR-0002](0002-supabase-postgresql-over-firebase.md)): the browser calls
  PostgREST and RPC functions directly under row level security, so no application server is needed for
  data access.
- Hosting is a static CDN on a free tier ([ADR-0004](0004-cloudflare-pages-hosting.md), constraint C-09).
- Accessibility to WCAG 2.1 AA, bilingual interface (en, bn-BD), strict type safety, and a small team
  that must be able to hire in Bangladesh.

The question: **what application style and core framework should the web client use?**

## Decision Drivers

1. No server tier to build, secure, host or pay for; output deployable to any static host.
2. Offline-capable PWA: the shell and POS must run from a service worker cache.
3. Interaction speed and bundle size on modest counter PCs and 4G phones.
4. End-to-end type safety from database to UI (generated Supabase types, Zod schemas).
5. Ecosystem for accessible components, forms, internationalization and testing.
6. Simplicity and maintainability for one to three engineers; fast feedback in development and CI.
7. Availability of developers in Bangladesh.

## Considered Options

1. **React 19 with TypeScript (strict) built by Vite as a single-page application (SPA).**
2. **Next.js** (App Router with React Server Components), deployed on Vercel, on Cloudflare through the
   OpenNext adapter, or as a static export.
3. **Laravel** (PHP) server-rendered application, with Blade and Livewire or with Inertia and React.

Other component frameworks (Vue, Svelte, Angular) were compared at the library level in
[architecture section 7](../architecture/architecture.md#7-technology-stack); React was preferred for
its ecosystem of accessible primitives (Radix, shadcn/ui) and hiring pool.

## Decision Outcome

Chosen option: **"React 19, TypeScript (strict) and Vite SPA"**, because it produces a static bundle
that any CDN can serve and a service worker can cache for offline use (drivers 1 and 2), it adds no
server attack surface, it keeps the build simple and fast (driver 6), and React with TypeScript gives the
largest ecosystem and hiring pool (drivers 5 and 7). Server-side rendering, the main advantage of the
alternatives, has little value for an authenticated, keyboard-driven application.

Rules that follow:

- The client is a pure SPA: `pnpm build` produces `dist/` (HTML, hashed JS and CSS, `_headers`) with no
  server runtime. Server-side work belongs in the database ([ADR-0007](0007-business-logic-in-transactional-postgres-functions.md))
  or in Supabase Edge Functions when secrets are required.
- TypeScript runs in strict mode with the additional checks already configured in `tsconfig.app.json`
  (`noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noPropertyAccessFromIndexSignature`
  and others). Database types are generated with `pnpm gen:types`.
- Routes are lazy-loaded per feature with React Router so the first screen stays within the bundle
  budget; reports and charts load on demand.
- Nothing in the bundle is secret: only `VITE_*` variables (the Supabase URL and publishable key, the
  Sentry DSN) are compiled in, and every authorization decision is made by the server.
- Supporting libraries (React Router, TanStack Query, React Hook Form with Zod, Tailwind CSS with
  shadcn/ui on Radix, i18next, Recharts, `vite-plugin-pwa`) are listed with their rationale in
  [architecture section 7](../architecture/architecture.md#7-technology-stack). Replacing one of them is
  a local decision unless it changes the application style, adds a server tier or adds a global client
  state store, which require a new ADR.

### Consequences

- Good, because hosting is a static CDN with unlimited bandwidth on a free tier, rollback is a redeploy
  of the previous build, and the frontend holds no business data.
- Good, because the attack surface is the browser plus Supabase only. There are no server functions,
  server actions or middleware to misconfigure; classes of vulnerability such as the Next.js middleware
  authorization bypass (CVE-2025-29927, March 2025) and the React Server Components remote code
  execution flaw (CVE-2025-55182, December 2025) do not apply to a client-only React build.
- Good, because the service worker can precache the whole shell, which is the foundation for offline
  POS in M4 and for repeat-visit loads under 1.5 seconds.
- Good, because Vite gives near-instant dev-server start and hot module replacement, and Vitest reuses
  the same configuration for unit and component tests.
- Bad, because the first visit downloads and executes the JavaScript shell before anything renders; the
  250 KB budget, route-level code splitting, immutable caching of hashed assets and the PWA cache keep
  this within NFR-PERF-003, and must be measured continuously.
- Bad, because the team assembles its own stack (routing, data fetching, forms) instead of receiving a
  framework's conventions; the choices and folder structure are fixed in architecture sections 7 to 9
  to avoid drift.
- Bad, because environment-specific values are baked in at build time, so staging and production are
  separate builds; Cloudflare Pages builds each environment with its own variables.
- Neutral, because a public marketing or SaaS sign-up site, if needed later, can be a separate static
  site and does not require changing this application.

### Confirmation

- CI job "Lint, typecheck, unit tests, build" runs ESLint, Prettier, `tsc -b` in strict mode, Vitest
  with coverage thresholds for `src/domain/**`, and `pnpm build` on every pull request.
- A bundle-size budget check (NFR-PERF-007) and Lighthouse checks for LCP and accessibility are added to
  CI before M4 (accepted technical debt in [architecture 22.2](../architecture/architecture.md#222-known-technical-debt-accepted)).
- Playwright end-to-end tests run against the production build, including keyboard-only POS flows and
  axe-core accessibility checks.
- The repository contains no server runtime code outside `supabase/` (database and Edge Functions);
  reviewers reject server-rendering frameworks or Node servers in `src/`.
- Review triggers: a requirement for public, indexable pages inside the application; a measured LCP above
  2.5 seconds on the reference 4G profile that code splitting cannot fix; or React or Vite ending
  maintenance of the major versions in use.

## Pros and Cons of the Options

### React, TypeScript and Vite SPA (chosen)

- Good, because output is static files that any CDN serves and any service worker can cache.
- Good, because the mental model is simple: all code runs in the browser and talks to one API.
- Good, because React's ecosystem covers every need of the project with accessible, well-tested
  libraries, and React developers are widely available in Bangladesh.
- Bad, because there is no server rendering, so the initial load depends on bundle discipline.
- Bad, because every rule enforced in the UI must be enforced again on the server; this is intended
  (the server is authoritative) but must not be forgotten.

### Next.js

- Good, because it offers server rendering, static generation, file-based routing and server actions,
  with a large community.
- Bad, because its main strengths (search-engine visibility and fast first paint of public content) do
  not apply to an application where every route requires sign-in.
- Bad, because using server components, server actions or middleware requires a server runtime:
  on Vercel, commercial use needs the Pro plan at USD 20 per member per month
  ([ADR-0004](0004-cloudflare-pages-hosting.md)); on Cloudflare it needs the OpenNext adapter on Workers.
  Either way a second server-side code path must re-check authorization that the database already
  enforces.
- Bad, because a static export (`output: 'export'`) removes server features and leaves a heavier
  framework producing the same SPA that Vite produces directly.
- Bad, because the split between server and client components, caching semantics that have changed
  between major versions, and the server-side vulnerabilities cited above increase maintenance and
  security effort for a small team.
- Bad, because offline-first behaviour is harder when routes expect to be rendered on a server.

### Laravel

- Good, because Laravel is popular in Bangladesh, includes authentication, validation, queues and an ORM,
  and runs on inexpensive PHP hosting.
- Bad, because Laravel is a backend framework: choosing it means running a PHP application server and
  re-implementing authentication, MFA and authorization that Supabase provides, with the operations
  burden rejected in [ADR-0002](0002-supabase-postgresql-over-firebase.md).
- Bad, because server-rendered interaction (Blade or Livewire) needs a network round trip of roughly 50
  to 120 ms to Singapore for many interactions, which conflicts with a keyboard-first POS that must feel
  instant, and cannot work offline without a separate JavaScript client.
- Bad, because it adds a second language (PHP) next to TypeScript and SQL, and cannot be hosted on a
  static CDN.
- Neutral, because Inertia with React would still require React skills while keeping the server tier.

## More Information

- [Architecture description](../architecture/architecture.md): sections 7 (technology stack), 8
  (repository layout), 9 (frontend architecture) and 15 (offline strategy)
- [SRS](../requirements/SRS.md): C-01, NFR-PERF-003, NFR-PERF-005, NFR-PERF-007, NFR-USAB-004,
  NFR-AVAIL-004
- [Security model](../security/security-model.md): browser security, headers and CSP
- Related decisions: [ADR-0002](0002-supabase-postgresql-over-firebase.md),
  [ADR-0004](0004-cloudflare-pages-hosting.md),
  [ADR-0007](0007-business-logic-in-transactional-postgres-functions.md)
- Vulnerability references: GitHub advisory for CVE-2025-29927 (Next.js middleware) and the React team's
  advisory for CVE-2025-55182 (React Server Components), both accessed October 2026
