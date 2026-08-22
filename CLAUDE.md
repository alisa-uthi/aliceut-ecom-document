# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current Project State

**Pre-implementation.** Repo contains `architecture-overview.md`, `phase-1/requirements/BRD.md` (v1.1, signed off 2026-08-19), and `phase-1/requirements/user-stories/` (39 stories, split by role: buyer/seller/admin/platform). No source code or build system yet. Next phase per BRD §12: detailed design (→ `phase-1/technical-design/`) + backlog decomposition. Do not scaffold code unless user explicitly asks.

## Repo Layout

```
architecture-overview.md     project-level architecture and evolution path
phase-1/
├── requirements/
│   ├── BRD.md
│   └── user-stories/     README.md (index) + buyer.md, seller.md, admin.md, platform.md
└── technical-design/     ERD, API specs, event schemas, and other Phase 1 detail
phase-2/                  (future: V2 scope — K8s, real payments, etc.)
```

Numeric `phase-N/` prefix sorts by delivery order. Requirements and technical design cleanly separated per phase.

Solo developer, learning/portfolio project, no deadline — quality over speed.

## Authoritative Reference

`architecture-overview.md` is the project-level architecture and evolution reference. `phase-1/requirements/BRD.md` is the single source of truth for Phase 1 scope, stack, and locked decisions. Always read both before proposing Phase 1 architecture, entities, or scope changes. Every BRD decision in §13 is signed off — treat as constraints, not suggestions.

## Design Reference

Figma file "AliceUT" is the authoritative UI/design source.
- URL: https://www.figma.com/design/F69ukaWjsqx4adgo26vDFQ/AliceUT
- fileKey: `F69ukaWjsqx4adgo26vDFQ`
- Skill for design system called `aliceut-design-system`

When UI/screen/component work is requested without a specified source, default to fetching from this file via Figma MCP tools (`get_design_context`, `get_metadata`, `get_screenshot`, `use_figma`). Load `/figma-design-to-code` skill before `get_design_context`; load `/figma-use` skill before `use_figma`.

## Progress Tracking

`PROGRESS.md` at repo root is the daily progress log. Read it at session start to see recent activity. Update it at session end (or when a meaningful milestone lands) with a new dated entry at the top. Keep entries concise — one bulleted list per section.

## Locked Stack (BRD §7.1, §13)

- **Frontend:** Angular + Angular Material
- **Backend:** NestJS (modular monolith, microservice-ready)
- **DBs:** PostgreSQL (transactional core) + MongoDB (activity/audit/high-write append data)
- **Search:** Elasticsearch/OpenSearch (self-hosted single-node)
- **Event bus:** Apache Kafka + Confluent Schema Registry (Avro, BACKWARD compat) + Kafka UI (`provectus/kafka-ui`)
- **ORM:** TypeORM with **raw-SQL migrations** (not decorator schema sync) + repository pattern behind interfaces (portability requirement — NFR-18)
- **Auth:** Passport.js (local + Google + Facebook), JWT with refresh rotation
- **Deploy V1:** docker-compose. **V2:** Kubernetes + Istio, Kafka via Strimzi

Redpanda / KRaft mode acceptable substitute if Kafka+Zookeeper too heavy.

## Non-Negotiable Rules

### Money handling (FR-P-04, Risks §10)
- Storage: Postgres `NUMERIC(19,4)` + ISO 4217 code column. FX rates use `NUMERIC(19,8)`.
- App code: `decimal.js` or `Big.js`. **Never JS `number` for monetary math.**
- API JSON: amounts as **strings** (`"99.99"`), not numbers.
- Lint rule required: forbid `number` type on `*price*`, `*amount*`, `*tax*`, `*fee*` fields.
- Currency-specific scale (JPY=0, BHD=3) driven by `Currency.minor_unit_scale`; storage stays 4 fractional digits.

### Pricing model (FR-P-01, §7.2)
```
Product → Offer (per seller) → Price (per currency, per price_type)
```
Cart/OrderItem reference `Offer`, not `Product`. Never store price on `Product`.

Price types: `LIST`, `SALE` (time-bounded), `B2B_TIER` (min_qty). PDP resolves effective price by account type + time + qty.

### Order immutability (FR-P-03)
`OrderItem` snapshots `unit_price`, `currency`, `tax`, `fx_rate_used_at_capture` at checkout. **Never re-derive historical amounts from live FX or current Price rows.**

### Event-driven writes (FR-P-09..P-13)
- Domain state changes (product, offer, inventory, order, KYC, moderation) publish to Kafka via **transactional outbox** (event row written in same Postgres tx as domain change; relay ships to Kafka).
- Search index (ES) updated **async from Kafka events**, not sync from API writes.
- Email/in-app notifications driven by Kafka consumers, not inline in handlers.
- Every event: `event_id` (UUID), `event_type`, `event_version`, `occurred_at`, `correlation_id`, `payload`.
- Consumers idempotent (dedupe on `event_id`), at-least-once, offset commit after side-effect, DLQ per consumer group.
- No cross-service DB reads — subscribe to events.

### V1 currencies
Seller pricing allowed: **USD, THB, JPY, SGD** only.

### Prohibited categories
Weapons, drugs, adult content. Moderation flags on taxonomy + keyword blocklist at listing time.

### B2B in V1
Same UX as B2C. Differentiation is branding only (badge, business logo on invoice, "Business" header tag). No bulk pricing/invoicing yet.

### Seed data
Kaggle "Amazon Product Data" dataset, curated to **100 products** across major categories. Architecture must still support 10k+ (NFR-03).

## Explicitly Out of Scope in V1 (BRD §3.2)

Do not implement unless user reopens scope: real payment gateway, real shipping, reviews/ratings, wishlist, recommendations, seller analytics, dispute mediation, commission/payout, i18n, native mobile, K8s.

## Prior-Session Context

Previous session (2026-08-19 21:09–22:01) ran BRD gathering with user acting as product owner. Session ended with "I'll continue in next session." Next expected activity: design phase kickoff or task decomposition. Confirm direction before writing code.
