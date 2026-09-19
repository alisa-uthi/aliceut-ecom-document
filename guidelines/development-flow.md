# Development Flow

**Status:** Draft  
**Source of truth:** [BRD v1.2](../phase-1/requirements/BRD.md), [architecture-overview](../architecture-overview.md)

This document is the developer's starting point for AliceUT. Read it once when onboarding; return to it when you need to understand how the pieces connect. It does not duplicate the detailed conventions ─ it maps the full workflow and points to the right document for each concern.

---

## Summary

| # | Section | Description |
|---|---------|-------------|
| 1 | [Repository overview](#1-repository-overview) | Repo layout: docs, backend, frontend, infra, utility pipeline |
| 2 | [Local development setup](#2-local-development-setup) | Prerequisites, `.env`, frontend build, docker compose, seed data |
| 3 | [Daily development workflow](#3-daily-development-workflow) | Branch , code , test , PR , merge cycle |
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

AliceUT is a multi-repo system:

| Repo | Contents |
|------|----------|
| `aliceut-ecom-document` | Design docs, architecture, conventions, guidelines, phase requirements |
| `aliceut-ecom-backend` | NestJS backend ─ Nx monorepo: API server, Kafka workers, domain libs |
| `aliceut-ecom-frontend` | Angular frontend ─ Nx monorepo: buyer/seller/admin portals, shared libs |
| `aliceut-ecom-infra` | `docker-compose.yml` and the config it mounts (nginx, alloy, prometheus, grafana) |
| `aliceut-ecom-utility-pipeline` | CI utility workflows (non-migration); seed data scripts, infra automation |

### Local workspace layout

Clone all repos as siblings under a single parent folder. The compose file lives in `aliceut-ecom-infra` and its relative bind-mount paths (`../aliceut-ecom-backend`, `../aliceut-ecom-frontend/dist/<app>`) assume exactly this layout — the sibling arrangement is load-bearing, not a preference.

```
aliceut-ecom/
├── aliceut-ecom-document/          # this repo ─ design docs and conventions
├── aliceut-ecom-backend/           # NestJS backend
├── aliceut-ecom-frontend/          # Angular frontend
├── aliceut-ecom-infra/             # docker-compose.yml + mounted config
├── aliceut-ecom-utility-pipeline/  # Utility Pipelines (non-migration)
```

### Monorepo layout (backend)

```
aliceut-ecom-backend/
├── apps/
│   ├── api/           NestJS HTTP server (composition root)
│   └── workers/       Kafka consumers + outbox relay
└── libs/
    ├── <domain>/      Feature modules (catalog, orders, pricing, …)
    ├── contracts/     OpenAPI JSON, Avro schemas, generated types
    └── shared/        Technical primitives (money, errors, logger, pagination)
```

See [backend-module-architecture.md](../conventions/backend-module-architecture.md) for module tier rules, layer dependency rules, and CQRS-lite handler pattern.

### Monorepo layout (frontend)

```
aliceut-ecom-frontend/
├── apps/
│   ├── buyer-app/       Mobile-first: public catalog, auth, cart, checkout, orders
│   ├── seller-app/      Desktop-first: listings, inventory, orders, KYC
│   └── admin-app/       Desktop-first: KYC moderation, user management, platform ops
└── libs/
    ├── api-client/      Generated Angular HTTP client — never hand-edit
    ├── ui/              Presentational components, pipes, directives (`@aliceut/shared-ui`)
    └── shared-util/     Pure utility functions (money formatting, date helpers)
```

App directory names are fixed by BRD §12 decision 12 (`buyer-app`, `seller-app`, `admin-app`) — the compose bind mounts and the build scripts both depend on them.

See [frontend-coding-standards.md](../conventions/frontend-coding-standards.md) for import boundary rules and path aliases.

---

<a id="2-local-development-setup"></a>
## 2. Local development setup

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Node.js | 22 LTS | https://nodejs.org |
| npm | 10+ | ships with Node 22 |
| Docker Desktop | Latest | https://docker.com |
| Angular CLI | 22+ | `npm install -g @angular/cli` |

No migration CLI to install: migrations run through TypeORM, which is already a backend dependency ([database-migrations.md § 2](../conventions/database-migrations.md#execution-engine)).

### Step 1 ─ Clone and install

```bash
mkdir aliceut-ecom && cd aliceut-ecom

git clone git@github.com:alisa-uthi/aliceut-ecom-backend.git
git clone git@github.com:alisa-uthi/aliceut-ecom-frontend.git
git clone git@github.com:alisa-uthi/aliceut-ecom-document.git
git clone git@github.com:alisa-uthi/aliceut-ecom-infra.git
git clone git@github.com:alisa-uthi/aliceut-ecom-utility-pipeline.git

# Install dependencies in each app repo
cd aliceut-ecom-backend && npm ci && cd ..
cd aliceut-ecom-frontend && npm ci && cd ..

# Copy CLAUDE.md templates so Claude Code loads project conventions automatically
cp aliceut-ecom-document/guidelines/templates/backend-CLAUDE.md  aliceut-ecom-backend/CLAUDE.md
cp aliceut-ecom-document/guidelines/templates/frontend-CLAUDE.md aliceut-ecom-frontend/CLAUDE.md
```

### Step 2 ─ Environment files

Copy the example env files and fill in development values. Never commit `.env` files.

```bash
# Run from inside aliceut-ecom-backend/
cp apps/api/.env.example     apps/api/.env
cp apps/workers/.env.example apps/workers/.env
```

Required variables per service are documented in [backend-coding-standards.md §6.2](../conventions/backend-coding-standards.md#6-environment-config). Commit `.env.example` files alongside source code with placeholder values (no secrets).

### Step 3 ─ Build the frontend apps

**Do this before `docker compose up`.** The three nginx services do not build the Angular apps — they bind-mount `../aliceut-ecom-frontend/dist/<app>` from the host. If the `dist/` directories do not exist yet, nginx starts successfully and serves an empty directory: every portal returns 403/404 and nothing in the compose output says why.

```bash
# Run from inside aliceut-ecom-frontend/
npm run build:buyer && npm run build:seller && npm run build:admin
```

Re-run the relevant build after any frontend change you want to see through nginx. During feature work, prefer `ng serve` (Step 7) and skip the nginx containers entirely. The bind-mount rationale and the same command string are in [docker-compose-topology.md § 10](../phase-1/technical-design/docker-compose-topology.md).

### Step 4 ─ Start infrastructure

The compose file lives in `aliceut-ecom-infra/` — run compose from that directory so its relative bind mounts resolve.

```bash
# Run from inside aliceut-ecom-infra/
docker compose up -d

# Verify all containers are healthy
docker compose ps
```

Compose services:

| Service | Port | Purpose |
|---------|------|---------|
| `buyer-nginx` | 4200 | Serves the built buyer app |
| `seller-nginx` | 4201 | Serves the built seller app |
| `admin-nginx` | 4202 | Serves the built admin app |
| `api` | 3000 | NestJS HTTP API |
| `workers` | — | Outbox relay + Kafka consumers |
| `postgres` | 5432 | Primary DB |
| `mongodb` | 27017 | Audit/activity logs |
| `redis` | 6379 | JWT revocation keys, cache |
| `minio` | 9000 / 9001 | Object storage / console |
| `minio-init` | — | One-shot bucket creation |
| `kafka` | 29092 | Event bus |
| `schema-registry` | 8081 | Avro schema registry |
| `kafka-ui` | 8080 | Kafka topic browser (provectus/kafka-ui) |
| `elasticsearch` | 9200 | Search index |
| `mailpit` | 8025 / 1025 | Email sink — web inbox / SMTP |
| `alloy` | 12345 | Log and metric collector |
| `loki` | 3100 | Log aggregation, LogQL queries |
| `prometheus` | 9090 | Metrics scrape and storage |
| `grafana` | 3200 | Dashboards over Loki and Prometheus |

Every service above is V1 — the observability four are not a later addition, and nothing here is optional for a working local stack. The table is the port map; the authoritative service, module-library and application counts are published in [architecture-overview.md § 10](../architecture-overview.md#deployment-topology) and are not restated here.

**Where outbound email goes.** Nothing in development sends real mail. The notification consumer's SMTP transport points at `mailpit:1025`, and every message it produces — email verification links, KYC decisions, low-stock digests, order confirmations — lands in the Mailpit inbox at `http://localhost:8025`, where links are clickable. That inbox is the way to verify an email-producing flow end to end; there is no other sink and no provider account to configure. Mailpit holds mail in memory and has no volume, so a `docker compose restart mailpit` empties it.

Full service definitions, health checks, and startup order: [docker-compose-topology.md](../phase-1/technical-design/docker-compose-topology.md).

### Step 5 ─ Run migrations

Migrations live in `aliceut-ecom-backend/migrations/phase-1/`. Run from inside the backend repo:

```bash
# DATABASE_URL comes from apps/api/.env (Step 2)
npm run migration:run

# Confirm what was applied
npm run migration:show
```

Nothing applies migrations for you — not `docker compose up`, not the API container on start. Running this script is the only way the schema advances.

See [database-migrations.md](../conventions/database-migrations.md) for full migration conventions.

### Step 6 ─ Seed development data

```bash
# Load the 100-product Kaggle seed (local dev only ─ never in test fixtures)
npm run seed:dev
```

The seed script is defined in `apps/api/package.json` inside `aliceut-ecom-backend/`. It calls `POST /internal/dev/seed` on a running API. Start the API first.

### Step 7 ─ Start the applications

For day-to-day feature work, run the apps from source with hot reload instead of through the nginx containers.

```bash
# Backend API
npm run dev -w @aliceut/api

# Workers (Kafka consumers + outbox relay)
npm run dev -w @aliceut/workers

# Frontend ─ buyer app
npm run serve -w @aliceut/buyer-app

# Frontend ─ seller app
npm run serve -w @aliceut/seller-app

# Frontend ─ admin app
npm run serve -w @aliceut/admin-app
```

Buyer app runs at `http://localhost:4200`, seller at `4201`, admin at `4202`. API at `http://localhost:3000`. Workers health check at `http://localhost:3001/health`.

These are the same host ports the nginx containers use, so stop the corresponding container before running `ng serve` against that port.

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
                      └─ Claude design review posts findings on PR (backend PRs only)
                          └─ Address BLOCKER findings from Claude review
                              └─ Self-review checklist (see §11)
                                  └─ Squash-merge to main
                                      └─ Delete branch
                                  └─ Tag release (when milestone complete)
```

See [git-workflow.md](git-workflow.md) for the full Git conventions including branch naming, commit format, PR template, and release tagging.

### When to open a PR

Open a PR **before** work is complete when you want to checkpoint progress or share a design. Use the `Draft` PR status on GitHub. Non-draft PRs signal "ready for merge" - CI gates block on them.

### Commit discipline

One logical change per commit. Compile and pass tests at each commit. No `WIP` commits on feature branches (squash them before opening a PR, or the squash-merge handles it).

---

<a id="4-conventions-map"></a>
## 4. Conventions map

| Concern | Document |
|---------|----------|
| Git branching, commits, PRs, releases | [git-workflow.md](git-workflow.md) |
| NestJS module structure, layers, CQRS | [backend-module-architecture.md](../conventions/backend-module-architecture.md) |
| REST API naming, response shapes, pagination, auth guards | [api-conventions.md](../conventions/api-conventions.md) |
| Database migrations (raw-SQL files, TypeORM CLI) | [database-migrations.md](../conventions/database-migrations.md) |
| JWT claims, refresh token storage, token TTLs | [auth-jwt-design.md](../conventions/auth-jwt-design.md) |
| Kafka event envelope, Avro schemas, consumer patterns, outbox | [kafka-events.md](../conventions/kafka-events.md) |
| Structured logging, correlation ID, Grafana Alloy stack | [observability.md](../conventions/observability.md) |
| Angular Material palette, design principles, components | [design-system.md](../conventions/design-system.md) |
| Data lifecycle (scheduled cleanup jobs, token cleanup, outbox cleanup) | [data-lifecycle.md](../conventions/data-lifecycle.md) |
| NestJS TypeScript config, ESLint, money patterns, DTOs, errors | [backend-coding-standards.md](../conventions/backend-coding-standards.md) |
| Angular project structure, state, forms, routing, performance | [frontend-coding-standards.md](../conventions/frontend-coding-standards.md) |
| Test pyramid, coverage thresholds, Jest/Playwright patterns | [testing-guidelines.md](testing-guidelines.md) |
| Claude Code subagent routing (which agent for which task) | [claude-code-subagents.md](claude-code-subagents.md) |

---

<a id="5-technology-decisions-reference"></a>
## 5. Technology decisions reference

All decisions below are signed off in BRD §12 ─ treat as constraints.

| Layer | Technology                               | Notes |
|-------|------------------------------------------|-------|
| Frontend | Angular 22+ + Angular Material           | Standalone components default |
| Backend | NestJS 11+ (modular monolith)            | Microservice-ready; no microservices in V1 |
| Primary DB | PostgreSQL                               | Transactional core, all domain state |
| Document DB | MongoDB                                  | Audit logs, activity feeds, high-write append data only |
| Cache | Redis                                    | Use for short-lived or high-speed data |
| File storage | MinIO                                    | Product images, KYC documents, user assets |
| Search | Elasticsearch / OpenSearch               | Single-node; updated async from Kafka |
| Event bus | Apache Kafka + Confluent Schema Registry | Avro, BACKWARD compatibility |
| ORM | TypeORM                                  | Raw-SQL migrations only; `synchronize: false` always |
| Auth | Passport.js + JWT                        | HS256; 15min access token; opaque refresh in httpOnly cookie |
| Money arithmetic | `decimal.js`                             | Never JS `number` for monetary math |
| Deploy V1 | docker-compose                           | No Kubernetes until V2 |

**Out of scope in V1:** real payment gateway, real shipping integration, reviews/ratings, wishlist, recommendations, seller analytics, dispute mediation, i18n, native mobile, Kubernetes.

---

<a id="6-api-client-generation"></a>
## 6. API client generation

The frontend never calls `HttpClient` directly for API endpoints. It uses a generated Angular client at `libs/api-client/` inside `aliceut-ecom-frontend/`.

### When to regenerate

Regenerate after any change to the backend's OpenAPI spec (`libs/contracts/openapi/aliceut-v1.json`):

1. A new endpoint is added or an existing one changes shape.
2. A DTO field is renamed, added, or removed.
3. A response envelope changes.

### How to regenerate

```bash
# From the frontend workspace root
npm run generate:api-client
```

This script calls `openapi-generator-cli typescript-angular` against `libs/contracts/openapi/aliceut-v1.json` (inside `aliceut-ecom-backend/`) and outputs to `libs/api-client/` inside `aliceut-ecom-frontend/`. The generated files are committed to source control.

### CI enforcement

A CI step runs the generator and diffs the output against the committed `api-client/`. A diff fails the build. This prevents the frontend consuming a stale client after a backend API change. See [backend-module-architecture.md §8](../conventions/backend-module-architecture.md#8-openapi-contract-generation) for the full OpenAPI generation pipeline.

---

<a id="7-database-changes"></a>
## 7. Database changes

**Never use TypeORM `synchronize: true`.** All schema changes go through raw SQL migrations.

### Authoring a migration

1. Add a new `{seq}_{description}.ts` shell plus its `.up.sql` + `.down.sql` pair in `aliceut-ecom-backend/migrations/phase-1/`.
2. Sequence number is 4-digit zero-padded, next in sequence, and the migration class name ends in the same four digits.
3. Test locally: run `npm run migration:run`, verify, then `npm run migration:revert` to confirm rollback works — one migration per invocation.
4. Open a PR in the backend repo, where the migrations live.

See [database-migrations.md](../conventions/database-migrations.md) for SQL rules (concurrent indexes, nullable columns, idempotent down scripts).

### Deploying migrations

Migrations are applied via the `db-migrate.yml` GitHub Actions `workflow_dispatch` in the backend repo ─ never automatically on code deploy, and never from a container entrypoint. Production requires a manual reviewer approval step.

---

<a id="8-mongodb-usage-rules"></a>
## 8. MongoDB usage rules

MongoDB (`MONGODB_URI`) is for **append-only, high-write data with no relational invariants**. Not for domain state.

| Use MongoDB | Use Postgres |
|-------------|-------------|
| User activity feed (product views, search history) | All domain entities (User, Product, Offer, Order) |
| Seller performance audit trail | Any table with foreign-key relationships |
| Admin audit log (KYC decisions, moderation actions) | Financial records (prices, transactions) |
| Notification read/unread state | Cart, inventory, outbox |

**Access pattern:** inject `MongoClient` or a Mongoose model in the relevant NestJS service. MongoDB collections are **not** managed by TypeORM ─ they have their own migration-free schema evolution. Document the collection schema in the relevant module's `README.md` when the collection is first created.

**No transactions across Postgres and MongoDB.** If a domain change must write to both, write to Postgres first (with outbox), then let a Kafka consumer write the denormalized copy to MongoDB. Never attempt a two-phase commit across both stores.

---

<a id="9-minio-usage-rules"></a>
## 9. MinIO usage rules

MinIO (`MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`) stores binary objects. Three buckets in V1:

| Bucket | Contents | Access |
|--------|---------|--------|
| `product-images` | Product and variant images (JPEG/PNG/WebP, max 5 MB each) | Public read, authenticated write |
| `kyc-documents` | KYC submission scans (PDF/JPEG, max 10 MB each) | Private; seller write, admin read |
| `user-assets` | Business logos and user profile images | Private; user read/write for own assets |

### Rules

- **Never store MinIO object URLs in Postgres directly.** Store the object key (e.g. `product-images/products/{productId}/{uuid}.jpg`). Generate presigned URLs at read time.
- **Presigned URL TTL:** 
  - Product images — 1 hour (long, public bucket, CDN-cacheable). 
  - KYC documents — 15 minutes (short, private, one-time download). 
  - User assets — 1 hour.
- **Virus scan on upload:** all KYC documents must pass a ClamAV scan before being made accessible. Block the upload API response until the scan completes (synchronous in V1).
- **Filename policy:** generate a UUIDv7 filename server-side. Never trust the client-supplied filename ─ it is stored only in a metadata column alongside the object key.

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

See [backend-coding-standards.md §3](../conventions/backend-coding-standards.md#3-money-handling-code-patterns) (backend) and [frontend-coding-standards.md §5](../conventions/frontend-coding-standards.md#5-money-display-patterns) (frontend).

### Event-driven writes

Every domain state change that must propagate externally (product, offer, inventory, order, KYC, moderation) publishes via transactional outbox ─ the `outbox_event` row is written in the **same Postgres transaction** as the domain change. No direct Kafka publish from application code.

See [kafka-events.md](../conventions/kafka-events.md) and [backend-module-architecture.md §6](../conventions/backend-module-architecture.md#6-outbox-integration-pattern).

### Order immutability

`FulfillmentItem` snapshots `unit_price`, `currency`, `tax`, `fx_rate_used_at_capture` at checkout. Historical amounts are **never** re-derived from live FX rates or current `Price` rows.

### Auth

Access token lives in memory only (frontend); refresh token in httpOnly cookie only. `JWT_SECRET` must be at least 32 bytes, generated per environment, stored in GitHub Secrets. Never hardcode tokens or secrets in source.

### Prohibited categories

No weapons, drugs, or adult content. Moderation flags on taxonomy + keyword blocklist at listing time. The admin portal enforces this ─ no bypass in any API endpoint.

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
- [ ] **(Backend PRs)** Claude design review has posted findings; all BLOCKER items addressed before merge

See [git-workflow.md §7.3](git-workflow.md#73-ci-pipeline) for the `claude-design-review` CI job setup.

### Manual (self-review before opening PR)

**Domain layer:**
- [ ] No NestJS / TypeORM / class-validator imports inside `domain/` layer
- [ ] Repository interface defines contracts only ─ no TypeORM types leak through

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
- [ ] No direct cross-module service injection except via `index.ts` public API or checkout,inventory approved exception

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
- [ ] No raw `HttpClient` call for API endpoints ─ always use generated client
- [ ] Access token never written to localStorage / sessionStorage
- [ ] Every data-fetching component handles loading / empty / error states
- [ ] All feature routes are lazily loaded

**Docs and migrations:**
- [ ] If a new DB column or table is added, a migration pair exists in `aliceut-ecom-backend/migrations/phase-N/`
- [ ] If a new MongoDB collection is introduced, schema is documented in the module README
- [ ] If a new env var is required, it is added to the `.env.example` file and [backend-coding-standards.md §6.2](../conventions/backend-coding-standards.md#6-environment-config)

