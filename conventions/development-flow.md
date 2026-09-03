# Development Flow

**Status:** Draft  
**Source of truth:** [BRD v1.1](../phase-1/requirements/BRD.md), [architecture-overview](../architecture-overview.md)

This document is the developer's starting point for AliceUT. Read it once when onboarding; return to it when you need to understand how the pieces connect. It does not duplicate the detailed conventions — it maps the full workflow and points to the right document for each concern.

---

## Summary

| # | Section | Description |
|---|---------|-------------|
| 1 | [Repository overview](#1-repository-overview) | Monorepo layout: backend, frontend, docs, utility pipeline |
| 2 | [Local development setup](#2-local-development-setup) | Prerequisites, `.env`, docker compose, seed data |
| 3 | [Daily development workflow](#3-daily-development-workflow) | Branch → code → test → PR → merge cycle |
| 4 | [Conventions map](#4-conventions-map) | Which convention to read for which concern |
| 5 | [Technology decisions reference](#5-technology-decisions-reference) | Stack summary and locked decisions |
| 6 | [API client generation](#6-api-client-generation) | When and how to regenerate the Angular client |
| 7 | [Database changes](#7-database-changes) | Migration authoring and deployment |
| 8 | [MongoDB usage rules](#8-mongodb-usage-rules) | What lives in Mongo vs Postgres |
| 9 | [MinIO usage rules](#9-minio-usage-rules) | File storage conventions |
| 10 | [Cross-cutting non-negotiables](#10-cross-cutting-non-negotiables) | Rules enforced project-wide (money, events, auth) |
| 11 | [Pre-merge checklist](#11-pre-merge-checklist) | Gate before any PR is merged |

---

<a id="1-repository-overview"></a>
## 1. Repository overview

AliceUT is a two-repo system:

| Repo | Contents |
|------|----------|
| `aliceut` | Application source: NestJS backend (`backend/`), Angular frontend (`frontend/`), docs (`phase-1/`, `conventions/`, `architecture-overview.md`) |
| `alice-ut-utility-pipeline` | Database migrations (`database/phase-N/`), CI workflows for schema changes |

Phase documentation lives in `aliceut`. Source code will also live in `aliceut` (not yet written — pre-implementation phase). Migrations are kept separate so they can be run by a dedicated operator workflow without touching application code.

### Monorepo layout (backend)

```
backend/
├── apps/
│   ├── api/           NestJS HTTP server (composition root)
│   └── workers/       Kafka consumers + outbox relay
└── libs/
    ├── <domain>/      Feature modules (catalog, orders, pricing, …)
    ├── contracts/     OpenAPI JSON, Avro schemas, generated types
    └── shared/        Technical primitives (money, errors, logger, pagination)
```

See [module-architecture.md](module-architecture.md) for module tier rules, layer dependency rules, and CQRS-lite handler pattern.

### Monorepo layout (frontend)

```
frontend/
├── apps/
│   ├── buyer-portal/    Mobile-first: public catalog, auth, cart, checkout, orders
│   ├── seller-portal/   Desktop-first: listings, inventory, orders, KYC
│   └── admin-portal/    Desktop-first: KYC moderation, user management, platform ops
└── libs/
    ├── api-client/      Generated Angular HTTP client — never hand-edit
    ├── shared-ui/       Presentational components, pipes, directives
    └── shared-util/     Pure utility functions (money formatting, date helpers)
```

See [frontend-coding-standards.md](frontend-coding-standards.md) §1 for import boundary rules and path aliases.

---

<a id="2-local-development-setup"></a>
## 2. Local development setup

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Node.js | 20 LTS | https://nodejs.org |
| pnpm | 9+ | `npm install -g pnpm` |
| Docker Desktop | Latest | https://docker.com |
| golang-migrate CLI | 4.18+ | `brew install golang-migrate` / download binary |
| Angular CLI | 17+ | `pnpm add -g @angular/cli` |

### Step 1 — Clone and install

```bash
git clone git@github.com:alisa-uthi/aliceut.git
cd aliceut
pnpm install
```

### Step 2 — Environment files

Copy the example env files and fill in development values. Never commit `.env` files.

```bash
cp backend/apps/api/.env.example     backend/apps/api/.env
cp backend/apps/workers/.env.example backend/apps/workers/.env
```

Required variables per service are documented in [backend-coding-standards.md §6.2](backend-coding-standards.md#6-environment-config). Commit `.env.example` files alongside source code with placeholder values (no secrets).

### Step 3 — Start infrastructure

```bash
# Start all infrastructure services (Postgres, MongoDB, MinIO, Kafka, Schema Registry, Elasticsearch, Kafka UI)
docker compose up -d

# Verify all containers are healthy
docker compose ps
```

Compose services:

| Service | Port | Purpose |
|---------|------|---------|
| `postgres` | 5432 | Primary DB |
| `mongodb` | 27017 | Audit/activity logs |
| `minio` | 9000 / 9001 | Object storage / console |
| `kafka` | 9092 | Event bus |
| `schema-registry` | 8081 | Avro schema registry |
| `kafka-ui` | 8080 | Kafka topic browser (provectus/kafka-ui) |
| `elasticsearch` | 9200 | Search index |

### Step 4 — Run migrations

Migrations live in `alice-ut-utility-pipeline/database/phase-1/`. Clone that repo alongside `aliceut` and run:

```bash
migrate \
  -path ../alice-ut-utility-pipeline/database/phase-1 \
  -database "postgres://aliceut:aliceut@localhost:5432/aliceut?sslmode=disable" \
  -table schema_migrations_phase1 \
  up
```

See [database-migrations.md](database-migrations.md) for full migration conventions.

### Step 5 — Seed development data

```bash
# Load the 100-product Kaggle seed (local dev only — never in test fixtures)
pnpm run seed:dev
```

The seed script is defined in `backend/apps/api/package.json`. It calls `POST /internal/dev/seed` on a running API. Start the API first.

### Step 6 — Start the applications

```bash
# Backend API
pnpm --filter @aliceut/api dev

# Workers (Kafka consumers + outbox relay)
pnpm --filter @aliceut/workers dev

# Frontend — buyer portal
pnpm --filter @aliceut/buyer-portal serve

# Frontend — seller portal
pnpm --filter @aliceut/seller-portal serve

# Frontend — admin portal
pnpm --filter @aliceut/admin-portal serve
```

Buyer portal runs at `http://localhost:4200`, seller at `4201`, admin at `4202`. API at `http://localhost:3000`. Workers health check at `http://localhost:3001/health`.

---

<a id="3-daily-development-workflow"></a>
## 3. Daily development workflow

The complete cycle from task to merged code:

```
GitHub Project card (issue)
  └─ Create branch: feature/ET-N-short-description
      └─ Implement + write tests
          └─ Commit (Conventional Commits format)
              └─ Push → open PR
                  └─ CI passes (build + lint + unit tests + coverage)
                      └─ Self-review checklist (see §11)
                          └─ Squash-merge to main
                              └─ Delete branch
                                  └─ Tag release (when milestone complete)
```

See [git-workflow.md](git-workflow.md) for the full Git conventions including branch naming, commit format, PR template, and release tagging.

### When to open a PR

Open a PR **before** work is complete when you want to checkpoint progress or share a design. Use the `Draft` PR status on GitHub. Non-draft PRs signal "ready for merge" — CI gates block on them.

### Commit discipline

One logical change per commit. Compile and pass tests at each commit. No `WIP` commits on feature branches (squash them before opening a PR, or the squash-merge handles it).

---

<a id="4-conventions-map"></a>
## 4. Conventions map

| Concern | Document |
|---------|----------|
| Git branching, commits, PRs, releases | [git-workflow.md](git-workflow.md) |
| NestJS module structure, layers, CQRS | [module-architecture.md](module-architecture.md) |
| REST API naming, response shapes, pagination, auth guards | [api-conventions.md](api-conventions.md) |
| Database migrations (SQL files, golang-migrate) | [database-migrations.md](database-migrations.md) |
| JWT claims, refresh token storage, token TTLs | [auth-jwt-design.md](auth-jwt-design.md) |
| Kafka event envelope, Avro schemas, consumer patterns, outbox | [kafka-events.md](kafka-events.md) |
| Structured logging, correlation ID, Grafana Alloy stack | [observability.md](observability.md) |
| Angular Material palette, design principles, components | [design-system.md](design-system.md) |
| Data lifecycle (pg_cron jobs, token cleanup, outbox cleanup) | [data-lifecycle.md](data-lifecycle.md) |
| NestJS TypeScript config, ESLint, money patterns, DTOs, errors | [backend-coding-standards.md](backend-coding-standards.md) |
| Angular project structure, state, forms, routing, performance | [frontend-coding-standards.md](frontend-coding-standards.md) |
| Test pyramid, coverage thresholds, Jest/Playwright patterns | [testing-guidelines.md](testing-guidelines.md) |

---

<a id="5-technology-decisions-reference"></a>
## 5. Technology decisions reference

All decisions below are signed off in BRD §12 — treat as constraints.

| Layer | Technology | Notes |
|-------|-----------|-------|
| Frontend | Angular 17+ + Angular Material | Standalone components default |
| Backend | NestJS (modular monolith) | Microservice-ready; no microservices in V1 |
| Primary DB | PostgreSQL | Transactional core, all domain state |
| Document DB | MongoDB | Audit logs, activity feeds, high-write append data only |
| File storage | MinIO | Product images, KYC documents, invoices |
| Search | Elasticsearch / OpenSearch | Single-node; updated async from Kafka |
| Event bus | Apache Kafka + Confluent Schema Registry | Avro, BACKWARD compatibility |
| ORM | TypeORM | Raw-SQL migrations only; `synchronize: false` always |
| Auth | Passport.js + JWT | HS256; 15min access token; opaque refresh in httpOnly cookie |
| Money arithmetic | `decimal.js` | Never JS `number` for monetary math |
| Deploy V1 | docker-compose | No Kubernetes until V2 |

**Out of scope in V1:** real payment gateway, real shipping integration, reviews/ratings, wishlist, recommendations, seller analytics, dispute mediation, i18n, native mobile, Kubernetes.

---

<a id="6-api-client-generation"></a>
## 6. API client generation

The frontend never calls `HttpClient` directly for API endpoints. It uses a generated Angular client at `frontend/libs/api-client/`.

### When to regenerate

Regenerate after any change to the backend's OpenAPI spec (`libs/contracts/openapi/aliceut-v1.json`):

1. A new endpoint is added or an existing one changes shape.
2. A DTO field is renamed, added, or removed.
3. A response envelope changes.

### How to regenerate

```bash
# From the frontend workspace root
pnpm run generate:api-client
```

This script calls `openapi-generator-cli typescript-angular` against `libs/contracts/openapi/aliceut-v1.json` and outputs to `frontend/libs/api-client/`. The generated files are committed to source control.

### CI enforcement

A CI step runs the generator and diffs the output against the committed `api-client/`. A diff fails the build. This prevents the frontend consuming a stale client after a backend API change. See [module-architecture.md §8](module-architecture.md#8-openapi-contract-generation) for the full OpenAPI generation pipeline.

---

<a id="7-database-changes"></a>
## 7. Database changes

**Never use TypeORM `synchronize: true`.** All schema changes go through raw SQL migrations.

### Authoring a migration

1. Add a new `{seq}_{description}.up.sql` + `.down.sql` pair in `alice-ut-utility-pipeline/database/phase-1/`.
2. Sequence number is 4-digit zero-padded, next in sequence.
3. Test locally: run `migrate up`, verify, then run `migrate down 1` to confirm rollback works.
4. Open a PR in the utility pipeline repo.

See [database-migrations.md](database-migrations.md) for SQL rules (concurrent indexes, nullable columns, idempotent down scripts).

### Deploying migrations

Migrations are applied via GitHub Actions `workflow_dispatch` in the utility pipeline repo — never automatically on code deploy. Production requires a manual reviewer approval step.

---

<a id="8-mongodb-usage-rules"></a>
## 8. MongoDB usage rules

MongoDB (`MONGODB_URI`) is for **append-only, high-write data with no relational invariants**. Not for domain state.

| Use MongoDB | Use Postgres |
|-------------|-------------|
| User activity feed (product views, search history) | All domain entities (User, Product, Offer, Order, …) |
| Seller performance audit trail | Any table with foreign-key relationships |
| Admin audit log (KYC decisions, moderation actions) | Financial records (prices, transactions) |
| Notification read/unread state | Cart, inventory, outbox |

**Access pattern:** inject `MongoClient` or a Mongoose model in the relevant NestJS service. MongoDB collections are **not** managed by TypeORM — they have their own migration-free schema evolution. Document the collection schema in the relevant module's `README.md` when the collection is first created.

**No transactions across Postgres and MongoDB.** If a domain change must write to both, write to Postgres first (with outbox), then let a Kafka consumer write the denormalized copy to MongoDB. Never attempt a two-phase commit across both stores.

---

<a id="9-minio-usage-rules"></a>
## 9. MinIO usage rules

MinIO (`MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`) stores binary objects. Three buckets in V1:

| Bucket | Contents | Access |
|--------|---------|--------|
| `product-images` | Product and variant images (JPEG/PNG/WebP, max 5 MB each) | Public read, authenticated write |
| `kyc-documents` | KYC submission scans (PDF/JPEG, max 10 MB each) | Private; seller write, admin read |
| `invoices` | Generated order invoices (PDF) | Private; buyer read for own orders |

### Rules

- **Never store MinIO object URLs in Postgres directly.** Store the object key (e.g. `product-images/products/{productId}/{uuid}.jpg`). Generate presigned URLs at read time.
- **Presigned URL TTL:** product images — 1 hour (long, public bucket, CDN-cacheable). KYC / invoices — 15 minutes (short, private, one-time download).
- **Virus scan on upload:** all KYC documents and invoices must pass a ClamAV scan before being made accessible. Block the upload API response until the scan completes (synchronous in V1).
- **Filename policy:** generate a UUID4 filename server-side. Never trust the client-supplied filename — it is stored only in a metadata column alongside the object key.

---

<a id="10-cross-cutting-non-negotiables"></a>
## 10. Cross-cutting non-negotiables

These rules apply project-wide. Violating any one of them is a PR blocker.

### Money

- Storage: `NUMERIC(19,4)` + ISO 4217 code column. FX rates: `NUMERIC(19,8)`.
- App arithmetic: `decimal.js` or `Money` value object only. Never JS `+`, `*`, `/` on monetary values.
- API wire format: amounts as **strings** (`"99.99"`), not JSON numbers.
- TypeScript: monetary fields typed as `string` at API/DB boundaries, `Decimal` inside arithmetic. `number` on a monetary field is a lint error.
- Currency-specific display scale: JPY=0, BHD=3, USD/THB/SGD=2. Storage stays 4 dp regardless.

See [backend-coding-standards.md §3](backend-coding-standards.md#3-money-handling-code-patterns) (backend) and [frontend-coding-standards.md §5](frontend-coding-standards.md#5-money-display-patterns) (frontend).

### Event-driven writes

Every domain state change that must propagate externally (product, offer, inventory, order, KYC, moderation) publishes via transactional outbox — the `outbox_event` row is written in the **same Postgres transaction** as the domain change. No direct Kafka publish from application code.

See [kafka-events.md](kafka-events.md) and [module-architecture.md §6](module-architecture.md#6-outbox-integration-pattern).

### Order immutability

`FulfillmentItem` snapshots `unit_price`, `currency`, `tax`, `fx_rate_used_at_capture` at checkout. Historical amounts are **never** re-derived from live FX rates or current `Price` rows.

### Auth

Access token lives in memory only (frontend); refresh token in httpOnly cookie only. `JWT_SECRET` must be at least 32 bytes, generated per environment, stored in GitHub Secrets. Never hardcode tokens or secrets in source.

### Prohibited categories

No weapons, drugs, or adult content. Moderation flags on taxonomy + keyword blocklist at listing time. The admin portal enforces this — no bypass in any API endpoint.

### V1 seller currencies

Seller pricing: `USD`, `THB`, `JPY`, `SGD` only. Any other currency code must be rejected at DTO validation (`@IsIn(['USD','THB','JPY','SGD'])`).

---

<a id="11-pre-merge-checklist"></a>
## 11. Pre-merge checklist

Gate every PR against this list before merging. CI handles the automated checks; the manual checks require judgment.

### Automated (CI blocks merge if failing)

- [ ] `tsc --noEmit` passes (both `api` and all Angular apps)
- [ ] `eslint` passes including money lint rule
- [ ] Unit tests pass; coverage thresholds met per module tier (see [testing-guidelines.md §2](testing-guidelines.md#coverage-thresholds))
- [ ] Commitlint: PR title and all commit messages follow Conventional Commits
- [ ] OpenAPI spec diff: if backend changed, frontend `api-client` is regenerated and committed

### Manual (self-review before opening PR)

**Domain layer:**
- [ ] No NestJS / TypeORM / class-validator imports inside `domain/` layer
- [ ] Repository interface defines contracts only — no TypeORM types leak through

**Money correctness:**
- [ ] No JS `number` type on monetary field
- [ ] All monetary arithmetic uses `decimal.js` / `Money` value object
- [ ] TypeORM monetary columns declared as `string` with `numericStringTransformer`
- [ ] JSON response monetary fields are strings

**Event-driven integrity:**
- [ ] Outbox row written in same transaction as domain state change
- [ ] Kafka consumer deduplicates on `event_id`
- [ ] Event payload includes `event_id`, `event_type`, `event_version`, `occurred_at`, `correlation_id`

**Cross-module boundaries:**
- [ ] No direct cross-module DB join (each module queries only its own tables)
- [ ] No direct cross-module service injection except via `index.ts` public API or checkout→inventory approved exception

**Security:**
- [ ] No hardcoded secret, key, or password
- [ ] No internal error detail (stack trace, SQL) exposed to clients
- [ ] No `ValidationPipe` re-registered at controller/handler level

**Testing:**
- [ ] New API endpoint has integration test (Supertest)
- [ ] New Tier 1 command/query handler has unit tests for happy path + error path
- [ ] New Angular feature has component tests
- [ ] No test reads `process.env` directly (use stubbed `ConfigService`)

**Frontend:**
- [ ] No raw `HttpClient` call for API endpoints — always use generated client
- [ ] Access token never written to localStorage / sessionStorage
- [ ] Every data-fetching component handles loading / empty / error states
- [ ] All feature routes are lazily loaded

**Docs and migrations:**
- [ ] If a new DB column or table is added, a migration pair exists in `alice-ut-utility-pipeline`
- [ ] If a new MongoDB collection is introduced, schema is documented in the module README
- [ ] If a new env var is required, it is added to the `.env.example` file and [backend-coding-standards.md §6.2](backend-coding-standards.md#6-environment-config)
