# Cross-Document Alignment Audit — Fix Plan

**Date:** 2026-09-22  
**Scope:** Full chain — `phase-1/requirements/` (BRD + user stories) → `phase-1/technical-design/` (ERD, MongoDB, API contracts, Kafka events, module architecture, docker-compose, cleanup jobs) → `phase-1/ui-design/` → `phase-1/diagrams/`, with `architecture-overview.md` and `conventions/` as constraint sources.  
**Method:** Eight non-overlapping audit dimensions, run fresh. No prior findings or gap analyses used as evidence.  
**Status:** Findings complete. No fixes applied — this document is the plan, not a record of work done.  

**Totals:** 20 CRITICAL, 63 MAJOR, 15 MINOR, plus 19 uncounted enum-drift rows and an unreported set of API MINORs.

---

## 1. Coverage

All eight dimensions reported: BRD-vs-stories, data model (ERD + MongoDB), non-negotiable rules, Kafka/events, API contracts, UI design, infrastructure, meta/process.

**Not verified — carry into the next audit:**

- Non-broker Kafka image consistency across `docker-compose-topology.md`.
- Dedupe-TTL and refresh-token parity against the TTL indexes in `data-model-mongodb.md`.
- NFR owner traceability for NFR-02, NFR-05..NFR-08, NFR-11, NFR-16, NFR-17.

**Withheld, not missing:** a 20-row pairwise enum-drift table across the API contracts (one row of it is the `account_type` finding in Wave 5), all API-dimension MINOR findings, and four story ACs with no locatable endpoint behaviour — seller tax-ID country regex, admin re-suspension 409-vs-extend, admin seller-profile active listings, order-history pagination shape.

---

## 2. Root causes

Five causes explain most findings. Fixing symptoms without these produces the same drift again.

1. **`phase-1/requirements/user-stories/README.md:4` pinned to BRD v1.1** while `BRD.md:4` is v1.2. The 2026-09-14 amendments (offer-level currency, rating removal, `FulfillmentItem` rename) never reached the stories, and from there never reached the UI docs. Only stale BRD-version citation in the repo.
2. **The BRD was amended by appendix, not in place.** `BRD.md:270-271` record the changes; `:33`, `:97`, `:144`, `:257` still state the superseded rule. Readers hit the FR table before the amendment list.
3. **`architecture-overview.md` acts as an amendment channel.** Redis entered at `:67` under a "Locked in BRD §12" heading (`:60`) that the BRD does not support, then propagated to 14 files, a readiness probe, and the OAuth login path.
4. **The sole-writer rule was never checked against the design.** Stated in three documents, contradicted in four places (findings #1, #16, #17, #19).
5. **Event payloads are systematically too thin for their consumers** (findings #3, #6, #7, #16, #20, and `PATCH /seller/profile`). Three consumer families — search indexer, notification dispatcher, audit writer — are specified to read fields their events do not carry, in a design that forbids the DB read that would supply them. Search and notifications are both unbuildable as written, and they are the first two modules on the Phase 2 extraction path (`architecture-overview.md:214`).

---

## 3. Wave 0 — Decision gate

Ten calls requiring product-owner sign-off. Each is a signed-BRD constraint or contradicts one, so no design document can be corrected until it resolves. Complete all ten before touching any other file.

1. **Redis — authorize or remove.** Largest blast radius.
   - Authorize: BRD amendment adding it to §12, then `CLAUDE.md` Locked Stack, then fix `docker-compose-topology.md:762` — `--maxmemory-policy allkeys-lru` can evict the single-use 60s OAuth code; needs `noeviction` or a dedicated instance.
   - Remove: rewrite `api-design/auth.md:95,843` (OAuth code exchange), `conventions/auth-jwt-design.md:253` (per-request read), `api-design/health.md:42,94` (readiness probe, `"fatal": true`), `api-design/admin.md:63,66,67`, and 10 further files.
   - Closes #2.
2. **`B2B_TIER` — keep or drop.** `BRD.md:144`/`:257` make it mandatory; `BRD.md:85`/`:146` say branding-only with bulk pricing deferred. Every downstream design doc already assumes the narrow reading, so "drop" matches what exists. Mirrored at `CLAUDE.md:75` vs `:96`.
3. **Sole-writer rule — enforce or retire.** The architecture's central claim.
   - Enforce: route the seller module's write surface through owning modules' application services, give `offer.changed` a single producer, remove the cleanup-job cross-schema JOIN, move `CurrencyScaleCache` out of `libs/shared`.
   - Retire: drop the Phase 2 extraction premise at `architecture-overview.md:186,218`.
   - No middle option. Most consequential decision in the set. Governs #1, #16, #17, #19.
4. **NFR-18 scope.** Amend to "Tier 1 repositories only", or drop the Tier 2 direct-`Repository<T>` rule at `conventions/backend-module-architecture.md:145-146`. Six of eleven modules currently violate a signed NFR. Closes #18.
5. **Prohibited content — flag or block.** `BRD.md:145` flags at listing time; `api-design/seller.md:56` blocks submit with 422. If block wins, FR-A-03's flagged-listing queue needs a different input source or the story changes. Closes #14.
6. **Kafka image.** `docker-compose-topology.md:629-671` uses `apache/kafka:3.8.0`; `BRD.md:207` names `bitnami/kafka` KRaft or confluentinc. Amend the risk row (cheapest) or switch the image.
7. **Search fallback when Elasticsearch is down.** `user-stories/buyer.md:82-83` and `user-stories/platform.md:153` require a Postgres-served curated fallback. Nominate the endpoint (`GET /catalog/products` is the candidate) or cut the AC.
8. **Admin manual flagging.** Keep `POST /admin/moderation` (`api-design/admin.md:72,908`) and amend `user-stories/admin.md:66`, or cut the endpoint from V1.
9. **CSV bulk inventory preview.** Add a `dryRun` preview and commit-on-confirm, or amend `user-stories/seller.md:176-177,182`. Currently `api-design/seller.md:1185` commits on the single POST.
10. **Zero-stock auto-hide.** Implement the default filter in catalog list and search query, or amend `user-stories/seller.md:58`. Currently `api-design/catalog.md:264,342` never drops zero-stock offers and `api-design/search.md:260` only recomputes an `in_stock` facet.

**Clerical, same BRD pass — no decision needed:**

- Drop Prisma from `BRD.md:139` (FR-P-04a) and `BRD.md:178` (NFR-08); §12 #3 locks TypeORM.
- Fix `BRD.md:208` to BACKWARD compatibility; it currently prescribes forward-compat against §12 #9 (`BRD.md:261`).
- Drop Redpanda from `CLAUDE.md:59` and `architecture-overview.md:77`; §12 #8 chose Kafka with KRaft as the fallback.
- Fix `BRD.md:152` (FR-P-12) to all six envelope fields — it lists three, omitting `event_type`, `event_version`, `payload`.

---

## 4. Wave 1 — Make search and notifications buildable

Largest cluster. Blocks the two modules first on the extraction path. Both subsystems are unbuildable as specified.

1. **Write a consumer-field matrix** — every consumer, every field it must write, the event that supplies it. This artifact does not exist, which is why the gap went unseen. Do this first; it scopes the rest of the wave.
2. **Fatten `product.changed` and `offer.changed`.** `api-design/seller.md:1768,1906,698` publish `{product_id, seller_id, change_type}` and a thin offer subset; `api-design/search.md:256-263,242` says the consumer writes title, description, category, images, variants, offer prices and seller name, and forbids cross-module DB reads (#20).
3. **Add `product_id` to both inventory topics and publish absolute `available_qty`, not `released_qty`.** Fixes routing for `_update/:productId` (`api-design/search.md:347`) and idempotency under at-least-once redelivery in one change (#6).
4. **Add recipient identity to notification events** — the four fulfillment topics (ET-02/03/04/16) carry no buyer email or name; all three `auth.*` payloads lack `full_name`; ET-01 (FR-B-10) needs items, subtotal, shipping, tax, tracking and ETA, none present in `PlacedFulfillmentRef`. Delete the forbidden `buyer_id` lookup at `conventions/kafka-events.md:105-106`, which `kafka-events.md:366` prohibits. Nine of 22 templates currently render (#7).
5. **Add an outbox row to `PATCH /seller/profile`** — `api-design/seller.md:82-102` writes none, while `api-design/search.md:256-263` indexes `seller_name`. A renamed seller is permanently stale.
6. **Fix four producer/schema mismatches** (#3):
   - `seller.kyc.submitted` — `api-design/seller.md:318,571` keys the partition on `applicationId`; `conventions/kafka-events.md:37,95-103` declares `seller_id`. Wrong key breaks per-seller ordering.
   - `seller.kyc.decided` — `api-design/admin.md:276` omits required identity fields (`conventions/kafka-events.md:143-155`).
   - `offer.changed` — `api-design/admin.md:807,978` omit `product_id`, `seller_id`, `currency_code`, `prices` (`conventions/kafka-events.md:792-814`). Without `product_id` the ES write cannot be routed.
   - `inventory.low_stock` — `api-design/seller.md:1159,1264` is six fields short of `conventions/kafka-events.md:906-918`; every field is rendered by ET-15.
7. **Pick one audit consumer group name** — `conventions/backend-module-architecture.md:55` says `audit`, `:59` says `platform.audit`. `consumer_group` is half the primary key of `platform.processed_event` (`data-model-erd.md:744-751`) and names the DLQ, so two names means every audit event applied twice and DLQ messages landing in an unconsumed topic (#4).
8. **Remove the `outcome = FAILED` dedupe write** at `conventions/kafka-events.md:74,86-89`. It is inserted before the offset commit, so the replay the 14-day DLQ window exists for is discarded as a duplicate. DLQ is currently write-only (#5).
9. **Settle the `offer.changed` producer** — `conventions/backend-module-architecture.md:45` lists catalog, `:51` lists seller; `phase-1/technical-design/kafka-events.md:14` states a single-producer contract. Falls out of Wave 0 decision 3 (#16).

---

## 5. Wave 2 — Money correctness

Non-negotiable rules. Small diffs, no dependencies — run in parallel with Wave 1.

1. `conventions/backend-coding-standards.md:233` — delete `?? 2` for minor-unit scale; `:192` of the same file forbids it verbatim. JPY and BHD both wrong (#13).
2. `phase-1/ui-design/seller-portal.md:601,617-623,642,1024-1030,1049` — make currency read-only on the offer and delete the duplicate-by-currency validator. Reintroduces the dimension `BRD.md:271` deleted; `user-stories/platform.md:12` and `api-design/catalog.md:45` already follow the amendment (#11).
3. `phase-1/ui-design/seller-portal.md:1019-1030,737,740,744,749,787,788,792` — route all monetary input through `CurrencyInput` and all output through `PriceDisplay` (`shared-components.md:118,126,128`, `conventions/design-system.md:436`). Plain text inputs and raw interpolation bypass `Currency.minor_unit_scale`, so JPY renders `1000.0000` (#12).
4. `api-design/seller.md:944` — drop "in [currency]" from the one-LIST-price-per-offer message; contradicts `api-design/pricing.md:58`, `user-stories/seller.md:96` and `BRD.md:271`.
5. **FR-P-02 "estimated" label — three gaps, one fix.** Add `converted`/`estimatedFrom` inputs to `PriceDisplay` (`conventions/design-system.md:379-402` exposes only amount/currency/`saleEndsAt`), spec the badge once, and add `fxAsOf`/`fxStale` to the cart's converted totals (`api-design/cart.md:84,93-100` vs `user-stories/platform.md:34`). Required visible label per `BRD.md:136`.
6. Add `compareAtAmount` (the live LIST amount when `priceType = SALE`) to the offer object in `api-design/catalog.md:209-228` and `api-design/search.md:165-175`, so a SALE price has something to strike through per `user-stories/buyer.md:124`.

---

## 6. Wave 3 — Missing contracts

No design artifact exists for any of these. Net-new writing, so start early.

1. **Product images, both directions.** Add `POST /seller/products/images` (multipart to storage key) with the error states at `user-stories/seller.md:59-64`, and specify how `storageKey` becomes fetchable — public bucket path or presigned GET — in `api-design/catalog.md` and `api-design/search.md`. Today there is no upload route (`api-design/seller.md:1686,1703` defers to an "upload step" that exists nowhere; the only upload in the repo is `POST /profile/me/logo` at `api-design/profile.md:24`) and no read path (`catalog.md:160,208` and `search.md:164` return a raw MinIO `storageKey`). FR-S-03 and FR-B-05 are both Must (#8).
2. **Index inventory.** NFR-01 (≤2s p95), NFR-02 (≤500ms p95) and NFR-03 (10k headroom) have no design artifact; the forward reference at `data-model-erd.md:7` dangles.
3. **Error envelope `code` field.** `conventions/api-conventions.md:139-146` defines `{statusCode, error, message, errors[]}`, so the `Code` column at `:152-161` and the domain codes `PRICE_CHANGED` (`api-design/orders.md:210-217`), `SKU_NOT_FOUND` (`api-design/seller.md:1193`) and `OFFER_UNAVAILABLE` (`api-design/cart.md:413`) have nowhere to serialize. Every documented domain error code is unreachable by clients until this lands.
4. **Search error contract.** `api-design/search.md:129-228` declares no `Errors:` section — add 400 malformed cursor, 422 unsupported currency, 503 search unavailable. While in the file, add `fuzziness: AUTO` (or a dedicated analyzer) to the `multi_match` at `search.md:222`; the mapping at `search.md:56-111` has no n-gram field, so FR-B-02's headline AC — "sonny headphon" matching "Sony WH-1000XM5" (`user-stories/buyer.md:77-79`) — cannot pass.
5. **KYC document encryption boundary.** `BRD.md:179` (NFR-09) requires encryption at rest; `docker-compose-topology.md:701-722` configures no SSE or KMS and `architecture-overview.md:154` only marks the bucket private. Specify SSE-S3 on `kyc-documents` or name the app-layer boundary.
6. **`tax_id`** — encrypt at rest (`data-model-erd.md:593` stores plaintext) and drop it as a search parameter (`api-design/admin.md:138`). NFR-09 (#15).
7. **Acceptance criteria for 13 NFRs.** NFR-01/04/08/11/12/16/17/18 have none at all; NFR-02/03/05/09/10 are cited but not testably.

---

## 7. Wave 4 — Propagate the amendments

Fix the leak source first, then sweep. Running this before Wave 0 means sweeping twice.

1. **`phase-1/requirements/user-stories/README.md:4` — bump "BRD.md v1.1 (signed off 2026-08-19)" to v1.2 and cite the amendments.** Root cause of the entire rating split. Same line also mismatches the date (2026-08-19 is the §12 sign-off; the document date is 2026-08-29).
2. **Apply the rating amendment in place.** `BRD.md:270` removed it 2026-09-14, but `BRD.md:33` (§3.1) and `BRD.md:97` (FR-B-03) still list it; `user-stories/buyer.md:95,96,100,127` specify it as a V1 deliverable; `data-model-erd.md:243` keeps the field; `PROGRESS.md:308` records the star widget as delivered. `phase-1/ui-design/buyer-portal.md:86,219,315,317` is correct ("No rating filter") and the search contract has no `minRating`. Also fix the false claim at `api-design/search.md:151` that the ERD has no rating field.
3. **Amend the BRD in place for `B2B_TIER`** — `BRD.md:144`, `:257` per Wave 0 decision 2, and `CLAUDE.md:75`/`:96`. Appendix-only fixes do not land, because the FR table is read first.
4. **Checkout step count.** `phase-1/ui-design/buyer-portal.md:636` says 3 steps and is correct on the facts (`api-design/orders.md:125` takes no `shippingMethodId`). Fix `user-stories/buyer.md:190-191`, `phase-1/ui-design/navigation-routing.md:155` and `phase-1/diagrams/01-buyer-journey.md:60-61`, which all say 4.
5. **Reconcile the 17 user stories** specifying V1 capability no FR authorises.
6. **Realign diagram 04** — `c805aed` touched diagrams 01, 02, 03, 05 and 06 but not 04, which still uses prose labels and still carries the merged-seller-status bug.

---

## 8. Wave 5 — Convention consistency

Pick one rule each, state it once in `conventions/`, link from the rest.

1. **Idempotency key scope** — `api-design/orders.md:221` keys on `(buyer_id, key)`; `api-design/seller.md:1500,1597,2053` and `api-design/admin.md:11-15` key on `(actor_user_id, key)`; `conventions/api-conventions.md:210-213` picks neither.
2. **Ownership response — do this one even if the rest of the wave waits.** `api-design/profile.md:348,380-381,427-428` return 403 for another owner's row, confirming the row exists; the seller module returns 404 for exactly this reason (`api-design/seller.md:805,1427`). The 403 is an enumeration oracle. Make profile return 404 and state the rule once.
3. **DELETE status code** — `conventions/api-conventions.md:68-69` mandates 204 empty; `api-design/seller.md:1031` and `api-design/admin.md:1079` return 200 with a body. Allow 200 for soft-delete explicitly, or switch to 204.
4. **`GET /orders?status=`** — `api-design/orders.md:477-480` computes derived status after keyset pagination, so a filtered page returns fewer than `limit` rows and `hasMore` lies. Filter in SQL on stored `fulfillment_status`, or document it as client-side only. Against `conventions/api-conventions.md:76-132`.
5. **Suspended-seller allowlist** — stated twice and differently at `conventions/api-conventions.md:179` vs `phase-1/technical-design/api-design.md:64` + `api-design/seller.md:98`. One document, linked.
6. **Guard matrix** — add `SellerNotSuspendedGuard` to the KYC-resubmit row at `phase-1/technical-design/api-design.md:47`; `api-design/seller.md:545,552-553` runs it.
7. **`account_type`** — three vocabularies: `conventions/auth-jwt-design.md:45` (JWT claim), `user-stories/platform.md:92-95` (`BUYER`/`B2B_BUYER`/`SELLER` seed), `BRD.md:146` (prose). One enum in conventions, referenced everywhere. Pull the 19 remaining enum-drift rows before starting this item.
8. **Address shape** — one DTO. Add `phone` to `api-design/profile.md:241-256,295,321` (required optional per `user-stories/buyer.md:342`); `api-design/orders.md:517` already returns `"phone": "string | null"` in the order snapshot built from `identity.address`, claiming a field its source cannot supply. Field names drift three ways: `orders.md:509-518` uses `fullName`/`stateProvince`/`phone`.
9. **Validation gaps** — add a field-rules table for the `POST /orders` checkout DTO including a mask pattern and length for `maskedPaymentDetail` (FR-P-08 `BRD.md:148`, NFR-07 `BRD.md:177`); cap `guestItems[]` in `api-design/cart.md:381-384` at the 50-distinct-offer limit enforced at `cart.md:413`.
10. **Variant deletion** — `api-design/seller.md:1890-1891` only upserts `ON CONFLICT (product_id, sku)`. Define a delete path and a 409 guard when PENDING orders exist (`user-stories/seller.md:76`).
11. **`ADMIN_REMOVAL` on a flag-only path** — `api-design/admin.md:975` sets `status_changed_reason='ADMIN_REMOVAL'` while `admin.md:72` only moves the offer to `FLAGGED`.

---

## 9. Wave 6 — UI design documents

Independent of Waves 1–5 apart from the money items already in Wave 2.

1. **Rewrite theming on Material 3.** `conventions/design-system.md:102-121,132-154` uses `mat.define-palette`, `define-light-theme`, `all-component-themes` and `define-typography-config` — all removed in the locked Angular 22+ (`architecture-overview.md:64`). The section cannot compile, so nothing else in the UI docs can be trusted until it is rewritten on `mat.theme()` tokens. Pin the Material version in the doc (#10).
2. **Reconcile `conventions/frontend-coding-standards.md:29-43` to the three-app Nx layout.** It describes a single-app Angular CLI workspace rooted on `angular.json` with no `apps/*` and no `libs/`, against BRD §12 #12 (`BRD.md:264`) and `architecture-overview.md:205`. `phase-1/ui-design/shared-components.md:28` makes `conventions/` outrank the UI docs, so the wrong document currently wins every tie — fix before any other UI edit (#9).
3. **One `NotificationBell` item shape**, taken from `api-design/notifications.md`. Currently forks four ways: `conventions/design-system.md:548` (`n.message`), `shared-components.md:83,87` (no title/body), `seller-portal.md:1189-1190` (`n.title`/`n.body`), `seller-portal.md:63` (no output bindings). Also make the target route an input or an emitted event — `design-system.md:551` hardcodes an app-specific route, which a `libs/ui` component cannot know, so it breaks in seller-app and admin-app (`navigation-routing.md:248-252`).
4. **Bind `DataTable` cursor inputs/outputs** at `seller-portal.md:444,728,870,970` per `conventions/design-system.md:508-519` and `shared-components.md:149-158`. Tables currently render with no way to advance the cursor.
5. **Convert six `[(ngModel)]` uses to reactive form controls** — `seller-portal.md:458,665,670,884,900` and `conventions/frontend-coding-standards.md:583`, the last being inside the document that forbids it at `:303-366` (also `shared-components.md:261`).
6. **`EmptyState`** — `seller-portal.md:207-213` passes `actionLabel`/`actionRoute`, which `shared-components.md:143` and `conventions/design-system.md:604,609` exclude. Add the inputs or use the documented content slot.
7. **Seller dashboard** — the low-stock chips and recent-orders block at `seller-portal.md:394-399,414-422` have no data source; `api-design/seller.md:2137-2153` returns four counts. Add the endpoints or delete the regions, then spec empty/loading/error states. FR-S-08 currently appears satisfied by widgets that cannot be built.
8. **Skip link** — specified only for admin (`admin-portal.md:45,93`); absent from `buyer-portal.md` and `seller-portal.md` against `conventions/design-system.md:679-684`. Put the skip link and `#main-content` in the shared app-shell spec. WCAG 2.4.1.
9. **Add `sellerName` to the PDP offer object** in `api-design/catalog.md:209-228` — it exists only on `GET /catalog/products/:id/offers` (`catalog.md:291`), so the PDP cannot render it per `user-stories/buyer.md:124`.

---

## 10. Wave 7 — Hygiene

No dependencies, no risk. Batch as one commit.

1. **Delete `scripts/create-github-issues.ps1`.** Dead in every mode including `-DryRun`: `:44` points `$epicDir` at the deleted `phase-1/backlog/epic-breakdown`, `:73` throws under `$ErrorActionPreference = "Stop"` (`:42`), and the `-DryRun` branch at `:101` is never reached. GitHub Issues is now the status source.
2. **`PROGRESS.md`** — mark the 2026-09-13 entry superseded (`:40-43` cite the 22 deleted backlog files as delivered); replace the next step at `:52` that orders running the broken script; add a dated entry for `c805aed` (74 files, +8128/−9662) and the two later unlogged commits; reword the index line at `:32`; strike or date-qualify the unreproducible "211 issues dry-run clean" claim at `:49`; complete the index at `:31-33` or drop its own rule at `:9`; fix the diagram count and paths at `:83` (claims 3 under `diagrams/`, two exist at repo root); fix Angular 20+ at `:116` against the locked 22+.
3. **`CLAUDE.md`** — restate `:7` as design-complete with GitHub Issues as the status source and implementation next; add Redis per Wave 0 decision 1; add the `aliceut-ecom-infra` sibling repo to the layout (`architecture-overview.md:184`, `guidelines/development-flow.md:38,43,50,148` — bind mounts are relative to that repo root, so the repos must be cloned as siblings); add the five missing directories `phase-1/diagrams/`, `phase-1/screens/`, `phase-1/audits/`, `scripts/`, `guidelines/templates/`; delete the five-week-stale Prior-Session Context at `:105-107`; sync the out-of-scope list at `:103` to BRD §3.2 (omits buyer email change, `BRD.md:64`).
4. **`phase-1/audits/`** — this document begins satisfying `architecture-overview.md:241`. Add records for the four earlier audit commits (`892c7de`, `b106925`, `8d2e704`, `c805aed`), which landed their decisions inline, or narrow the row's claim.
5. **`phase-2/`** — listed in `CLAUDE.md:11-25` and `README.md:107`, absent on disk. Annotate as planned in both.
6. **Five dead email-template anchors** — `user-stories/buyer.md:308-312` link `email-templates.md#et-0N----…` with four hyphens; GitHub's slug keeps two, so every buyer email-trigger row lands at the top of the file. Replace `----` with `--` or add explicit `<a id="et-0N">` anchors.
7. **Compose build context** — `docker-compose-topology.md:63-64` builds `api`/`workers` from `./backend`; the compose file lives in `aliceut-ecom-infra`, so the path is `../aliceut-ecom-backend`.
8. **Logging env vars** — add `LOG_SENSITIVE_KEYS` to `.env.example` with its full default key list (required by `conventions/backend-coding-standards.md:519` and `conventions/observability.md:97`, absent from `docker-compose-topology.md:125-310`); pick one `LOG_MAX_BODY_BYTES` default (4096 at `docker-compose-topology.md:132` and `backend-coding-standards.md:520` vs 10000 at `conventions/observability.md:89`).
9. **`registeredJobs`** — `api-design/health.md:240,270` hardcodes 6; `conventions/backend-module-architecture.md:101-109` lists 7 scheduled tasks; `phase-1/technical-design/cleanup-jobs.md:17-26` lists 10 cleanup jobs. Derive the count and reconcile the three lists.
10. **Minor path and route fixes** — `conventions/frontend-coding-standards.md:400,412` uses `/auth/login` while every route doc uses `/login`; `phase-1/screens/` is documented nowhere (`CLAUDE.md:11-25`, `README.md:107`, `architecture-overview.md:225-241`); root `*.html` files are orphaned, referenced only by the inaccurate `PROGRESS.md:83`; `guidelines/testing-guidelines.md:682` names a non-existent `phase-1/seed/` and `guidelines/git-workflow.md:362` mandates updating a `CHANGELOG.md` that does not exist; `BRD.md:266` still frames backlog decomposition as pending.

---

## 11. Sequencing

1. **Wave 0 alone, first.** Every later wave depends on at least one of its decisions.
2. **Waves 1, 2 and 3 in parallel** — different files, no overlap.
3. **Wave 4 only after Wave 0 lands**, or the sweep runs twice.
4. **Waves 5, 6 and 7 any time after that.** Wave 7 is available whenever a cheap win is wanted.

Two preparatory items: close the unverified dedupe-TTL and `data-model-mongodb.md` TTL-index check before Wave 1, since it lands in the middle of the event work; pull the 19-row enum-drift table before Wave 5 item 7.

---

## 12. Findings index

The 20 CRITICAL findings, by the numbers used above.

1. **Sole-writer rule does not exist for four schemas** — `conventions/backend-module-architecture.md:41` and `architecture-overview.md:111` vs `api-design/seller.md:69-76,83-84,692-699,832-837`. Seller endpoints write `catalog.offer`, `catalog.product`, `catalog.product_variant`, `catalog.product_image`, `pricing.offer_price`, `inventory.stock` and read `admin.moderation_case`; `seller.md:692-699` inserts into three foreign schemas in one transaction. No `ApplicationService` appears anywhere in the document. Also breaks `conventions/backend-module-architecture.md:380-392` and the extraction premise at `architecture-overview.md:218`. *Confirmed independently by two dimensions.*
2. **Redis is mandatory, unauthorized, and falsely attributed to the BRD** — `architecture-overview.md:60` ("Locked in BRD §12") vs `:67`, `:151`, `:180`. BRD §12 has no Redis row; `grep -ci redis` returns 0 for both `BRD.md` and `CLAUDE.md`. Load-bearing at `api-design/auth.md:95,843`, `conventions/auth-jwt-design.md:253`, `api-design/health.md:42,94`, `api-design/admin.md:63,66,67`; 14 files total. `docker-compose-topology.md:762` can evict the OAuth code.
3. **Four Avro producer/schema mismatches** — see Wave 1 item 6 for the four citations.
4. **Audit consumer group has two names** — `conventions/backend-module-architecture.md:55` vs `:59`, against the `platform.processed_event` primary key at `data-model-erd.md:744-751`.
5. **DLQ path defeats its own replay** — `conventions/kafka-events.md:74,86-89`.
6. **Search indexing structurally non-idempotent** — `api-design/search.md:347` issues `_update/:productId` while neither inventory topic carries `product_id`; `released_qty` published where absolute `available_qty` is required.
7. **Notification recipients unresolvable by any permitted means** — `conventions/kafka-events.md:105-106` vs `:366`; four fulfillment topics, three `auth.*` payloads, and ET-01 all short of required fields, against the completeness claim at `kafka-events.md:625`. Nine of 22 templates render.
8. **Product images have no upload endpoint and no read path** — `api-design/seller.md:1686,1703`, `api-design/profile.md:24`, `api-design/catalog.md:160,208`, `api-design/search.md:164`, `user-stories/seller.md:51,59-64`. FR-S-03 and FR-B-05 both Must. *Confirmed independently by two dimensions.*
9. **Frontend conventions describe a single-app CLI workspace** — `conventions/frontend-coding-standards.md:29-43` vs `BRD.md:264` (§12 #12) and `architecture-overview.md:205`, with `shared-components.md:28` making the wrong document authoritative.
10. **Design system written against Angular Material M2** — `conventions/design-system.md:102-121,132-154` vs `architecture-overview.md:64`.
11. **Seller portal reintroduces per-price currency** — `phase-1/ui-design/seller-portal.md:601,617-623,642,1024-1030,1049` vs `BRD.md:271`, `user-stories/platform.md:12`, `api-design/catalog.md:45`.
12. **Money bypasses the money components** — `seller-portal.md:1019-1030,737,740,744,749,787,788,792` vs `shared-components.md:118,126,128` and `conventions/design-system.md:436`.
13. **Currency scale defaults to 2** — `conventions/backend-coding-standards.md:233` vs `:192`.
14. **Prohibited-content flag-versus-block conflict** — `BRD.md:145` vs `api-design/seller.md:56`.
15. **`tax_id` stored plaintext and searchable** — `data-model-erd.md:593` and `api-design/admin.md:138` vs `BRD.md:179` (NFR-09).
16. **Two modules produce `offer.changed`** — `conventions/backend-module-architecture.md:45` vs `:51`, against the single-producer contract at `phase-1/technical-design/kafka-events.md:14`.
17. **Cross-schema JOIN inside a scheduled job, deliberately** — `phase-1/technical-design/cleanup-jobs.md:390-391` joins `seller.seller_profile` to `identity.user`, and `:431` states the join exists to spare the consumer a cross-schema read. Against `conventions/backend-module-architecture.md:41` and `conventions/backend-coding-standards.md:743`.
18. **NFR-18's repository-interface rule unmet for 6 of 11 modules** — `BRD.md:188` vs `conventions/backend-module-architecture.md:145-146`, which mandates injecting `Repository<T>` directly in Tier 2 services; Tier 3 has no repositories.
19. **`libs/shared` reads `pricing.currency` by raw SQL** — `conventions/backend-coding-standards.md:237-240` (`CurrencyScaleCache`) vs `architecture-overview.md:203`, `architecture-overview.md:111`, and `conventions/backend-coding-standards.md:544-546`.
20. **Event payloads cannot build the ES document the search design specifies** — `api-design/seller.md:1768,1906,698` vs `api-design/search.md:256-263,242`.

MAJOR and MINOR findings are cited inline in Waves 0–7 above; each carries its own `path:line` on both sides.

---

## 13. Cross-dimension confirmations

Findings reached independently by more than one audit dimension, listed because independent arrival raises confidence:

- **Rating filter** — four dimensions.
- **Checkout step count** — three dimensions.
- **Sole-writer breach (#1)** — two dimensions.
- **Product-image gap (#8)** — two dimensions.
- **Redis (#2)** — two dimensions.
- **`B2B_TIER` contradiction** — two dimensions, both finding it confined to `BRD.md` and `CLAUDE.md` with every downstream doc already agreeing on the narrow reading.
- **Diagram 04** — one dimension plus commit evidence that `c805aed` skipped it.
