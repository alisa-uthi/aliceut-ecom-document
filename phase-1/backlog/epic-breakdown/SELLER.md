# EPIC: SELLER — Seller Module

**Sprint:** 4
**Lib:** `libs/seller/`
**Module:** `SellerModule`
**Controllers:** `SellerController` (onboarding, KYC, dashboard)
**Kafka producers:** `seller.kyc.submitted`

Overview: Manages seller onboarding, KYC application lifecycle, and seller profile. Seller registration is separate from buyer registration. The KYC flow gates all catalog actions. Suspension state (managed by Admin module) affects catalog visibility and dashboard access.

---

### SELLER-001 — seller Schema Migrations
**US Ref:** —
**Estimate:** M
**Dependencies:** PLATFORM-001
**Implementation Notes:**
- File: `libs/seller/src/infrastructure/migrations/0001_seller_schema.sql`
- Tables: `seller.seller_profile`, `seller.kyc_application`
- All columns per data-model-erd.md seller section
- `seller.seller_profile.kyc_status` uses `seller_kyc_status` enum
- `seller.seller_profile.suspension_status` uses `seller_suspension_status` enum; default `ACTIVE`
- FK: `seller_profile.user_id → identity.user(id)` (cross-schema; applied after identity schema)
- FK: `kyc_application.reviewer_user_id → identity.user(id)` (nullable FK)
- Index: `seller_profile(user_id)` unique, `seller_profile(kyc_status)`, `seller_profile(suspension_status)`

**Done Criteria:**
- Seller profile tables created; cross-schema FK constraints apply after identity schema

---

### SELLER-002 — SellerProfile Entity + Repository Interface
**US Ref:** US-S-01
**Estimate:** M
**Dependencies:** SELLER-001
**Implementation Notes:**
- TypeORM entity for `seller.seller_profile`
- `SellerProfileRepository`: `findByUserId(userId)`, `findById(id)`, `save(profile)`, `updateKycStatus(id, status)`, `updateSuspensionStatus(id, status, suspendedUntil?, reason?)`
- Domain: `SellerProfile.isApproved()`, `SellerProfile.isActive()` (approved + not suspended), `SellerProfile.canList()` (approved + active)
- `SellerProfile.suspend(duration: Duration | 'PERMANENT', reason)`: sets `suspension_status = SUSPENDED`, `suspended_until` (null for permanent)
- `SellerProfile.reinstate(reason)`: sets `suspension_status = ACTIVE`, clears `suspended_until`

**Done Criteria:**
- Unit test: `SellerProfile.canList()` = false when `suspension_status = SUSPENDED`

---

### SELLER-003 — KycApplication Entity + Repository Interface
**US Ref:** US-S-01
**Estimate:** M
**Dependencies:** SELLER-001
**Implementation Notes:**
- TypeORM entity for `seller.kyc_application`
- `KycApplicationRepository`: `findById(id)`, `findBySellerId(sellerId)`, `findPending()`, `save(application)`
- `submitted_data JSONB`: `{ businessName, businessType, taxId, country, address, phone }`
- `document_references JSONB`: `[{ type: 'business_license'|'id_document'|'proof_of_address', storageKey: string }]` — never document content; only MinIO keys
- `KycApplication.isResubmission()`: check if `prior_rejection_date` is set

**Done Criteria:**
- KycApplication entity saves and retrieves JSONB fields correctly

---

### SELLER-004 — POST /seller/register
**US Ref:** US-S-01
**Estimate:** L
**Dependencies:** AUTH-002, SELLER-002
**Implementation Notes:**
- `POST /seller/register` — Step 1: account setup
- DTO: `SellerRegisterDto { email, password, fullName }`
- Logic:
  1. If email matches existing account: require password authentication to link SELLER role (return `{ action: 'authenticate', message: 'Email already registered. Sign in to add seller role.' }`)
  2. If new email: create `identity.user` with `roles = ['SELLER']` (no BUYER role by default per US-S-01); create `seller.seller_profile` with `kyc_status = PENDING_KYC`
  3. Issue JWT (seller role); do NOT issue email verification (seller registration does not require email verification in V1 — seller portal uses email/password; email used for notifications)
- No OAuth on seller portal
- Response: `{ accessToken, refreshToken, sellerId, requiresKyc: true }`

**Done Criteria:**
- New seller registers → user with SELLER role + seller_profile with kyc_status=PENDING_KYC created
- Existing buyer email → prompt to authenticate before linking SELLER role

---

### SELLER-005 — POST /seller/kyc (KYC Form + Doc Upload)
**US Ref:** US-S-01, NFR-09
**Estimate:** L
**Dependencies:** SELLER-003, INFRA-010
**Implementation Notes:**
- `POST /seller/kyc` — multipart form: business data fields + file uploads
- DTO fields: `businessName` (legal), `businessType` (LLC/SOLE_PROP/CORP), `taxId`, `country` (ISO 3166-1 alpha-2), `businessAddress`, `phone`
- File uploads: `businessLicense` (PDF/image ≤10MB), `idDocument` (PDF/image ≤10MB), `proofOfAddress` (PDF/image ≤10MB)
- Files uploaded to MinIO `kyc-documents` bucket with PRIVATE policy; keys: `kyc/{sellerId}/{uuid}.{ext}`
- `document_references` in DB: store only MinIO keys, never file content
- One active KYC application per seller (pending or approved). Cannot resubmit if approved. Must use resubmit endpoint if rejected (SELLER-007)
- Publish `seller.kyc.submitted` outbox event
- KYC docs are PII: access logged per NFR-09 (log every fetch via presigned URL)

**Done Criteria:**
- KYC form submitted → `kyc_application` row in DB with PENDING status + MinIO objects in `kyc-documents` bucket
- `seller.kyc.submitted` event in outbox
- Second submission while PENDING → 409 "Application already pending"

---

### SELLER-006 — GET /seller/kyc/status
**US Ref:** US-S-02
**Estimate:** S
**Dependencies:** SELLER-003
**Implementation Notes:**
- Returns current KYC application status + message for banner display
- Response: `{ status: 'PENDING_KYC'|'UNDER_REVIEW'|'APPROVED'|'REJECTED', message: string, submittedAt?, decisionReason? }`
- Seller sees: `PENDING_KYC` → no application yet; `UNDER_REVIEW` → submitted, waiting; `APPROVED` → can list; `REJECTED` → reason shown + resubmit CTA

**Done Criteria:**
- Newly registered seller → status `PENDING_KYC` (no application yet)
- After KYC submission → status `UNDER_REVIEW`

---

### SELLER-007 — POST /seller/kyc/resubmit
**US Ref:** US-S-02
**Estimate:** M
**Dependencies:** SELLER-003
**Implementation Notes:**
- Only available when most recent application status = `REJECTED`
- Same fields as SELLER-005; creates new `kyc_application` row linked to prior rejection
- Sets `prior_application_id` and `prior_rejection_date` in new application JSONB
- Publish `seller.kyc.submitted` event with `is_resubmission: true`
- Old rejection application not deleted (audit trail)

**Done Criteria:**
- Resubmit when status=PENDING → 409 (already pending)
- Resubmit when status=APPROVED → 409 (already approved)
- Resubmit when status=REJECTED → creates new application; `is_resubmission: true` in event

---

### SELLER-008 — SellerKycGuard
**US Ref:** US-S-02
**Estimate:** M
**Dependencies:** SELLER-002
**Implementation Notes:**
- `SellerKycGuard implements CanActivate`: checks authenticated seller's `kyc_status = APPROVED` and `suspension_status = ACTIVE`
- Applied to all catalog/inventory/pricing seller endpoints
- If `kyc_status != APPROVED`: 403 with `{ code: 'KYC_REQUIRED', message: 'Account pending KYC approval' }`
- If `suspension_status = SUSPENDED`: 403 with `{ code: 'ACCOUNT_SUSPENDED', message: 'Account suspended. Limited access only.' }` — exception: mark-ship and read-only order endpoints still accessible per US-A-05
- File: `libs/seller/src/guards/seller-kyc.guard.ts`

**Done Criteria:**
- Unapproved seller calling `POST /seller/products` → 403 KYC_REQUIRED
- Suspended seller calling `POST /seller/products` → 403 ACCOUNT_SUSPENDED
- Suspended seller calling `POST /seller/fulfillments/:id/ship` → 200 (allowed)

---

### SELLER-009 — GET /seller/dashboard
**US Ref:** US-S-00
**Estimate:** M
**Dependencies:** SELLER-002
**Implementation Notes:**
- Aggregation query: `{ pendingOrders, lowStockSkus, activeListings, flaggedListings }`
- `pendingOrders`: `COUNT(*) FROM orders.fulfillment WHERE seller_id = ? AND status = 'PENDING'`
- `lowStockSkus`: `COUNT(*) FROM inventory.stock s JOIN catalog.offer o ON s.offer_id = o.id WHERE o.seller_id = ? AND (s.on_hand_qty - s.reserved_qty) < s.low_stock_threshold`
- `activeListings`: `COUNT(*) FROM catalog.offer WHERE seller_id = ? AND status = 'ACTIVE'`
- `flaggedListings`: `COUNT(*) FROM catalog.offer WHERE seller_id = ? AND status = 'FLAGGED'`
- Counts update on page load (no real-time push)
- Also includes suspension/approval banner data

**Done Criteria:**
- Dashboard returns correct counts reflecting live DB state
- Cross-schema queries work (orders, inventory, catalog all queried)

---

### SELLER-010 — Outbox Event: seller.kyc.submitted
**US Ref:** US-P-10
**Estimate:** S
**Dependencies:** PLATFORM-004
**Implementation Notes:**
- Avro schema per kafka-events.md §1.1 `seller.kyc.submitted`
- Payload: `seller_id, user_id, kyc_application_id, business_name, submitted_at, seller_email, is_resubmission, prior_application_id? (nullable), prior_rejection_date? (nullable)`
- Published in same transaction as `kyc_application` save
- Partition key: `seller_id`

**Done Criteria:**
- Schema registered in Schema Registry
- Event appears in Kafka UI after KYC submission
