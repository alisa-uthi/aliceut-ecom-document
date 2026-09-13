# Epic: ADMIN — Admin Module

**Epic ID:** ADMIN
**Sprint(s):** 4
**Total Tasks:** 14

## Epic Goal

Admin back-office operations: KYC review, content moderation (flagged listings), and seller suspension/reinstatement. Admin endpoints require `ADMIN` role.

---

## Tasks

### ADMIN-001 — Admin Schema Migrations (moderation_case)

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- File: `libs/admin/src/infrastructure/migrations/0001_admin_schema.sql`
- Raw-SQL migration creating `admin.moderation_case`:
  - `id` (UUIDv7), `offer_id` FK → `catalog.offer(id)`, `flag_reason` (enum: `PROHIBITED_CATEGORY`|`KEYWORD_MATCH`|`MANUAL_REPORT`), `status` (`PENDING`|`RESOLVED`), `resolution` (`moderation_decision` enum per `data-model-erd.md`: `REMOVE`|`DISMISS`) nullable, `resolved_by` FK → `auth.user(id)` nullable, `resolved_at` nullable, `flagged_at`, `created_at`
  - No `WARNED` resolution — dropped from scope (two-outcome model only, matching `api-design/admin.md`'s `/decide` endpoint)
- Indexes: `moderation_case(offer_id)`, `moderation_case(status)`, `moderation_case(flagged_at)`

**Done Criteria:**
- Table created with all constraints
- `status` and `resolution` enums enforced (only `REMOVE`/`DISMISS` accepted for `resolution`)

---

### ADMIN-002 — ModerationCase Entity + Repository Interface

- **US Ref:** US-A-03
- **Estimate:** M
- **Dependencies:** ADMIN-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes:**
- File: `libs/admin/src/moderation/moderation-case.entity.ts`
- `ModerationCaseRepository` interface (portability seam, NFR-18) behind DI token; TypeORM implementation registered separately
- Methods: `create`, `findQueue(filters)`, `findById`, `resolve(id, resolution, resolvedBy)`

**Done Criteria:**
- Repository CRUD covered by unit tests against the interface (not the TypeORM impl directly)

---

### ADMIN-003 — GET /admin/kyc

- **US Ref:** US-A-01
- **Estimate:** M
- **Dependencies:** SELLER-003
- **Spec References:** `phase-1/technical-design/api-design/admin.md` (KYC endpoints)

**Implementation Notes:**
- `GET /admin/kyc` — `@JwtAuthGuard` + `@Roles('ADMIN')`; paginated pending-KYC queue
- Filter: `?country=` ; Sort: `?sortBy=submittedAt` (default oldest-first — fair queue)
- Response includes SLA badge data (elapsed time since submission vs. SLA threshold) — exact response shape per `api-design/admin.md`'s KYC list endpoint

**Done Criteria:**
- Only pending applications returned
- `?country=` filters correctly; default sort is oldest-submitted-first
- SLA badge reflects correct elapsed-time bucket

---

### ADMIN-004 — POST /admin/kyc/:id/approve

- **US Ref:** US-A-02
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/kyc/:id/approve` — `@Roles('ADMIN')`
- Activates the seller (`kyc_status = APPROVED`); publishes `seller.kyc.decided` via outbox (`{sellerId, decision: 'APPROVED'}`), triggering ET-06 (seller approved email) per `email-templates.md`
- Request/response shape exactly per `api-design/admin.md`'s KYC decide endpoint

**Done Criteria:**
- Approve → seller can access catalog/inventory/pricing endpoints
- `seller.kyc.decided` outbox event written in the same transaction as the status update

---

### ADMIN-005 — POST /admin/kyc/:id/reject

- **US Ref:** US-A-02
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/kyc/:id/reject { reason: string }` — `@Roles('ADMIN')`; `reason` required (400 if missing)
- Sets `kyc_status = REJECTED`; publishes `seller.kyc.decided` via outbox (`{sellerId, decision: 'REJECTED', reason}`), triggering ET-07 per `email-templates.md`

**Done Criteria:**
- Reject without `reason` → 400
- `seller.kyc.decided` outbox event carries the rejection reason

---

### ADMIN-006 — GET /admin/moderation

- **US Ref:** US-A-03
- **Estimate:** M
- **Dependencies:** ADMIN-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md` (moderation list endpoint)

**Implementation Notes:**
- `GET /admin/moderation` — `@Roles('ADMIN')`; paginated flagged-listings queue
- Returns `moderation_case` rows with `status = PENDING`, sorted by `flagged_at DESC`
- Joined with `catalog.offer`/`catalog.product`/seller info for display — exact response shape per `api-design/admin.md`

**Done Criteria:**
- Queue shows only `PENDING` cases
- Sorted `flagged_at DESC`

---

### ADMIN-007 — POST /admin/moderation/:caseId/decide

- **US Ref:** US-A-04, US-A-04b
- **Estimate:** L
- **Dependencies:** ADMIN-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/moderation/:caseId/decide { decision: 'REMOVE'|'DISMISS', reason?: string }` — `@Roles('ADMIN')`; exact request/response shape per `api-design/admin.md`'s combined decide endpoint
- `reason` required when `decision = REMOVE` (400 if missing); optional for `DISMISS`
- `REMOVE` branch: sets `catalog.offer.status = REMOVED`, `moderation_case.resolution = REMOVE`, `resolved_at`, `resolved_by`; publishes `moderation.listing.removed` via outbox — this event drives ET-09 as a **daily digest** (not a direct email), per `kafka-events.md` §2 / `email-templates.md`
- `DISMISS` branch: listing stays live (`catalog.offer.status = ACTIVE`), sets `moderation_case.resolution = DISMISS`, `resolved_at`, `resolved_by`; publishes `offer.changed` via outbox per `api-design/admin.md`'s DB-mapping table

**Done Criteria:**
- `REMOVE` without `reason` → 400
- `REMOVE` → offer status → `REMOVED`; `moderation.listing.removed` outbox event written in the same transaction
- `DISMISS` → offer remains `ACTIVE`; `moderation_case.resolution = DISMISS`; `offer.changed` outbox event written in the same transaction
- Deciding an already-resolved case → 404/409 (case not found in `PENDING` state)

---

### ADMIN-008 — POST /admin/sellers/:id/suspend

- **US Ref:** US-A-05
- **Estimate:** L
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/sellers/:id/suspend { reason: string, durationDays?: number }` — `@Roles('ADMIN')`; `durationDays` omitted = indefinite
- Sets seller `status = SUSPENDED`, `suspended_until` (if duration given)
- Deactivates all `ACTIVE` offers for the seller
- Publishes `seller.suspended` via outbox (`{sellerId, reason, expiresAt}`) — triggers ET-10 per `email-templates.md`

**Done Criteria:**
- Suspend → seller `status = SUSPENDED`; all `ACTIVE` offers deactivated
- `seller.suspended` outbox event written in the same transaction

---

### ADMIN-009 — POST /admin/sellers/:id/reinstate

- **US Ref:** US-A-05b
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/sellers/:id/reinstate { notes?: string }` — `@Roles('ADMIN')`; early/manual lift (before `suspended_until` elapses)
- Reactivates only offers deactivated **because of this suspension** (not offers a seller deliberately deactivated themselves)
- Sets seller `status = ACTIVE`; clears `suspended_until`
- Publishes `seller.reinstated` via outbox — triggers ET-12 per `email-templates.md`

**Done Criteria:**
- Reinstate → seller `status = ACTIVE`; only suspension-deactivated offers reactivated
- Reinstating a non-suspended seller → 422
- `seller.reinstated` outbox event written in the same transaction

---

### ADMIN-010 — GET /admin/sellers

- **US Ref:** US-A-06
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- `GET /admin/sellers` — `@Roles('ADMIN')`; paginated
- Search: `?search=` matches name, email, or `tax_id`
- Exact response shape per `api-design/admin.md`'s seller-list endpoint

**Done Criteria:**
- `?search=` matches partial name/email/tax_id (case-insensitive)

---

### ADMIN-011 — GET /admin/sellers/:id

- **US Ref:** US-A-06
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- `GET /admin/sellers/:id` — `@Roles('ADMIN')`; full profile
- Includes: KYC status (+ application history), active listings, moderation history (`moderation_case` rows joined via seller's offers)
- Exact response shape per `api-design/admin.md`'s seller-detail endpoint

**Done Criteria:**
- Full seller detail includes KYC status, listings, and moderation history
- Seller not found → 404

---

### ADMIN-012 — GET /admin/dashboard

- **US Ref:** US-A-00
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- `GET /admin/dashboard` — `@Roles('ADMIN')`
- Live counts: pending KYC applications, flagged listings (`moderation_case` with `status = PENDING`), suspended sellers, SLA breaches (KYC applications past SLA threshold)
- Exact response shape per `api-design/admin.md`'s dashboard endpoint

**Done Criteria:**
- Counts match direct DB queries for each metric
- SLA breach count reflects the same threshold used in ADMIN-003's badge logic

---

### ADMIN-013 — Suspension Expiry Scheduler

- **US Ref:** US-P-18
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- File: `apps/workers/src/schedulers/suspension-expiry.scheduler.ts`
- Polls `SELECT * FROM seller.seller_profile WHERE status = 'SUSPENDED' AND suspended_until <= now() LIMIT 50 FOR UPDATE SKIP LOCKED`
- For each: reactivate suspension-deactivated offers, set `status = ACTIVE`, publish `seller.suspension_expired` via outbox — triggers ET-11 per `email-templates.md`
- `SKIP LOCKED` prevents double-processing across multiple worker instances

**Done Criteria:**
- Seller suspended with a duration: auto-reinstated within one poll cycle of expiry
- `seller.suspension_expired` outbox event published
- Multiple worker instances: no double-reinstatement

---

### ADMIN-014 — Outbox Events Wiring

- **US Ref:** US-P-10
- **Estimate:** M
- **Dependencies:** PLATFORM-004
- **Spec References:** `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- Verifies/wires the full set of outbox events this epic is responsible for producing: `seller.kyc.decided` (ADMIN-004/005), `seller.suspended` (ADMIN-008), `seller.reinstated` (ADMIN-009), `seller.suspension_expired` (ADMIN-013), `moderation.listing.removed` and `offer.changed` (both ADMIN-007, per decision branch)
- No new topics introduced beyond the catalog in `kafka-events.md` §1

**Done Criteria:**
- Each of the 6 named events is observed on its Kafka topic during an end-to-end test of the corresponding ADMIN flow
- Event schemas validate against the Avro schemas registered per PLATFORM-004
