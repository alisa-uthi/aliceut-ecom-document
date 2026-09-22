# Wave 0 Decision Record — Cross-Document Alignment Audit

**Date:** 2026-09-22
**Decided by:** Product owner (alisa-uthi)
**Input:** [2026-09-22-alignment-audit-fix-plan.md](2026-09-22-alignment-audit-fix-plan.md) §3 (Wave 0 — Decision gate)
**Status:** All ten decisions closed. These are now constraints, at the same level as BRD §12.

Every design document corrected in Waves 1–7 must conform to the rulings below.

---

## D-01 — Redis: **AUTHORIZE**

Redis is admitted to the V1 stack.

**Required changes:**
- Amend `BRD.md` §12 to add Redis as a locked stack component (cache + short-lived
  single-use token store).
- Add Redis to `CLAUDE.md` Locked Stack.
- `docker-compose-topology.md:762` — change `--maxmemory-policy allkeys-lru` to
  `noeviction`. The 60-second single-use OAuth authorization code lives in Redis; LRU
  eviction can silently drop it mid-flow. If a cache instance with eviction is wanted
  later, it must be a **separate** instance from the token store.
- `architecture-overview.md:60` — the "Locked in BRD §12" heading becomes true once the
  BRD amendment lands. Keep the heading, land the amendment.

**Rejected alternative:** removal, which would have rewritten `api-design/auth.md:95,843`,
`conventions/auth-jwt-design.md:253`, `api-design/health.md:42,94`,
`api-design/admin.md:63,66,67` and 10 further files.

**Closes:** CRITICAL #2.

---

## D-02 — `B2B_TIER`: **DROP**

`B2B_TIER` is not a V1 price type. Price types in V1 are `LIST` and `SALE` only.

**Rationale:** `BRD.md:85` and `:146` make B2B differentiation branding-only with bulk
pricing deferred. Every downstream design document already assumes this narrow reading —
"drop" matches what exists.

**Required changes:**
- `BRD.md:144` and `BRD.md:257` — remove `B2B_TIER` from the price-type enumeration.
- `CLAUDE.md:75` and `CLAUDE.md:96` — same.
- Any price-type enum in `phase-1/technical-design/` that still lists `B2B_TIER` —
  remove, and remove `min_qty`-based resolution from the effective-price rules.
- PDP effective-price resolution becomes: account type is **not** an input; time and
  price type only.

---

## D-03 — Sole-writer rule: **ENFORCE**

Each Postgres schema has exactly one owning module that writes it. The Phase 2 extraction
premise (`architecture-overview.md:186,218`) stands.

**Required changes:**
- Seller module's write surface routes through the owning modules' application services.
  `api-design/seller.md:69-76,83-84,692-699,832-837` currently writes `catalog.offer`,
  `catalog.product`, `catalog.product_variant`, `catalog.product_image`,
  `pricing.offer_price`, `inventory.stock` directly, and reads `admin.moderation_case`.
  Each becomes a call to the owning module's application service. The
  three-foreign-schema transaction at `seller.md:692-699` becomes an orchestration across
  application services within one transaction boundary owned by the caller.
- `offer.changed` gets a **single** producer. Per
  `phase-1/technical-design/kafka-events.md:14`, the producer is the schema owner:
  **catalog**. Remove seller from the producer list at
  `conventions/backend-module-architecture.md:51`.
- Remove the cross-schema JOIN at `phase-1/technical-design/cleanup-jobs.md:390-391`
  (`seller.seller_profile` → `identity.user`) and the rationale at `:431`.
- Move `CurrencyScaleCache` out of `libs/shared`
  (`conventions/backend-coding-standards.md:237-240`). It reads `pricing.currency` by raw
  SQL; it belongs to the pricing module, exposed through the pricing application service.

**Rejected alternative:** retiring the rule, which would have dropped microservice
readiness — a BRD §12 stack property.

**Closes:** CRITICAL #1, #16, #17, #19.

---

## D-04 — NFR-18 scope: **AMEND TO TIER 1 ONLY**

The repository-interface requirement binds **Tier 1** (core transactional) repositories
only. Tier 2 services may inject `Repository<T>` directly; Tier 3 has no repositories.

**Required changes:**
- `BRD.md:188` (NFR-18) — scope the requirement to Tier 1 repositories, and state the
  portability rationale applies to the transactional core.
- `conventions/backend-module-architecture.md:145-146` — keep the direct-`Repository<T>`
  rule for Tier 2, and cite the amended NFR-18 so the two documents agree explicitly.
- Name the Tier 1 modules in whichever document defines the tiers, so "Tier 1" is not
  itself ambiguous.

**Closes:** CRITICAL #18.

---

## D-05 — Prohibited content: **HYBRID (block hard, flag soft)**

Two tiers, stated once and referenced from both sides.

| Trigger | Behaviour |
|---|---|
| Prohibited taxonomy node, or exact hit on the hard blocklist | **422 at submit.** Listing is not created. |
| Fuzzy / keyword-suspicion match | Listing is **created** with offer status `FLAGGED` and a `admin.moderation_case` row. |

> **The Trigger column above is superseded by [D-14](#d-14--d-05s-tier-discriminator-the-matched-terms-stored-enforcement-not-the-precision-of-the-match).**
> The two *Behaviour* cells stand unchanged and are what FR-A-03 depends on. What changed is
> how a trigger is assigned to a tier: not by how precisely the text matched ("exact hit"
> versus "fuzzy"), which is unimplementable in both directions, but by the stored
> `enforcement` of the blocklist term that matched. Read the rows as **hard tier** = a
> prohibited taxonomy node or a term stored `BLOCK`; **soft tier** = a term stored `FLAG`.
> The original wording is left in place rather than rewritten, because this is a record of
> what was signed off and D-14 carries the amendment.

**Required changes:**
- `BRD.md:145` — restate as the two-tier rule above; the flag path is what feeds FR-A-03.
- `api-design/seller.md:56` — keep the 422 but scope it to the hard tier, and document
  the soft tier's `FLAGGED` outcome as a success response.
- FR-A-03's flagged-listing queue keeps its input source (the soft tier), so
  `user-stories/admin.md` needs no change for this decision.

**Closes:** CRITICAL #14.

---

## D-06 — Kafka image: **AMEND THE BRD**

`apache/kafka:3.8.0` (official Apache image, KRaft mode) is the V1 broker image.

**Required changes:**
- `BRD.md:207` — replace the `bitnami/kafka` / `confluentinc` naming with
  `apache/kafka:3.8.0`, KRaft mode.
- `docker-compose-topology.md:629-671` is already correct — do not change it.
- While in `BRD.md`, note that Redpanda is **not** the chosen substitute (see the
  clerical list below).

---

## D-07 — Elasticsearch-down fallback: **NOMINATE `GET /catalog/products`**

The curated fallback required by `user-stories/buyer.md:82-83` and
`user-stories/platform.md:153` is served by the Postgres-backed catalog list.

**Required changes:**
- `api-design/search.md` — add `503 SEARCH_UNAVAILABLE` to the error contract (this is
  also Wave 3 item 4) and document that clients fall back to
  `GET /catalog/products` on 503, with a `degraded` indicator so the UI can label the
  results as browse-not-search.
- `phase-1/ui-design/buyer-portal.md` — spec the degraded-state presentation.
- Do not build a second search path inside the search module; the fallback is a client
  redirect to an endpoint that already exists.

---

## D-08 — Admin manual flagging: **KEEP THE ENDPOINT**

`POST /admin/moderation` (`api-design/admin.md:72,908`) stays in V1.

**Required changes:**
- `user-stories/admin.md:66` — amend to include manual flagging as an admin capability,
  with the acceptance criteria the endpoint already implies.
- `api-design/admin.md:975` — the `status_changed_reason='ADMIN_REMOVAL'` on a
  flag-only path is still wrong (Wave 5 item 11). Manual flagging sets `FLAGGED`;
  `ADMIN_REMOVAL` belongs only to the removal path.

---

## D-09 — CSV bulk inventory: **ADD `dryRun` PREVIEW**

The bulk inventory endpoint gains a preview mode; commit happens on a second, confirmed
call.

**Required changes:**
- `api-design/seller.md:1185` — add `dryRun` (query param or body flag). With `dryRun`
  set, parse and validate every row, return per-row results, write nothing. Without it,
  commit.
- Spec the per-row result shape: row number, SKU, parsed quantity, and either `OK` or a
  validation error code (`SKU_NOT_FOUND` already exists at `seller.md:1193`).
- The commit call is idempotent under the same idempotency key as every other seller
  mutation (see Wave 5 item 1 for the key-scope ruling).
- `user-stories/seller.md:176-177,182` needs no change — it already describes this.

---

## D-10 — Zero-stock offers: **IMPLEMENT THE DEFAULT FILTER**

Catalog list and search exclude zero-stock offers by default.

**Required changes:**
- `api-design/catalog.md:264,342` — default to excluding offers with
  `available_qty = 0`. Add `includeOutOfStock=true` as an explicit opt-in.
- `api-design/search.md:260` — apply the same default in the ES query, not only as a
  recomputed `in_stock` facet. The facet stays, for the opt-in case.
- PDP (`GET /catalog/products/:id`) still returns the offer, rendered out-of-stock —
  a direct link to a sold-out product must not 404.
- `user-stories/seller.md:58` needs no change — it already describes this.

---

## Clerical — same BRD pass, no decision required

These were listed in the fix plan §3 as needing no sign-off. Apply them with the
decisions above.

- Drop Prisma from `BRD.md:139` (FR-P-04a) and `BRD.md:178` (NFR-08). §12 #3 locks
  TypeORM.
- Fix `BRD.md:208` to **BACKWARD** schema compatibility. It currently prescribes
  forward-compat, against §12 #9 (`BRD.md:261`).
- Drop Redpanda from `CLAUDE.md:59` and `architecture-overview.md:77`. §12 #8 chose
  Kafka, with KRaft mode as the fallback for Zookeeper weight — not a different broker.
- Fix `BRD.md:152` (FR-P-12) to list all six envelope fields. It lists three, omitting
  `event_type`, `event_version`, `payload`.

---

## Amendment mechanics

Root cause 2 of the fix plan is that the BRD was amended **by appendix**, so readers hit
the superseded rule in the FR table first and never reached the amendment list.

**Every change above is applied in place, at the cited line**, with the amendment list at
`BRD.md:270-271` extended to record it. Appendix-only edits do not count as applied.

---

# Addendum — decisions raised during execution

Decisions D-01…D-10 above came from the fix plan's Wave 0 gate. The two below surfaced
while the waves were executing, and carry the same authority.

## D-11 — Re-suspending an already-suspended seller: **409, plus a separate amend endpoint**

Closes one of the four story acceptance criteria the audit could not locate endpoint
behaviour for (fix plan §1, "Withheld, not missing").

- `POST` suspend against a seller whose suspension is **active** returns **409 Conflict**.
  The suspension state machine has no re-entry.
- Amending an active suspension — its end date, its reason, or both — is a **separate
  `PATCH`** on the suspension resource. Specify it in `api-design/admin.md`: request shape,
  the fields that may be amended, the 404/409 cases, and the audit trail it writes.
- Consequence for the event contract: `seller.suspended` carries **no `is_extension`
  field**. An amendment is a distinct operation and, if it needs an event at all, a
  distinct event type — do not overload `seller.suspended` with a boolean discriminator.
- `user-stories/admin.md` needs the re-suspension AC stated to match.

## D-12 — New Kafka topic `seller.profile_changed`: **approved**

`PATCH /seller/profile` previously wrote no outbox row while `api-design/search.md`
indexes `seller_name`, so a renamed seller went permanently stale in search. D-03
(sole-writer ENFORCE) forbids the cross-module DB read that would otherwise supply the
name, leaving a new topic as the only option.

Topic counts across the technical-design documents move to **29 topics / 39 consumer
groups / 39 DLQs**. Any document stating other counts is stale and must be updated.

The 29th is `seller.suspension_amended`, added under D-11. It is audit-only, so it adds a
topic without adding a consumer group or a DLQ — which is why the group and DLQ counts do
not move with it. An earlier revision of this decision said 28; that was one behind.

## D-13 — Two-producer topics: **`listing.flagged` collapses to one producer; audit-family topics may have many**

> **Provenance:** this one is a controller ruling, not a product-owner ruling. It follows
> from D-03 and D-05 rather than adding anything new, which is why it was not escalated.
> Flagged to the product owner when made; override it if the reading is wrong.

`conventions/kafka-events.md:14` requires one producer per topic. Wave 1 found two topics
with two producers each. They are not the same case.

**`listing.flagged` — one producer: admin.** Both paths write an
`admin.moderation_case` row: the admin path is manual flagging (D-08), the seller path is
the soft tier's flag-on-create (D-05). D-03 makes the `admin` schema writable by the admin
module alone, so the seller path already has to route through the admin module's
application service — and the producer is the module that writes the row in the same
transaction as the outbox event. The two-producer table comes out; the two *call sites*
stay, both entering through admin.

**`pii.accessed` — many producers, legitimately.** Audit is a cross-cutting concern, not a
domain state change. It owns no schema, so sole-writer has nothing to say about it, and any
module that touches PII must be able to record that it did. Forcing it through one module
would either centralise every PII read or lose the events.

**The rule to state in `conventions/kafka-events.md` § 1**, replacing the flat
one-producer-per-topic sentence: a topic carrying a **domain state change** has exactly one
producer — the module that owns the schema the change was written to. A topic carrying
**audit or observability** records has as many producers as there are modules generating
them, and its schema is owned by the audit consumer rather than by any producer. Name which
family each existing topic belongs to, so the next editor does not have to infer it.

## D-14 — D-05's tier discriminator: **the matched term's stored enforcement, not the precision of the match**

> **Provenance:** like D-13, a controller ruling rather than a product-owner ruling, and
> this one **amends the wording of a signed-off decision** — D-05 above, and FR-P-06c with
> it. It was not escalated because it changes how the two tiers are told apart, not what
> either tier does: the hard tier still 422s with no listing, the soft tier still creates
> the listing `FLAGGED` with a `admin.moderation_case` row, and FR-A-03's input is
> unchanged. Flagged to the product owner when made. If the original reading was meant
> literally, override this and the design follows.

D-05 as signed off made **match precision** the discriminator: "exact hit on the hard
blocklist" against "fuzzy / keyword-suspicion match". Wave 1's C5 work found that
unimplementable in both directions:

- an admin cannot flag a precisely-spelled term they only want reviewed, because precise
  spelling forces the hard tier
- an admin cannot hard-block a pattern that has no single exact spelling, because a pattern
  forces the soft tier

The tier is therefore a property of **the blocklist term that matched** — each term stored
as blocking or flagging — and explicitly not of how precisely the text matched. Substring,
whole-word and pattern matching exist on both tiers — the three `match_type` values are
`SUBSTRING`, `WORD` and `REGEX`, and "exact" is not one of them. Where terms of both tiers match, the
strictest wins.

Design carries this as `admin.keyword_blocklist.enforcement` (`BLOCK` | `FLAG`), required,
no default, **independent of `match_type`** (`WORD` | `SUBSTRING` | `REGEX`).
`data-model-erd.md:668` states the independence and why conflating the two columns is the
mistake to avoid. `BRD.md:145` states the rule without naming a column or table, so the
requirement reads without opening a design document.

Recorded on the existing FR-P-06c amendment bullet at `BRD.md:278`, not as a second bullet
— the same requirement amended twice in one day's pass is one decision, and two bullets
would read as two.

**Consequence for later waves:** a document that still tiers by match precision is stale.
Wave 6 owes the blocklist screen an `enforcement` control (required, no default, so there
is currently no way to create a term through the UI) and must not present the choice as a
matching-precision setting.
