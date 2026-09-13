# EPIC: CART — Cart Module

**Sprint:** 4
**Lib:** `libs/cart/`
**Module:** `CartModule`
**Controllers:** `CartController`
**No Kafka events produced** (cart state changes are not domain events)

Overview: Manages the server-side authenticated cart. Guest carts live in browser localStorage (no server component). Cart merges at login. Each GET /cart call re-resolves effective prices to reflect seller changes. Stale items (inactive offer) are labelled but not auto-removed. Cart is NOT a price-locking mechanism — price is locked only at checkout.

---

### CART-001 — cart Schema Migrations
**US Ref:** —
**Estimate:** S
**Dependencies:** PLATFORM-001
**Implementation Notes:**
- File: `libs/cart/src/infrastructure/migrations/0001_cart_schema.sql`
- Tables: `cart.cart`, `cart.cart_item`
- `cart.cart.user_id` unique (one server cart per authenticated user)
- `cart_item(cart_id, offer_id)` unique (no duplicate offer+variant in cart; qty is updated instead)
- FK: `cart.user_id → identity.user(id)`, `cart_item.offer_id → catalog.offer(id)` (cross-schema)
- Index: `cart(user_id)`, `cart_item(cart_id)`

**Done Criteria:**
- Cart tables created; unique constraints work

---

### CART-002 — Cart Entity + Repository Interface
**US Ref:** US-B-06
**Estimate:** M
**Dependencies:** CART-001
**Implementation Notes:**
- TypeORM entity for `cart.cart`
- `CartRepository`: `findByUserId(userId)`, `findOrCreate(userId)`, `save(cart)`
- `CartService.getOrCreateCart(userId)`: returns existing cart or creates empty one

**Done Criteria:**
- `findOrCreate` creates cart on first call; returns existing on subsequent calls

---

### CART-003 — CartItem Entity + Repository Interface
**US Ref:** US-B-06
**Estimate:** M
**Dependencies:** CART-001
**Implementation Notes:**
- TypeORM entity for `cart.cart_item`
- `CartItemRepository`: `findByCart(cartId)`, `findByCartAndOffer(cartId, offerId)`, `countByCart(cartId)`, `save(item)`, `delete(id)`
- No price stored on cart_item; price re-resolved on every GET /cart

**Done Criteria:**
- `findByCartAndOffer` returns existing item for deduplication (update qty instead of insert)

---

### CART-004 — GET /cart
**US Ref:** US-B-06
**Estimate:** L
**Dependencies:** CART-003, PRICING-005
**Implementation Notes:**
- `@JwtAuthGuard`; returns enriched cart with live price resolution
- For each cart item:
  1. Load offer + product + variant
  2. Check `offer.status != ACTIVE` → mark as `isStale: true`
  3. Re-resolve effective price via `EffectivePriceService.resolve(offerId, { accountType, qty: item.quantity, preferredCurrency })`
  4. Check available inventory (INVENTORY-002); if `available_qty < item.quantity` → mark `availableQty` in response
- Response: `{ items: [{ id, offerId, productTitle, variantLabel, quantity, unitPrice, currency, lineTotal, isStale, isAvailable, availableQty, productImageUrl }], itemCount, subtotal, hasStaleItems }`
- Checkout CTA disabled in frontend when `hasStaleItems: true`
- `subtotal` uses decimal.js for aggregation (never JS number)

**Done Criteria:**
- GET /cart returns live prices (re-resolved on every call)
- Stale item (offer.status = REMOVED) → `isStale: true` in response
- Subtotal calculation uses decimal arithmetic (0.1 + 0.2 = 0.30)

---

### CART-005 — POST /cart/items
**US Ref:** US-B-06
**Estimate:** M
**Dependencies:** CART-002, INVENTORY-002
**Implementation Notes:**
- DTO: `AddToCartDto { offerId, quantity (≥1) }`
- Checks:
  1. Offer exists and `status = ACTIVE` → 422 if not
  2. `available_qty >= quantity` → 422 "Only N available" if insufficient
  3. `countByCart(cartId) < 50` → 422 "Cart limit reached" if 50 items already
- If item already in cart (same offerId): increment quantity (up to available_qty)
- Returns updated cart item

**Done Criteria:**
- Adding inactive offer → 422
- Adding qty=5 when only 3 available → 422 "Only 3 available"
- Adding 51st distinct item → 422 "Cart limit reached"
- Adding existing offer increments quantity

---

### CART-006 — PUT /cart/items/:id
**US Ref:** US-B-06
**Estimate:** M
**Dependencies:** CART-003, INVENTORY-002
**Implementation Notes:**
- DTO: `UpdateCartItemDto { quantity: number (≥1) }`
- Ownership check: cart item must belong to authenticated user's cart → 404 if not
- Re-validate `available_qty >= newQuantity` → 422 "Only N available"
- Returns updated cart item

**Done Criteria:**
- Update qty to exceed available → 422 with correct available count
- Update another user's cart item → 404

---

### CART-007 — DELETE /cart/items/:id
**US Ref:** US-B-06
**Estimate:** S
**Dependencies:** CART-003
**Implementation Notes:**
- Ownership check: cart item must belong to authenticated user's cart
- Hard delete (not soft delete)
- Returns 204 No Content

**Done Criteria:**
- Delete own item → 204; cart item gone on next GET /cart
- Delete another user's item → 404

---

### CART-008 — Guest Cart Merge on Login
**US Ref:** US-B-07
**Estimate:** L
**Dependencies:** CART-002, INVENTORY-002
**Implementation Notes:**
- Triggered in `AuthService.login()` after successful authentication, if client sends `guestCart` in request body
- `guestCart` format: `[{ offerId, quantity }]` (same as localStorage format in frontend)
- Merge logic:
  1. For each guest item:
     - Check offer is ACTIVE and `available_qty > 0`
     - If offer already in server cart: `newQty = serverQty + guestQty`; cap at `available_qty`
     - If not in cart: add as new item (check 50-item limit)
  2. Collect result: `{ addedCount, adjustedCount, skippedCount }`
- Return: `{ accessToken, refreshToken, user, cartMergeResult }`
- Toast message logic: "N item(s) from your guest session were added to your cart." + append adjustment warning if `adjustedCount > 0`

**Done Criteria:**
- Login with guest cart: server cart contains merged items
- Quantity caps at live available_qty (checked at merge time)
- Inactive offer in guest cart → skipped (not added)
- Cart limit (50 items) respected during merge

---

### CART-009 — Stale Item Detection
**US Ref:** US-B-06
**Estimate:** M
**Dependencies:** CART-003, CATALOG-008
**Implementation Notes:**
- Part of GET /cart response enrichment (CART-004)
- Stale = `offer.status != ACTIVE` (REMOVED, FLAGGED, INACTIVE)
- Response field: `isStale: true` with `staleReason: 'Unavailable'`
- `hasStaleItems: boolean` at cart level — used by checkout CTA guard
- Stale items are NOT auto-removed; buyer must explicitly remove them
- Buyer cannot proceed to checkout while `hasStaleItems = true`

**Done Criteria:**
- Seller removes listing → GET /cart shows that item as stale
- POST /orders/checkout with stale items: stale items excluded from checkout (not a blocking error; included in `skipped_items` response per US-B-09)

---

### CART-010 — Cart 50-Item Limit
**US Ref:** US-B-06
**Estimate:** S
**Dependencies:** CART-002
**Implementation Notes:**
- Enforced in `CartService.addItem()` before inserting new item
- Count distinct `(cart_id, offer_id)` combinations in `cart_item`
- If count >= 50: throw `CartLimitException` → 422 "Cart limit reached. Remove an item to continue."
- Updating quantity of existing item does NOT increment distinct count

**Done Criteria:**
- 50 distinct items already in cart → adding 51st → 422
- Increasing quantity of existing item → 200 (not limited)
