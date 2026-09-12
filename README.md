# AliceUT E-Commerce (Amazon Clone) — Global Multi-Vendor Marketplace

**Documentation repository**

AliceUT E-Commerce is a learning and portfolio project: a production-grade Amazon-inspired multi-vendor
marketplace built to demonstrate full-stack engineering patterns. This repository contains all
design documentation — requirements, technical specifications, UI design, and cross-phase
conventions — produced before implementation begins.

---

## What is in this repository

This is a **design-only repository**. Everything needed to start coding is here; The documents capture:

- A signed Business Requirements Document (BRD v1.2)
- User stories across all roles (buyer, seller, admin, platform)
- Full data model (PostgreSQL ERD + MongoDB collections)
- REST API contracts for all endpoints across modules, with sequence diagrams
- Kafka event catalog — topics, full Avro schemas, consumer groups, DLQ topology
- Docker Compose topology — services fully specified
- NestJS module architecture — hexagonal 4-layer, CQRS-lite, outbox pattern
- UI screen specifications — screens across three Angular portals
- Cross-phase conventions (auth/JWT, API standards, database migrations, design system, event
  envelope)

---

## Repository structure

```
aliceut-ecom-document/
├── architecture-overview.md        Project-level architecture and evolution path
│                                   (cross-phase reference; read this first)
│
├── conventions/                    Stable cross-phase technical decisions
│   ├── api-conventions.md          REST naming, money serialization, pagination, error shape
│   ├── auth-jwt-design.md          JWT access/refresh token spec, OAuth flows, guard matrix
│   ├── database-migrations.md      Raw-SQL migration conventions (TypeORM)
│   ├── design-system.md            Angular Material theme, 8px grid, shared component specs
│   ├── kafka-events.md             Event envelope, Avro BACKWARD compat rules
│   └── backend-module-architecture.md      Hexagonal 4-layer structure, CQRS-lite, outbox integration
│
├── phase-1/
│   ├── requirements/
│   │   ├── BRD.md                  Business Requirements Document v1.2 (signed off)
│   │   └── user-stories/
│   │       ├── README.md           Story index, dependency graph, sprint plan
│   │       ├── buyer.md            US-B-00 – US-B-15 (16 stories)
│   │       ├── seller.md           US-S-00 – US-S-11 (14 stories)
│   │       ├── admin.md            US-A-00 – US-A-06 (10 stories)
│   │       ├── platform.md         US-P-01 – US-P-19 (19 stories)
│   │       └── email-templates.md  ET-01 – ET-21 transactional email specs
│   │
│   ├── technical-design/
│   │   ├── api-design.md           Module index + guard matrix (entry point)
│   │   ├── api-design/             Per-module endpoint specs with sequence diagrams
│   │   │   ├── auth.md             Registration, login, OAuth, token rotation, password flows
│   │   │   ├── profile.md          Profile read/update, address book CRUD
│   │   │   ├── catalog.md          Category tree, product list/detail, public offer listing
│   │   │   ├── pricing.md          Effective price resolution, FX rate cache
│   │   │   ├── search.md           Full-text search with facets (Elasticsearch)
│   │   │   ├── cart.md             Cart CRUD, guest cart merge
│   │   │   ├── orders.md           Checkout (transactional), order list/detail
│   │   │   ├── seller.md           KYC, offer/inventory/product management, seller order ops
│   │   │   ├── admin.md            KYC decisions, seller suspension, moderation queue
│   │   │   ├── notifications.md    In-app notification list, mark read
│   │   │   └── health.md           Liveness/readiness probe
│   │   ├── data-model-erd.md       Full PostgreSQL ERD (module schemas, constraints, indexes)
│   │   ├── data-model-mongodb.md   MongoDB collections (audit logs, activity events)
│   │   ├── kafka-events.md         14 topics, Avro schemas, consumer groups, DLQ topology
│   │   ├── docker-compose-topology.md  13-service spec, volumes, networks, .env.example
│   │   ├── backend-module-architecture.md  Phase 1 module inventory, tiers, scheduled tasks
│   │
│   └── ui-design/
│       ├── buyer-portal.md         13 screens (home, search, PDP, cart, checkout, orders, auth)
│       ├── seller-portal.md        10 screens (dashboard, listings, orders, inventory, KYC)
│       ├── admin-portal.md         8 screens (dashboard, KYC queue, moderation, seller mgmt)
│       ├── navigation-routing.md   Route trees, 9 auth guards, guard matrix, TitleStrategy
│       └── design-system.md        (superseded by conventions/design-system.md)
│
└── phase-2/                        Future — K8s, real payments, reviews, analytics
    └──
```

`conventions/` holds decisions that apply to every phase. `phase-N/` directories hold
requirements and design for that specific delivery. Numeric prefix sorts phases by delivery
order.

---

## Technology stack

All choices are locked in BRD §12. Changes require a BRD amendment.

| Concern | Choice |
|---------|--------|
| Frontend | Angular + Angular Material |
| Backend | NestJS (modular monolith, microservice-ready) |
| Frontend repo | Nx monorepo — `apps/buyer-app`, `apps/seller-app`, `apps/admin-app` |
| Backend repo | Nx monorepo — `apps/api`, `apps/workers`, `libs/<module>/` |
| Primary database | PostgreSQL — transactional source of truth |
| Audit / activity | MongoDB — append-only, event-fed |
| Search | Elasticsearch / OpenSearch (self-hosted, single-node in V1) |
| Event bus | Apache Kafka (KRaft mode) + Confluent Schema Registry (Avro, BACKWARD compat) |
| Kafka management | `provectus/kafka-ui` |
| ORM | TypeORM with raw-SQL migrations + repository interfaces |
| Auth | Passport.js — local + Google + Facebook; JWT with refresh rotation |
| Object storage | MinIO (S3-compatible) — `product-images`, `kyc-documents`, `user-assets` |
| Money arithmetic | `decimal.js` or `Big.js` — JS `number` is forbidden for monetary values |
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

*Solo developer project. Quality over speed.*
