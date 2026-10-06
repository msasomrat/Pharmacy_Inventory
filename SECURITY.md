# Security Policy

The Pharmacy Inventory Management System (PIMS) stores pharmacy stock, sales, customer and prescription
records. We take reports of security weaknesses seriously and are grateful to anyone who reports them
responsibly. This policy explains how to report a vulnerability, what to expect from us, and what is in
scope.

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues, pull requests or
discussions.**

Report privately by email to **`security@<mail-domain>`** (the PIMS business email domain; see
[Placeholders](#placeholders) below). This mailbox is the primary and only public reporting channel.
It is monitored by the Owner and the engineering lead, and its contents are never forwarded to public
trackers.

The same address, the policy link and the preferred languages are published in machine-readable form
at `https://<app-domain>/.well-known/security.txt` ([RFC 9116](https://www.rfc-editor.org/rfc/rfc9116)).
If an OpenPGP key is listed there under `Encryption`, you may encrypt your report with it; encryption
is optional.

Repository collaborators may instead open a draft advisory from the repository's **Security** tab
(**Advisories**, **New draft security advisory**). Outside reporters cannot do this, because the
repository is private ([README, License](README.md#license)).

Do not attach customer, patient or prescription data to a report; describe it instead (for example
"the response contained another organization's customer names").

Please include as much of the following as you can:

- The affected component (web app, database migration or function, Edge Function, CI workflow,
  configuration) and the file, function or URL path.
- The version, release tag or commit SHA you tested.
- Step-by-step reproduction instructions, a proof of concept, and the role you used (for example
  Salesman, Branch Manager, Owner) when the issue involves permissions.
- The impact you believe an attacker could achieve (for example reading another organization's data,
  changing prices or stock, bypassing two-factor authentication).
- Any suggested fix or mitigation.
- Whether and how you would like to be credited.

Reports may be written in English or Bangla.

## What to expect

Business days are Sunday to Thursday, Asia/Dhaka time (UTC+6).

| Stage                                | Target                                                                                        |
| ------------------------------------ | --------------------------------------------------------------------------------------------- |
| Acknowledgement of your report       | Within 2 business days                                                                        |
| Initial assessment and severity      | Within 5 business days                                                                        |
| Status updates                       | At least every 7 days until the report is resolved                                            |
| Fix or mitigation, Critical severity | Within 48 hours of confirmation                                                               |
| Fix or mitigation, High severity     | Within 7 days of confirmation                                                                 |
| Fix or mitigation, Medium severity   | Within 30 days of confirmation                                                                |
| Fix or mitigation, Low severity      | Within 90 days or in the next planned release                                                 |
| Public disclosure                    | Coordinated with you, normally after the fix is deployed and at most 90 days after the report |

Severity is assessed with CVSS v3.1 and the impact on tenant isolation, health and personal data, money
and stock integrity. If we decide that a report is not a vulnerability or is out of scope, we will
explain why.

After a fix is released we send you, and the affected pharmacies, a written advisory describing the
issue, the affected and fixed versions and, if you wish, your name; the same advisory is recorded as a
GitHub Security Advisory in the private repository. We do not offer a paid bug bounty at this time.

## Supported versions

PIMS is deployed as a hosted application, and only the current production deployment receives security
fixes. Any other deployment must be updated to the latest release to receive them.

| Version                                    | Supported |
| ------------------------------------------ | --------- |
| `main` branch (next release)               | Yes       |
| Latest release (`0.x`, currently deployed) | Yes       |
| Older releases                             | No        |

Before version 1.0.0, any release may change behavior; security fixes are made on `main` and shipped
in a new release rather than backported.

## Scope

### In scope

- The web application in `src/`, its security headers in `public/_headers` and its
  `public/.well-known/security.txt`.
- Database migrations, Row Level Security policies, grants and functions in `supabase/`.
- Supabase Edge Functions in `supabase/functions/`.
- GitHub Actions workflows and repository configuration in `.github/`.
- Official PIMS deployments operated by the maintainers, **subject to the rules of engagement below**.

Examples of issues we especially want to hear about:

- Access to another organization's or another branch's data.
- Performing an action beyond your role, such as a Salesman voiding a sale, exceeding a discount limit
  or adjusting stock.
- Bypassing two-factor authentication for Owner or Branch Manager accounts.
- Changing prices, totals, stock, the controlled-drug register or the audit log in ways the business
  rules forbid.
- Exposure of customer, patient or prescription data, or of secrets.
- Injection, cross-site scripting or server-side request forgery.
- Prompt injection or data leakage in the AI features (when released).

### Out of scope

- Vulnerabilities in third-party platforms (Supabase, Cloudflare, GitHub, Anthropic, Sentry); please
  report those to the vendor. Misconfiguration of those platforms by PIMS is in scope.
- Denial-of-service or load testing, and volumetric attacks.
- Social engineering, phishing or physical attacks against pharmacy staff, customers or premises.
- Attacks that require physical access to an unlocked counter PC or a compromised device.
- Self-XSS, clickjacking on pages without sensitive actions, and missing security headers without a
  demonstrated impact.
- Reports produced only by automated scanners without a working proof of concept.
- Rate limiting on endpoints that are not security sensitive.
- Use of the public Supabase anon (publishable) key or project URL: these are public by design, and
  access control is enforced by Row Level Security.
- Outdated browsers or operating systems that no longer receive security updates.

## Rules of engagement

PIMS holds real health and personal data. To protect patients and customers:

- Test against your own local instance whenever possible: after `pnpm install`, `pnpm db:start`
  (requires Docker) and `pnpm dev` start a complete local stack that holds only data you create.
- Do not access, modify, download or keep data that does not belong to you. If you encounter customer,
  patient or prescription data, stop, do not share it, and report what you found.
- Do not degrade the service for pharmacies, run denial-of-service tests or send spam.
- Do not contact pharmacy staff or customers, and do not attempt social engineering.
- Give us reasonable time to fix the issue before any public disclosure.

We will not pursue or support legal action against anyone who reports a vulnerability in good faith
and follows these rules. If you are unsure whether an activity is allowed, ask in your report first.

## Security documentation

- [Security model](docs/security/security-model.md): threat model, roles and permissions, and controls.
- [Contributing guide](CONTRIBUTING.md): how contributions are reviewed, including security checks.

Contributors must never commit secrets. Every `VITE_*` variable is bundled into the public web app, so
the Supabase service role key and other API keys must never be placed in `.env` files used by the
frontend.

## For maintainers

- Keep the `security@<mail-domain>` mailbox (or alias) active and forwarded to both the Owner and the
  engineering lead, with spam filtering that never silently discards mail; check it at least every
  business day.
- Keep `public/.well-known/security.txt` (RFC 9116) current. It must contain at least:

  ```text
  Contact: mailto:security@<mail-domain>
  Expires: <date at most 12 months ahead, ISO 8601, for example 2027-10-01T00:00:00+06:00>
  Preferred-Languages: en, bn
  Canonical: https://<app-domain>/.well-known/security.txt
  Policy: https://<app-domain>/.well-known/security-policy.txt
  ```

  Add an `Encryption:` line only if an OpenPGP key is published. Because the repository is private,
  `Policy:` must point to a publicly reachable copy of this file (served from
  `public/.well-known/security-policy.txt`), not to GitHub. Renew `Expires` before it lapses.

- Track each report as a draft GitHub Security Advisory in the private repository (GitHub private
  vulnerability reporting is not available to outside reporters on a private repository), triage it
  within the timelines above and follow incident playbook IR-10 in the
  [runbook](docs/operations/runbook.md).
- Request a CVE through the advisory only if PIMS is ever distributed to parties outside the
  maintainers' own deployments; for the hosted application, the written advisory to affected
  pharmacies is sufficient.

### Placeholders

`<mail-domain>` and `<app-domain>` are the email and web-app domains chosen during production setup
(see the [runbook](docs/operations/runbook.md), section 3.1). Until they are chosen, the maintainers
must replace `security@<mail-domain>` in this file with a monitored interim address controlled by the
Owner, so that a working contact is always published.
