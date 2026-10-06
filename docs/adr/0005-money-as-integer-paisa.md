---
status: accepted
date: 2026-10-06
decision-makers:
  - Engineering lead
consulted:
  - Database design owner
  - Product owner (pharmacy owner)
informed:
  - All contributors
---

# ADR-0005: Represent money as integer paisa and rates as integer basis points

## Context and Problem Statement

Every PIMS screen that matters to the business shows money: MRP and sale prices, purchase costs, line
and invoice discounts, loyalty discounts and points, VAT contained in MRP-inclusive prices, optional
rounding to the nearest taka, split payments across cash, bKash, Nagad, Rocket and card, customer dues
(বাকি), supplier dues, refunds and profit. The currency is the Bangladeshi taka (৳, BDT), which has 100
paisa.

The rules are strict:

- An invoice total must equal the sum of its lines plus an explicit rounding adjustment, payments plus
  due must equal the total, and an invoice discount must be allocated to lines so that line nets are
  exact (FR-POS-019, NFR-REL-005).
- A sale price may never exceed the MRP printed on the pack (C-11, FR-POS-012).
- Derived balances (stock value, customer and supplier dues, loyalty liability) must equal their
  ledgers with **zero tolerance** in the nightly check (NFR-REL-003).
- Partial returns must never refund more than was paid (FR-POS-051).
- The same calculation runs in two places: authoritatively in PostgreSQL
  ([ADR-0007](0007-business-logic-in-transactional-postgres-functions.md)) and as a preview in the
  browser; both must agree to the paisa (NFR-REL-011).

Binary floating point cannot represent most decimal fractions exactly. In JavaScript, which has only
IEEE 754 doubles as its default number type:

| Expression               | Result                | Expected |
| ------------------------ | --------------------- | -------- |
| `0.1 + 0.2`              | `0.30000000000000004` | `0.3`    |
| ten times `0.10` summed  | `0.9999999999999999`  | `1`      |
| `Math.floor(1.15 * 100)` | `114`                 | `115`    |
| `(1.005).toFixed(2)`     | `"1.00"`              | `"1.01"` |

A one-paisa drift per line is invisible on a receipt but breaks zero-tolerance reconciliation, makes
gapless audits noisy, and erodes trust when the owner's report disagrees with the cash drawer by a few
paisa every day.

Pack pricing adds a second problem. Prices are printed per pack, while stock is held in base units (the
smallest sellable unit, C-05). A strip of 14 tablets with an MRP of ৳50.00 costs 357.142857... paisa per
tablet. Storing a rounded per-tablet price either undercharges (357 × 14 = 4,998 paisa, ৳49.98 for a
full strip) or exceeds the MRP (358 × 14 = 5,012 paisa, ৳50.12), which is not allowed.

The question: **how are money amounts and rates represented and calculated in the database, the API
and the client?**

## Decision Drivers

1. Exactness: arithmetic on amounts must be exact; rounding happens only at defined points.
2. One rule set in two implementations (SQL and TypeScript) that can be proven identical.
3. Safety by construction: a wrong representation should be hard to introduce and easy to detect.
4. Transport through PostgREST JSON to JavaScript without precision loss.
5. Performance and storage for tables that grow by hundreds of thousands of rows per branch per year.
6. Correct display in English and Bangla, with lakh and crore digit grouping.

## Considered Options

1. **Floating-point taka:** `double precision` in the database and JavaScript `number` with decimals.
2. **Decimal taka:** `NUMERIC(14,2)` in the database and a decimal library (for example `decimal.js` or
   `big.js`) in TypeScript.
3. **Integer paisa:** `BIGINT` minor units in the database and integer `number` values with a branded
   type in TypeScript; rates as integer basis points.
4. **PostgreSQL `money` type.**
5. **Integer paisa with JavaScript `BigInt` everywhere** in the client.

## Decision Outcome

Chosen option: **"Integer paisa"**, because integer addition, subtraction and multiplication by integer
quantities are exact in both PostgreSQL and JavaScript within the bounds below, rounding then occurs only
in a handful of named functions, and plain integers pass through PostgREST JSON and TypeScript without
conversion (drivers 1, 2 and 4). Integer columns with a `_paisa` suffix make the unit visible in every
query and payload (driver 3).

Rules (the normative specification is
[database design 3.6 and 3.7](../database/database-design.md#37-rounding-and-allocation-rules)):

| Topic         | Rule                                                                                                                                                                                                                                                                 |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Storage       | Every money column is `bigint` with the suffix `_paisa` (1 BDT = 100 paisa). `real`, `double precision`, `numeric` money columns and the `money` type are forbidden.                                                                                                 |
| Rates         | Percentages and rates are `integer` basis points with the suffix `_bp` (100 bp = 1 %, 10,000 bp = 100 %); for example 12.5 % is `1250`. SRS constraint C-04 also allows `NUMERIC(5,2)`; PIMS uses basis points throughout so there is one representation.            |
| Quantities    | `integer` base units ([ADR-0008](0008-append-only-inventory-ledger-with-fefo.md)); never fractional.                                                                                                                                                                 |
| Pack prices   | A lot stores MRP and sale price for `price_basis_quantity` base units (normally one pack); line gross is `round(quantity * price / basis)` per allocated lot, so a full strip always costs exactly its MRP.                                                          |
| Rounding      | Round half up to the nearest paisa (half away from zero for negative values), only at the points R-1 to R-7 of the database design: percentages, proportional allocation, partial reversal, pack pricing, contained VAT and optional cash rounding.                  |
| Allocation    | Amounts spread over lines (invoice discount, loyalty cap) use an allocation whose parts always sum exactly to the total (R-3, `app.allocate_proportionally`).                                                                                                        |
| Cash rounding | Optional per organization (`cash_rounding = 'nearest_taka'`): an explicit `rounding_paisa` adjustment between -49 and +50 paisa, never hidden in a line.                                                                                                             |
| VAT           | Prices are MRP-inclusive; VAT contained in a net amount is `round(net * vat_bp / (10000 + vat_bp))`, default rate 0 bp.                                                                                                                                              |
| Bounds        | Application amounts are limited to 10^12 paisa (৳10 billion) in magnitude, `MAX_PAISA` in `src/domain/money.ts`; database columns use `CHECK` constraints for sign and range.                                                                                        |
| Client        | `src/domain/money.ts` defines the branded type `Paisa`, parses user input from strings without floating point (`parseTaka`), and formats with lakh and crore grouping (`formatTaka`: `৳12,34,567.89`, Bangla digits in `bn`). Client calculations are previews only. |
| API           | RPC payloads and results carry integers in paisa; the client converts to taka only for display.                                                                                                                                                                      |

Worked examples (part of the shared client and database test vectors, NFR-REL-011):

| Case                                | Calculation                                     | Result                     |
| ----------------------------------- | ----------------------------------------------- | -------------------------- |
| 2.5 % discount on ৳123.45           | `round(12345 * 250 / 10000)` = `round(308.625)` | 309 paisa (৳3.09)          |
| 5 tablets from a ৳50.00 strip of 14 | `round(5 * 5000 / 14)` = `round(1785.71...)`    | 1,786 paisa (৳17.86)       |
| Full strip of 14 from the same lot  | `round(14 * 5000 / 14)`                         | 5,000 paisa (৳50.00)       |
| VAT contained in ৳107.50 at 7.5 %   | `round(10750 * 750 / (10000 + 750))`            | 750 paisa (৳7.50)          |
| Cash rounding of ৳1,234.56          | `round(123456 / 100.0) * 100 - 123456`          | +44 paisa, total ৳1,235.00 |

### Consequences

- Good, because sums, differences and products with integer quantities are exact, so totals, ledgers and
  projections reconcile with zero tolerance.
- Good, because every rounding point is a named, tested function (`app.percent_of`,
  `app.allocate_proportionally` and the pricing function in the database; `percentOf` in TypeScript), so
  disagreements between client preview and server can be located quickly.
- Good, because `bigint` is 8 bytes and integer arithmetic is fast, which matters for reports over
  hundreds of thousands of lines.
- Good, because the `_paisa` and `_bp` suffixes make unit mistakes visible in code review; mixing taka and
  paisa in one expression looks wrong.
- Bad, because every amount entered or displayed must be converted between taka and paisa; mistakes
  (for example sending `12.5` instead of `1250`) are possible. Branded types, Zod integer schemas and
  database integer types reject them at the first boundary.
- Bad, because database tools and ad-hoc SQL show paisa, so report and export code must always format
  values; exports state the unit in the column header.
- Bad, because JavaScript numbers are exact only up to 2^53 - 1 (about 9.007 × 10^15). Amounts up to
  `MAX_PAISA` are safe, but an intermediate product such as `amount * bp` can exceed this bound near the
  limit: `999999999999 * 9999` evaluates to `9998999999990000` in JavaScript, one less than the exact
  value. Real invoice amounts are many orders of magnitude smaller, but the helper must be made exact
  (follow-up F-1 below).
- Neutral, because PostgreSQL `sum()` over `bigint` returns `numeric`; report functions cast results back
  to `bigint`, and totals remain far below the JSON-safe bound.

### Confirmation

- Vitest unit and property-based tests (fast-check, at least 10,000 generated cases per property) prove
  that allocations sum to their totals, refunds never exceed amounts paid, and percentages round half up
  (NFR-REL-005); `src/domain/money.test.ts` is the starting point and the coverage threshold for
  `src/domain/**` is enforced in `vite.config.ts`.
- pgTAP tests reproduce the same vectors in SQL, and a contract test runs shared vectors against both
  implementations (NFR-REL-011).
- A platform guard test (to be added to `supabase/tests/database/001_platform_guards.test.sql` in M1)
  fails if any column in the `public`, `app` or `audit` schemas uses `real`, `double precision` or
  `money`, or if a column ending in `_paisa` is not `bigint` or one ending in `_bp` is not `integer`.
- The pull request checklist item "Money handled as integer paisa" is checked for every change touching
  amounts.
- The nightly integrity checks (database design section 17.2) report any non-zero difference between
  projections and ledgers.
- Review triggers: support for a second currency or a currency with three decimal places, which would
  require a currency column and minor-unit metadata, is a new ADR.

### Follow-up work

| ID  | Item                                                                                                                                                                                                                                       | Owner           | Needed by |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------- | --------- |
| F-1 | Make `percentOf` (and any future helper that multiplies two amounts or an amount by a rate) exact over the whole `MAX_PAISA` range, for example by computing the intermediate product with `BigInt`, and add a property test at the bounds | Engineering     | M2        |
| F-2 | Implement `price_basis_quantity` on lots and allocations, replacing per-base-unit prices ([database design delta D-05](../database/database-design.md#21-implementation-deltas))                                                           | Database design | M1 freeze |
| F-3 | Implement exact lot cost value (`cost_value_paisa`) so cost of goods sold and stock value reconcile to goods-receipt amounts ([delta D-06](../database/database-design.md#21-implementation-deltas))                                       | Database design | M1 freeze |

## Pros and Cons of the Options

### Floating-point taka

- Good, because it is the default in JavaScript and needs no conversion for display.
- Bad, because results such as those in the context table are routine, and errors accumulate across lines,
  allocations and ledgers, breaking zero-tolerance reconciliation.
- Bad, because equality comparisons and rounding become unreliable, which is unacceptable for financial
  records.

### Decimal taka (`NUMERIC(14,2)` and a decimal library)

- Good, because amounts read naturally in SQL (`123.45`) and arithmetic is exact when done in
  `numeric` or with the library.
- Bad, because PostgREST serializes `numeric` as a JSON number, which JavaScript parses into a binary
  float; every client calculation must remember to go through the decimal library, and one forgotten
  place reintroduces drift.
- Bad, because assigning a value with more decimals to `NUMERIC(14,2)` rounds silently on insert, which
  creates hidden rounding points instead of explicit ones.
- Bad, because the decimal library adds roughly 10 to 30 KB to the client bundle and its own API to learn,
  and `numeric` arithmetic is slower than integer arithmetic in large reports.

### Integer paisa (chosen)

- Good, because it is exact, compact, fast and natural for both PostgreSQL and JavaScript.
- Good, because the unit is fixed and visible in names, which supports review and automated checks.
- Bad, because conversion at the user interface is always required, and the 2^53 bound must be respected
  in client arithmetic.

### PostgreSQL `money` type

- Good, because it stores fixed-point amounts compactly.
- Bad, because its input and output format depend on the server's `lc_monetary` setting, its fractional
  precision is fixed by locale, and operations with `numeric` and rates are awkward; the PostgreSQL
  community advises against it for application data.
- Bad, because client libraries return it as a locale-formatted string such as `$1,234.56`, which must be
  parsed again.

### Integer paisa with `BigInt` everywhere in the client

- Good, because it removes the 2^53 bound entirely.
- Bad, because `BigInt` values cannot be serialized to JSON without custom code, are not returned by
  `supabase-js`, cannot be mixed with `number` in expressions (a `TypeError`), and are not accepted by
  most UI and charting libraries.
- Bad, because the bound it removes is far above realistic amounts; using `BigInt` only inside the few
  helpers that form large intermediate products (follow-up F-1) gives the same safety at much lower cost.

## More Information

- [Database design](../database/database-design.md): sections 3.6 (data types), 3.7 (rounding and
  allocation rules), 9.1 (sale calculation), 9.6 (valuation) and 9.7 (proportional reversal)
- [Architecture description](../architecture/architecture.md): section 13 (cross-cutting concerns,
  money)
- [SRS](../requirements/SRS.md): C-04, C-05, C-11, FR-POS-012, FR-POS-019, FR-POS-051, FR-INV-002,
  NFR-REL-003, NFR-REL-005, NFR-REL-011
- Code: `src/domain/money.ts`, `src/domain/money.test.ts`, `app.percent_of` and
  `app.allocate_proportionally` in `supabase/migrations/20261006120000_foundation.sql`
- Related decisions: [ADR-0007](0007-business-logic-in-transactional-postgres-functions.md) (server-side
  pricing), [ADR-0008](0008-append-only-inventory-ledger-with-fefo.md) (base units and lot cost)
- PostgreSQL documentation, "Monetary Types": <https://www.postgresql.org/docs/current/datatype-money.html>
