# EPIC: ADMIN — Admin Module

**Sprint:** 4
**Lib:** `libs/admin/`
**Module:** `AdminModule`
**Controllers:** `AdminController`
**Kafka producers:** `seller.kyc.decided`, `seller.suspended`, `seller.reinstated`, `seller.suspension_expired`, `moderation.listing.removed`, `listing.flagged`

Overview: Provides the admin portal's backend functionality: KYC review, catalog moderation, seller suspension, and seller search. All endpoints require `ADMIN` role (403 on wrong role). Suspension and reinstatement emit events consumed by the Search module for bulk offer visibility updates.

---

### ADMIN-001 — admin Schema Migrations
**US Ref:** —
**Estimate:** M
**Dependencies:** PLATFORM-001
**Implementation Notes:**
- File: `libs/admin/src/infrastructure/migrations/0001_admin_schema.sql`
- Table: `admin.moderation_case`; all columns per data-model-erd.md admin section
- FK: `moderation_case.offer_id → catalog.offer(id)` (cross-schema; after catalog)
- FK: `moderation_case.decided_by_user_id → identity.user(id)` (cross-schema; after identity)
- Index: `moderation_case(offer_id)`, `moderation_case(status)`, `moderation_case(created_at)`

**Done Criteria:**
- `admin.moderation_case` table created; can insert test row

---

### ADMIN-002 — ModerationCase Entity + Repository Interface
**US Ref:** US-A-03
**Estimate:** M
**Dependencies:** ADMIN-001
**Implementation Notes:**
- TypeORM entity for `admin.moderation_case`
- `ModerationCaseRepository`: `findOpen()`, `findByOffer(offerId)`, `findById(id)`, `save(case)`
- `ModerationCase.resolve(decision, reason, decidedByUserId)`: set `status = RESOLVED`, `decision`, `decided_at`, `decided_by_user_id`

**Done Criteria:**
- ModerationCase entity + repository work; resolve method sets correct fields

---

### ADMIN-003 — GET /admin/kyc
**US Ref:** US-A-01
**Estimate:** M
**Dependencies:** SELLER-003
**Implementation Notes:**
- `@Roles('ADMIN')` + pagination query params (`page`, `limit`, `country?`, `sortBy: 'submitted_at'`)
- Returns `PaginatedResponseDto<KycApplicationDto>`
- Each row: `{ kyc_application_id, seller_id, business_name, country, submitted_at, days_pending, is_resubmission, prior_rejection_reason?, sla_breach (days_pending > 3) }`
- SLA breach: `NOW() > submitted_at + INTERVAL '72 hours'` → `sla_breach: true`
- Filter: `WHERE kyc_status = 'UNDER_REVIEW'` (submitted, not yet decided)
- Sort: `submitted_at ASC` (oldest first, default) or as specified

**Done Criteria:**
- Returns paginated list of UNDER_REVIEW applications; SLA breach flag correct

---

### ADMIN-004 — POST /admin/kyc/:id/approve
**US Ref:** US-A-02
**Estimate:** M
**Dependencies:** SELLER-002, SELLER-003
**Implementation Notes:**
- Approves a KYC application
- Transaction:
  1. Set `kyc_application.status = APPROVED`, `decided_at = now()`, `reviewer_user_id = admin user id`
  2. Set `seller_profile.kyc_status = APPROVED`
  3. Publish `seller.kyc.decided` outbox event (`{ decision: 'APPROVED', seller_id, ... }`)
- Returns 200 with updated seller profile
- Idempotent: approving an already-approved application returns 200 without re-writing
- Log document view access per NFR-09

**Done Criteria:**
- Approve → seller_profile.kyc_status = APPROVED; `seller.kyc.decided` event in outbox
- Seller can now create listings (SellerKycGuard passes)

---

### ADMIN-005 — POST /admin/kyc/:id/reject
**US Ref:** US-A-02
**Estimate:** M
**Dependencies:** SELLER-002, SELLER-003
**Implementation Notes:**
- DTO: `RejectKycDto { reason: string (≤500 chars) }`
- Transaction:
  1. `kyc_application.status = REJECTED`, `decision_reason = reason`, `decided_at`, `reviewer_user_id`
  2. `seller_profile.kyc_status = REJECTED` (seller can resubmit)
  3. Publish `seller.kyc.decided` (`{ decision: 'REJECTED', rejection_reason, ... }`)
- Seller notified via ET-07 (Notification consumer)

**Done Criteria:**
- Reject → seller_profile.kyc_status = REJECTED; seller can resubmit via SELLER-007

---

### ADMIN-006 — GET /admin/moderation
**US Ref:** US-A-03
**Estimate:** M
**Dependencies:** ADMIN-002
**Implementation Notes:**
- Returns open moderation cases: `WHERE status = 'OPEN'`
- Each row: `{ case_id, offer_id, product_title, seller_name, flag_reason, source, flagged_at, offer_snippet }`
- Sort: `flagged_at DESC`
- Paginated; `@Roles('ADMIN')`

**Done Criteria:**
- Returns only OPEN cases; sorted by flagged_at DESC

---

### ADMIN-007 — POST /admin/moderation/:id/remove
**US Ref:** US-A-04
**Estimate:** L
**Dependencies:** ADMIN-002, CATALOG-011
**Implementation Notes:**
- DTO: `RemoveListingDto { reason: RemovalReason (PROHIBITED_CATEGORY|IP_VIOLATION|MISLEADING|OTHER), freeText: string }`
- Transaction:
  1. Resolve `moderation_case` with `decision = REMOVE`
  2. Set `offer.status = REMOVED`, `offer.status_changed_reason = 'ADMIN_REMOVAL'`
  3. If all offers for a product are REMOVED: set `product.status = REMOVED`
  4. Write `pending_listing_removal_digest` staging row (for ET-09 daily digest)
  5. Publish `moderation.listing.removed` outbox event
- Pending PENDING orders for removed listings remain active (seller still responsible)
- Audit record created automatically (admin user + timestamp + reason)

**Done Criteria:**
- Remove listing → offer.status = REMOVED; `moderation.listing.removed` event in outbox
- Staging row added to `pending_listing_removal_digest`
- Product removed from search (via Search module's Kafka consumer)

---

### ADMIN-008 — POST /admin/moderation/:id/clear
**US Ref:** US-A-04b
**Estimate:** M
**Dependencies:** ADMIN-002, CATALOG-011
**Implementation Notes:**
- DTO: `ClearFlagDto { note?: string (≤500 chars) }`
- Transaction:
  1. Resolve `moderation_case` with `decision = DISMISS`
  2. Transition offer from `FLAGGED → ACTIVE`
  3. Publish updated `offer.changed` event (offer reactivated)
- Listing stays live; flag resolved; Search consumer reactivates in index
- Audit record: admin + timestamp + note
- Cleared listings do not re-trigger same auto-flag unless content changes (guard re-runs on next edit)

**Done Criteria:**
- Clear → offer.status = ACTIVE; moderation_case = RESOLVED/DISMISSED
- `offer.changed` event published; ES document updated

---

### ADMIN-009 — POST /admin/sellers/:id/suspend
**US Ref:** US-A-05
**Estimate:** L
**Dependencies:** SELLER-002, CATALOG-011
**Implementation Notes:**
- DTO: `SuspendSellerDto { reason: string, duration: '7d'|'30d'|'90d'|'permanent' }`
- Transaction:
  1. Set `seller_profile.suspension_status = SUSPENDED`, `suspended_until` (null for permanent), `suspension_reason`
  2. Set all seller's `ACTIVE` offers to `INACTIVE` with `status_changed_reason = 'SUSPENSION'`
  3. Publish `seller.suspended` outbox event
- Edge cases:
  - Already permanently suspended → 409 "Seller is already permanently suspended"
  - Already temporarily suspended → allow update (extend suspension); update `suspended_until` and `suspension_reason`; audit log
- Suspend buyer role is NOT affected (same user account; buyer functionality remains)

**Done Criteria:**
- Suspend → seller_profile.suspension_status = SUSPENDED; all ACTIVE offers → INACTIVE (SUSPENSION reason)
- `seller.suspended` event in outbox; Search consumer removes offers from ES

---

### ADMIN-010 — POST /admin/sellers/:id/reinstate
**US Ref:** US-A-05b
**Estimate:** M
**Dependencies:** SELLER-002, CATALOG-011
**Implementation Notes:**
- DTO: `ReinstateSeller { reason: string (≤500 chars) }`
- Transaction:
  1. Set `seller_profile.suspension_status = ACTIVE`; clear `suspended_until`
  2. Restore only offers with `status_changed_reason = 'SUSPENSION'` → set to `ACTIVE`; clear `status_changed_reason`
  3. Do NOT restore offers with `status = REMOVED` (admin-removed stay removed)
  4. Publish `seller.reinstated` outbox event
- Audit record: admin + timestamp + reason

**Done Criteria:**
- Reinstate → only SUSPENSION-reason offers reactivated; REMOVED offers unchanged
- `seller.reinstated` event in outbox; Search consumer restores offers in ES

---

### ADMIN-011 — GET /admin/sellers
**US Ref:** US-A-06
**Estimate:** M
**Dependencies:** SELLER-002
**Implementation Notes:**
- `GET /admin/sellers?q=<search_term>&page=&limit=`
- Search by: `business_name ILIKE`, `user.email ILIKE`, `seller_profile.tax_id = exact`
- Returns: `[{ seller_id, business_name, email, kyc_status, suspension_status, registration_date }]`
- Paginated

**Done Criteria:**
- Search by business name returns matching sellers (case-insensitive)
- Search by exact tax_id works

---

### ADMIN-012 — GET /admin/sellers/:id (Full Profile)
**US Ref:** US-A-06
**Estimate:** M
**Dependencies:** SELLER-002, ADMIN-002
**Implementation Notes:**
- Returns full seller profile: `{ seller_id, business_name, email, kyc_status, suspension_status, suspended_until?, all_kyc_applications, active_listings_count, removed_listings_count, moderation_history }`
- `moderation_history`: all resolved moderation cases with timestamps + admin actors + decisions
- Links to KYC review (latest application) and suspension action
- All document views logged per NFR-09

**Done Criteria:**
- Profile includes full moderation history with admin actors

---

### ADMIN-013 — GET /admin/dashboard
**US Ref:** US-A-00
**Estimate:** M
**Dependencies:** SELLER-002, ADMIN-002
**Implementation Notes:**
- Aggregation: `{ pendingKycCount, flaggedListingsCount, suspendedSellersCount, slaBreach72hCount }`
- `pendingKycCount`: `COUNT WHERE kyc_application.status = 'UNDER_REVIEW'`
- `flaggedListingsCount`: `COUNT WHERE moderation_case.status = 'OPEN'`
- `suspendedSellersCount`: `COUNT WHERE seller_profile.suspension_status = 'SUSPENDED'`
- `slaBreach72hCount`: `COUNT WHERE kyc_application.status = 'UNDER_REVIEW' AND submitted_at < NOW() - INTERVAL '72 hours'`

**Done Criteria:**
- Dashboard returns correct live counts

---

### ADMIN-014 — Suspension Expiry Scheduler
**US Ref:** US-P-18
**Estimate:** M
**Dependencies:** SELLER-002, CATALOG-011
**Implementation Notes:**
- File: `apps/workers/src/schedulers/suspension-expiry.scheduler.ts`
- `@Interval(SUSPENSION_EXPIRY_INTERVAL_MS)` (default 3600s = 1h)
- Query: `WHERE suspension_status = 'SUSPENDED' AND suspended_until IS NOT NULL AND suspended_until <= now() FOR UPDATE SKIP LOCKED`
- For each match: same logic as ADMIN-010 (reinstate); publish `seller.suspension_expired` event
- Idempotent: re-running against already-ACTIVE sellers is a no-op

**Done Criteria:**
- Timed suspension expires → seller reactivated; SUSPENSION-reason offers restored; `seller.suspension_expired` event in outbox
- Permanent suspension (suspended_until IS NULL) is NOT auto-lifted

---

### ADMIN-015 — Outbox Events: seller.kyc.decided, seller.suspended, seller.reinstated, seller.suspension_expired, moderation.listing.removed, listing.flagged
**US Ref:** US-P-10
**Estimate:** M
**Dependencies:** PLATFORM-004
**Implementation Notes:**
- Register all 6 Avro schemas per kafka-events.md definitions
- `seller.kyc.decided` payload: `{ seller_id, decision, rejection_reason?, seller_email, decided_at }`
- `seller.suspended` payload: `{ seller_id, user_id, reason, duration_type ('TIMED'|'PERMANENT'), suspended_until?, suspended_by_admin_id, suspended_at, affected_offers_count }`
- `seller.reinstated` payload: `{ seller_id, reason, reinstated_by_admin_id, reinstated_at, restored_offers_count }`
- `seller.suspension_expired` payload: `{ seller_id, expired_at, restored_offers_count }`
- `moderation.listing.removed` payload: `{ offer_id, product_id, seller_id, product_title, removal_reason, removal_reason_text, removed_by_admin_id, removed_at }`
- `listing.flagged` payload: `{ offer_id, product_id, seller_id, flag_reason, source ('AUTO_KEYWORD'|'AUTO_CATEGORY'|'ADMIN'), flagged_at }`

**Done Criteria:**
- All 6 schemas registered in Schema Registry
- Events emitted correctly after respective admin actions
