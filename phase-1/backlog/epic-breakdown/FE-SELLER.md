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
- Revenue displayed via `<app-money>` — always string, USD base
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
- **Dependencies:** FE-SHARED-001
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
- Route: `/kyc/submit` (multi-step form)
- Step 1: Business info — business name, registration number, address, tax ID
- Step 2: Document upload — file input for each required document type (IDENTITY, BUSINESS_REG, TAX_CERT)
  - Accepted: PDF, JPG, PNG; max 5MB each
  - File preview: filename + size; remove button
  - Upload via `POST /seller/kyc/documents` (multipart, one doc at a time)
  - Upload progress indicator (MatProgressBar)
- Step 3: Review & submit — `POST /seller/kyc/submit`
- Cannot skip steps; stepper enforces order

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
- Routes: `/listings/new`, `/listings/:offerId/edit`
- Sections:
  - Product info: title (required), description, brand, category (MatSelect with category tree), attributes (dynamic key-value pairs)
  - Pricing sub-form (see FE-SELLER-005 for detail)
  - Inventory: initial stock quantity, low-stock threshold
- Create flow: `POST /catalog/products` → `POST /catalog/offers` → set pricing → set inventory
- Edit flow: load offer data → `PATCH /catalog/offers/:offerId` (product data, price, inventory as separate calls)
- Reactive form with `FormGroup`; all validators run before save
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
- Embedded inside product form (FE-SELLER-004) as reusable component: `<app-pricing-form>`
- Supported currencies: USD, THB, JPY, SGD only (V1)
- Per currency:
  - LIST price input: text input typed as `string`; validated via `new Decimal(value).isFinite()`
  - SALE price (optional): text input + start/end date pickers (MatDatepicker)
  - B2B price (optional; shown only if `user.accountType === 'BUSINESS'`): text input + min qty
- Price inputs never bound to `number` type — always `string`
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
- Image upload widget inside product form
- Multiple file inputs; max 5 images; accepted formats: JPG, PNG, WebP; max 2MB each
- Drag-and-drop support via Angular CDK drag-and-drop (reorder images)
- Upload via `POST /catalog/products/:productId/images` (multipart)
- Upload one at a time; show progress bar per file
- Thumbnail preview after upload; delete button per image
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
- Route: `/listings/import`
- File input: CSV only; max 5MB
- Client-side CSV preview (first 5 rows) before upload
- CSV template download link (static file in assets)
- Upload via `POST /seller/listings/import` (multipart)
- Upload shows progress bar; server streams import progress via polling `GET /seller/import/:jobId/status`
- Result display: rows imported / rows failed / error details table (row number + error message)

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
- Route: `/fulfillments`
- Table: fulfillment ID, buyer name (partial — first name only for privacy), items summary, status badge, placed-at date, actions
- Status filter: PENDING / PROCESSING / SHIPPED / DELIVERED / CANCELLED / REFUNDED
- Default filter: PENDING + PROCESSING (new orders needing action)
- Actions per row: "View details" → `/fulfillments/:fulfillmentId`
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
- Route: `/fulfillments/:fulfillmentId`
- Sections: fulfillment items (with snapshot prices), buyer shipping address (display only), status timeline
- Actions based on current status:
  - PENDING/PROCESSING: "Mark as shipped" button → dialog asks for tracking number → `POST /orders/fulfillments/:id/ship`
  - SHIPPED/DELIVERED: "Request refund" button → dialog with reason dropdown → `POST /orders/fulfillments/:id/refund`
  - Any non-terminal: "Cancel" button → confirm dialog with reason → `POST /orders/fulfillments/:id/cancel`
- All amount displays via `<app-money>` (snapshot prices from FulfillmentItem)
- Tracking number field validates non-empty string

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
