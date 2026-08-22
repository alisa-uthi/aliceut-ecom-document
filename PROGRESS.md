# Project Progress — AliceUT (Amazon Clone)

Daily log of work on this project. Newest entry on top. One entry per active day.

**How to update**
- At session end, or when a milestone lands, add a new dated section at the top (below this header).
- Keep each subsection to bullets. If a subsection is empty, omit it.
- Use ISO date `YYYY-MM-DD`.
- Each day gets an explicit `<a id="YYYY-MM-DD"></a>` anchor immediately above its heading so external links resolve reliably (GitHub also auto-anchors the heading, but the explicit id survives renderer differences). Add the new date to the **Index** below.

**Index**
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
