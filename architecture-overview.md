# AliceUT Architecture Overview

**Status:** Complete  
**Project architecture:** This document defines the project-level architecture and its evolution path.  
**Phase 1 scope source:** [BRD v1.1](phase-1/requirements/BRD.md) and the Phase 1 user stories.

---

## 1. Architecture goals

- Deliver the buyer, seller, and admin V1 loops in one deployable application.
- Keep transactional state strongly consistent while supporting asynchronous search and notifications.
- Make module ownership and contracts explicit so modules can be extracted later without redesigning the data model.
- Prepare every domain module to become an independently built and deployed Kubernetes service in a later phase.
- Preserve monetary precision and the price captured at checkout.
- Run the complete local/demo environment with Docker Compose.

## 2. Project evolution

The signed requirements currently cover Phase 1 only. This overview therefore defines the architectural direction for the whole project while marking V1 implementation decisions explicitly:

| Stage | Architecture state |
|---|---|
| Phase 1 / V1 | Angular client and NestJS modular monolith, one PostgreSQL database partitioned by module schema, Kafka/event outbox, Elasticsearch, MongoDB, and Docker Compose. |
| Later phases | Modules are extracted incrementally into independently built and deployed Kubernetes services, progressing to database-per-service without breaking published API or event contracts. |

Future product scope remains governed by its phase requirements document. This overview does not itself approve a new feature or reopen signed-off requirements.

## 3. Phase 1 system context

```text
Browser
  │ HTTPS
  ▼
Angular + Angular Material SPA
  │ REST/JSON + JWT
  ▼
NestJS modular monolith
  ├── PostgreSQL       transactional system of record + transactional outbox
  ├── MongoDB          append-only audit and activity records
  ├── Elasticsearch    product-search read model
  └── Kafka ─────────── asynchronous domain events
        │                    │
        ▼                    ├── search indexer → Elasticsearch
  Schema Registry            ├── notification consumers → email / in-app records
  (Avro schemas)             └── audit consumer → MongoDB

External integrations: Google/Facebook OAuth; exchangerate.host for display-only FX.
Fake payment and shipping remain internal V1 adapters; no gateway or carrier is called.
```

The Angular SPA is the only browser client. NestJS exposes versioned REST endpoints and contains the business modules below. Kafka is an internal integration boundary: modules do not synchronously read another module's database or write its tables.

## 4. Phase 1 application modules

| Module | Responsibilities | Primary persistence / outputs |
|---|---|---|
| Identity | Registration, local/OAuth login, JWT refresh rotation, account roles | PostgreSQL: users, refresh sessions |
| Catalog | Product taxonomy, variants, seller offers, moderation state | PostgreSQL; `product.changed`, `offer.changed` |
| Pricing | Price rows, effective-price resolution, display FX fallback | PostgreSQL: prices, FX rates |
| Inventory | Seller stock, availability and low-stock state | PostgreSQL; `inventory.changed` |
| Search | Search API and facets over the denormalized product index | Elasticsearch (read-only from API) |
| Cart | Guest and authenticated carts, merge on login | PostgreSQL for authenticated carts; browser local storage for guest cart |
| Checkout and orders | Address, shipping/payment simulation, inventory reservation, immutable orders and fulfillments | PostgreSQL; `order.finalized`, `fulfillment.placed` |
| Seller | KYC application, listing and fulfilment operations | PostgreSQL; KYC/order events |
| Administration | KYC decisions and catalog moderation | PostgreSQL; moderation events |
| Notifications | Email and in-app notification projections | Kafka consumer; PostgreSQL/Mongo read records as designed later |
| Platform | Outbox relay, event envelope, idempotency, DLQ handling, audit logging | PostgreSQL outbox + Kafka + MongoDB |

Modules communicate in-process through application interfaces for synchronous commands and queries. Every domain state change that needs external propagation writes an outbox record in the same PostgreSQL transaction; the relay publishes it to Kafka. This permits later service extraction without changing the event contract.

## 5. Phase 1 data ownership and read models

| Store | Owner / purpose | Rules |
|---|---|---|
| PostgreSQL | Source of truth for users, catalog, offers, prices, inventory, carts, addresses, orders, KYC, moderation, FX cache, and outbox | Raw SQL migrations only; repositories isolate TypeORM usage. |
| MongoDB | High-write, append-only activity and audit data | Populated from events; not the source of truth for order or catalog state. |
| Elasticsearch | Search documents and filter/sort facets | Updated asynchronously from Kafka only; never written from the request path. |
| Kafka | Durable domain-event transport | At-least-once delivery. Consumers deduplicate by `event_id`; commit offsets only after side effects succeed. |
| Confluent Schema Registry | Avro schema compatibility | Self-managed Community License edition: basic registry functionality is free and needs no commercial license key. One `<topic>-value` subject per topic; compatibility mode is `BACKWARD`. |

### PostgreSQL schema boundaries

V1 uses one PostgreSQL database, with a schema per application module. This keeps Docker Compose and cross-module transactions simple while making ownership boundaries explicit for future service extraction.

| PostgreSQL schema | Owning module | Example tables |
|---|---|---|
| `identity` | Identity | `users`, `refresh_sessions`, `addresses` |
| `catalog` | Catalog | `products`, `product_variants`, `categories`, `offers` |
| `pricing` | Pricing | `prices`, `currencies`, `fx_rates` |
| `inventory` | Inventory | `inventory`, `stock_reservations` |
| `cart` | Cart | `carts`, `cart_items` |
| `orders` | Checkout and orders | `orders`, `fulfillments`, `fulfillment_items`, `addresses` |
| `seller` | Seller | `seller_profiles`, `kyc_applications` |
| `admin` | Administration | `moderation_cases` |
| `notifications` | Notifications | `in_app_notifications` |
| `platform` | Platform | `outbox_events`, `processed_events` |

- A module writes only tables in its owned schema; no domain table belongs in `public`.
- Raw SQL migrations must qualify their schema and preserve module ownership.
- Prefer module interfaces and Kafka events over cross-schema writes. Cross-schema foreign keys are permitted only for essential transactional references, such as cart or order items referencing an offer.
- A future extracted service owns the data currently held by its schema; it must consume published events instead of reading another service's database.

### Money and pricing invariants

- Store money in PostgreSQL as `NUMERIC(19,4)` with ISO 4217 currency code; use string values at API boundaries and `decimal.js` or `Big.js` in application code.
- `Product` has no price. The hierarchy is `Product → Offer → Price`; cart and order items reference an `Offer`.
- Price resolution considers account type, selected quantity, time bounds, price type, and buyer display currency. FX conversion is display-only.
- At checkout, `FulfillmentItem` snapshots unit price, currency, tax, FX rate used, and quantity. Historical orders never read a current offer price to calculate a total.

## 6. Phase 1 core flows

### Catalog change to searchable product

```text
Seller/Admin command
  → Catalog transaction (domain rows + outbox row)
  → Outbox relay publishes Avro event to Kafka
  → Search-index consumer updates Elasticsearch document
  → Buyer search endpoint queries Elasticsearch
```

Search is therefore eventually consistent. The target propagation lag is no more than five seconds p95; the catalog command response does not wait for indexing.

### Checkout to confirmation

```text
Buyer checkout request
  → validate address, cart, prices, stock, and idempotency key
  → one PostgreSQL transaction per seller/currency group (inside the checkout request):
       reserve/decrement inventory, create Fulfillment + immutable FulfillmentItem snapshots,
       record mock shipping/payment result, write fulfillment.placed outbox event
  → write order.finalized outbox event (same tx as Order status write, after all groups processed)
  → return confirmation with placed fulfillments, mock tracking, ETAs, and any skipped/failed groups
  → relay publishes order.finalized and fulfillment.placed events asynchronously
  → notification, seller, audit, and analytics consumers process each event idempotently
```

The confirmation is served from the committed order transaction, not from Kafka consumer completion. Outbox relay retries failed publication; poison messages are routed to a consumer-specific DLQ with alerting.

## 7. Phase 1 external boundaries

| Boundary | V1 design |
|---|---|
| OAuth | Passport strategies for Google and Facebook. OAuth identity is linked to a user account after verified-email handling. |
| FX rates | A scheduled adapter refreshes the PostgreSQL FX cache from exchangerate.host. Rates may only be used for display conversion. |
| Payment | Internal fake-payment adapter returns deterministic mock outcomes. No real payment credentials or provider calls. |
| Shipping | Internal fake-shipping adapter calculates configured mock method, cost, ETA, and tracking number. No carrier API calls. |
| Email | Kafka-driven outbound-email adapter. Sending is asynchronous and failure-isolated from user requests. |

## 8. Phase 1 deployment topology

One Docker Compose environment runs the Angular UI, NestJS API, PostgreSQL, MongoDB, Elasticsearch (single node), Kafka (KRaft acceptable), self-managed Confluent Schema Registry, Kafka UI, and the outbox relay/consumers. Development secrets are injected via environment variables and are never committed.

V1 uses only the registry's free Community License functionality. It excludes commercial Schema Registry features: security-plugin RBAC, Schema Linking/exporters, and broker-side Schema Validation. The Community License is source-available rather than Apache 2.0, and it must not be used to offer a competing hosted schema-registry service.

Ingress terminates TLS in the deployment environment and forwards API calls to NestJS. Health checks are required for the API and each stateful dependency; backup the PostgreSQL volume before schema migrations.

## 9. Quality attributes and guardrails

| Concern | Design response |
|---|---|
| Reliability | PostgreSQL transaction + outbox prevents lost state-change events; consumers are idempotent and have DLQs. |
| Security | DTO validation, parameterized queries, Argon2id passwords, short-lived JWTs with refresh rotation, and secrets in environment variables. |
| Performance | Elasticsearch serves search; API avoids synchronous indexing; product listing target is ≤2s p95 and search ≤500ms p95. |
| Scalability | Search model supports 10,000+ products; module interfaces and Kafka contracts are future extraction seams. |
| Portability | Raw SQL migrations and repository interfaces prevent TypeORM leakage into domain logic. |
| Observability | Structured JSON logs and correlation IDs on requests and every event; monitor outbox and consumer lag. |

## 10. Phase 1 backend implementation structure

V1 ships as one NestJS API deployment, but the backend is a modular monorepo rather than a single undifferentiated application. The API is only a composition root: it wires module packages together and owns shared HTTP concerns. Business logic remains inside the module that owns it.

```text
backend/
├── apps/
│   ├── api/                         V1 NestJS HTTP composition root
│   └── workers/                     outbox relay and Kafka consumer processes
├── libs/
│   ├── identity/                    domain, application, infrastructure, HTTP adapter
│   ├── catalog/                     domain, application, infrastructure, HTTP adapter
│   ├── pricing/
│   ├── inventory/
│   ├── cart/
│   ├── orders/
│   ├── seller/
│   ├── admin/
│   ├── search/
│   ├── notifications/
│   ├── platform/                    outbox, idempotency, audit, observability
│   ├── contracts/                   OpenAPI specifications, REST DTOs, and Avro event definitions
│   └── shared/                      technical primitives only; no shared domain logic
└── migrations/
    ├── identity/                    raw SQL for the `identity` schema
    ├── catalog/                     raw SQL for the `catalog` schema
    └── ...
```

Each module has a public application interface (commands, queries, and published events), domain model, infrastructure adapters, and transport adapters. Another module may depend on that public interface or a versioned contract, but it must not import another module's repository, entity, ORM model, or schema-specific infrastructure.

- Keep module configuration and secrets namespaced, so a future deployment receives only its own settings.
- Place all Avro schemas and generated event types in `contracts`; version contracts independently from module implementation.
- Run the outbox relay and Kafka consumers as separate V1 worker processes, even if Docker Compose initially deploys them beside the API. This makes them independently scalable and directly maps to later Kubernetes Deployments.
- Keep raw SQL migrations grouped by owning PostgreSQL schema. A migration can reference another schema only for an essential cross-module foreign key and must document that dependency.
- Treat cross-module transaction flows as explicit V1 composition flows. For extraction, replace them with reservations, idempotent commands, and event-driven saga steps rather than relying on a distributed database transaction.
- `shared` may contain logging, error, validation, money, authentication, and transport primitives, but never a domain entity or business rule owned by a module.

### OpenAPI contract and generated client

The REST contract is OpenAPI 3.x. NestJS controllers and transport DTOs are annotated to produce a versioned OpenAPI document through `SwaggerModule.createDocument`; domain entities and persistence models are never exposed directly. The generated document is published as a build artifact and committed/exported under `libs/contracts/openapi/` for review and compatibility checks.

The Angular application consumes a generated TypeScript client, not hand-written `HttpClient` endpoint wrappers. CI runs OpenAPI Generator with the stable `typescript-angular` generator against the versioned specification and writes the result to a generated client library, for example `frontend/libs/api-client/`. Generated files must not be manually edited.

```text
NestJS controllers + transport DTOs
  → OpenAPI 3.x document (`libs/contracts/openapi/aliceut-v1.json`)
  → OpenAPI Generator (`typescript-angular`)
  → generated Angular API client
  → Angular feature code
```

- Tag every operation by owning module and use stable, unique `operationId` values; they become generated client method names.
- Version the contract under `/api/v1` and publish breaking changes only through a new major API version. CI must fail when contract generation or client generation leaves uncommitted changes.
- Define JWT bearer security, standard error responses, pagination, idempotency headers, and all money fields in the OpenAPI document. Monetary values are JSON strings, never numbers.
- Keep public request/response DTOs in the transport layer. Map them explicitly to application commands and query results so a later service extraction can retain the same contract.
- During module extraction, a module publishes its own OpenAPI document and generated client package; the V1 combined contract can remain as an API-gateway aggregation until consumers migrate.

## 11. Later-phase service extraction and Kubernetes deployment

V1 is intentionally a modular monolith. Its module boundaries, PostgreSQL schemas, repository interfaces, and Kafka event contracts are extraction seams—not separate deployables yet.

The target for a later phase is one independently built container image and Kubernetes `Deployment` per domain module: Identity, Catalog, Pricing, Inventory, Search, Cart, Checkout/Orders, Seller, Administration, Notifications, and Platform workers. Each service exposes only its owned API, uses an internal Kubernetes `Service` for synchronous traffic where necessary, and publishes/consumes its existing Kafka contracts for asynchronous communication. K9s may be used to operate the cluster, but Kubernetes (K8s) is the deployment platform.

Extraction must happen incrementally, beginning with low-coupling consumers such as Search and Notifications. A module is only extracted after its data ownership is enforceable: the extracted service becomes the sole writer of the data in its current PostgreSQL schema, and other services use its API or Kafka events instead of direct database access. The final target is database-per-service, migrated schema by schema; sharing the Phase 1 PostgreSQL database is a temporary transition, not the end state.

Each service deployment will have independent resource requests/limits, readiness/liveness probes, horizontal-autoscaling policy where justified, configuration and secrets, structured logs, metrics, and distributed tracing with propagated correlation IDs. Kubernetes plus Istio remains a post-V1 concern.

## 12. Explicit Phase 1 boundaries

- This is a modular monolith, not a microservice deployment.
- Recommendations, review authoring, wishlists, real payment, real carrier shipping, seller analytics, native apps, Kubernetes, and i18n are excluded.
- B2B uses the same buyer workflow as B2C; only approved branding differences apply.

## 13. Phase-specific technical design

This project-level overview is complete. Detailed design is maintained within the relevant phase under `phase-N/technical-design/`, where it can evolve with that phase's approved requirements.

For Phase 1, the next documents are the API contracts, Kafka/Avro event and outbox design, authentication/authorization design, and Docker Compose runbook. Later phases define their own service-extraction, Kubernetes, and data-migration designs when their scope is approved.
