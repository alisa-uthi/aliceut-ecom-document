# AliceUT E-Commerce (Amazon Clone) Architecture Overview

**Status:** Complete  
**Scope:** Project-level architecture and evolution path. Per-phase implementation detail lives in `phase-N/technical-design/`.

---

## Summary

- [1. Architecture goals](#architecture-goals)
- [2. System overview](#system-overview)
- [3. Project evolution](#project-evolution)
- [4. Technology stack](#technology-stack)
- [5. Application modules](#application-modules)
- [6. Architectural patterns](#architectural-patterns)
- [7. Architectural invariants](#architectural-invariants)
- [8. Data architecture](#data-architecture)
- [9. External integration boundaries](#external-integration-boundaries)
- [10. Deployment topology](#deployment-topology)
- [11. Quality attributes](#quality-attributes)
- [12. Implementation structure](#implementation-structure)
- [13. Service extraction roadmap](#service-extraction-roadmap)
- [14. Phase-specific design documents](#phase-specific-design-documents)

<a id="architecture-goals"></a>
## 1. Architecture goals

- Deliver buyer, seller, and admin experiences as three separate Angular portal applications backed by one NestJS API.
- Keep transactional state strongly consistent while supporting asynchronous search and notifications.
- Make module ownership and contracts explicit so modules can be extracted later without redesigning the data model or breaking API consumers.
- Preserve monetary precision and the exact price captured at checkout, across all phases.
- Run a complete local/demo environment with Docker Compose in Phase 1; graduate to Kubernetes in later phases.

<a id="system-overview"></a>
## 2. System overview

AliceUT E-Commerce is a multi-sided marketplace connecting buyers, sellers, and platform administrators. Mimic Amazon website for learning purpose only.

- **Buyers** browse a product catalog, add items to cart, and complete checkout. Purchases group into per-seller fulfillments with shipping and payment processing.
- **Sellers** onboard via KYC, manage product listings and offers, set prices in supported currencies, and fulfill orders.
- **Admins** review KYC applications, moderate listings, and manage seller suspension.

Three Angular applications — buyer storefront, seller portal, and admin portal — are the only browser clients. Each targets the same versioned NestJS REST API.

<a id="project-evolution"></a>
## 3. Project evolution

Signed requirements currently cover Phase 1 only. This overview defines the architectural direction for the whole project while marking phase-specific implementation choices explicitly.

| Stage | Architecture state |
|---|---|
| Phase 1 | Angular clients + NestJS modular monolith. One PostgreSQL database partitioned by module schema. Kafka event bus with transactional outbox. Elasticsearch for search. MongoDB for audit/activity. Docker Compose deployment. |
| Phase 2+ | Modules extracted incrementally into independently deployed Kubernetes services. Database-per-service. Kafka via Strimzi. Service mesh via Istio. Real payment gateway, carrier shipping, and advanced features per approved requirements. |

Future product scope is governed by its phase requirements document. This overview does not itself approve a new feature or reopen signed requirements.

<a id="technology-stack"></a>
## 4. Technology stack

Locked in BRD §12. Not revisable without a BRD amendment.

| Concern | Choice                                                                          |
|---|---------------------------------------------------------------------------------|
| Frontend | Angular 22+ + Angular Material                                                  |
| Backend | NestJS 11+ (modular monolith, microservice-ready)                               |
| Primary DB | PostgreSQL (transactional source of truth)                                      |
| Audit / activity | MongoDB (append-only, event-fed)                                                |
| Search | Elasticsearch / OpenSearch (self-hosted, single-node in V1)                     |
| Event bus | Apache Kafka + Confluent Schema Registry (Avro, BACKWARD compat) + Kafka UI     |
| ORM | TypeORM with raw-SQL migrations + repository interfaces                         |
| Auth | Passport.js (local + Google + Facebook), JWT with refresh rotation              |
| Object storage | MinIO (S3-compatible; `product-images`, `kyc-documents`, `user-assets` buckets) |
| V1 deploy | Docker Compose                                                                  |
| V2+ deploy | Kubernetes + Istio; Kafka via Strimzi                                           |

Redpanda / KRaft mode is an acceptable substitute if Kafka + ZooKeeper is too heavy for local development.

<a id="application-modules"></a>
## 5. Application modules

These bounded contexts are stable across all phases. Module boundaries, PostgreSQL schemas, and Kafka contracts are extraction seams — the same contracts persist when a module becomes an independent service.

| Module | Responsibilities |
|---|---|
| Identity | Registration, local/OAuth login, JWT refresh rotation, account roles, address book |
| Catalog | Product taxonomy, variants, seller offers, moderation state |
| Pricing | Price rows, effective-price resolution, display-only FX rates |
| Inventory | Seller stock, reservation, low-stock state |
| Search | Search API and facets over the denormalized product index |
| Cart | Guest (browser) and authenticated (server) carts; merge on login |
| Checkout and Orders | Address, shipping/payment, inventory reservation, immutable orders and fulfillments |
| Seller | KYC application, listing and fulfillment operations |
| Administration | KYC decisions and catalog moderation |
| Notifications | Email and in-app notification projections |
| Platform | Outbox relay, event envelope, idempotency, DLQ handling, audit logging |

Modules communicate in-process through application interfaces for synchronous commands and queries in Phase 1. Every domain state change that needs external propagation writes an outbox record in the same PostgreSQL transaction; the relay publishes it to Kafka.

<a id="architectural-patterns"></a>
## 6. Architectural patterns

### Transactional outbox

Every domain state change (catalog, price, inventory, order, KYC, moderation) writes both its domain rows and a `platform.outbox_event` row in one PostgreSQL transaction. An outbox relay process polls pending events and publishes to Kafka. Downstream consumers (search indexer, notification dispatcher, audit writer) are idempotent and deduplicate on `event_id`.

This prevents lost events without distributed transactions and is the primary extraction seam for later microservice decomposition.

### Module ownership contract

A module is the sole writer of its PostgreSQL schema. Other modules may read via its application interface (in-process, Phase 1) or Kafka projections (extracted service, Phase 2+). Cross-schema foreign keys are permitted only for essential transactional references documented in the data model ERD. No module reads another module's tables directly.

### Eventual consistency for search

The Elasticsearch index is rebuilt from Kafka events. It is a read model and may lag the PostgreSQL source of truth by up to the defined SLA (target: ≤5 s p95). API writes never wait for indexing.

### Effective-price resolution

Price is never stored on `Product`. The hierarchy is `Product → Offer (per seller) → Price (per currency, per price_type)`. Cart and fulfillment items reference `Offer`. At checkout, `FulfillmentItem` snapshots `unit_price`, `currency`, `tax`, and `fx_rate_used_at_capture`. Historical orders never re-derive amounts from live FX or current price rows.

<a id="architectural-invariants"></a>
## 7. Architectural invariants

These rules apply in all phases and cannot be relaxed without a BRD amendment.

**Money handling**
- Storage: `NUMERIC(19,4)` + ISO 4217 currency code column. FX rates: `NUMERIC(19,8)`.
- App code: `decimal.js` or `Big.js`. Never JS `number` for monetary math.
- API JSON: amounts as strings (`"99.99"`), never numbers.
- Currency-specific display scale driven by `Currency.minor_unit_scale`; storage always uses 4 fractional digits.

**Order immutability**
`FulfillmentItem` snapshots are written once at checkout. Unit price, currency, tax, and FX rate are never recalculated from current data after the transaction commits.

**Event envelope**
Every Kafka event carries: `event_id` (UUIDv7), `event_type`, `event_version`, `occurred_at`, `correlation_id`, `payload`. Consumers commit offsets only after side-effects succeed. Each consumer group has a dedicated DLQ.

**Seller pricing currencies (V1)**
USD, THB, JPY, SGD only.

**Prohibited categories**
Weapons, drugs, adult content. Checked at listing time via taxonomy flag and keyword blocklist.

<a id="data-architecture"></a>
## 8. Data architecture

| Store | Owner / purpose | Rules |
|---|---|---|
| PostgreSQL | Source of truth for users, catalog, offers, prices, inventory, carts, orders, KYC, moderation, and outbox | Raw SQL migrations; one schema per module; repository interfaces isolate ORM usage |
| MongoDB | Audit logs and activity events (append-only) | Populated from Kafka events; never source of truth for order or catalog state |
| Elasticsearch | Search documents and facets | Written from Kafka consumers only; never from the API request path |
| Kafka | Durable domain-event transport | At-least-once delivery; consumers idempotent; BACKWARD-compatible Avro schemas |
| MinIO | Binary assets (images, documents, user files) | Three buckets: `product-images` (public read), `kyc-documents` (private, presigned GET), `user-assets` (private) |

PostgreSQL uses one schema per module. The owning module is the sole writer; others use its application interface or subscribe to its events.

See `phase-1/technical-design/data-model-erd.md` for the full table-level design.

<a id="external-integration-boundaries"></a>
## 9. External integration boundaries

| Boundary | V1 design | V2+ intent |
|---|---|---|
| OAuth | Passport.js strategies for Google and Facebook | Same |
| FX rates | Scheduled refresh from exchangerate.host; display-only cache in PostgreSQL | Same or commercial provider |
| Payment | Fake internal adapter; deterministic mock outcomes | Real payment gateway |
| Shipping | Fake internal adapter; mock method, cost, ETA, tracking | Real carrier APIs |
| Email | Kafka-driven outbound SMTP adapter; asynchronous, failure-isolated | Same pattern; provider may change |
| Object storage | MinIO (self-hosted S3-compatible) | S3 or equivalent managed service |

<a id="deployment-topology"></a>
## 10. Deployment topology

**Phase 1 (Docker Compose):** Three nginx containers serving the Angular apps, NestJS API, NestJS workers (outbox relay + Kafka consumers), PostgreSQL, MongoDB, Elasticsearch, Kafka, Confluent Schema Registry, Kafka UI, and MinIO. Full topology and service configuration in `phase-1/technical-design/docker-compose-topology.md`.

**Phase 2+ (Kubernetes):** One `Deployment` per domain module. Each service owns its data store. Kafka via Strimzi. Service mesh via Istio. Extraction begins with low-coupling consumers (Search, Notifications) and progresses inward. A module extraction is complete when the extracted service is the sole writer of its schema and all consumers use its API or Kafka events instead of direct database access.

<a id="quality-attributes"></a>
## 11. Quality attributes

| Concern | Design response |
|---|---|
| Reliability | PostgreSQL transaction + outbox prevents lost state-change events; consumers are idempotent and have DLQs |
| Security | DTO validation, parameterized queries, Argon2id passwords, short-lived JWTs with refresh rotation, secrets in environment variables |
| Performance | Elasticsearch serves search; API avoids synchronous indexing; targets: product listing ≤2 s p95, search ≤500 ms p95 |
| Scalability | Search model supports 10,000+ products; module interfaces and Kafka contracts are future extraction seams |
| Portability | Raw SQL migrations and repository interfaces prevent ORM leakage into domain logic |
| Observability | Structured JSON logs and correlation IDs on requests and every event; monitor outbox relay and consumer lag |

<a id="implementation-structure"></a>
## 12. Implementation structure

**Backend** is a Nx monorepo (`aliceut-ecom-backend/`) with `apps/api`, `apps/workers`, and one `libs/<module>/` per bounded context. `libs/contracts/` holds OpenAPI specs and Avro event definitions; `libs/shared/` holds technical primitives only (logging, error, validation, money, auth) — never domain logic owned by a module. See `phase-1/technical-design/module-architecture.md` for the full structure.

**Frontend** is a Nx monorepo (`aliceut-ecom-frontend/`) with `apps/buyer-app`, `apps/seller-app`, `apps/admin-app` and shared libraries under `libs/`, including a generated TypeScript API client from the OpenAPI spec. Generated client files must not be manually edited. See `phase-1/ui-design/` for screen-level design.

**REST contract** is OpenAPI 3.x. NestJS generates the spec via `SwaggerModule`; Angular consumes a generated client via OpenAPI Generator (`typescript-angular`). Domain entities are never exposed directly. Breaking changes require a new API version.

<a id="service-extraction-roadmap"></a>
## 13. Service extraction roadmap

V1 is a modular monolith. Extraction order in Phase 2+, subject to approved requirements:

1. **Low-coupling consumers first** — Search and Notifications (event consumers with no synchronous upstream callers)
2. **Mid-tier modules** — Catalog, Pricing, Inventory (strong ownership, clear API surface)
3. **Core transaction modules last** — Identity, Cart, Orders/Checkout (deepest coupling, most cross-module FK dependencies)

Extraction prerequisites per module: (a) service becomes the sole writer of its schema, (b) all synchronous callers use its HTTP API, (c) all async consumers subscribe to its Kafka events, (d) cross-schema foreign keys in its migration are replaced by event-driven projections.

<a id="phase-specific-design-documents"></a>
## 14. Phase-specific design documents

Detailed design evolves within each phase's directory.

### Phase 1

| Document | Location |
|---|---|
| Business requirements | `phase-1/requirements/BRD.md` |
| User stories | `phase-1/requirements/user-stories/` |
| Data model and ERD | `phase-1/technical-design/data-model-erd.md` |
| REST API contracts | `phase-1/technical-design/api-design.md` |
| Kafka / Avro event schemas | `phase-1/technical-design/kafka-events.md` |
| Docker Compose topology | `phase-1/technical-design/docker-compose-topology.md` |
| NestJS module architecture | `phase-1/technical-design/module-architecture.md` |
| Implementation specifications | `phase-1/technical-design/implementation-specs.md` |
| UI design and screen specs | `phase-1/ui-design/` |
