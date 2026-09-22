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
