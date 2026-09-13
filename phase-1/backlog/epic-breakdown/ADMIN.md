# Epic: ADMIN — Admin Module

**Epic ID:** ADMIN  
**Sprint(s):** 5  
**Total Tasks:** 15  

## Epic Goal

Admin back-office operations: KYC review, seller suspension/reinstatement, content moderation, user management, and platform monitoring. All admin actions are audited. Admin endpoints require `ADMIN` role.

---

## Tasks

### ADMIN-001 — admin Schema Migrations

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- File: `libs/admin/src/infrastructure/migrations/0001_admin_schema.sql`
- Tables:
  - `admin.moderation_case`: id (UUIDv7), offer_id FK → `catalog.offer(id)`, status (`PENDING`|`REVIEWING`|`RESOLVED`|`DISMISSED`), assigned_to FK → `auth.user(id)` nullable, flag_reason (enum: `PROHIBITED_CATEGORY`|`KEYWORD_MATCH`|`MANUAL_REPORT`), resolution (`REMOVED`|`CLEARED`|`WARNED`) nullable, reviewer_notes TEXT nullable, resolved_at nullable, created_at
  - `admin.suspension_history`: id (UUIDv7), seller_id FK, suspended_by FK → `auth.user(id)`, reason TEXT, duration_days INT nullable, expires_at TIMESTAMP nullable, reinstated_at nullable, reinstated_by FK nullable, created_at
- Indexes: `moderation_case(offer_id)`, `moderation_case(status)`, `suspension_history(seller_id)`

**Done Criteria:**
- Tables created with all constraints
- `moderation_case.status` enum enforced

---

### ADMIN-002 — KYC Review: GET /admin/kyc/queue

- **US Ref:** US-A-01
- **Estimate:** M
- **Dependencies:** SELLER-003
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /admin/kyc/queue` — `@JwtAuthGuard` + `@Roles('ADMIN')`
- Returns paginated list of `seller.kyc_application` rows with `status = 'SUBMITTED'`
- Joined with `seller.seller_profile` and `auth.user` for context
- Response per item: `{ applicationId, sellerId, sellerDisplayName, businessName, documentType, submittedAt, documentFrontUrl (presigned, 900s) }`
- Sorted by `submitted_at ASC` (oldest first — fair queue)
- Filter: `?sellerId=` to look up specific seller

**Done Criteria:**
- Only SUBMITTED applications returned
- Presigned URL valid for 900s
- Sorted oldest first

---

### ADMIN-003 — KYC Review: POST /admin/kyc/:id/decide

- **US Ref:** US-A-01
- **Estimate:** M
- **Dependencies:** ADMIN-002, PLATFORM-003
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/kyc/:id/decide { decision: 'APPROVED'|'REJECTED', reviewNotes?: string }` — `@Roles('ADMIN')`
- For `APPROVED`:
  - Update `kyc_application.status = 'APPROVED'`, set `reviewed_at`, `reviewer_id`
  - Update `seller.seller_profile.kyc_status = 'APPROVED'`
  - Publish `seller.kyc.decided` outbox event `{ sellerId, decision: 'APPROVED' }`
- For `REJECTED`:
  - `reviewNotes` required (400 if missing)
  - Update `kyc_application.status = 'REJECTED'`
  - Update `seller.seller_profile.kyc_status = 'REJECTED'`
  - Publish `seller.kyc.decided` event `{ sellerId, decision: 'REJECTED', reviewNotes }`
- Log to MongoDB audit via `AuditLogService.log()`

**Done Criteria:**
- Approve → seller can now access catalog/inventory/pricing endpoints
- Reject without reviewNotes → 400
- `seller.kyc.decided` event in Kafka within 2s

---

### ADMIN-004 — GET /admin/sellers (seller list)

- **US Ref:** US-A-06
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /admin/sellers` — `@Roles('ADMIN')`; paginated cursor-based
- Filters: `?status=ACTIVE|SUSPENDED|CLOSED&kycStatus=PENDING|UNDER_REVIEW|APPROVED|REJECTED&search=<name>`
- Response: `{ id, displayName, businessName, kycStatus, status, createdAt, activeListings, suspensionExpiresAt }`
- `activeListings`: subquery count from `catalog.offer`
- `search`: matches `display_name` or `business_name` (case-insensitive)

**Done Criteria:**
- Filter `?status=SUSPENDED` returns only suspended sellers
- `search=alice` matches partial names (case-insensitive)

---

### ADMIN-005 — GET /admin/sellers/:id (seller detail)

- **US Ref:** US-A-06
- **Estimate:** S
- **Dependencies:** ADMIN-004, SELLER-003
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /admin/sellers/:id` — `@Roles('ADMIN')`
- Returns full seller profile + latest KYC application + suspension history + active listings count + fulfillment stats
- `suspensionHistory`: last 5 entries from `admin.suspension_history`
- `kycApplications`: all applications (history, not just latest)

**Done Criteria:**
- Full seller detail with KYC history and suspension log
- Seller not found → 404

---

### ADMIN-006 — GET /admin/users (user list)

- **US Ref:** US-A-05
- **Estimate:** M
- **Dependencies:** AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /admin/users` — `@Roles('ADMIN')`; paginated
- Filters: `?role=BUYER|SELLER|ADMIN&isEmailVerified=true|false&search=<email|name>`
- Response: `{ id, email, displayName, role, isEmailVerified, createdAt, lastLoginAt }`
- `lastLoginAt`: from latest `auth.refresh_token` `created_at` or `auth.user.last_login_at` field

**Done Criteria:**
- Filter by role works
- Search by email partial match works
- `lastLoginAt` populated from latest refresh token created_at

---

### ADMIN-007 — GET/PATCH /admin/users/:id (user detail + role management)

- **US Ref:** US-A-05
- **Estimate:** M
- **Dependencies:** ADMIN-006, AUTH-014
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /admin/users/:id` — returns full user profile + roles + linked seller profile (if any)
- `PATCH /admin/users/:id { role?: 'BUYER'|'SELLER'|'ADMIN' }` — role change
  - ADMIN cannot demote themselves (403 if `req.user.sub === userId`)
  - Upgrading to SELLER: calls `SellerService.getOrCreateProfile(userId)`
  - Downgrading from SELLER: do NOT auto-delete seller data (history preserved)
- `POST /admin/users/:id/close-account` — sets `auth.user.status = 'CLOSED'`; revokes all tokens; publishes `account.closed` event
- Log all changes to MongoDB audit

**Done Criteria:**
- Admin cannot change their own role
- Role upgrade to SELLER → seller profile created
- Account closure → tokens revoked; user cannot log in

---

### ADMIN-008 — Content Moderation: GET /admin/moderation/queue

- **US Ref:** US-A-02, US-A-03
- **Estimate:** M
- **Dependencies:** ADMIN-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /admin/moderation/queue` — `@Roles('ADMIN')`; paginated
- Returns `moderation_case` rows with `status = 'PENDING'|'REVIEWING'`
- Joined with `catalog.offer`, `catalog.product`, `auth.user` (seller)
- Response per case: `{ caseId, offerId, productTitle, productImageUrl, sellerId, sellerName, flagReason, status, createdAt }`
- Sorted by `created_at ASC`

**Done Criteria:**
- Queue shows pending and reviewing cases
- Sorted oldest first

---

### ADMIN-009 — Content Moderation: POST /admin/moderation/:id/resolve

- **US Ref:** US-A-02, US-A-03
- **Estimate:** M
- **Dependencies:** ADMIN-008, PLATFORM-003
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/moderation/:id/resolve { resolution: 'REMOVED'|'CLEARED'|'WARNED', reviewerNotes?: string }` — `@Roles('ADMIN')`
- For `REMOVED`:
  - Update `catalog.offer.status = 'REMOVED'`
  - Publish `moderation.listing.removed` outbox event (triggers SEARCH-005, NOTIFICATIONS-006)
- For `CLEARED`:
  - Update `moderation_case.resolution = 'CLEARED'`
  - Publish `moderation.listing.cleared` event (triggers seller notification)
- For `WARNED`:
  - Update case; publish `moderation.listing.warned` event (triggers seller notification)
- Update `moderation_case.status = 'RESOLVED'`, `resolved_at = now()`, `assigned_to = req.user.sub`
- Log to audit

**Done Criteria:**
- REMOVED: offer status = REMOVED; `moderation.listing.removed` in Kafka; ES document deleted (via SEARCH-005)
- CLEARED: seller notified; case resolved
- Resolving non-existent case → 404

---

### ADMIN-010 — Seller Suspension: POST /admin/sellers/:id/suspend

- **US Ref:** US-A-07
- **Estimate:** M
- **Dependencies:** SELLER-010, ADMIN-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/sellers/:id/suspend { reason: string, durationDays?: number }` — `@Roles('ADMIN')`
- Calls `SellerService.suspend(sellerId, reason, durationDays)`
- Insert `admin.suspension_history` row
- Publishes `seller.suspended` event (payload: `{ sellerId, reason, expiresAt }`)
- Side effects via Kafka consumers:
  - CATALOG: deactivate all ACTIVE offers
  - ORDERS: auto-refund PROCESSING fulfillments (ORDERS-018)
  - SEARCH: hide products (SEARCH-004)
  - NOTIFICATIONS: notify seller (NOTIFICATIONS-006)
- `durationDays` null = indefinite

**Done Criteria:**
- Suspend → seller `status = SUSPENDED`; all ACTIVE offers deactivated
- `seller.suspended` event in Kafka
- `suspension_history` row inserted

---

### ADMIN-011 — Seller Reinstatement: POST /admin/sellers/:id/reinstate

- **US Ref:** US-A-07
- **Estimate:** M
- **Dependencies:** ADMIN-010
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /admin/sellers/:id/reinstate { notes?: string }` — `@Roles('ADMIN')`
- Calls `SellerService.reinstate(sellerId)`
- Update `suspension_history.reinstated_at = now()`, `reinstated_by = req.user.sub`
- Publishes `seller.reinstated` event
- Side effects via Kafka:
  - CATALOG: reactivate offers with `status_changed_reason = 'SUSPENSION'`
  - SEARCH: restore products in ES
  - NOTIFICATIONS: notify seller

**Done Criteria:**
- Reinstate → seller `status = ACTIVE`; suspended offers reactivated
- `seller.reinstated` event in Kafka
- Reinstating non-suspended seller → 422

---

### ADMIN-012 — Suspension Expiry Scheduler

- **US Ref:** US-A-07
- **Estimate:** M
- **Dependencies:** ADMIN-010
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- File: `apps/workers/src/schedulers/suspension-expiry.scheduler.ts`
- Cron: every 10 minutes
- Query: `SELECT * FROM seller.seller_profile WHERE status = 'SUSPENDED' AND suspension_expires_at < now() LIMIT 50 FOR UPDATE SKIP LOCKED`
- For each: call `SellerService.reinstate(sellerId)`; update `suspension_history`; publish `seller.reinstated` event
- `SKIP LOCKED`: prevents multiple worker instances from processing same row

**Done Criteria:**
- Seller suspended for 1 day: auto-reinstated within 10 min of expiry
- `seller.reinstated` event published
- Multiple workers: no double-reinstatement (SKIP LOCKED)

---

### ADMIN-013 — GET /admin/moderation/auto-flagged (auto-moderation queue)

- **US Ref:** US-A-03
- **Estimate:** M
- **Dependencies:** CATALOG-010, ADMIN-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /admin/moderation/auto-flagged` — `@Roles('ADMIN')`
- Returns moderation cases with `flag_reason = 'PROHIBITED_CATEGORY'` or `'KEYWORD_MATCH'` (system-generated, not manually reported)
- These cases are created by `CatalogService.checkModeration()` on listing creation/update
- Shows: offer details, matched category/keyword, seller info
- Allows bulk dismiss (POST /admin/moderation/bulk-dismiss) for false positives

**Done Criteria:**
- Auto-flagged cases separated from manual reports
- Bulk dismiss endpoint marks multiple cases as `resolution = 'CLEARED'`

---

### ADMIN-014 — GET /admin/platform/health

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- `GET /admin/platform/health` — `@Roles('ADMIN')` (more detailed than public `/health`)
- Returns:
  - Postgres: `{ status: 'up'|'down', latencyMs }`
  - MongoDB: `{ status, latencyMs }`
  - Redis: `{ status, latencyMs }`
  - Kafka: `{ status, topicCount, consumerGroupLag: [{ group, lag }] }`
  - Elasticsearch: `{ status, indexCount, documentsCount }`
  - MinIO: `{ status, buckets: [name] }`
- Each check uses timeout 3s; failure = `status: 'down'`
- Aggregate: if any `status = 'down'` → HTTP 503 overall; else 200

**Done Criteria:**
- All services up: 200 with all status = 'up'
- Kill Redis → 503 with Redis status = 'down'

---

### ADMIN-015 — GET /admin/audit-log

- **US Ref:** US-A-08
- **Estimate:** M
- **Dependencies:** PLATFORM-004
- **Spec References:** `phase-1/technical-design/api-design/admin.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /admin/audit-log` — `@Roles('ADMIN')`; queries MongoDB `audit_logs`
- Filters: `?actorId=&targetType=User|Seller|Offer|Order|KycApplication&targetId=&from=&to=&action=`
- Response: paginated list of audit entries `{ id, actorId, actorEmail, action, targetType, targetId, metadata, createdAt }`
- Sorted: `createdAt DESC`
- Used for: compliance, fraud investigation, admin accountability
- `actorEmail` resolved by joining `auth.user` table (or MongoDB stores it inline)

**Done Criteria:**
- Filter by `targetType=Seller&targetId={id}` returns all admin actions on that seller
- Filter by `actorId` returns all actions by a specific admin
- Date range filter works
