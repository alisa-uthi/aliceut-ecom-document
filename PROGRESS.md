# Project Progress — AliceUT (Amazon Clone)

Daily log of work on this project. Newest entry on top. One entry per active day.

**How to update**
- At session end, or when a milestone lands, add a new dated section at the top (below this header).
- Keep each subsection to bullets. If a subsection is empty, omit it.
- Use ISO date `YYYY-MM-DD`.
- Each day gets an explicit `<a id="YYYY-MM-DD"></a>` anchor immediately above its heading so external links resolve reliably (GitHub also auto-anchors the heading, but the explicit id survives renderer differences). Add the new date to the **Index** below.

**Index**
- [2026-08-29](#2026-08-29) — Requirements deep-dive: order lifecycle, buyer story validation, auth portals, diagrams, BA revalidation.
- [2026-08-22](#2026-08-22) — Phase 1 architecture overview.
- [2026-08-19](#2026-08-19) — Requirements freeze + repo scaffolding.

**Entry template**
```
<a id="YYYY-MM-DD"></a>
## YYYY-MM-DD
**Focus:** one-line theme of the day.

**Done:**
- shipped or completed items

**Decisions:**
- locked choices (link to BRD § when relevant)

**Blockers:**
- what is stuck and why

**Next:**
- immediate next steps for the following session
```

<a id="2026-08-29"></a>
## 2026-08-29
**Focus:** Full requirements deep-dive across 4 sessions — order lifecycle, buyer story validation, auth portals & diagrams, BA revalidation.

**Done:**

_Order lifecycle & cross-doc consistency_
- Refined buyer stories US-B-06–US-B-12; added `email-templates.md` (ET-01–ET-04).
- Locked entity hierarchy: `Order` → `Fulfillment` (per seller) → `FulfillmentItem` (snapshotted). `OrderItem` removed everywhere.
- Defined `Order.placement_outcome` (immutable: `FULLY_PLACED` | `PARTIALLY_PLACED`) vs `Order.status` (projected read model).
- Kafka events: `order.finalized` (per Order), `fulfillment.placed/shipped/delivered/refunded` (per Fulfillment).
- Removed BRD §7 (content moved to architecture-overview + technical-design); renumbered §8–§12.

_Buyer story validation (39 → 43 → 59 stories total over the day)_
- Validated all buyer stories; fixed US-B-06 vs US-B-09 contradiction (skip-at-submit wins, not disabled CTA).
- US-B-01: email verification gates checkout (not browsing); OAuth accounts pre-verified.
- Added US-B-13 (password reset, 60-min TTL, no enumeration), US-B-14 (address book, 10-cap), US-B-15 (profile management).
- US-B-05: variant-level availability, B2B tier display, imported-rating tooltip.
- US-B-07: silent merge → toast; US-B-09: guest checkout deferred; US-B-11: no cancel in V1.

_Auth portals & diagram source files_
- Locked auth portal routes: buyer (`/login`, `/register`), seller (`/seller/login`, `/seller/register`), admin (`/admin/login` only). Seller + admin: email/password only, no OAuth.
- Dual-role confirmed: one account may hold BUYER + SELLER; ADMIN never co-held with either.
- ET-08: CC admin on every auto-flag. ET-21 added: admin KYC alert on submit/resubmit, `review_by` = submitted_at + 3 business days.
- US-A-00b: admin accounts seeded in DB (not docker-compose); hashed password in DB.
- Created `phase-1/diagrams/` — 6 Mermaid source files (01–06) with story refs + invariants; removed `flows.html`.
- Added Git conventions (one-line commits) to CLAUDE.md.

_BA revalidation (41 findings)_
- Full pass: 7 critical, 22 major, 12 minor. ERD criticals deferred to tech design.
- DIAG-01: email verification gate added to diagram 06-auth-portals (`email_verified` branch).
- README-01: added US-B-00, US-A-00b, US-P-17/18/19; total 54 → 59; sprint + dependency graph updated.
- Multi-role: `User.roles` is now an array; `SELLER_PENDING` removed in favour of `SellerProfile.kyc_status` gating.
- FX staleness: `staleness_threshold` aligned to 4 h (was 24 h) in implementation-specs.
- REAL-06 (US-B-09): second price-change rejection in plain behavior language.
- REAL-04 (US-P-17): concurrency-safety note on reservation expiry scheduler.
- REAL-09 (US-A-05): suspended-seller restriction rephrased as observable behavior; API guard spec added.

**Decisions:**
- Cart cleared only for placed fulfillments; skipped + failed items remain in cart.
- `Order.status` projected read model; `Order.placement_outcome` immutable checkout record.
- Email amounts use `fx_rate_used_at_capture`; templates stored as DB rows.
- Email verification gates checkout only — avoids hard friction at registration.
- Password reset: no-enumeration response pattern.
- OAuth-only buyer accounts must set local password (US-B-15) before accessing `/seller/register`.
- ERD structural corrections deferred to tech design phase.
- User stories stay behavior-only; implementation detail lives in implementation-specs.

**Next:**
- Begin Phase 1 technical design (`phase-1/technical-design/`).

---

<a id="2026-08-22"></a>
## 2026-08-22
**Focus:** Phase 1 technical-design kickoff.

**Done:**
- Added the project architecture overview, covering module boundaries, data ownership, event flows, deployment evolution, and Phase 1 scope boundaries.
- Marked the project architecture overview complete; detailed technical design continues within each phase.
- Aligned buyer-story UI criteria with the Buyer Portal mock without expanding the signed BRD scope.
- Added the Phase 1 ERD/data-model design for PostgreSQL module schemas, MongoDB audit/activity collections, order immutability, and outbox ownership.
- Clarified the V1 order lifecycle across buyer, seller, and platform stories: `PENDING → SHIPPED → DELIVERED`, with a full-refund transition from every post-payment status.

**Decisions:**
- V1 remains a NestJS modular monolith with PostgreSQL transaction/outbox ownership and Kafka integration seams.
- Later phases will extract domain modules into independently built and deployed Kubernetes services, moving to database-per-service incrementally.
- V1 backend will use a modular monorepo with module-owned code, contracts, schemas, migrations, and worker processes to preserve extraction seams.
- REST APIs will use a versioned OpenAPI contract generated from NestJS transport DTOs; Angular consumes an OpenAPI-generated TypeScript client.
- PostgreSQL 18+ uses native UUIDv7 identifiers for generated entities and events; audit timestamps remain explicit columns.
- Seller coupon-code promotions are deferred from Phase 1 and reserved for a future `promotion` module/schema with immutable order-redemption snapshots.
- Reusable buyer addresses are owned by Identity; Orders stores only an immutable checkout address snapshot.
- A tracking number is generated at order placement and retained at shipment; stock is restored only for a refund before shipment.

**Next:**
- Define OpenAPI endpoint contracts and Avro event/outbox details.

---

<a id="2026-08-19"></a>
## 2026-08-19
**Focus:** Requirements freeze + repo scaffolding for Phase 1.

**Done:**
- BRD v1.1 signed off (`phase-1/requirements/BRD.md`).
- User stories split by role into `phase-1/requirements/user-stories/` — 39 stories across buyer / seller / admin / platform, indexed by `README.md`.
- Linked Figma file "AliceUT" (`F69ukaWjsqx4adgo26vDFQ`) as authoritative design source; recorded in `CLAUDE.md` → *Design Reference*.
- Draft screens for "Buyer" in Figma

**Decisions:**
- Locked stack per BRD §7.1 / §13 — Angular + Angular Material, NestJS modular monolith, Postgres + Mongo, Elasticsearch, Kafka + Schema Registry, TypeORM w/ raw-SQL migrations, Passport.js + JWT, docker-compose V1 → K8s V2.
- V1 seller currencies restricted to USD / THB / JPY / SGD.
- Money storage `NUMERIC(19,4)` + ISO 4217; app-side `decimal.js`/`Big.js`; API amounts as strings.
- Pricing model: `Product → Offer → Price`; cart/order references `Offer`, never `Product`.
- Order line items snapshot `unit_price`, `currency`, `tax`, `fx_rate_used_at_capture` — never re-derive.
- All domain writes via Kafka **transactional outbox**; consumers idempotent, DLQ per group.

**Blockers:**
- None.

**Next:**
- Design UI and re-align with the user stories
- Kick off Phase 1 **technical design** in `phase-1/technical-design/` — architecture overview, ERD (Postgres + Mongo), API contracts, Kafka event schemas (Avro), outbox pattern doc.
- Backlog decomposition of the 39 user stories into implementation tasks.
- Confirm direction with user before writing any code.
