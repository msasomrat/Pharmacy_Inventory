---
status: accepted
date: 2026-10-06
decision-makers:
  - Engineering lead
  - Product owner (pharmacy owner)
consulted:
  - Security model owner
informed:
  - All contributors
---

# ADR-0004: Host the web application on Cloudflare Pages

## Context and Problem Statement

The web client is a static single-page application: `pnpm build` produces HTML, hashed JavaScript and
CSS, and a `_headers` file ([ADR-0003](0003-react-vite-typescript-spa.md)). All business data lives in
Supabase in Singapore ([ADR-0002](0002-supabase-postgresql-over-firebase.md)); the static host serves
code only and stores no customer or business data.

The host must:

- allow **commercial use** on the plan we pay for: PIMS is the operating system of a pharmacy business
  and may later be sold as a service;
- cost nothing during the pilot and stay within the free tier for the first branches (C-09);
- serve users in Dhaka quickly (LCP under 2.5 seconds on 4G, NFR-PERF-003) and keep serving during
  traffic spikes such as every terminal downloading a new release;
- set HTTP security headers on every response, including a strict Content-Security-Policy and HSTS
  (NFR-SEC-005), from a file versioned in the repository (`public/_headers`);
- build automatically from GitHub, give every pull request its own preview URL, and roll back a bad
  release in under 5 minutes (architecture QAS-10);
- never pause or disable the site because a usage quota ran out, because a paused frontend stops sales at
  every branch.

The question: **where should the static frontend be hosted?**

## Decision Drivers

1. Commercial use permitted at the price we pay.
2. Cost: free for the pilot and the first branches; no per-seat fees.
3. No hard quota that can take the site offline (bandwidth or build credits).
4. Control of response headers through a versioned file.
5. Preview deployment per pull request and branch; one-click rollback.
6. Edge delivery close to Dhaka.
7. Portability: the same static output must be deployable elsewhere with minimal change.

## Considered Options

1. **Cloudflare Pages** (Git integration, Free plan).
2. **Vercel** (Hobby plan, or Pro).
3. **Netlify** (Free plan).
4. **Firebase Hosting** (Spark plan).
5. **Cloudflare Workers with static assets** (Cloudflare's newer deployment model for static sites and
   full-stack applications).

Not shortlisted: GitHub Pages (no custom response headers, so no CSP or HSTS control, and not intended
for commercial software services), and Amazon S3 with CloudFront (paid from the first request and more
configuration to secure and maintain).

## Decision Outcome

Chosen option: **"Cloudflare Pages"**, because it is the only shortlisted option whose free plan
explicitly allows commercial use with unmetered static bandwidth and requests (drivers 1 to 3), it
reads the `_headers` file we already maintain (driver 4), and it provides Git-driven builds, preview URLs
per branch and instant rollback (driver 5) on a global network with edge locations close to Dhaka
(driver 6).

Configuration (the delivery pipeline is specified in
[architecture 14.4](../architecture/architecture.md#144-delivery-pipeline)):

- One Pages project connected to the GitHub repository. The production branch is `production`, which only
  the release workflow fast-forwards to a release tag; every other branch, including `main`, builds as a
  preview with staging environment variables.
- Build command `pnpm build`, output directory `dist/`, Node 22. Build watch paths skip builds for
  documentation-only changes, protecting the monthly build allowance.
- Security and caching headers come from `public/_headers` (copied to `dist/`); header values are owned
  by the [security model](../security/security-model.md#102-http-security-headers).
- Production uses a custom domain with Cloudflare-managed TLS. Preview URLs (`*.pages.dev`) connect only
  to the staging Supabase project, which holds synthetic data only
  ([security model](../security/security-model.md) threat T-CI-08). Putting preview URLs behind
  Cloudflare Access (free for small teams) is recommended as an additional layer and is proposed to the
  security model owner.
- No Pages Functions are used. If server-side code is ever needed at the edge, that is a new ADR.

### Consequences

- Good, because hosting costs USD 0 at any foreseeable traffic: static requests and bandwidth are
  unmetered on the Free plan, and there are no per-member seats.
- Good, because a release that breaks a screen is undone with "rollback to previous deployment" in
  under 5 minutes, independent of the database (architecture 14.4).
- Good, because every pull request gets a preview URL for review and user acceptance without extra
  infrastructure.
- Good, because headers are code: CSP, HSTS, framing and caching rules are reviewed in pull requests and
  checked automatically on deployed previews.
- Good, because without a top-level `404.html`, Pages serves `index.html` for unknown paths, which is the
  fallback client-side routing needs.
- Bad, because the Free plan allows 500 builds per month, one concurrent build and a 20-minute build
  timeout (at the time of writing). With trunk-based development and several pushes per day this is
  sufficient but must be watched; build watch paths and skipping documentation-only commits are the
  first levers.
- Bad, because preview URLs are public by default, so anyone who learns one can load the staging
  application; staging data still requires a staging login and is synthetic, and Cloudflare Access can
  close the gap.
- Bad, because Cloudflare now steers new projects towards Workers with static assets; Pages remains
  supported, but new features may arrive there first. Migration is low-cost because Workers static
  assets read the same `_headers` and `_redirects` files and serve the same `dist/` output.
- Bad, because a Cloudflare-wide incident (as on 18 November 2025) makes the application unreachable for
  users without a cached copy. From M4 the PWA service worker serves the cached shell, so installed
  terminals keep working while Supabase is reachable.
- Neutral, because the frontend holds no business data, so the host's location has no data-protection
  impact; the data-residency question is entirely in ADR-0002.

### Confirmation

- Every pull request shows a Cloudflare Pages preview deployment check; merges to `main` build the staging
  alias; production deploys happen only from the release workflow.
- From M2, an automated check requests every preview deployment and fails the pull request when the
  required security headers are missing (security model test SEC-TC-17); post-deploy smoke tests repeat
  the check against staging and production.
- The build count is part of the weekly usage review; more than 400 builds in a month (80 percent of the
  allowance) triggers build-path tuning or moving builds to GitHub Actions with direct upload.
- Review triggers: Cloudflare announces deprecation of Pages or removes commercial use or unmetered
  bandwidth from the Free plan; the build allowance is exceeded in two consecutive months; or a feature
  we need exists only on Workers. The default response is migration to Workers with static assets, which
  keeps the same vendor, output and headers file.

## Pros and Cons of the Options

### Cloudflare Pages (chosen)

- Good, because the Free plan allows commercial use, unlimited sites, unlimited static requests and
  bandwidth, and preview deployments per branch.
- Good, because `_headers` and `_redirects` files give full control of response headers and routing.
- Good, because Cloudflare's network has edge locations close to Dhaka, and hashed assets are cached with
  `Cache-Control: public, max-age=31536000, immutable`.
- Bad, because of the build allowance and concurrency limits described above.
- Bad, because some limits of the `_headers` file (at the time of writing 100 rules and 2,000 characters
  per line) constrain very long CSP values; the current policy is well below them.

### Vercel

- Good, because it has excellent developer experience, preview deployments and analytics.
- Bad, because the Hobby plan is restricted to non-commercial personal use; Vercel's fair-use guidelines
  define commercial use as any deployment used for financial gain of anyone involved, which includes a
  pharmacy's internal business system and any future SaaS. Commercial use requires Pro at USD 20 per
  member per month, so two maintainers would cost about USD 40 per month, more than the Supabase Pro
  plan that holds all the data.
- Bad, because its strengths (server rendering, edge middleware) are features this SPA deliberately does
  not use ([ADR-0003](0003-react-vite-typescript-spa.md)).

### Netlify

- Good, because it supports the same `_headers` and `_redirects` file format, deploy previews and
  instant rollback, and allows commercial use.
- Bad, because the Free plan is credit-based: at the time of writing 300 credits per month, where each
  production deploy costs 15 credits and each GB of bandwidth 20 credits. Twenty production deploys
  alone exhaust the month.
- Bad, because when credits run out, every site on the account is paused until the next billing cycle,
  which would stop sales at every branch (driver 3). Avoiding that requires a paid plan.

### Firebase Hosting

- Good, because commercial use is allowed on the Spark plan, preview channels exist, and Google's CDN is
  reliable.
- Bad, because the Spark plan includes 10 GB of storage and 360 MB of data transfer per day (about 10 GB
  per month); exceeding the daily transfer interrupts serving until the quota resets, unless the project
  moves to pay-as-you-go Blaze with a billing account.
- Bad, because headers are configured in `firebase.json` rather than the `_headers` format shared by
  Cloudflare and Netlify, and pull request previews need a service-account key stored in CI.
- Bad, because it adds a Google Cloud project and account solely for hosting, since PIMS does not use
  other Firebase services ([ADR-0002](0002-supabase-postgresql-over-firebase.md)).

### Cloudflare Workers with static assets

- Good, because static asset requests are free and unmetered, `_headers` and `_redirects` are supported,
  and it is the model Cloudflare now recommends for new full-stack projects.
- Good, because it would allow server-side code later in the same deployment.
- Bad, because for a purely static site it adds a `wrangler` configuration and deployment step without
  benefit today, and the server-side capability it adds is one we deliberately avoid.
- Neutral, because it is the planned fallback if Pages stops meeting our needs.

## More Information

- [Architecture description](../architecture/architecture.md): sections 14 (environments and deployment
  pipeline), 20 (cost model), 21 (QAS-10)
- [Security model, HTTP security headers](../security/security-model.md#102-http-security-headers)
- [SRS](../requirements/SRS.md): C-09, NFR-SEC-005, NFR-PERF-003
- [Operations runbook](../operations/runbook.md): frontend rollback procedure
- Related decisions: [ADR-0002](0002-supabase-postgresql-over-firebase.md),
  [ADR-0003](0003-react-vite-typescript-spa.md)
- Vendor terms and limits as published in October 2026; re-verify before relying on them:
  Cloudflare Pages limits <https://developers.cloudflare.com/pages/platform/limits/>, Cloudflare Workers
  static assets migration guide <https://developers.cloudflare.com/workers/static-assets/migrate-from-pages/>,
  Vercel fair use guidelines <https://vercel.com/docs/limits/fair-use-guidelines>, Netlify pricing
  <https://www.netlify.com/pricing/>, Firebase pricing <https://firebase.google.com/pricing>.
