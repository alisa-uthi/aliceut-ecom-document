# Project Progress — AliceUT (Amazon Clone)

Daily log of work on this project. Newest entry on top. One entry per active day.

**How to update**
- At session end, or when a milestone lands, add a new dated section at the top (below this header).
- Keep each subsection to bullets. If a subsection is empty, omit it.
- Use ISO date `YYYY-MM-DD`.
- Each day gets an explicit `<a id="YYYY-MM-DD"></a>` anchor immediately above its heading so external links resolve reliably (GitHub also auto-anchors the heading, but the explicit id survives renderer differences). Add the new date to the **Index** below.

**Index**
- [2026-08-29c](#2026-08-29c) — Auth portal design, ET-21, diagram MD files.
- [2026-08-29b](#2026-08-29b) — Buyer story real-world validation: 3 critical fixes + 3 new stories + minor clarifications.
- [2026-08-29](#2026-08-29) — Buyer user story clarification + order lifecycle design + cross-doc consistency sweep.
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

<a id="2026-08-29c"></a>
## 2026-08-29 (session 3)
**Focus:** Auth portal design, ET-21 admin KYC alert, diagram source files.

**Done:**
- Locked auth portal separation: buyer (`/login`, `/register`), seller (`/seller/login`, `/seller/register`), admin (`/admin/login` only). Seller and admin portals: email/password only, no OAuth.
- Dual-role confirmed: one account may hold BUYER + SELLER; portals are independent entry points.
- ET-08 updated: CC admin on every auto-flag (passive moderation queue awareness).
- ET-21 added to V1: admin KYC alert fires on every KYC submit/resubmit; includes `review_by` SLA deadline (submitted_at + 3 business days).
- US-A-00b corrected: admin accounts seeded directly in database (not docker-compose); hashed password stored in DB.
- Created `phase-1/diagrams/` with 6 Mermaid source files (01–06), each with user story references and key invariants.
- Removed `flows.html`; diagrams now live in standalone MD files.
- Added `## Git Conventions` to CLAUDE.md: one-line commits only.

**Decisions:**
- OAuth-only buyer accounts must set local password (US-B-15) before accessing `/seller/register`.
- ADMIN role never co-held with BUYER or SELLER on the same account.

**Next:**
- Review seller.md and platform.md stories for real-world gaps (same pass as buyer session 2).
- Proceed to Phase 1 technical design once all story roles signed off.

---

<a id="2026-08-29b"></a>
## 2026-08-29 (session 2)
**Focus:** Buyer story real-world validation and gap remediation.

**Done:**
- Validated all 12 existing buyer stories against real-world e-commerce behavior.
- **Critical fix (US-B-06 vs US-B-09):** removed contradictory "CTA disabled while stale items exist" rule; aligned to US-B-09 skip-at-submit behavior.
- **Critical gap (US-B-01):** added email verification AC — email/password accounts cannot checkout until verified; OAuth pre-verified.
- **Added US-B-13** (Reset forgotten password): email link, 60-min TTL, no email enumeration, OAuth set-password variant.
- **Added US-B-14** (Manage delivery addresses): save/edit/delete, default address, checkout pre-fill, 10-address cap.
- **Added US-B-15** (Manage account profile): display name, change password, B2B business name, email read-only.
- **US-B-05 clarifications:** variant-level availability (badge + CTA update on variant select), B2B tier threshold display, imported rating tooltip.
- **US-B-03 note:** imported rating tooltip to prevent buyer confusion.
- **US-B-07:** replaced silent merge with toast; quantity-capped variation covered.
- **US-B-09 note:** guest checkout explicitly deferred to future phase.
- **US-B-11 note:** no cancel action in V1, placeholder text defined.
- Updated README.md: buyer count 11 → 15, total 39 → 43, sprint assignments updated, dependency graph updated.

**Decisions:**
- Email verification gates checkout only (not browsing/cart) — avoids hard friction at registration.
- Password reset uses no-enumeration response pattern (security).
- Address book max 10 per account — reasonable V1 cap.
- Email change deferred (requires re-verification flow not yet scoped).

**Next:**
- Review seller.md and admin.md stories for same real-world gaps.
- Proceed to Phase 1 technical design once all story roles signed off.

---

<a id="2026-08-29"></a>
## 2026-08-29
**Focus:** Order lifecycle design + cross-doc consistency.

**Done:**
- Refined buyer stories US-B-06 through US-B-12; added email-templates.md (ET-01–ET-04).
- Defined entity hierarchy: `Order` (buyer container) → `Fulfillment` (per seller) → `FulfillmentItem` (snapshotted line items). `OrderItem` removed everywhere.
- Defined `Order.placement_outcome` (`FULLY_PLACED` | `PARTIALLY_PLACED`, immutable) vs `Order.status` (derived from Fulfillment states, projected read model).
- Kafka events: `order.finalized` (once per Order), `fulfillment.placed/shipped/delivered/refunded` (per Fulfillment).
- Removed BRD §7 (stack/entities/events belong in architecture-overview + technical-design); renumbered §8–§13 → §7–§12; updated CLAUDE.md refs.
- Propagated all renames to `BRD.md`, `architecture-overview.md`, `seller.md`, `platform.md`, `email-templates.md`.

**Decisions:**
- Cart cleared only for placed fulfillments; skipped (inactive offer) + failed (stock) items remain in cart.
- `Order.status` is a projected read model value; `Order.placement_outcome` is the immutable checkout outcome.
- Email amounts converted to buyer's preferred currency via `fx_rate_used_at_capture`; templates stored as DB rows.

**Next:**
- Clarify remaining buyer stories US-B-01 through US-B-05.
- Review seller.md, admin.md, platform.md stories.
- Proceed to Phase 1 technical design after story sign-off.

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
