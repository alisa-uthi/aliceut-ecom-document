# EPIC: SELLER — Seller Module

**Sprint:** 3  
**Lib:** `libs/seller/`  
**Module:** `SellerModule`  
**Controllers:** `SellerController`  
**Kafka producers:** `seller.kyc.submitted`  

Overview: Seller onboarding — registration, KYC document submission and status tracking, KYC resubmission, and the seller dashboard summary. Seller profile is created on first seller-role login; KYC approval is required before any listing actions.

---

### SELLER-001 — seller Schema Migrations

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- File: `libs/seller/src/infrastructure/migrations/0001_seller_schema.sql`
- Tables:
  - `seller.seller_profile`: id (same as `auth.user.id`), display_name, business_name nullable, logo_url nullable, kyc_status (enum: `PENDING`|`UNDER_REVIEW`|`APPROVED`|`REJECTED`), status (`ACTIVE`|`SUSPENDED`|`CLOSED`), suspension_expires_at nullable, suspension_reason nullable, created_at, updated_at
  - `seller.kyc_application`: id (UUIDv7 PK), seller_id FK, document_type (`ID_CARD`|`PASSPORT`|`BUSINESS_REG`), document_front_key, document_back_key nullable, selfie_key nullable, submitted_at, reviewed_at nullable, reviewer_id nullable, review_notes nullable, status (`SUBMITTED`|`APPROVED`|`REJECTED`)
- `seller.seller_profile.id → auth.user(id)` FK
- `seller.kyc_application.seller_id → seller.seller_profile(id)` FK
- Index: `seller_profile(kyc_status)`, `seller_profile(status)`, `kyc_application(seller_id)`

**Done Criteria:**
- Tables created; `kyc_status` constraint enforces allowed values

---

### SELLER-002 — SellerProfile Entity + Auto-creation on Role Upgrade

- **US Ref:** US-S-01
- **Estimate:** M
- **Dependencies:** SELLER-001, AUTH-014
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- TypeORM entity for `seller.seller_profile`
- `SellerService.getOrCreateProfile(userId)`: returns existing profile or creates one with `kyc_status='PENDING'`, `status='ACTIVE'`
- Called from: `AUTH-014` (role upgrade to SELLER) — create profile if not exists
- `SellerRepository`: `findById(id)`, `findByKycStatus(status)`, `save(profile)`, `updateStatus(id, status, reason?, expiresAt?)`

**Done Criteria:**
- Role upgrade: seller profile created automatically with `kyc_status=PENDING`
- Calling `getOrCreateProfile` twice: idempotent (no duplicate)

---

### SELLER-003 — KycApplication Entity + POST /seller/kyc

- **US Ref:** US-S-02
- **Estimate:** L
- **Dependencies:** SELLER-001, SHARED-006
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- TypeORM entity for `seller.kyc_application`
- `POST /seller/kyc` — multipart form; `@JwtAuthGuard` + `@Roles('SELLER')`
- DTO: `SubmitKycDto { documentType: 'ID_CARD'|'PASSPORT'|'BUSINESS_REG', documentFront: file, documentBack?: file, selfie?: file }`
- Upload documents to MinIO `kyc-documents` bucket; keys: `kyc/{sellerId}/{uuid}-{docType}-front.jpg` etc.
- Store keys only (not URLs) in DB — presigned on demand
- Create `kyc_application` row (`status='SUBMITTED'`); set `seller_profile.kyc_status = 'UNDER_REVIEW'`
- Publish `seller.kyc.submitted` outbox event
- Block resubmission if existing application is `UNDER_REVIEW` → 422 `KYC_ALREADY_UNDER_REVIEW`
- Block if already `APPROVED` → 422 `KYC_ALREADY_APPROVED`

**Done Criteria:**
- Submit KYC → files uploaded to MinIO; application row created; profile status = UNDER_REVIEW
- Submit when UNDER_REVIEW → 422
- `seller.kyc.submitted` event in outbox

---

### SELLER-004 — GET /seller/kyc/status

- **US Ref:** US-S-02
- **Estimate:** S
- **Dependencies:** SELLER-003
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /seller/kyc/status` — `@JwtAuthGuard` + `@Roles('SELLER')`
- Returns: `{ kycStatus, latestApplication: { id, documentType, submittedAt, reviewedAt, reviewNotes, status } | null }`
- `documentFrontUrl` — presigned MinIO URL (900s TTL) if application exists
- `reviewNotes` visible to seller only when `status = 'REJECTED'`

**Done Criteria:**
- PENDING (no application): `{ kycStatus: 'PENDING', latestApplication: null }`
- After submit: `{ kycStatus: 'UNDER_REVIEW', latestApplication: { status: 'SUBMITTED', ... } }`
- After rejection: `reviewNotes` visible in response

---

### SELLER-005 — POST /seller/kyc/resubmit

- **US Ref:** US-S-02
- **Estimate:** M
- **Dependencies:** SELLER-003
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /seller/kyc/resubmit` — same multipart as initial submission
- Allowed only when latest application `status = 'REJECTED'`
- Create new `kyc_application` row; set `seller_profile.kyc_status = 'UNDER_REVIEW'`
- Previous rejected application retained (history for admin review)
- Publish `seller.kyc.submitted` event (same event type as initial submission)

**Done Criteria:**
- Resubmit when status = APPROVED → 422
- Resubmit when status = UNDER_REVIEW → 422
- Valid resubmit → new application row; profile status = UNDER_REVIEW

---

### SELLER-006 — SellerKycGuard (POST /seller/register flow)

- **US Ref:** US-S-03
- **Estimate:** S
- **Dependencies:** SELLER-002, AUTH-018
- **Spec References:** `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Defined in AUTH-018 (`SellerKycGuard`)
- Checks `seller_profile.kyc_status = 'APPROVED'` AND `seller_profile.status = 'ACTIVE'`
- Applied to: all endpoints in CATALOG (seller CRUD), PRICING (seller pricing), INVENTORY (seller inventory)
- Logic in `SellerService.getApprovedAndActiveProfile(userId)` — single query joining seller_profile

**Done Criteria:**
- Seller with `kyc_status = 'PENDING'` → 403 `KYC_NOT_APPROVED`
- Suspended seller → 403 `SELLER_SUSPENDED`

---

### SELLER-007 — POST /seller/register

- **US Ref:** US-S-01
- **Estimate:** S
- **Dependencies:** SELLER-002, AUTH-014
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `POST /seller/register { displayName, businessName? }` — `@JwtAuthGuard`; works for BUYER (upgrades) or SELLER (updates profile)
- If user is BUYER: call `AuthService.upgradeToSeller(userId)` internally; create profile
- If user already SELLER: update `display_name`, `business_name` only
- Validation: `displayName` 2–100 chars; `businessName` optional, 2–200 chars if provided

**Done Criteria:**
- BUYER registers as seller: role upgraded, profile created in one call
- SELLER updates: only display_name/business_name updated (no role change)

---

### SELLER-008 — GET /seller/dashboard

- **US Ref:** US-S-09
- **Estimate:** M
- **Dependencies:** SELLER-002, CATALOG-008, INVENTORY-002
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /seller/dashboard` — `@JwtAuthGuard` + `@Roles('SELLER')`; does NOT require KYC
- Response: `{ kycStatus, activeListings, pendingOrders, lowStockCount, totalRevenue: null (V1 placeholder), suspensionInfo: { expiresAt, reason } | null }`
- `activeListings`: count of `catalog.offer WHERE seller_id = ? AND status = 'ACTIVE'`
- `pendingOrders`: count of fulfillment items where seller_id and status IN (`PROCESSING`, `SHIPPED`)
- `lowStockCount`: count of stock rows where `available_qty - reserved_qty <= reorder_threshold`
- `totalRevenue`: null in V1 (no payment tracking yet; placeholder for V2)

**Done Criteria:**
- Seller with 3 active listings, 1 pending order, 2 low-stock: response reflects all counts
- KYC PENDING seller can still access dashboard (only catalog/inventory blocked)

---

### SELLER-009 — Outbox Event: seller.kyc.submitted

- **US Ref:** FR-P-09
- **Estimate:** S
- **Dependencies:** SHARED-005, SELLER-003
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Avro schema for `seller.kyc.submitted`:
  - Payload: `{ seller_id, application_id, document_type, submitted_at }`
- Written in same transaction as `kyc_application` insert
- Admin notifications consumer (NOTIFICATIONS-007) sends email to admin on this event

**Done Criteria:**
- Schema registered; Kafka UI shows event within 2s of KYC submission

---

### SELLER-010 — Seller Suspension / Reinstatement (internal service API)

- **US Ref:** US-A-07
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- Not an HTTP endpoint — internal `SellerService` methods called by `AdminController` (ADMIN-009, ADMIN-010):
  - `suspend(sellerId, reason, durationDays?)`: set `status = 'SUSPENDED'`, set `suspension_expires_at` (null = indefinite)
  - `reinstate(sellerId)`: set `status = 'ACTIVE'`, clear suspension fields
- Suspension side effects (handled by Kafka consumers in respective modules):
  - Deactivate all seller's ACTIVE offers → emit `seller.suspended` event (ADMIN handles; CATALOG consumer reacts)
  - Force-logout seller → call `AuthService.revokeAllSessions(sellerId)`
- Reinstatement side effects (on `seller.reinstated` event):
  - CATALOG consumer: reactivate offers with `status_changed_reason = 'SUSPENSION'`
- Suspension expiry scheduler (ADMIN-014): auto-reinstate when `suspension_expires_at < now()`

**Done Criteria:**
- Suspend → seller `status = SUSPENDED`; all ACTIVE offers deactivated
- Reinstate → seller `status = ACTIVE`; offers with SUSPENSION reason reactivated
