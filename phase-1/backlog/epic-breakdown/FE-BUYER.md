# Epic: FE-BUYER — Buyer Portal

**Epic ID:** FE-BUYER  
**Sprint(s):** 17  
**Total Tasks:** 13  

## Epic Goal

Full buyer-facing storefront: home page, search + filters, product detail page (with other sellers section), cart, checkout, order confirmation, order history, order detail, profile, address book, notification bell. All money values via `PriceDisplayComponent`/`<aliceut-price-display>` (per `phase-1/ui-design/shared-components.md`; string-based, never JS `number`) for display.

---

## Tasks

### FE-BUYER-001 — Home page

- **US Ref:** US-B-01
- **Estimate:** M
- **Dependencies:** FE-SHARED-001, FE-SHARED-002
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/api-design/search.md`

**Implementation Notes:**
- Route: `/` (buyer-app root). Screen/layout/breakpoints per `phase-1/ui-design/buyer-portal.md` §Screen 1
- Featured products: `GET /search?limit=12&sortBy=newest` (no auth required)
- Category grid: `GET /catalog/categories`
- Search bar (top nav) → `/search?q=` on submit
- Price via `<aliceut-price-display>` (never raw number)

**Done Criteria:**
- Home page loads without auth
- Product cards display price as formatted string (not raw number)
- Category links navigate to `/search?category=<id>`
- Empty state if no products yet (seed not run)

---

### FE-BUYER-002 — Search results page

- **US Ref:** US-B-03
- **Estimate:** L
- **Dependencies:** FE-BUYER-001
- **Spec References:** `phase-1/technical-design/api-design/search.md`

**Implementation Notes:**
- Route: `/search?q=&category=&brand=&minPrice=&maxPrice=&inStockOnly=&sortBy=&cursor=`. Screen/layout per `phase-1/ui-design/buyer-portal.md` §Screen 2
- `SearchService.search(params)` calls `GET /search` with all params
- Cursor-based pagination: "Load more" appends results to list
- URL reflects all filter state (shareable links)

**Done Criteria:**
- `GET /search?q=laptop` shows matching products
- Changing sort updates URL and re-fetches
- "Load more" appends next page without losing current results
- URL with all params is shareable and re-loads same state

---

### FE-BUYER-003 — Filter sidebar

- **US Ref:** US-B-03
- **Estimate:** M
- **Dependencies:** FE-BUYER-002
- **Spec References:** `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/api-design/catalog.md`

**Implementation Notes:**
- Filter sidebar layout per `phase-1/ui-design/buyer-portal.md` §Screen 2 (Layout)
- Category tree from `GET /catalog/categories`
- Price range inputs: stored as strings; parsed via `new Decimal()` before query
- Filter state synced to URL params; changes trigger new search

**Done Criteria:**
- Category filter shows only relevant categories for current results
- Price range inputs accept decimal strings; invalid input shows error
- Mobile: filter sidebar accessible via drawer/sheet
- Applying filter updates URL and results simultaneously

---

### FE-BUYER-004 — Product detail page (PDP)

- **US Ref:** US-B-04
- **Estimate:** L
- **Dependencies:** FE-BUYER-001
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/api-design/cart.md`

**Implementation Notes:**
- Route: `/products/:offerId`. Screen/layout per `phase-1/ui-design/buyer-portal.md` §Screen 3
- Calls `GET /catalog/products/:productId` + `GET /catalog/offers/:offerId`
- Add to cart: `POST /cart/items`; quantity selector (min 1, max available stock)
- Seller info: seller name only (ratings/reviews out of scope V1 per BRD §3.2)

**Done Criteria:**
- PDP loads for authenticated and unauthenticated users
- SALE price shows strikethrough LIST price
- Out-of-stock: Add to cart button disabled
- Add to cart success: snackbar confirmation + cart icon badge increments

---

### FE-BUYER-005 — Other sellers section (PDP)

- **US Ref:** US-B-05
- **Estimate:** M
- **Dependencies:** FE-BUYER-004
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`

**Implementation Notes:**
- Section within PDP per `phase-1/ui-design/buyer-portal.md` §Screen 3 ("Other Sellers")
- Calls `GET /catalog/products/:productId/offers`; excludes current offer; sorted by effective price ascending
- Hidden if only one offer exists

**Done Criteria:**
- Section visible when 2+ offers exist for same product
- Clicking "Add to cart" in other-sellers section adds that seller's offer
- Price shown for each offer (as string via `<aliceut-price-display>`)
- Section hidden when only one seller has this product

---

### FE-BUYER-006 — Cart page

- **US Ref:** US-B-06
- **Estimate:** L
- **Dependencies:** FE-BUYER-004
- **Spec References:** `phase-1/technical-design/api-design/cart.md`

**Implementation Notes:**
- Route: `/cart` (requires `authGuard`). Screen/layout per `phase-1/ui-design/buyer-portal.md` §Screen 4
- Calls `GET /cart` on load; items grouped by seller
- Quantity change: `PATCH /cart/items/:itemId`, debounce 500ms
- Remove: `DELETE /cart/items/:itemId` with confirm dialog
- "Proceed to checkout" → `/checkout`

**Done Criteria:**
- Cart groups items by seller
- Changing quantity updates line total and subtotal (decimal.js math, displayed as string)
- Removing last item shows empty state
- Cart persists across page refresh (server-side cart)

---

### FE-BUYER-007 — Checkout page

- **US Ref:** US-B-07
- **Estimate:** XL
- **Dependencies:** FE-BUYER-006, FE-AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/api-design/cart.md`

**Implementation Notes:**
- Route: `/checkout` (requires `authGuard`). Step layout per `phase-1/ui-design/buyer-portal.md` §Screen 5 (address / summary / mock payment — display only, no real processing)
- "Place order" → `POST /cart/checkout` with selected address (address book: `GET /identity/addresses`)
- On success: redirect to `/orders/:orderId/confirmation`
- On error: `INSUFFICIENT_STOCK` → highlight out-of-stock items; `SELLER_SUSPENDED` → notify seller unavailable, prompt to remove

**Done Criteria:**
- Cannot proceed without valid shipping address
- All amounts shown as strings via `<aliceut-price-display>`
- "Place order" shows spinner; button disabled during request
- On success: redirect to confirmation page with order ID
- Insufficient stock: shows which items are unavailable (from error response)

---

### FE-BUYER-008 — Order confirmation page

- **US Ref:** US-B-08
- **Estimate:** M
- **Dependencies:** FE-BUYER-007
- **Spec References:** `phase-1/technical-design/api-design/orders.md`

**Implementation Notes:**
- Route: `/orders/:orderId/confirmation`. Screen per `phase-1/ui-design/buyer-portal.md` §Screen 6
- Calls `GET /orders/:orderId`
- "Continue shopping" → `/`; "View order details" → `/orders/:orderId`

**Done Criteria:**
- Loads correct order data after redirect from checkout
- Direct navigation to `/orders/:orderId/confirmation` for existing order works
- All monetary amounts shown as strings

---

### FE-BUYER-009 — Order history page

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** FE-AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`

**Implementation Notes:**
- Route: `/orders` (requires `authGuard`). Screen per `phase-1/ui-design/buyer-portal.md` §Screen 7
- Calls `GET /orders?limit=20&cursor=`; cursor-based "load more"
- Status badge via shared `StatusBadgeComponent` (`shared-components.md` §2)
- Filter: status filter chips (All / Active / Completed / Cancelled)

**Done Criteria:**
- Orders listed newest-first
- Status badges reflect current derived status
- "Load more" appends; doesn't reset list
- Filter chips update query and re-fetch

---

### FE-BUYER-010 — Order detail page

- **US Ref:** US-B-10
- **Estimate:** M
- **Dependencies:** FE-BUYER-009
- **Spec References:** `phase-1/technical-design/api-design/orders.md`

**Implementation Notes:**
- Route: `/orders/:orderId`. Screen per `phase-1/ui-design/buyer-portal.md` §Screen 8
- Calls `GET /orders/:orderId`
- Amounts from FulfillmentItem snapshot; shipping address is PII — display only, never logged client-side
- "Track shipment" link: opens mock tracking URL from `tracking_number` (visible only when `status = SHIPPED`)

**Done Criteria:**
- All amounts from FulfillmentItem snapshot (not live pricing)
- Tracking link visible only when `status = SHIPPED`
- Page accessible without coming from order history (direct URL works)

---

### FE-BUYER-011 — Profile page

- **US Ref:** US-B-11
- **Estimate:** M
- **Dependencies:** FE-AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`

**Implementation Notes:**
- Route: `/account/profile` (requires `authGuard`). Screen per `phase-1/ui-design/buyer-portal.md` §Screen 11
- Calls `GET /identity/profile`; save via `PATCH /identity/profile`
- Avatar upload: `POST /identity/profile/avatar` (multipart)
- Email read-only (change-email flow out of scope V1)

**Done Criteria:**
- Profile loads with current values pre-filled
- Avatar upload shows preview; saves to MinIO; updates display
- Save shows success snackbar
- Invalid phone number: validation error

---

### FE-BUYER-012 — Address book page

- **US Ref:** US-B-12
- **Estimate:** M
- **Dependencies:** FE-AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`

**Implementation Notes:**
- Route: `/account/addresses` (requires `authGuard`). Screen per `phase-1/ui-design/buyer-portal.md` §Screen 11 (address tab)
- Calls `GET /identity/addresses`
- Max 10 addresses enforced by API; hide "Add address" once reached
- Delete: confirm dialog via shared `ConfirmDialogComponent` (`shared-components.md` §7) → `DELETE /identity/addresses/:id`
- Set default: `PATCH /identity/addresses/:id { isDefault: true }`

**Done Criteria:**
- Default address marked visually
- Cannot add 11th address (UI prevents + API rejects)
- Delete address not in use (not selected in active checkout)
- Setting new default removes old default badge

---

### FE-BUYER-013 — Notification bell

- **US Ref:** US-B-13
- **Estimate:** M
- **Dependencies:** FE-SHARED-006
- **Spec References:** `phase-1/technical-design/api-design/orders.md`

**Implementation Notes:**
- Shared `NotificationBellComponent` (`phase-1/ui-design/shared-components.md` §1) in top nav; `/notifications` route per `buyer-portal.md` §Screen 16
- Badge count: `GET /notifications/unread-count`, polled every 30s
- "Mark all read" → `POST /notifications/read-all`
- `/notifications` full list: `GET /notifications` (paginated)

**Done Criteria:**
- Badge count updates within 30s of new notification
- Clicking notification in dropdown marks it read and navigates to relevant page (orderId → `/orders/:orderId`)
- "Mark all read" clears badge count
- Polling stops when user logs out
