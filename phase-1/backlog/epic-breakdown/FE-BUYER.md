# Epic: FE-BUYER — Buyer Portal

**Epic ID:** FE-BUYER  
**Sprint(s):** 17  
**Status:** Later  
**Total Tasks:** 13  

## Epic Goal

Full buyer-facing storefront: home page, search + filters, product detail page (with other sellers section), cart, checkout, order confirmation, order history, order detail, profile, address book, notification bell. All money values via `<app-money>` (string-based); never JS `number` for display.

---

## Tasks

### FE-BUYER-001 — Home page

**Estimate:** M (4h)  
**User Story:** US-B-01  
**Dependencies:** FE-SHARED-001, FE-SHARED-002  

**Implementation Notes:**
- Route: `/` (buyer-app root)
- Featured products section: `GET /search?limit=12&sortBy=newest` (no auth required)
- Category grid: static list of top-level categories from `GET /catalog/categories`
- Search bar (top nav): routes to `/search?q=` on submit
- Responsive grid: 4 columns (desktop) → 2 (tablet) → 1 (mobile)
- Product card: thumbnail, title, effective price (LIST or SALE), in-stock badge
- Price rendered via `<app-money [amount]="product.listPriceUsd" currency="USD">`

**Done Criteria:**
- Home page loads without auth
- Product cards display price as formatted string (not raw number)
- Category links navigate to `/search?category=<id>`
- Empty state if no products yet (seed not run)

---

### FE-BUYER-002 — Search results page

**Estimate:** L (8h)  
**User Story:** US-B-03  
**Dependencies:** FE-BUYER-001  

**Implementation Notes:**
- Route: `/search?q=&category=&brand=&minPrice=&maxPrice=&inStockOnly=&sortBy=&cursor=`
- `SearchService.search(params)` calls `GET /search` with all params
- Results grid: same product card component as home page
- Loading skeleton: MatSkeletonLoader placeholders while request pending
- "No results" empty state with suggestions
- Sort dropdown: Relevance / Price Low-High / Price High-Low / Newest
- Cursor-based pagination: "Load more" button (not page numbers); appends results to list
- URL reflects all filter state (shareable links)

**Done Criteria:**
- `GET /search?q=laptop` shows matching products
- Changing sort updates URL and re-fetches
- "Load more" appends next page without losing current results
- URL with all params is shareable and re-loads same state

---

### FE-BUYER-003 — Filter sidebar

**Estimate:** M (4h)  
**User Story:** US-B-03  
**Dependencies:** FE-BUYER-002  

**Implementation Notes:**
- Collapsible left sidebar on search results page (hidden on mobile → drawer/sheet)
- Filters:
  - Category tree (from `GET /catalog/categories`; hierarchical checkboxes)
  - Price range: two number inputs (stored as strings; parsed via `new Decimal()` before query)
  - In-stock only: toggle
  - Brand: multi-select checkboxes (top 10 brands from search results' aggregations — V1: static from search response)
- Filter state synced to URL params; changes trigger new search
- "Clear all filters" button resets to empty `q=` results

**Done Criteria:**
- Category filter shows only relevant categories for current results
- Price range inputs accept decimal strings; invalid input shows error
- Mobile: filter sidebar accessible via drawer/sheet
- Applying filter updates URL and results simultaneously

---

### FE-BUYER-004 — Product detail page (PDP)

**Estimate:** L (8h)  
**User Story:** US-B-04  
**Dependencies:** FE-BUYER-001  

**Implementation Notes:**
- Route: `/products/:offerId`
- Calls `GET /catalog/products/:productId` + `GET /catalog/offers/:offerId`
- Image gallery: main image + thumbnails (from MinIO URLs in offer data)
- Effective price display: if SALE price active, show SALE price + strikethrough LIST price
- B2B badge: if `user.roles` includes `BUYER` + account type = business → show B2B badge
- Add to cart: calls `POST /cart/items`; quantity selector (min 1, max available stock)
- Stock indicator: "In stock" / "Low stock (X left)" / "Out of stock"
- Seller info: seller name, rating placeholder (V1: static 4.5★)

**Done Criteria:**
- PDP loads for authenticated and unauthenticated users
- SALE price shows strikethrough LIST price
- Out-of-stock: Add to cart button disabled
- Add to cart success: snackbar confirmation + cart icon badge increments

---

### FE-BUYER-005 — Other sellers section (PDP)

**Estimate:** M (4h)  
**User Story:** US-B-05  
**Dependencies:** FE-BUYER-004  

**Implementation Notes:**
- Section below main PDP content: "Other offers for this product"
- Calls `GET /catalog/products/:productId/offers` (all active offers for same product)
- Lists: seller name, price in buyer's currency, in-stock status, "Add to cart" button
- Sorted by effective price ascending
- Excludes current offer (the one shown in main PDP section)
- Hidden if only one offer exists

**Done Criteria:**
- Section visible when 2+ offers exist for same product
- Clicking "Add to cart" in other-sellers section adds that seller's offer
- Price shown for each offer (as string via `<app-money>`)
- Section hidden when only one seller has this product

---

### FE-BUYER-006 — Cart page

**Estimate:** L (8h)  
**User Story:** US-B-06  
**Dependencies:** FE-BUYER-004  

**Implementation Notes:**
- Route: `/cart` (requires `authGuard`)
- Calls `GET /cart` on load; renders line items grouped by seller
- Line item: product thumbnail, title, seller name, unit price (string), quantity input, remove button, line total
- Quantity input: PATCH `/cart/items/:itemId` on change; debounce 500ms
- Remove: DELETE `/cart/items/:itemId` with confirm dialog
- Order summary: subtotal (sum of line totals), note about taxes/shipping
- "Proceed to checkout" button → `/checkout`
- Cart badge in nav: calls `GET /cart` → count of items

**Done Criteria:**
- Cart groups items by seller
- Changing quantity updates line total and subtotal (decimal.js math, displayed as string)
- Removing last item shows empty state
- Cart persists across page refresh (server-side cart)

---

### FE-BUYER-007 — Checkout page

**Estimate:** XL (12h)  
**User Story:** US-B-07  
**Dependencies:** FE-BUYER-006, FE-AUTH-001  

**Implementation Notes:**
- Route: `/checkout` (requires `authGuard`)
- Step 1: Shipping address — select from address book (`GET /identity/addresses`) or add new inline
- Step 2: Order summary — read-only cart grouped by seller with effective prices
- Step 3: Payment — mock payment form (card number/expiry/CVV fields — display only, no real processing)
- "Place order" button calls `POST /cart/checkout` with selected address
- Loading state during checkout (can take several seconds: reservation + snapshot + fulfillment creation)
- On success: redirect to `/orders/:orderId/confirmation`
- On error:
  - `INSUFFICIENT_STOCK`: highlight out-of-stock items; prompt to remove
  - `SELLER_SUSPENDED`: notify seller unavailable; prompt to remove

**Done Criteria:**
- Cannot proceed without valid shipping address
- All amounts shown as strings via `<app-money>`
- "Place order" shows spinner; button disabled during request
- On success: redirect to confirmation page with order ID
- Insufficient stock: shows which items are unavailable (from error response)

---

### FE-BUYER-008 — Order confirmation page

**Estimate:** M (4h)  
**User Story:** US-B-08  
**Dependencies:** FE-BUYER-007  

**Implementation Notes:**
- Route: `/orders/:orderId/confirmation`
- Calls `GET /orders/:orderId` to fetch order details
- Shows: order ID, placed-at timestamp, items per seller, total amount, shipping address
- "Continue shopping" button → `/`
- "View order details" button → `/orders/:orderId`
- Email confirmation notice: "A confirmation email has been sent to {email}"

**Done Criteria:**
- Loads correct order data after redirect from checkout
- Direct navigation to `/orders/:orderId/confirmation` for existing order works
- All monetary amounts shown as strings

---

### FE-BUYER-009 — Order history page

**Estimate:** M (4h)  
**User Story:** US-B-09  
**Dependencies:** FE-AUTH-001  

**Implementation Notes:**
- Route: `/orders` (requires `authGuard`)
- Calls `GET /orders?limit=20&cursor=` with cursor pagination
- Order card: order ID, placed-at date, status badge (OPEN/COMPLETED/CANCELLED), total amount, thumbnail of first item
- Status badge colors: OPEN=blue, COMPLETED=green, CANCELLED=grey, PARTIAL_REFUND=orange
- Cursor-based "load more"
- Filter: status filter chips (All / Active / Completed / Cancelled)

**Done Criteria:**
- Orders listed newest-first
- Status badges reflect current derived status
- "Load more" appends; doesn't reset list
- Filter chips update query and re-fetch

---

### FE-BUYER-010 — Order detail page

**Estimate:** M (4h)  
**User Story:** US-B-10  
**Dependencies:** FE-BUYER-009  

**Implementation Notes:**
- Route: `/orders/:orderId`
- Calls `GET /orders/:orderId`
- Sections:
  - Order header: ID, placed-at, overall status
  - Fulfillments list: per-seller section showing items, fulfillment status, tracking number (if shipped)
  - Payment summary: amount paid (from snapshot; as string)
  - Shipping address (display only; PII — rendered as-is, never logged client-side)
- Fulfillment status badges per seller: PENDING/PROCESSING/SHIPPED/DELIVERED/CANCELLED/REFUNDED
- "Track shipment" link: opens tracking URL in new tab (mock URL from `tracking_number` field)

**Done Criteria:**
- All amounts from FulfillmentItem snapshot (not live pricing)
- Tracking link visible only when `status = SHIPPED`
- Page accessible without coming from order history (direct URL works)

---

### FE-BUYER-011 — Profile page

**Estimate:** M (4h)  
**User Story:** US-B-11  
**Dependencies:** FE-AUTH-001  

**Implementation Notes:**
- Route: `/account/profile` (requires `authGuard`)
- Calls `GET /identity/profile`
- Editable fields: first name, last name, phone
- Avatar upload: file input → `POST /identity/profile/avatar` (multipart); preview before upload
- Read-only fields: email (change email flow out of scope V1)
- Save via `PATCH /identity/profile`
- MatFormField with reactive form + validators

**Done Criteria:**
- Profile loads with current values pre-filled
- Avatar upload shows preview; saves to MinIO; updates display
- Save shows success snackbar
- Invalid phone number: validation error

---

### FE-BUYER-012 — Address book page

**Estimate:** M (4h)  
**User Story:** US-B-12  
**Dependencies:** FE-AUTH-001  

**Implementation Notes:**
- Route: `/account/addresses` (requires `authGuard`)
- Calls `GET /identity/addresses`
- Address cards: full address display, "Default" badge on default address, Edit / Delete buttons
- Max 10 addresses enforced by API; if 10 exist, hide "Add address" button + show tooltip
- Add/edit: inline expand or MatDialog form (street, city, state, postal, country, label)
- Delete: confirm dialog before `DELETE /identity/addresses/:id`
- Set default: PUT button calls `PATCH /identity/addresses/:id { isDefault: true }`

**Done Criteria:**
- Default address marked visually
- Cannot add 11th address (UI prevents + API rejects)
- Delete address not in use (not selected in active checkout)
- Setting new default removes old default badge

---

### FE-BUYER-013 — Notification bell

**Estimate:** M (4h)  
**User Story:** US-B-13  
**Dependencies:** FE-SHARED-010  

**Implementation Notes:**
- `<app-notification-badge>` in top nav (auth-required; hidden when logged out)
- Badge count from `GET /notifications/unread-count` (polled every 30s via `interval(30000)`)
- Click opens MatMenu dropdown showing latest 5 unread notifications
- Each row: icon by type, title, relative time (e.g. "2 minutes ago")
- "Mark all read" button calls `POST /notifications/read-all`
- "View all" link → `/notifications`
- `/notifications` route: full paginated list using `GET /notifications`

**Done Criteria:**
- Badge count updates within 30s of new notification
- Clicking notification in dropdown marks it read and navigates to relevant page (orderId → `/orders/:orderId`)
- "Mark all read" clears badge count
- Polling stops when user logs out
