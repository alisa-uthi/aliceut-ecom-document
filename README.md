# AliceUT E-Commerce (Amazon Clone) — Global Multi-Vendor Marketplace

**Documentation repository**

AliceUT E-Commerce is a learning and portfolio project: a production-grade Amazon-inspired multi-vendor
marketplace built to demonstrate full-stack engineering patterns. This repository contains all
design documentation — requirements, technical specifications, UI design, and cross-phase
conventions — produced before implementation begins.

---

## What is in this repository

This is a **design-only repository**. Everything needed to start coding is here; the documents capture:

- A signed Business Requirements Document (BRD v1.2)
- User stories across all roles (buyer, seller, admin, platform)
- Full data model (PostgreSQL ERD + MongoDB collections)
- REST API contracts for all endpoints across modules, with sequence diagrams
- Kafka event catalog — topics, full Avro schemas, consumer groups, DLQ topology
- Docker Compose topology — 13 services fully specified
- NestJS module architecture — three tiers, CQRS-lite, transactional outbox pattern
- UI screen specifications — screens across three Angular portals + shared component library
- Flow diagrams — buyer journey, seller lifecycle, fulfillment state machine, auth portals
- Cross-phase conventions (auth/JWT, API standards, database migrations, design system, event envelope, observability)
- Developer guidelines (git workflow, testing pyramid, local setup, Claude Code subagent routing)

---

## Repository structure

```
aliceut-ecom-document/
├── CLAUDE.md                          Claude Code instructions for this repo
├── PROGRESS.md                        Daily progress log (newest entry on top)
├── architecture-overview.md           Project-level architecture and evolution path
│                                      (cross-phase reference; read this first)
│
├── conventions/                       Stable cross-phase technical decisions
│   ├── api-conventions.md             REST naming, money serialization, pagination, error shape
│   ├── auth-jwt-design.md             JWT access/refresh token spec, OAuth flows, guard matrix
│   ├── backend-coding-standards.md    TypeScript config, ESLint, money patterns, DTOs, errors
│   ├── backend-module-architecture.md Hexagonal tiers, CQRS-lite, outbox integration
│   ├── data-lifecycle.md              pg_cron cleanup job convention (cross-phase)
│   ├── database-migrations.md         Raw-SQL migration conventions (golang-migrate)
│   ├── design-system.md               Angular Material theme, 8px grid, shared component specs
│   ├── frontend-coding-standards.md   Angular project structure, state, forms, routing, performance
│   ├── kafka-events.md                Event envelope, Avro BACKWARD compat rules
│   └── observability.md               Structured logging, correlation ID, Grafana Alloy stack
│
├── guidelines/                        Developer process documentation
│   ├── development-flow.md            Developer onboarding, local setup, daily workflow (start here)
│   ├── git-workflow.md                Branching, commits, PR template, releases
│   ├── testing-guidelines.md          Test pyramid, coverage thresholds, Jest/Playwright patterns
│   ├── claude-code-subagents.md       Claude Code subagent routing — which agent for which task
│   └── templates/
│       ├── backend-CLAUDE.md          CLAUDE.md template — copy to aliceut-ecom-backend/ on clone
│       └── frontend-CLAUDE.md         CLAUDE.md template — copy to aliceut-ecom-frontend/ on clone
│
├── phase-1/
│   ├── requirements/
│   │   ├── BRD.md                     Business Requirements Document v1.2 (signed off 2026-08-19)
│   │   └── user-stories/
│   │       ├── README.md              Story index, dependency graph, sprint plan
│   │       ├── buyer.md               US-B-00 – US-B-15 (16 stories)
│   │       ├── seller.md              US-S-00 – US-S-11 (14 stories)
│   │       ├── admin.md               US-A-00 – US-A-06 (10 stories)
│   │       ├── platform.md            US-P-01 – US-P-19 (19 stories)
│   │       └── email-templates.md     ET-01 – ET-21 transactional email specs
│   │
│   ├── diagrams/                      Cross-cutting flow diagrams for Phase 1
│   │   ├── 01-buyer-journey.md        Buyer purchase flow (browse → cart → checkout → fulfillment)
│   │   ├── 02-seller-lifecycle.md     Seller account and KYC lifecycle
│   │   ├── 03-fulfillment-lifecycle.md Order fulfillment state machine
│   │   ├── 04-admin-moderation.md     Admin KYC and moderation decision flow
│   │   ├── 05-pricing-model.md        Product → Offer → Price pricing model
│   │   └── 06-auth-portals.md         Auth flows across buyer/seller/admin portals
│   │
│   ├── technical-design/
│   │   ├── api-design.md              Module index + guard matrix (entry point for API specs)
│   │   ├── api-design/                Per-module endpoint specs with sequence diagrams
│   │   │   ├── auth.md                Registration, login, OAuth, token rotation, password flows
│   │   │   ├── profile.md             Profile read/update, address book CRUD
│   │   │   ├── catalog.md             Category tree, product list/detail, public offer listing
│   │   │   ├── pricing.md             Effective price resolution, FX rate cache
│   │   │   ├── search.md              Full-text search with facets (Elasticsearch)
│   │   │   ├── cart.md                Cart CRUD, guest cart merge
│   │   │   ├── orders.md              Checkout (transactional), order list/detail
│   │   │   ├── seller.md              KYC, offer/inventory/product management, seller order ops
│   │   │   ├── admin.md               KYC decisions, seller suspension, moderation queue
│   │   │   ├── notifications.md       In-app notification list, mark read
│   │   │   └── health.md              Liveness/readiness probe
│   │   ├── backend-module-architecture.md  Phase 1 module inventory and tier assignments
│   │   ├── cleanup-jobs.md            Phase 1 pg_cron cleanup job implementations
│   │   ├── data-model-erd.md          Full PostgreSQL ERD (module schemas, constraints, indexes)
│   │   ├── data-model-mongodb.md      MongoDB collections (audit logs, activity events)
│   │   ├── docker-compose-topology.md 13-service spec, volumes, networks, .env.example
│   │   └── kafka-events.md            14 topics, Avro schemas, consumer groups, DLQ topology
│   │
│   └── ui-design/
│       ├── buyer-portal.md            13 screens (home, search, PDP, cart, checkout, orders, auth)
│       ├── seller-portal.md           10 screens (dashboard, listings, orders, inventory, KYC)
│       ├── admin-portal.md            8 screens (dashboard, KYC queue, moderation, seller mgmt)
│       ├── navigation-routing.md      Route trees, 9 auth guards, guard matrix, TitleStrategy
│       └── shared-components.md       libs/ui/ Angular component library spec
│
└── phase-2/                           Future — K8s, real payments, reviews, analytics
```

`conventions/` holds decisions that apply to every phase. `guidelines/` holds developer process docs. `phase-N/` directories hold requirements and design for that specific delivery. Numeric prefix sorts phases by delivery order.

---

## Technology stack

All choices are locked in BRD §12. Changes require a BRD amendment.

| Concern | Choice |
|---------|--------|
| Frontend | Angular 22+ + Angular Material |
| Backend | NestJS 11+ (modular monolith, microservice-ready) |
| Frontend repo | Nx monorepo — `apps/buyer-app`, `apps/seller-app`, `apps/admin-app` |
| Backend repo | Nx monorepo — `apps/api`, `apps/workers`, `libs/<module>/` |
| Primary database | PostgreSQL — transactional source of truth |
| Audit / activity | MongoDB — append-only, event-fed |
| Cache | Redis |
| Search | Elasticsearch / OpenSearch (self-hosted, single-node in V1) |
| Event bus | Apache Kafka + Confluent Schema Registry (Avro, BACKWARD compat) |
| Kafka management | `provectus/kafka-ui` |
| ORM | TypeORM with raw-SQL migrations + repository interfaces |
| Auth | Passport.js — local + Google + Facebook; JWT with refresh rotation |
| Object storage | MinIO (S3-compatible) — `product-images`, `kyc-documents`, `user-assets` |
| Money arithmetic | `decimal.js` — JS `number` is forbidden for monetary values |
| V1 deployment | Docker Compose (13 services) |
| V2+ deployment | Kubernetes + Istio; Kafka via Strimzi |

---

## Project goals

| Objective | Success indicator |
|-----------|-------------------|
| Demonstrate full-stack marketplace competency for portfolio | Deployable demo with all four personas usable end-to-end |
| Learn production patterns (auth, search, microservice-ready structure) | Codebase passes security and performance NFRs |
| Support 10,000+ products without redesign | Architecture validated by load test on seeded 100-product catalog |
| Provide realistic marketplace behavior for demo | Buyer can search → cart → checkout; seller can list → fulfill; admin can moderate |

---

## New developer start

1. Read [`architecture-overview.md`](architecture-overview.md) — project-level architecture.
2. Read [`phase-1/requirements/BRD.md`](phase-1/requirements/BRD.md) §12 — locked decisions.
3. Follow [`guidelines/development-flow.md`](guidelines/development-flow.md) — local setup, daily workflow.
4. Install Claude Code subagents: [`guidelines/claude-code-subagents.md`](guidelines/claude-code-subagents.md).

---

*Solo developer project. Quality over speed.*
