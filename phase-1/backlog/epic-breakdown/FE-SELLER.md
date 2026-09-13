# Epic: FE-SELLER — Seller Portal

**Epic ID:** FE-SELLER  
**Sprint(s):** 17–18  
**Total Tasks:** 12  

## Epic Goal

Seller portal (separate Angular app at `seller-app`): KYC onboarding flow, product/offer management with image upload and pricing sub-form, inventory management with CSV import, fulfillment dashboard with ship/refund/cancel actions, seller dashboard with revenue summary. Suspended seller view. All pricing inputs stored/displayed as decimal strings.

---

## Tasks

### FE-SELLER-001 — Seller dashboard

- **US Ref:** US-S-01
- **Estimate:** M
- **Dependencies:** FE-SHARED-001, FE-SHARED-002
- **Spec References:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/api-design/catalog.md`

**Implementation Notes:**
- Route: `/dashboard` (seller-app root; requires `sellerGuard` + `sellerActiveGuard`)
- Summary cards: total listings count, active orders count, pending fulfillments count
- Revenue summary: total revenue last 30 days (from `GET /seller/dashboard` endpoint)
- Revenue displayed via `<aliceut-price-display>` — always string, USD base
- Recent orders table: last 5 fulfillments with status badge
- Quick-action buttons: "Add product", "View fulfillments"

**Done Criteria:**
- Dashboard loads only for SELLER role with ACTIVE seller status
- Revenue shown as formatted decimal string (not raw number)
- Suspended seller: redirected to suspended view (FE-SELLER-011)
- KYC not approved: redirected to KYC status page (FE-SELLER-002)

---

### FE-SELLER-002 — KYC status page

- **US Ref:** US-S-02
- **Estimate:** M
- **Dependencies:** FE-AUTH-009
- **Spec References:** `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Route: `/kyc/status`
- Shows current KYC status: PENDING / UNDER_REVIEW / APPROVED / REJECTED
- Status-specific content:
  - `PENDING`: "Complete your KYC to start selling" + CTA to `/kyc/submit`
  - `UNDER_REVIEW`: "Your application is under review. We'll notify you within 2-3 business days."
  - `APPROVED`: "Your account is approved! Redirecting to dashboard…" + auto-redirect
  - `REJECTED`: rejection reason from API + "Resubmit" CTA + link to `/kyc/submit`
- Calls `GET /seller/profile` to get `kyc_status`

**Done Criteria:**
- Correct message and CTA for each status
- APPROVED: auto-redirects to `/dashboard` after 2s
- REJECTED: shows rejection reason from API response

---

### FE-SELLER-003 — KYC document upload (onboarding)

- **US Ref:** US-S-03
- **Estimate:** L
- **Dependencies:** FE-SELLER-002
- **Spec References:** `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Route: `/kyc/submit`. Stepper layout/fields per `phase-1/ui-design/seller-portal.md` §Screen 3
- Document upload: `POST /seller/kyc/documents` (multipart, one doc at a time); shared `FileUploadComponent` (`shared-components.md` §6)
- Final submit: `POST /seller/kyc/submit`

**Done Criteria:**
- All 3 document types uploaded before submit enabled
- File size > 5MB: error before upload attempt
- Upload shows progress bar
- After submit: redirected to `/kyc/status` with UNDER_REVIEW message
- Documents stored in MinIO `kyc-documents` bucket (access-controlled)

---

### FE-SELLER-004 — Product/offer form (create & edit)

- **US Ref:** US-S-04
- **Estimate:** XL
- **Dependencies:** FE-SELLER-001
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/api-design/pricing.md`

**Implementation Notes:**
- Routes: `/listings/new`, `/listings/:offerId/edit`. Form layout/sections per `phase-1/ui-design/seller-portal.md` §Screen 6
- Create flow: `POST /catalog/products` → `POST /catalog/offers` → set pricing (FE-SELLER-005) → set inventory
- Edit flow: load offer data → `PATCH /catalog/offers/:offerId` (product data, price, inventory as separate calls)
- Auto-save draft to localStorage (keyed by offerId or "new") every 30s

**Done Criteria:**
- Create: new product + offer appear in listings after save
- Edit: pre-populated form with current values
- Category selection: hierarchical MatSelect showing parent > child
- Save disabled until required fields valid
- Auto-save draft recovered on page refresh

---

### FE-SELLER-005 — Pricing sub-form

- **US Ref:** US-S-05
- **Estimate:** L
- **Dependencies:** FE-SELLER-004
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`

**Implementation Notes:**
- Embedded in product form (FE-SELLER-004) as `<app-pricing-form>`; layout per `phase-1/ui-design/seller-portal.md` §Screen 11
- Supported currencies: USD, THB, JPY, SGD only (V1)
- Price inputs never bound to `number` type — always `string`; validated via `new Decimal(value).isFinite()`
- Calls `POST /pricing/offers/:offerId/prices` per currency
- Validation: SALE price must be < LIST price (decimal comparison); end date must be > start date

**Done Criteria:**
- All price inputs accept and store string values
- SALE price > LIST price: form error (no save)
- Adding USD price mandatory; other currencies optional
- B2B price section hidden for non-business account type
- Invalid decimal (e.g. "abc"): validation error, not NaN

---

### FE-SELLER-006 — Image upload

- **US Ref:** US-S-06
- **Estimate:** M
- **Dependencies:** FE-SELLER-004
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`

**Implementation Notes:**
- Image widget inside product form; layout/limits per `phase-1/ui-design/seller-portal.md` §Screen 6; shared `FileUploadComponent` (`shared-components.md` §6)
- Upload via `POST /catalog/products/:productId/images` (multipart); reorder via `PATCH /catalog/products/:productId/images`
- Image stored in MinIO `product-images` bucket; URL returned from API

**Done Criteria:**
- Up to 5 images uploaded; 6th upload blocked with error message
- Files > 2MB: rejected before upload (client-side check)
- Drag to reorder images works; new order saved via `PATCH /catalog/products/:productId/images`
- Delete image: confirm dialog; image removed from MinIO and DB

---

### FE-SELLER-007 — Listings management

- **US Ref:** US-S-07
- **Estimate:** M
- **Dependencies:** FE-SELLER-004
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Route: `/listings`
- Calls `GET /seller/offers?limit=20&cursor=&status=`
- Table: product thumbnail, title, status badge, LIST price (USD), stock quantity, actions
- Status filter chips: All / ACTIVE / INACTIVE / FLAGGED
- Actions per row: Edit (→ `/listings/:offerId/edit`), Toggle active/inactive, Delete
- Toggle active: `PATCH /catalog/offers/:offerId { status: 'ACTIVE' | 'INACTIVE' }`
- Delete: confirm dialog → `DELETE /catalog/offers/:offerId`
- Flagged offers: orange badge; tooltip with flag reason; cannot toggle to ACTIVE until moderation review

**Done Criteria:**
- Listings load with correct status badges
- Toggle active/inactive updates badge instantly (optimistic update)
- Flagged offers: "Edit" still allowed; toggle to ACTIVE blocked
- Delete: offer removed from list after confirmation

---

### FE-SELLER-008 — Inventory management

- **US Ref:** US-S-08
- **Estimate:** M
- **Dependencies:** FE-SELLER-007
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Route: `/inventory`
- Table: product title, offer ID, current stock, low-stock threshold, reserved qty, actions
- Inline edit: click stock quantity to edit; `PATCH /inventory/offers/:offerId { quantity_available }` on blur
- Low-stock highlight: row turns yellow when `current_stock <= low_stock_threshold`
- Actions: Edit threshold, View reservation history

**Done Criteria:**
- Inline stock edit saves immediately on blur
- Low-stock rows highlighted in yellow
- Stock = 0: row highlighted in red + offer auto-deactivated badge

---

### FE-SELLER-009 — CSV bulk import

- **US Ref:** US-S-09
- **Estimate:** L
- **Dependencies:** FE-SELLER-007
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Route: `/listings/import`. Dialog layout per `phase-1/ui-design/seller-portal.md` §Screen 9 (CSV Import Dialog)
- Upload via `POST /seller/listings/import` (multipart); progress polled via `GET /seller/import/:jobId/status`

**Done Criteria:**
- CSV preview shown before upload
- Template download link works
- Import result shows success count and per-row errors
- Failed rows: error message explains reason (e.g., "Price must be a decimal string")
- Imported products appear in listings after completion

---

### FE-SELLER-010 — Fulfillment dashboard

- **US Ref:** US-S-10
- **Estimate:** L
- **Dependencies:** FE-SELLER-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Route: `/fulfillments`. Table layout per `phase-1/ui-design/seller-portal.md` §Screen 7; shared `DataTableComponent` (`shared-components.md` §5)
- Default filter: PENDING + PROCESSING (new orders needing action)
- Cursor-based "load more"

**Done Criteria:**
- Default view shows only actionable orders (PENDING + PROCESSING)
- Status badges color-coded
- Cursor pagination works correctly

---

### FE-SELLER-011 — Fulfillment detail + ship/refund/cancel

- **US Ref:** US-S-11
- **Estimate:** L
- **Dependencies:** FE-SELLER-010
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Route: `/fulfillments/:fulfillmentId`. Layout per `phase-1/ui-design/seller-portal.md` §Screen 8
- Ship: `POST /orders/fulfillments/:id/ship`; Refund: `POST /orders/fulfillments/:id/refund`; Cancel: `POST /orders/fulfillments/:id/cancel`
- Amounts from FulfillmentItem snapshot via `<aliceut-price-display>`

**Done Criteria:**
- Ship action shows tracking number input; validates non-empty
- Refund action only available for SHIPPED/DELIVERED
- Amounts shown from snapshot (not live pricing)
- After action: status badge updates; appropriate buttons removed

---

### FE-SELLER-012 — Suspended seller view

- **US Ref:** US-S-12
- **Estimate:** S
- **Dependencies:** FE-SHARED-005
- **Spec References:** `phase-1/technical-design/api-design/seller.md`

**Implementation Notes:**
- Shown when `sellerActiveGuard` detects `seller_status === 'SUSPENDED'`
- Route: `/suspended`
- Content: suspension reason, suspension end date (if temporary), contact info for appeals
- All seller-app routes redirect here while suspended
- Existing fulfillments still visible read-only (to complete pending shipments)
- "View my fulfillments" link → `/fulfillments` (read-only mode; no ship/cancel actions)

**Done Criteria:**
- Suspended seller lands on this page from any seller-app URL
- Suspension reason and end date shown (from `GET /seller/profile`)
- Fulfillments page accessible in read-only mode while suspended
- Reinstatement: `sellerActiveGuard` re-checks on navigation; redirects to dashboard once reinstated
