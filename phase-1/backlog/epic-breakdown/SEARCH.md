# EPIC: SEARCH — Search Module

**Sprint:** Directional — Sprints 12+ (not yet formally planned; groom each 2-sprint window before execution, per `sprint-plan.md`)  
**Total Tasks:** 14  

Elasticsearch-backed full-text product search with real-time index maintenance via Kafka consumers. All index writes are event-driven (async from domain events); no sync writes from the API.

---

## SEARCH-001 — Elasticsearch Products Index Mapping

- **US Ref:** US-B-02
- **Estimate:** L
- **Dependencies:** INFRA-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § Product search response shape, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- File: `libs/search/src/infrastructure/elasticsearch/index-bootstrap.service.ts`
- Document model: **not** a flat offer-per-document index. Per `api-design/search.md`'s response shape, the index is a per-**product** document with a nested `lowestOffer` (and, per module note below, the full active-offer set needed to recompute it) — mapping must support `productId`, `title`, `brand`, `categoryId`, `categoryPath`, `images`, nested offer/price fields, `inStock`, plus fields backing `facets.categories` and `facets.priceRange`
- Exact field list and types: derive from `api-design/search.md`'s documented response (`GET /search/products`) and the ES Index Maintenance section's per-event field updates — do not invent a separate flat schema
- Idempotent bootstrap: skip if index exists (catch `resource_already_exists_exception`)

**Done Criteria:**
- Workers start: `products` index exists in Elasticsearch with a mapping supporting every field in `GET /search/products`'s documented response
- Restarting workers does not fail (idempotent create)

---

## SEARCH-002 — SearchController: GET /search/products

- **US Ref:** US-B-02
- **Estimate:** L
- **Dependencies:** SEARCH-001
- **Spec References:** `phase-1/technical-design/api-design/search.md` § Product search

**Implementation Notes:**
- **Path corrected:** the documented endpoint is `GET /search/products`, not `GET /search`.
- Full query params, response shape, and sequence: see `api-design/search.md`'s Product search endpoint — do not restate the full contract here (params: `q`, `categoryId`, `priceMin`, `priceMax`, `currency`, `inStock`, `sortBy`, `limit`, `cursor`)
- `@Public()`; pagination via ES `search_after` (opaque cursor), not raw offset

**Done Criteria:**
- Per `api-design/search.md`'s response/error shape for `GET /search/products`
- Empty `q` returns all active products (browse mode)

---

## SEARCH-003 — ES Query Builder

- **US Ref:** US-B-03
- **Estimate:** L
- **Dependencies:** SEARCH-001
- **Spec References:** `phase-1/technical-design/api-design/search.md` § Product search sequence

**Implementation Notes:**
- Query construction (multi-match on title/brand/description, bool filters for status/seller_active/category/price/stock, sort, `search_after`, aggregations): see `api-design/search.md`'s sequence diagram note — do not restate the ES query body here
- Price filters (`priceMin`/`priceMax`) always resolved against the documented per-currency `display_prices`-style field, not a single USD-only field

**Done Criteria:**
- Per `api-design/search.md`'s sequence note for query construction
- Fuzzy title match returns relevant results for a near-miss query

---

## SEARCH-004 — Faceted Aggregations

- **US Ref:** US-B-03
- **Estimate:** M
- **Dependencies:** SEARCH-003
- **Spec References:** `phase-1/technical-design/api-design/search.md` § Product search response (`facets`)

**Implementation Notes:**
- Facet shape: see `api-design/search.md`'s response `facets.categories` (id/name/count) and `facets.priceRange` (min/max/currency + always-present display fields) — do not restate the exact JSON here

**Done Criteria:**
- Per `api-design/search.md`'s documented `facets` shape
- Category facet counts match live ES aggregation for the current filter set

---

## SEARCH-005 — Kafka Consumer: product.changed

- **US Ref:** US-P-11
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § product.changed, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- Consumer group: `search.product-changed` (per `api-design/search.md` — not an invented name)
- Behavior (upsert on create/update, delete on `REMOVED`, idempotency via `platform.processed_event`): see `api-design/search.md`'s `product.changed` sequence

**Done Criteria:**
- Per `api-design/search.md`'s `product.changed` sequence outcomes
- Duplicate event: idempotent (no double-apply)

---

## SEARCH-006 — Kafka Consumer: offer.changed

- **US Ref:** US-P-11
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § offer.changed

**Implementation Notes:**
- Consumer group: `search.offer-changed`
- Behavior (upsert/remove offer in the product document's nested offers, recompute `lowestOffer`, `inStock`; index only when seller `kyc_status = APPROVED` and `suspension_status = ACTIVE` per the event payload): see `api-design/search.md`'s `offer.changed` sequence

**Done Criteria:**
- Per `api-design/search.md`'s `offer.changed` sequence outcomes
- Offer from a non-approved/suspended seller is never indexed

---

## SEARCH-007 — Kafka Consumer: inventory.changed

- **US Ref:** US-P-11
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § inventory.changed and inventory.reservation_expired

**Implementation Notes:**
- Consumer group: `search.inventory-changed`
- Behavior (update `available_qty` on the affected offer, recompute `inStock`): see `api-design/search.md`'s combined inventory sequence

**Done Criteria:**
- Stock reduced to 0 → `inStock` recalculated per product (false only if no other in-stock offers remain)

---

## SEARCH-008 — Kafka Consumer: seller.suspended

- **US Ref:** US-A-05
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § seller.suspended and seller.reinstated / seller.suspension_expired

**Implementation Notes:**
- Consumer group: `search.seller-suspended`
- Behavior (bulk set `seller_active = false` for all `offer_ids` in the event payload; recalculate `inStock` per affected product): see `api-design/search.md`'s seller-suspension sequence

**Done Criteria:**
- Seller suspended → all their offers excluded from search within 2s

---

## SEARCH-009 — Kafka Consumer: seller.reinstated / seller.suspension_expired

- **US Ref:** US-A-05b
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § seller.suspended and seller.reinstated / seller.suspension_expired

**Implementation Notes:**
- Consumer groups: `search.seller-reinstated` (manual reinstatement), `search.suspension-expired` (timed expiry via Workers scheduler)
- Behavior (bulk restore `seller_active = true` for SUSPENSION-deactivated offers): see `api-design/search.md`'s reinstatement/expiry sequence branches

**Done Criteria:**
- Reinstated seller's offers reappear in search results

---

## SEARCH-010 — Kafka Consumer: moderation.listing.removed

- **US Ref:** US-A-04
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § moderation.listing.removed and listing.soft_deleted

**Implementation Notes:**
- **Consumer group name corrected:** `search.listing-removed` (not `search.moderation-removed`) — per `api-design/search.md`
- Behavior (remove seller's offer from the product's nested offers; delete the product document entirely if no active offers remain): see `api-design/search.md`'s moderation-removal sequence branch

**Done Criteria:**
- Admin removes listing → offer removed from search; product document deleted if it was the last active offer
- Idempotent: removing an already-removed offer is a no-op, no error

---

## SEARCH-011 — Kafka Consumer: listing.soft_deleted

- **US Ref:** US-P-11
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § moderation.listing.removed and listing.soft_deleted

**Implementation Notes:**
- Consumer group: `search.listing-soft-deleted`
- Behavior: unconditional product document delete (US-P-11), idempotent if the document is already absent — see `api-design/search.md`'s soft-delete sequence branch

**Done Criteria:**
- Seller soft-deletes own listing → product document deleted from ES
- Deleting an already-deleted document: no error

---

## SEARCH-012 — Kafka Consumer: fx_rate.updated

- **US Ref:** US-P-02
- **Estimate:** L
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § fx_rate.updated, PRICING-008

**Implementation Notes:**
- Consumer group: `search.fx-rate-updated`
- Behavior (bulk-refresh display prices for all offer documents priced in the event's `base_currency`, decimal-safe): see `api-design/search.md`'s `fx_rate.updated` sequence
- Produced by PRICING-008's hourly FX refresh scheduler

**Done Criteria:**
- Changed FX rate → affected offer documents' display prices refreshed within 2s

---

## SEARCH-013 — Kafka Consumer: inventory.reservation_expired

- **US Ref:** US-P-17
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/api-design/search.md` § inventory.changed and inventory.reservation_expired

**Implementation Notes:**
- Consumer group: `search.reservation-expired`
- Behavior (update `available_qty` after a reservation is released by the Workers expiry scheduler; recompute `inStock`): see `api-design/search.md`'s combined inventory sequence, `inventory.reservation_expired` branch

**Done Criteria:**
- Expired reservation released → `available_qty` increases in ES; `inStock` recalculated if it was previously 0

---

## SEARCH-014 — ES Unavailable Fallback

- **US Ref:** US-B-02
- **Estimate:** M
- **Dependencies:** SEARCH-002
- **Spec References:** `phase-1/technical-design/api-design/search.md`

**Implementation Notes:**
- When Elasticsearch is unreachable: `GET /search/products` returns a structured 503 rather than an unhandled 500
- On an **empty query** (`q` absent/blank) specifically, fall back to a featured-products list read directly from Postgres (`catalog.product`/`catalog.offer`) so the homepage/browse experience degrades gracefully instead of failing outright

**Done Criteria:**
- ES down + empty query → 200 with Postgres-backed featured-products fallback
- ES down + non-empty query → structured 503, not a raw 500

---

## Notes / Flagged Discrepancies (not silently resolved)

- **Task inventory expanded from 8 to 14 to match `backlog.md`.** The prior draft merged several of `backlog.md`'s discrete Kafka-consumer tasks (e.g. old SEARCH-004 combined `seller.suspended` + `seller.reinstated`/`seller.suspension_expired` into one task; old SEARCH-006 combined the query controller, query builder, and facets into one), used wrong/invented consumer group names, and was missing consumers entirely for `offer.changed`, `listing.soft_deleted`, `fx_rate.updated`, and `inventory.reservation_expired`, plus the ES-unavailable-fallback task. Rewritten to `backlog.md`'s exact SEARCH-001…014 task IDs, titles, dependencies, and US-refs.
- **Endpoint path corrected:** `GET /search/products`, not `GET /search` — per `api-design/search.md`'s Endpoint Index (the only documented Search endpoint).
- **Document model corrected:** the index is a per-product document with a nested `lowestOffer`/offers structure (per `api-design/search.md`'s response shape), not the prior draft's flat offer-per-document model with `price_usd`/`prices` fields.
- **Consumer group names corrected to the 10 confirmed in `api-design/search.md`:** `search.product-changed`, `search.offer-changed`, `search.inventory-changed`, `search.reservation-expired`, `search.seller-suspended`, `search.seller-reinstated`, `search.suspension-expired`, `search.listing-removed` (was wrongly `search.moderation-removed`), `search.listing-soft-deleted`, `search.fx-rate-updated`.
- **Removed — out of scope, no counterpart in `backlog.md` or `api-design/search.md`:** the prior draft's SEARCH-007 (autocomplete `GET /search/suggest`) and SEARCH-008 (admin `POST /admin/search/reindex`). Neither appears in `backlog.md`'s canonical SEARCH task list nor in `api-design/search.md`'s Endpoint Index. Dropped rather than built; flagged in case a spec owner intended them as future scope.
- **Sprint header corrected to directional/ungroomed status** per `sprint-plan.md`'s "Sprints 12+ (directional, not formally planned)" note, rather than a fixed sprint number.
