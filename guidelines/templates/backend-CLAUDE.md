# CLAUDE.md — aliceut-ecom-backend

> Copy this file to the root of `aliceut-ecom-backend/` as `CLAUDE.md` on first clone.
> Full conventions live in sibling repo `../aliceut-ecom-document/`. Read them before proposing architectural changes.

---

## Repo identity

NestJS 11+ modular monolith. Phase 1. Single HTTP API (`apps/api`) + Kafka workers (`apps/workers`) + domain libs (`libs/`).

## Locked stack (BRD §12 — treat as constraints, not suggestions)

| Layer | Technology |
|-------|-----------|
| Framework | NestJS 11+ |
| Primary DB | PostgreSQL — TypeORM, `synchronize: false`, raw-SQL migrations only |
| Document DB | MongoDB — audit/activity append-only data only |
| Cache | Redis |
| Object storage | MinIO |
| Search | Elasticsearch single-node — updated async from Kafka, never sync |
| Event bus | Apache Kafka + Confluent Schema Registry (Avro, BACKWARD compat) |
| Auth | Passport.js (local + Google + Facebook) + JWT refresh rotation |
| Money | `decimal.js` — never JS `number` for monetary math |
| Deploy | docker-compose (V1) |

---

## Module tiers

Three tiers. Pick based on domain complexity — never apply Tier 1 where Tier 2 suffices.

| Tier | Pattern | Example Modules                                     |
|------|---------|-----------------------------------------------------|
| **1 — Full hexagonal** | `domain/` → `application/` → `infrastructure/` + repository interfaces | `catalog`, `orders`, `pricing`, `inventory`, `cart` |
| **2 — Simplified service** | `service/` + TypeORM entity + controller | `identity`, `seller`, `admin`                       |
| **3 — Thin / infra** | No owned domain entities; pure read models or event fan-out | `search`, `notifications`, `platform`, `workers`    |

Full layout: `../aliceut-ecom-document/conventions/backend-module-architecture.md`

## Layer dependency rules (Tier 1)

```
domain/ ← application/ ← infrastructure/
```

- `domain/` has **zero** framework imports. No NestJS, no TypeORM, no class-validator.
- `application/` imports only `domain/`. No TypeORM types leak through repository interfaces.
- `infrastructure/` implements repository interfaces; TypeORM lives here only.
- Cross-module access via `index.ts` public API only — no deep imports into another module's internals.

---

## Non-negotiables — read before writing any code

### Money (every violation is a PR blocker)

- Storage: `NUMERIC(19,4)` + ISO 4217 currency code column. FX rates: `NUMERIC(19,8)`.
- Arithmetic: `decimal.js` or `Money` value object. No `+`, `*`, `/` on monetary values.
- TypeORM column: `type: 'numeric'` + `numericStringTransformer` — stores as string, reads as string.
- DTO wire format: amounts as **strings** (`"99.99"`), never JSON numbers.
- TypeScript: monetary fields typed `string` at boundaries, `Decimal` inside arithmetic. `number` on a monetary field is a lint error.
- V1 seller currencies: `USD`, `THB`, `JPY`, `SGD` only. Reject anything else at DTO validation.

Full patterns: `../aliceut-ecom-document/conventions/backend-coding-standards.md §3`

### Event-driven writes (transactional outbox)

- Every domain state change that propagates externally (product, offer, inventory, order, KYC, moderation) publishes via outbox.
- The `outbox_event` row is written in the **same Postgres transaction** as the domain change.
- No direct Kafka publish from application code — only the outbox relay (in `apps/workers`) publishes to Kafka.
- Elasticsearch updated **async from Kafka events** — never sync from API handlers.
- Email and in-app notifications driven by Kafka consumers — never inline in handlers.
- Every event must have: `event_id` (UUIDv7), `event_type`, `event_version`, `occurred_at`, `correlation_id`, `payload`.
- Consumers: idempotent (dedupe on `event_id`), at-least-once, commit offset after side-effect, DLQ per consumer group.

Full patterns: `../aliceut-ecom-document/conventions/kafka-events.md`

### Order immutability

`FulfillmentItem` snapshots `unit_price`, `currency`, `tax`, `fx_rate_used_at_capture` at checkout. Never re-derive historical amounts from live FX rates or current `Price` rows.

### Auth

Access token in memory only (frontend responsibility). Refresh token in httpOnly cookie only. `JWT_SECRET` ≥ 32 bytes. Never hardcode tokens or secrets.

Full spec: `../aliceut-ecom-document/conventions/auth-jwt-design.md`

### Pricing model

```
Product → Offer (per seller) → Price (per currency, per price_type)
```

Cart and `FulfillmentItem` reference `Offer`, not `Product`. Never store price on `Product`.

### Prohibited categories

No weapons, drugs, adult content. Moderation keyword blocklist enforced at listing time.

---

## Database migrations

- All schema changes are raw SQL files in `migrations/phase-N/`.
- Naming: `{4-digit-seq}_{description}.up.sql` + `.down.sql`.
- Never use TypeORM `synchronize: true`.
- Test locally: `migrate up`, verify, `migrate down 1`.
- Applied via GitHub Actions `workflow_dispatch` in `aliceut-ecom-utility-pipeline` — never auto-run on deploy.

Full rules: `../aliceut-ecom-document/conventions/database-migrations.md`

---

## Subagent routing

Install: `claude plugin install voltagent/awesome-claude-code-subagents` (one-time per machine).

| Task | Agent |
|------|-------|
| Implement backend feature / fix | `voltagent-core-dev:backend-developer` |
| Docker / Compose changes | `voltagent-infra:docker-expert` |
| CI/CD pipeline changes | `voltagent-infra:devops-engineer` |
| Write integration tests / E2E | `voltagent-qa-sec:qa-expert` |
| Local review before push | `voltagent-qa-sec:code-reviewer` + `voltagent-qa-sec:performance-engineer` (run both in parallel) |
| Auth / KYC / financial code | also add `voltagent-qa-sec:security-auditor` |
| Complex migration / query tuning | also add `voltagent-infra:database-administrator` |

Full guide: `../aliceut-ecom-document/guidelines/claude-code-subagents.md`

---

## Full conventions reference

All paths relative to the sibling `aliceut-ecom-document/` repo:

| Concern | File |
|---------|------|
| Module tiers, layer rules, CQRS-lite, outbox | `conventions/backend-module-architecture.md` |
| TypeScript config, ESLint, money patterns, DTOs, errors | `conventions/backend-coding-standards.md` |
| Kafka event envelope, Avro, consumer idempotency, DLQ | `conventions/kafka-events.md` |
| JWT claims, refresh token storage, TTLs | `conventions/auth-jwt-design.md` |
| Raw-SQL migrations, golang-migrate, rollback rules | `conventions/database-migrations.md` |
| REST naming, response shapes, pagination, auth guards | `conventions/api-conventions.md` |
| Structured logging, correlation ID | `conventions/observability.md` |
| MongoDB usage rules | `guidelines/development-flow.md §8` |
| MinIO usage rules | `guidelines/development-flow.md §9` |
| Git branching, commits, PR template, releases | `guidelines/git-workflow.md` |
| Test pyramid, coverage thresholds, Jest patterns | `guidelines/testing-guidelines.md` |
| Daily dev workflow, local setup | `guidelines/development-flow.md` |

---

## Pre-merge checklist (compact)

Full checklist: `../aliceut-ecom-document/guidelines/development-flow.md §11`

**Domain layer**
- [ ] No NestJS/TypeORM/class-validator imports inside `domain/`
- [ ] Repository interface exposes no TypeORM types

**Money**
- [ ] No `number` type on any monetary field
- [ ] All arithmetic uses `decimal.js` / `Money` VO
- [ ] JSON responses: monetary fields are strings

**Events**
- [ ] Outbox row written in same transaction as domain change
- [ ] Consumer deduplicates on `event_id`
- [ ] All required envelope fields present

**Security**
- [ ] No hardcoded secrets
- [ ] No stack trace / SQL detail in error responses

**Tests**
- [ ] New API endpoint has Supertest integration test
- [ ] New Tier 1 handler has unit tests (happy path + error path)
