# ADR-0019: Locale-to-currency table, `PARTIALLY_PLACED` on skipped lines, duplicate SKU is `422`

**Status:** Accepted
**Date:** 2026-10-18
**Affects:** `phase-1/technical-design/api-design/profile.md` (§ `preferredCurrency` semantics), `phase-1/technical-design/api-design/orders.md` (§ Place order field semantics, § Rules), `phase-1/technical-design/data-model-erd.md` (§ checkout rule 6), `phase-1/technical-design/api-design/seller.md` (§ Create product errors)
**Implemented by:** none, the code already behaves as specified (aliceut-ecom-backend#38, #53)

## Context

`spec-compliance.md` entry 1 listed three places where the design was silent or
self-contradictory and the code had picked an answer. The user ratified each.

**Locale to currency.** US-B-01 and profile.md say "Auto" resolves to the
currency matching the `Accept-Language` locale, with no table. The code
resolves only the highest-q locale, takes its region's currency, and gives a
bare language the region it is overwhelmingly spoken in.

**`PARTIALLY_PLACED` with only skipped lines.** kafka-events.md § 2.8 says a
`skipped_items` entry makes `placement_outcome` `PARTIALLY_PLACED`;
orders.md and data-model-erd.md said only a failed group does. The code
follows § 2.8.

**Duplicate SKU in one product.** seller.md says `sku` is unique within the
product and lists no status for a violation; the code answers `422`.

## Decision

**1. Locale table.** `Accept-Language` resolves as follows, and the table is
the spec:

| Step | Rule |
|---|---|
| Locale | The highest-q range; ties go to header order; `q=0` and `*` are ignored. A lower-ranked locale is never consulted, so `en-GB, th;q=0.8` resolves from `en-GB`. |
| Region | The tag's region subtag (`th-TH`, `zh-Hant-SG`); a tag with none takes its language's likely region: `en` US, `th` TH, `ja` JP. Any other bare language has no region. |
| Currency | Region `US` USD, `TH` THB, `JP` JPY, `SG` SGD. Anything else, no header, or no region: `USD`. |

**2. `PARTIALLY_PLACED`.** `placement_outcome` is `PARTIALLY_PLACED` when at
least one group failed **or** at least one line was skipped, and the order
still has at least one placed group. It is `FULLY_PLACED` otherwise. A checkout
in which no group placed creates no order and returns `422`, as before.

**3. Duplicate SKU.** Two variants with the same `sku` in one create-product
request, or a `sku` already used by another variant of the same product, is
`422`. It is a business-rule conflict on otherwise well-formed input, not
shape validation (`400`), and not a conflict with an existing resource
(`409`): nothing exists yet when a create request repeats a SKU.

## Consequences

No code change. The three spec statements now match what the backend already
does, so `spec-compliance.md` drops the three bullets.

The locale table is deliberately small: it covers the four seller-priceable
currencies only. A new V1 currency means a new row here, in
`display-currency.ts`, and an ADR.

## Alternatives considered

**Resolve every listed locale in q order and take the first priceable one.**
Rejected by the user in the ratified behavior: `en-GB, th;q=0.8` would price in
THB for a buyer whose browser prefers British English.

**`PARTIALLY_PLACED` only for failed groups.** A buyer whose lines were
skipped would get a `FULLY_PLACED` order that lacks lines they asked for, and
the confirmation email's `skipped_items` section would sit on an order that
claims to be complete.

**`400` or `409` for a duplicate SKU.** See Decision 3.
