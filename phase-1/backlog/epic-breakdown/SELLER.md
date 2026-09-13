# EPIC: SELLER — Seller Module

**Sprint:** 9  
**Lib:** `libs/seller/`  
**Module:** `SellerModule`  
**Controllers:** `SellerController`  
**Kafka producers:** `seller.kyc.submitted`  

Overview: Seller onboarding — a BUYER submits business info, tax ID, and identity/business documents in one registration call; this creates the seller profile and KYC application together, adds the SELLER role, and starts KYC review. KYC approval gates listing/pricing/inventory actions via `SellerKycGuard`; sellers can check status and resubmit after rejection. Dashboard summary is available regardless of KYC status.

---

### SELLER-001 — seller Schema Migrations

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md` § seller schema, `phase-1/technical-design/api-design/seller.md` § DB Mapping

**Implementation Notes:**
- File: `libs/seller/src/infrastructure/migrations/0001_seller_schema.sql`
- `seller.seller_profile`: `id` UUID PK, `user_id` UUID FK → `identity.user(id)` (unique, required), `business_name` TEXT required, `tax_id` TEXT required, `kyc_status seller_kyc_status` required (`PENDING_KYC`\|`APPROVED`\|`REJECTED`), `suspension_status seller_suspension_status` required default `ACTIVE` (`ACTIVE`\|`SUSPENDED`), `suspended_until` TIMESTAMPTZ nullable, `suspension_reason` TEXT nullable, `created_at`/`updated_at`
- `seller.kyc_application`: `id` UUID PK, `seller_id` UUID FK → `seller.seller_profile(id)` required, `submitted_data` JSONB required, `document_references` JSONB required, `status kyc_status` required (`PENDING`\|`UNDER_REVIEW`\|`APPROVED`\|`REJECTED` — distinct enum from `seller_profile.kyc_status`), `reviewer_user_id` UUID nullable FK → `identity.user(id)`, `decision_reason` TEXT nullable, `submitted_at`/`decided_at`, `created_at`/`updated_at`
- Exact column list/types: see ERD. Enum semantics and lifecycle: see api-design/seller.md.
- Indexes: `seller_profile(user_id)` unique, `seller_profile(kyc_status)`, `kyc_application(seller_id)`, `kyc_application(status)`

**Done Criteria:**
- Tables created; both enum constraints enforce allowed values; FK to `identity.user` enforced

---

### SELLER-002 — SellerProfile Entity + Repository Interface

- **US Ref:** US-S-01
- **Estimate:** M
- **Dependencies:** SELLER-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md` § seller schema

**Implementation Notes:**
- TypeORM entity for `seller.seller_profile` (fields per SELLER-001)
- `SellerProfileRepository` interface: `findById(id)`, `findByUserId(userId)`, `findByKycStatus(status)`, `save(profile)`, `updateKycStatus(id, status)`, `updateSuspension(id, { suspensionStatus, suspendedUntil?, suspensionReason? })`
- `updateSuspension` is consumed by ADMIN's suspend/reinstate tasks (ADMIN-008, ADMIN-009) — suspend/reinstate is owned by the ADMIN epic, not SELLER; this repository is the shared write path
- No auto-creation on role upgrade: a profile exists only after SELLER-004 (`POST /seller/register`) runs — it creates the profile and the KYC application together in one transaction

**Done Criteria:**
- Repository methods (incl. `updateSuspension`) covered by unit tests
- No profile exists for a user until SELLER-004 runs

---

### SELLER-003 — KycApplication Entity + Repository Interface

- **US Ref:** US-S-01
- **Estimate:** M
- **Dependencies:** SELLER-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md` § seller schema

**Implementation Notes:**
- TypeORM entity for `seller.kyc_application` (`submitted_data`/`document_references` JSONB, `status kyc_status`)
- `KycApplicationRepository` interface: `findLatestBySellerId(sellerId)`, `findById(id)`, `save(application)`
- `document_references`: array of MinIO storage keys (see SELLER-004/SELLER-005), never URLs — presigned on demand

**Done Criteria:**
- Repository methods covered by unit tests
- `findLatestBySellerId` returns the most recent row by `submitted_at`

---

### SELLER-004 — POST /seller/register (step 1: account; link SELLER role to existing account or create new)

- **US Ref:** US-S-01
- **Estimate:** L
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/seller.md` § POST /seller/register (endpoint + sequence)

**Implementation Notes:**
- Auth, request/response shape, MinIO upload, and outbox emission: see api-design/seller.md's `POST /seller/register` sequence — do not restate the full contract here.
- Task-specific: Auth BUYER + EMAIL_VERIFIED; 409 if the user already has a seller profile. Single transaction: append SELLER role to `identity.user`, `INSERT seller_profile` (`kyc_status=PENDING_KYC`, `suspension_status=ACTIVE`), `INSERT kyc_application` (`status=PENDING`), upload documents to MinIO `kyc-documents` bucket (AES-256 at rest), publish `seller.kyc.submitted` outbox event.
- **Discrepancy flagged:** this task's title frames registration as "step 1: account" separate from KYC submission (see SELLER-005). The documented API combines account/role linking and KYC submission into this single endpoint — there is no separate account-only registration call in `api-design/seller.md`. Not resolved here; left to spec owner.

**Done Criteria:**
- Per api-design/seller.md's response/error list for this endpoint
- Existing seller profile → 409

---

### SELLER-005 — POST /seller/kyc (KYC form + doc upload to MinIO kyc-documents bucket; presigned GET for download)

- **US Ref:** US-S-01
- **Estimate:** L
- **Dependencies:** SELLER-003
- **Spec References:** `phase-1/technical-design/api-design/seller.md` § POST /seller/register, § POST /seller/kyc/resubmit

**Implementation Notes:**
- **Discrepancy flagged:** `api-design/seller.md`'s Endpoint Index has no standalone `POST /seller/kyc` path — initial KYC submission is documented as part of `POST /seller/register` (SELLER-004). Implemented here as the shared KYC document module (upload + presigned retrieval) consumed by SELLER-004 and SELLER-007, rather than its own public endpoint, so the work isn't duplicated.
- MinIO `kyc-documents` bucket; key pattern `kyc/{sellerId}/{uuid}-{docName}`; store keys only in `document_references`, never URLs
- Presigned `GET` for document download: TTL 900s, generated on demand (admin review, seller status check)

**Done Criteria:**
- Upload helper produces storage keys consumed correctly by SELLER-004 and SELLER-007
- Presigned GET returns a valid, time-limited URL for a stored key

---

### SELLER-006 — GET /seller/kyc/status (returns current application status + rejection reason if applicable)

- **US Ref:** US-S-02
- **Estimate:** S
- **Dependencies:** SELLER-003
- **Spec References:** `phase-1/technical-design/api-design/seller.md` § GET /seller/kyc

**Implementation Notes:**
- **Discrepancy flagged (naming only):** documented path is `GET /seller/kyc` (no `/status` suffix). Implement the documented path.
- Auth SELLER. Response shape: see api-design/seller.md — `{ id, status, submittedAt, decidedAt, decisionReason }`
- `decisionReason` populated only when `status = REJECTED`

**Done Criteria:**
- Response reflects the latest `kyc_application` row for the seller
- `decisionReason` present only after rejection

---

### SELLER-007 — POST /seller/kyc/resubmit (update docs + resubmit; links to prior rejection)

- **US Ref:** US-S-02
- **Estimate:** M
- **Dependencies:** SELLER-003
- **Spec References:** `phase-1/technical-design/api-design/seller.md` § POST /seller/kyc/resubmit

**Implementation Notes:**
- Full contract (request fields, guard, response): see api-design/seller.md's `POST /seller/kyc/resubmit` sequence.
- Task-specific: allowed only when the latest `kyc_application.status = REJECTED`; inserts a new `kyc_application` row (`status=PENDING`); updates `seller_profile.kyc_status = PENDING_KYC`; previous rejected application retained for admin history; publishes `seller.kyc.submitted` with `is_resubmission=true`. Uses the upload helper from SELLER-005.

**Done Criteria:**
- Resubmit when latest status != REJECTED → error per spec
- Valid resubmit → new `kyc_application` row; `seller_profile.kyc_status = PENDING_KYC`; outbox event with `is_resubmission=true`

---

### SELLER-008 — SellerKycGuard (block listing endpoints until kyc_status=APPROVED and suspension_status=ACTIVE)

- **US Ref:** US-S-02
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/seller.md` § Sequence Diagram Conventions

**Implementation Notes:**
- Checks `seller_profile.kyc_status = APPROVED` AND `suspension_status = ACTIVE`
- Applied to seller-role endpoints in CATALOG (seller CRUD), PRICING (seller pricing), INVENTORY (seller inventory)
- Suspended-seller exception (per spec's Sequence Diagram Conventions): a `SUSPENDED` seller may still access `GET /seller/orders`, `GET /seller/orders/:id`, `POST /seller/orders/:id/ship` — guard must not block those three regardless of guard level
- Logic in `SellerService.getApprovedAndActiveProfile(userId)` — single query

**Done Criteria:**
- `kyc_status != APPROVED` on a guarded endpoint → 403
- `suspension_status = SUSPENDED` on a guarded endpoint → 403, except the 3 order endpoints listed above

---

### SELLER-009 — GET /seller/dashboard (counts: pending orders, low-stock SKUs, active listings, flagged listings)

- **US Ref:** US-S-00
- **Estimate:** M
- **Dependencies:** SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/seller.md` § GET /seller/dashboard

**Implementation Notes:**
- Auth SELLER; does NOT require KYC approval
- Response fields and per-field source queries (active listings, pending orders, low-stock, flagged listings): see api-design/seller.md's dashboard endpoint — reads across `catalog.offer` and `inventory.stock` (cross-module read, not a build dependency; hence dependency stays SELLER-002 only per backlog)
- `totalRevenue`: null in V1 (no payment tracking yet — out of scope per CLAUDE.md)

**Done Criteria:**
- Counts match underlying rows for a seller with active listings, pending orders, and low-stock SKUs
- KYC-`PENDING_KYC` seller can still access the dashboard (only catalog/pricing/inventory endpoints are guard-blocked)

---

### SELLER-010 — Outbox Event: seller.kyc.submitted (Avro schema; seller_id, kyc_application_id, is_resubmission)

- **US Ref:** US-P-10
- **Estimate:** S
- **Dependencies:** PLATFORM-004
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md` § seller schema

**Implementation Notes:**
- Avro payload: `{ seller_id, kyc_application_id, is_resubmission }` — supersedes any earlier draft with a `document_type`/`submitted_at` payload; documents are now a JSONB array (`document_references`), not one enum field per application
- Written in the same transaction as the `kyc_application` insert (SELLER-004 initial submission, SELLER-007 resubmission)
- Consumed by NOTIFICATIONS (admin email) — see NOTIFICATIONS epic

**Done Criteria:**
- Schema registered in Confluent Schema Registry; event visible in Kafka UI within 2s of submission or resubmission
- `is_resubmission` correctly `false` on SELLER-004, `true` on SELLER-007

---

## Notes / Flagged Discrepancies (not silently resolved)

- **Task numbering realigned to `backlog.md`.** The prior draft of this file numbered tasks differently from `backlog.md`'s canonical SELLER-001…010 (e.g. its old SELLER-003 merged entity+endpoint work that `backlog.md` splits across SELLER-003/SELLER-005). Renumbered to match `backlog.md` and `sprint-plan.md` (Sprint 9) exactly, since ADMIN.md's SELLER-002/SELLER-003 dependency references already assume this numbering.
- **Register vs. KYC submission is one endpoint, not two** (SELLER-004/SELLER-005) — `api-design/seller.md` has no standalone `POST /seller/kyc`. Handled by scoping SELLER-005 as a shared upload helper rather than inventing a nonexistent endpoint; flagged for the spec owner to reconcile `backlog.md`'s two-task framing with the one-endpoint API design.
- **`GET /seller/kyc/status` vs. documented `GET /seller/kyc`** (SELLER-006) — path suffix mismatch, implement the documented path.
- **Removed:** the prior draft's standalone "Seller Suspension / Reinstatement" task (old SELLER-010) — not present in `backlog.md`'s SELLER list. That behavior belongs to ADMIN-008/ADMIN-009, which already depend on SELLER-002 for the `updateSuspension` write path added there.
