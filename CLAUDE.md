# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Current Project State

**Phase 1 design complete; implementation not started.** Requirements (`phase-1/requirements/BRD.md` v1.4, agreed 2026-08-19; amended 2026-09-14, 2026-09-22 and 2026-09-30 + `user-stories/`), technical design (`phase-1/technical-design/`) and UI design (`phase-1/ui-design/`) are all written and cross-aligned. No source code or build system yet.

**This repo holds specs, not task state.** Implementation status belongs in GitHub Issues + Milestones + a Project board, never in a checked-in backlog file — the reason `phase-1/backlog/` and `scripts/create-github-issues.ps1` were deleted (c805aed, 2026-09-19).

The decomposition lives in **`phase-N/tasks.csv`** as an **import seed**, which is a different thing from task state: `phase-1/tasks.csv` carries 136 rows (61 backend, 44 frontend, 13 migration, 18 infra) with their spec references, dependencies and sprint, and deliberately has **no status, assignee or progress column** — add one and it becomes the backlog file that was deleted. All 136 issues were imported on 2026-09-30 and linked to Project 3 `aliceut-ecom`.

`scripts/github-issues/` holds the tooling: `import-issues.sh --phase N` creates or updates the issues (matched by an `aliceut-task-id` marker, so re-runs never duplicate) and links each to the board; `validate-tasks.sh --phase N` checks a seed and must be clean before an import; `TEMPLATE.md` is the row contract and the procedure for decomposing a new phase. Issue bodies link to spec sections and never copy their text, so a spec edit cannot leave an issue stale. Change a task by editing the CSV and re-running — never by editing the issue.

Do not scaffold code unless user explicitly asks.

## Repo Layout

```
architecture-overview.md     project-level architecture and evolution path
README.md                    repo guide and document index
PROGRESS.md                  daily progress log
conventions/                 cross-phase technical conventions (API, auth/JWT, module structure,
│                            data lifecycle, DB migrations, Kafka event envelope, observability,
│                            Angular Material design system,
│                            aliceut-ecom-backend / aliceut-ecom-frontend coding standards)
guidelines/                  developer process docs (git workflow, testing guidelines,
│                            development flow / onboarding, subagent routing)
└── templates/               CLAUDE.md templates copied into the backend / frontend repos
phase-1/
├── requirements/        BRD.md + user-stories/ (buyer / seller / admin / platform)
├── technical-design/    phase-specific designs (ERD, API specs, module inventory, event catalog,
│                        compose topology, cleanup jobs, consumer field matrix)
├── ui-design/           phase-specific UI designs (portal wireframes, shared components,
│                        navigation routing)
├── diagrams/            Mermaid flow and lifecycle diagrams (01–06)
├── screens/             exported Figma screen images
└── tasks.csv            issue import seed for this phase (no status column — not a backlog)
scripts/github-issues/   issue importer + seed validator + task template
phase-2/                 (planned, not yet on disk: V2 scope — K8s, real payments, etc.)
```

Numeric `phase-N/` prefix sorts by delivery order. `conventions/` holds stable cross-phase technical decisions. `guidelines/` holds developer process docs (git, testing, onboarding). Requirements and technical design cleanly separated per phase.

**Sibling repos.** This document repo is one of four that must be cloned side by side: `aliceut-ecom-document`, `aliceut-ecom-backend`, `aliceut-ecom-frontend`, `aliceut-ecom-infra`. The `docker-compose.yml` and every config it mounts live in `aliceut-ecom-infra`, and its bind mounts are relative to that repo root — a different layout breaks compose (`architecture-overview.md § 10`, `guidelines/development-flow.md § 1`).

Solo developer, learning/portfolio project, no deadline — quality over speed.

## Authoritative Reference

`architecture-overview.md` is the project-level architecture and evolution reference. `phase-1/requirements/BRD.md` is the single source of truth for Phase 1 scope, stack, and resolved decisions. Always read both before proposing Phase 1 architecture, entities, or scope changes. §12 records the decisions currently in force: follow them by default rather than reopening them ad hoc, and when one genuinely needs to change, amend the BRD in the same pass so every document that cites it stays aligned.

## Design Reference

Figma file "AliceUT" is the authoritative UI/design source.
- URL: https://www.figma.com/design/F69ukaWjsqx4adgo26vDFQ/AliceUT
- fileKey: `F69ukaWjsqx4adgo26vDFQ`
- Skill for design system called `aliceut-design-system`

When UI/screen/component work is requested without a specified source, default to fetching from this file via Figma MCP tools (`get_design_context`, `get_metadata`, `get_screenshot`, `use_figma`). Load `/figma-design-to-code` skill before `get_design_context`; load `/figma-use` skill before `use_figma`.

## Progress Tracking

`PROGRESS.md` at repo root is the daily progress log. Read it at session start to see recent activity. Update it at session end (or when a meaningful milestone lands) with a new dated entry at the top. Keep entries concise — one bulleted list per section.

## Current Stack (BRD §12)

- **Frontend:** Angular 22+ + Angular Material
- **Backend:** NestJS 11+ (modular monolith, microservice-ready)
- **DBs:** PostgreSQL (transactional core) + MongoDB (activity/audit/high-write append data) + MinIO (store images and documents)
- **Search:** Elasticsearch/OpenSearch (self-hosted single-node)
- **Cache + short-lived token store:** Redis (`noeviction` on the instance holding single-use tokens — the 60s OAuth authorization code lives there; an eviction-enabled cache instance must be separate)
- **Event bus:** Apache Kafka (`apache/kafka:3.8.0`, KRaft mode) + Confluent Schema Registry (Avro, BACKWARD compat) + Kafka UI (`provectus/kafka-ui`)
- **ORM:** TypeORM with **raw-SQL migrations** (not decorator schema sync) + repository pattern behind interfaces for Tier 1 modules (portability requirement — NFR-18)
- **Auth:** Passport.js (local + Google + Facebook), JWT with refresh rotation
- **Deploy V1:** docker-compose. **V2:** Kubernetes + Istio, Kafka via Strimzi

Kafka runs in KRaft mode (no Zookeeper) to keep the local footprint down. Redpanda is not a substitute.

## Core Rules

### Money handling (FR-P-04, Risks §9)
- Storage: Postgres `NUMERIC(19,4)` + ISO 4217 code column. FX rates use `NUMERIC(19,8)`.
- App code: `decimal.js` or `Big.js`. **Never JS `number` for monetary math.**
- API JSON: amounts as **strings** (`"99.99"`), not numbers.
- Lint rule required: forbid `number` type on `*price*`, `*amount*`, `*tax*`, `*fee*` fields.
- Currency-specific scale (JPY=0, BHD=3) driven by `Currency.minor_unit_scale`; storage stays 4 fractional digits.

### Pricing model (FR-P-01)
```
Product → Offer (per seller, one currency) → Price (per price_type)
```
Currency lives on the offer (`catalog.offer.native_currency_code`), not on the price row — a second currency means a second offer. Cart/FulfillmentItem reference `Offer`, not `Product`. Never store price on `Product`.

Price types: `LIST`, `SALE` (time-bounded). No `B2B_TIER` in V1. PDP resolves effective price by price type + time — account type and quantity are not inputs.

### Order immutability (FR-P-03)
`FulfillmentItem` snapshots `unit_price`, `currency`, `tax`, `fx_rate_used_at_capture` at checkout. **Never re-derive historical amounts from live FX or current Price rows.**

### Event-driven writes (FR-P-09..P-13)
- Domain state changes (product, offer, inventory, order, KYC, moderation) publish to Kafka via **transactional outbox** (event row written in same Postgres tx as domain change; relay ships to Kafka).
- Search index (ES) updated **async from Kafka events**, not sync from API writes.
- Email/in-app notifications driven by Kafka consumers, not inline in handlers.
- Every event: `event_id` (UUID), `event_type`, `event_version`, `occurred_at`, `correlation_id`, `payload`.
- Consumers idempotent (dedupe on `event_id`), at-least-once, offset commit after side-effect, DLQ per consumer group.
- No cross-service DB reads — subscribe to events.

### V1 currencies
Seller pricing allowed: **USD, THB, JPY, SGD** only.

### Prohibited categories (FR-P-06c)
Weapons, drugs, adult content. Two tiers at listing time. The tier comes from the **stored `enforcement` of the blocklist term that matched** (`BLOCK` | `FLAG`), not from how precisely the text matched — `match_type` (`SUBSTRING` | `WORD` | `REGEX`) is an independent column and every matching mode exists on both tiers. Prohibited taxonomy node or a `BLOCK` term → **422 at submit, no listing created**; a `FLAG` term → listing **created** as `FLAGGED` with an `admin.moderation_case` row (this is FR-A-03's queue input). Strictest matched tier wins.

### B2B in V1
Same UX as B2C. Differentiation is branding only (badge, business logo on invoice, "Business" header tag). No bulk pricing/invoicing yet.

### Seed data
Kaggle "Amazon Product Data" dataset, curated to **100 products** across major categories. Architecture must still support 10k+ (NFR-03).

## Explicitly Out of Scope in V1 (BRD §3.2)

Do not implement unless user reopens scope: real payment gateway, real shipping, reviews/ratings, wishlist, recommendations, seller analytics, dispute mediation, commission/payout, i18n, native mobile, K8s, buyer email address change.
