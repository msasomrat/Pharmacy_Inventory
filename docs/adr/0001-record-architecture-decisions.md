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

# ADR-0001: Record architecture decisions as MADR documents in the repository

## Context and Problem Statement

PIMS is built and maintained by a very small team (initially one engineer) for a pharmacy business in
Dhaka that intends to open more branches and may later sell the software to other pharmacies. The
architecture risk register names knowledge concentrated in one person as a high-likelihood risk
([architecture R-08](../architecture/architecture.md#221-risks)), and the SRS requires "an ADR per
significant decision" (NFR-MAINT-007).

Several early decisions are unusual enough that a newcomer will be tempted to undo them unless the
reasoning is written down. Examples: clients may not insert into `sales` even though PostgREST would
allow it, money is never a decimal number, stock is never updated in place, and every query is filtered
by row level security rather than by application code. Each of these choices removes a class of
defects, but only while everyone follows it.

A future buyer, auditor or SaaS customer performing technical due diligence will also ask why the system
is built the way it is. Answers that live in chat history or in one person's memory are lost.

The question: **how, where and in what format does the project record significant technical
decisions?**

## Decision Drivers

- Low overhead: a typical record should take under one hour to write and fifteen minutes to review.
- Versioned with the code and reviewed through the same pull-request workflow (protected `main`,
  CODEOWNERS approval).
- Readable on GitHub without extra tools, and parseable by simple scripts for index checks.
- Captures alternatives and trade-offs, not only the outcome.
- Supports changing a decision without losing the history of the old one.
- Usable by a non-technical approver (the pharmacy owner) for cost and vendor decisions.
- Discoverable from the code that implements a decision.

## Considered Options

1. No formal records: rely on commit messages, pull request descriptions and chat.
2. Decision pages in an external wiki or shared drive (Notion, Google Docs, Confluence).
3. Lightweight ADRs in the format proposed by Michael Nygard (Title, Status, Context, Decision,
   Consequences).
4. MADR 4.0 records in `docs/adr/` of the application repository.
5. A request-for-comments (RFC) process with design documents and formal comment periods.

## Decision Outcome

Chosen option: "MADR 4.0 records in `docs/adr/`", because it keeps decisions next to the code under
the same review controls, requires alternatives and both good and bad consequences to be stated, has a
machine-readable status in YAML front matter, and its "Confirmation" section forces each decision to say
how compliance is checked.

Rules that follow from this decision (details in the [ADR index](README.md)):

- Records are numbered `NNNN`, never renumbered or reused, and named `NNNN-kebab-case-title.md`.
- Status values are `proposed`, `accepted`, `rejected`, `deprecated` and `superseded by ADR-NNNN`.
- An accepted record is not rewritten; a changed decision is a new record that supersedes it.
- The ADR, the index, the [architecture decision index](../architecture/architecture.md#23-architecture-decision-index)
  and every affected canonical document are updated in the same pull request.
- ADRs hold rationale; specifications stay in their canonical documents (SRS, database design, security
  model, roadmap) and are linked rather than copied.
- Code that embodies a non-obvious decision cites the ADR in a comment, as `src/domain/money.ts` does for
  [ADR-0005](0005-money-as-integer-paisa.md).

### Consequences

- Good, because the reasoning behind the platform, data model and security choices survives staff
  changes and can be handed to an auditor or buyer as-is.
- Good, because decisions are reviewed with the same rigour and audit trail as code, and the history of
  every change is in Git.
- Good, because "Bad, because" sections make accepted risks explicit, so they can be monitored instead of
  rediscovered.
- Good, because review triggers in each record turn "revisit later" into checkable conditions.
- Bad, because writing records costs time, roughly one to two hours per significant decision including
  review.
- Bad, because records can drift from reality if implementation changes without a new ADR; mitigated by
  the pull request checklist and milestone reviews below.
- Bad, because there is a risk of overlap with the architecture description; mitigated by the
  canonical-ownership rule (ADRs explain why, other documents specify what).
- Neutral, because the product owner reads ADRs on GitHub rather than in a familiar office tool; short
  "Context" and "Decision Outcome" sections keep them readable.

### Confirmation

- The pull request template contains the item "Docs/ADR/threat model updated if behaviour or
  architecture changed"; reviewers reject pull requests that change an accepted decision without a new
  ADR.
- At each milestone exit the engineering lead walks the index, checks the review triggers in every
  accepted ADR, and confirms that architecture section 23 contains no decision marked "to be recorded"
  for work already delivered.
- Planned for M2: a CI step that fails when an ADR file lacks valid front matter, uses a status outside
  the allowed set, or is missing from the index table in [README.md](README.md).
- Review trigger: if the team grows beyond about five engineers or decisions start needing cross-team
  consultation, revisit whether a lightweight RFC stage should precede ADRs.

## Pros and Cons of the Options

### No formal records

- Good, because there is no overhead.
- Bad, because rationale is scattered across commits and chats, is not searchable by topic, and is lost
  when people leave.
- Bad, because it fails NFR-MAINT-007 and leaves risk R-08 unmitigated.

### External wiki or shared drive

- Good, because rich editing and commenting are familiar to non-engineers.
- Bad, because pages are not versioned with the code, not reviewed through pull requests, and drift
  silently.
- Bad, because access depends on a separate account and vendor, and the pages are not shipped with the
  source when the software is sold or handed over.

### Nygard-style ADRs

- Good, because the format is minimal and widely known.
- Neutral, because it is close to MADR and would also be stored in the repository.
- Bad, because it has no explicit place for decision drivers, the options that were rejected, or how
  compliance is confirmed, which are the parts most valuable to a future reader.

### MADR 4.0 in the repository

- Good, because it structures drivers, options, consequences and confirmation while staying plain
  Markdown.
- Good, because YAML front matter makes status and dates machine-checkable.
- Bad, because it is longer than the Nygard format, so small decisions may feel heavy; the
  "When an ADR is required" rules in the index limit ADRs to significant decisions.

### RFC process

- Good, because it scales to many teams and long-running design debates.
- Bad, because comment periods and formal roles are disproportionate for a team of one to three
  engineers and would slow delivery of milestones M1 to M3.

## More Information

- [ADR index, process and template](README.md)
- [Architecture description, section 23](../architecture/architecture.md#23-architecture-decision-index)
- [SRS](../requirements/SRS.md): NFR-MAINT-007 (decisions documented), constraint C-01 (stack changes
  require an ADR)
- [Engineering standards](../engineering/engineering-standards.md): Definition of Done and review
  checklist
- MADR: <https://adr.github.io/madr/> (version 4.0, accessed October 2026)
- Michael Nygard, "Documenting Architecture Decisions" (2011):
  <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
