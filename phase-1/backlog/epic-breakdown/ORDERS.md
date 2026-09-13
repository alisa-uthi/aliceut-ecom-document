# Epic: ORDERS — Orders / Checkout Module

**Epic ID:** ORDERS  
**Sprint(s):** 13–14  
**Status:** Later  
**Total Tasks:** 22  

## Epic Goal

Checkout atomically: group cart by seller/currency, reserve inventory, snapshot immutable prices, create fulfillments. Mock payment. Order + fulfillment lifecycle (PENDING→SHIPPED→DELIVERED; PENDING/SHIPPED→REFUNDED; PENDING→CANCELLED). Scheduled workers for mock delivery and auto-refund of suspended seller orders.

---

## Tasks

### ORDERS-001 — orders schema raw-SQL migrations

**Estimate:** L (8h)  
**User Story:** —  
**Dependencies:** PLATFORM-001  

**Implementation Notes:**
- Create `orders` PostgreSQL schema
- Tables:
  ```sql
  CREATE TABLE orders.order (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    display_id VARCHAR(20) NOT NULL UNIQUE,  -- e.g. ORD-a1b2c3d4
    buyer_id UUID NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    placement_outcome VARCHAR(20) NOT NULL DEFAULT 'SUCCESS',  -- SUCCESS|PARTIAL|FAILED
    shipping_address JSONB NOT NULL,   -- snapshot at checkout
    preferred_currency CHAR(3) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX idx_order_buyer ON orders.order (buyer_id, created_at DESC);

  CREATE TABLE orders.fulfillment (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    display_id VARCHAR(20) NOT NULL UNIQUE,  -- e.g. FUL-a1b2c3d4
    order_id UUID NOT NULL REFERENCES orders.order(id),
    seller_id UUID NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    currency CHAR(3) NOT NULL,
    shipping_method VARCHAR(50),
    tracking_number VARCHAR(100),
    eta TIMESTAMPTZ,
    placed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    shipped_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancel_reason TEXT,
    refund_reason TEXT
  );
  CREATE INDEX idx_fulfillment_order ON orders.fulfillment (order_id);
  CREATE INDEX idx_fulfillment_seller ON orders.fulfillment (seller_id, status);

  CREATE TABLE orders.fulfillment_item (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    fulfillment_id UUID NOT NULL REFERENCES orders.fulfillment(id),
    offer_id UUID NOT NULL,
    variant_id UUID,
    product_title VARCHAR(500) NOT NULL,    -- snapshot
    variant_attributes JSONB,               -- snapshot
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(19,4) NOT NULL,      -- snapshot at checkout
    currency CHAR(3) NOT NULL,              -- snapshot
    tax_amount NUMERIC(19,4) NOT NULL DEFAULT 0,
    fx_rate_used_at_capture NUMERIC(19,8),  -- snapshot if cross-currency
    reservation_id UUID                     -- reference to consumed reservation
    -- NO updated_at: this table is immutable after insert
  );
  CREATE INDEX idx_fulfillment_item_fulfillment ON orders.fulfillment_item (fulfillment_id);

  CREATE TABLE orders.payment_attempt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    order_id UUID NOT NULL REFERENCES orders.order(id),
    amount NUMERIC(19,4) NOT NULL,
    currency CHAR(3) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'SIMULATED_SUCCESS',
    provider VARCHAR(50) NOT NULL DEFAULT 'MOCK',
    provider_ref VARCHAR(100),
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );

  CREATE TABLE orders.idempotency_key (
    key VARCHAR(100) PRIMARY KEY,
    order_id UUID REFERENCES orders.order(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
  );
  ```

**Done Criteria:**
- All 5 tables created
- `fulfillment_item` has NO `updated_at` column (immutable after insert)
- `unit_price` and `fx_rate_used_at_capture` are NUMERIC (not float)

---

### ORDERS-002 — Order entity + repository interface

**Estimate:** M (4h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-001  

**Implementation Notes:**
- `Order` TypeORM entity; `display_id` generated as `ORD-${id.slice(0,8)}`
- `IOrderRepository`: `findById`, `findByBuyer`, `create`, `updateStatus`
- `status` derived from fulfillment states (ORDERS-013); not set directly on order table
- `shipping_address` stored as JSONB snapshot (not FK to address table)

**Done Criteria:**
- Order created with auto-generated `display_id`
- `shipping_address` JSONB has complete address fields at time of checkout

---

### ORDERS-003 — Fulfillment entity + repository + status state machine

**Estimate:** M (4h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-001  

**Implementation Notes:**
- `Fulfillment` TypeORM entity
- State machine: `PENDING→SHIPPED`, `PENDING→CANCELLED`, `PENDING/SHIPPED→REFUNDED`, `SHIPPED→DELIVERED`
- `FulfillmentStatusService.transition(fulfillment, newStatus, em)` enforces valid transitions
- `display_id`: `FUL-${id.slice(0,8)}`

**Done Criteria:**
- Invalid transition (e.g., DELIVERED→PENDING) → throws ConflictException
- All timestamps (shipped_at, delivered_at, etc.) set on transition

---

### ORDERS-004 — FulfillmentItem entity + repository (immutable)

**Estimate:** M (4h)  
**User Story:** US-P-03  
**Dependencies:** ORDERS-001  

**Implementation Notes:**
- `FulfillmentItem` TypeORM entity; NO `@UpdateDateColumn`
- `unit_price` and `tax_amount` stored as strings in TypeScript (NUMERIC in DB)
- Fields snapshotted at checkout: `productTitle`, `variantAttributes`, `unitPrice`, `currency`, `taxAmount`, `fxRateUsedAtCapture`
- No service should ever UPDATE a fulfillment_item row after insert

**Done Criteria:**
- TypeScript type has no update method on repository
- `unit_price` returned as string from API (never as number)
- ESLint: no-direct-update rule on fulfillment_item (enforced via code review)

---

### ORDERS-005 — PaymentAttempt entity + repository (mock, append-only)

**Estimate:** M (4h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-001  

**Implementation Notes:**
- `PaymentAttempt` TypeORM entity; always `provider: 'MOCK'`, `status: 'SIMULATED_SUCCESS'`
- V1 mock payment: always succeeds; real payment gateway out of scope
- Append-only: no updates, no deletes

**Done Criteria:**
- PaymentAttempt created with every order
- Always `status: 'SIMULATED_SUCCESS'` in V1

---

### ORDERS-006 — IdempotencyKey entity + CheckoutIdempotencyService

**Estimate:** M (4h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-001  

**Implementation Notes:**
- `Idempotency-Key` header on `POST /orders/checkout`
- Service checks if key exists → return existing order; otherwise create new
- Key TTL: 24h
- If existing key found for same request → return 200 with existing order (no duplicate processing)

**Done Criteria:**
- Same idempotency key on two requests → second request returns first order (no duplicate)
- Expired key → treated as new request

---

### ORDERS-007 — CheckoutService: cart validation

**Estimate:** L (8h)  
**User Story:** US-B-09  
**Dependencies:** CART-003  

**Implementation Notes:**
- Re-resolve all offer prices from `PricingService` (NOT from cart)
- Compare to "expected" prices (frontend may send expected prices for revalidation UX)
- Collect unavailable items: `offer.status !== 'ACTIVE'` or `available_qty = 0`
- Return: `{ availableItems, unavailableItems, priceChangedItems }`
- Unavailable items excluded from checkout (not hard failure — partial checkout)
- Zero available items → hard failure; 422

**Done Criteria:**
- Cart with 1 unavailable item → checkout proceeds with remaining items; unavailable noted in response
- All items unavailable → 422 with reason
- Price change detected → `priceChangedItems` flagged (frontend shows modal)

---

### ORDERS-008 — CheckoutService: seller/currency grouping

**Estimate:** M (4h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-007  

**Implementation Notes:**
- Group available cart items by `(seller_id, currency)` → creates one fulfillment per group
- Each fulfillment has exactly one currency (seller's pricing currency)
- Single order contains multiple fulfillments

**Done Criteria:**
- Items from 2 sellers → 2 fulfillments
- Items from same seller but different currencies → 2 fulfillments
- Group mapping: `Map<sellerCurrencyKey, CartItem[]>`

---

### ORDERS-009 — CheckoutService: atomic reservation + snapshot transaction

**Estimate:** XL (16h)  
**User Story:** US-P-03  
**Dependencies:** ORDERS-008  

**Implementation Notes:**
- Critical path; single PostgreSQL transaction per fulfillment group
- For each group (in sequence, not parallel):
  1. Reserve inventory for each item: `InventoryService.reserve(offerId, qty, orderId, em)`
  2. Snapshot prices: `PricingService.resolveEffectivePrice(offerId, currency, accountType, qty)`
  3. Create `fulfillment` row
  4. Create `fulfillment_item` rows (immutable snapshots)
  5. Write outbox event `fulfillment.placed`
  6. Remove cart items for successfully reserved offers
- If reservation fails for a group: skip that group; include in `failedGroups` response
- Outer transaction: create `order` row first; link all fulfillments to order
- Snapshot `shipping_address` as JSONB from buyer's selected address

**Done Criteria:**
- Unit price in `fulfillment_item` is immutable snapshot, not FK to live price
- Concurrent checkouts for last item: exactly one succeeds; other gets `INSUFFICIENT_STOCK` in `failedGroups`
- Cart items for successful fulfillments cleared; failed groups' items remain in cart
- All operations in one DB transaction per group; partial group failure rolls back that group only

---

### ORDERS-010 — CheckoutService: mock payment simulation

**Estimate:** M (4h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-009  

**Implementation Notes:**
- After reservations and fulfillments created: create `payment_attempt` row (always SIMULATED_SUCCESS)
- V1: no real payment; always succeeds; never fails
- Payment amount: sum of all fulfillment subtotals in buyer's preferred currency (FX converted)

**Done Criteria:**
- `payment_attempt` row created with `status: 'SIMULATED_SUCCESS'`
- Mock payment never throws

---

### ORDERS-011 — Order + Fulfillment display_id generation

**Estimate:** S (2h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-002  

**Implementation Notes:**
- `display_id` generated from first 8 hex chars of UUID: `ORD-${id.replace(/-/g,'').slice(0,8).toUpperCase()}`
- Must be unique (UNIQUE constraint enforces)
- Collision probability negligible with UUIDv7

**Done Criteria:**
- All orders have `ORD-XXXXXXXX` format
- All fulfillments have `FUL-XXXXXXXX` format
- Duplicate display_id rejected by DB constraint

---

### ORDERS-012 — POST /orders/checkout

**Estimate:** L (8h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-009  

**Implementation Notes:**
- `@UseGuards(JwtAuthGuard)`; email must be verified (`email_verified: true`) to checkout
- `CheckoutDto`: `addressId`, `idempotencyKey`
- Idempotency check first (ORDERS-006)
- Response: `{ orderId, displayId, status, placementOutcome: 'SUCCESS'|'PARTIAL'|'FAILED', fulfillments: [], skippedItems: [], failedGroups: [] }`
- `PARTIAL`: some groups succeeded, some failed
- `FAILED`: all groups failed

**Done Criteria:**
- Successful checkout → 201 with order + fulfillments
- Email not verified → 403 `EMAIL_NOT_VERIFIED`
- Partial: response clearly identifies succeeded and failed groups

---

### ORDERS-013 — Order aggregate status derivation

**Estimate:** M (4h)  
**User Story:** US-B-09  
**Dependencies:** ORDERS-003  

**Implementation Notes:**
- Order status is derived from fulfillment statuses (not stored directly)
- Rules: ALL PENDING → PENDING; ANY SHIPPED (rest PENDING) → PARTIALLY_SHIPPED; ALL SHIPPED → SHIPPED; ALL DELIVERED → DELIVERED; ALL CANCELLED → CANCELLED; ALL REFUNDED → REFUNDED; mixed → PARTIALLY_FULFILLED
- Exposed as computed property or materialized on read

**Done Criteria:**
- Order with 2 fulfillments: one SHIPPED, one PENDING → order status PARTIALLY_SHIPPED
- All fulfillments DELIVERED → order status DELIVERED

---

### ORDERS-014 — GET /orders (buyer order history)

**Estimate:** M (4h)  
**User Story:** US-B-11  
**Dependencies:** ORDERS-002  

**Implementation Notes:**
- `@UseGuards(JwtAuthGuard)`
- Paginated; newest first; `limit` max 20
- Each item: `{ orderId, displayId, status, createdAt, fulfillmentCount, itemCount, hasPartialFailure }`
- `hasPartialFailure`: true if `placement_outcome == 'PARTIAL'` (show warning in UI)

**Done Criteria:**
- Returns only buyer's own orders
- Correct pagination with cursor
- `hasPartialFailure` flag present on partial orders

---

### ORDERS-015 — GET /orders/:id (order detail)

**Estimate:** M (4h)  
**User Story:** US-B-11  
**Dependencies:** ORDERS-002  

**Implementation Notes:**
- Full order detail: order + all fulfillments + all fulfillment_items (with snapshots)
- Include payment status
- Fulfillment items show snapshotted prices (not current live prices)
- Ownership check: buyer can only view own orders

**Done Criteria:**
- `unit_price` in response is the snapshot value, not current live price
- Other buyer attempting to view → 404 (not leak order existence)

---

### ORDERS-016 — GET /seller/fulfillments

**Estimate:** M (4h)  
**User Story:** US-S-05  
**Dependencies:** ORDERS-003  

**Implementation Notes:**
- Paginated, filterable by `status` tab
- Each row: `{ fulfillmentId, displayId, status, buyerName, orderDate, itemCount, totalAmount, currency }`
- Only seller's own fulfillments
- Default sort: newest `placed_at` first

**Done Criteria:**
- Seller sees only their fulfillments
- Filter by `?status=PENDING` works
- `totalAmount` computed from fulfillment_item snapshots

---

### ORDERS-017 — GET /seller/fulfillments/:id

**Estimate:** M (4h)  
**User Story:** US-S-05b  
**Dependencies:** ORDERS-003  

**Implementation Notes:**
- Full fulfillment detail with items
- Includes buyer's shipping address (PII — access logged per NFR-09)
- Access log to MongoDB: `{ sellerId, fulfillmentId, buyerAddressAccessed: true, accessedAt }`

**Done Criteria:**
- Buyer's address visible to seller
- Access logged to MongoDB audit collection on every GET

---

### ORDERS-018 — POST /seller/fulfillments/:id/ship

**Estimate:** M (4h)  
**User Story:** US-S-06  
**Dependencies:** ORDERS-003  

**Implementation Notes:**
- `ShipDto`: `trackingNumber?`, `estimatedDeliveryDays?` (default from seller profile `fulfillment_window_days`)
- Transition `PENDING → SHIPPED`
- Set `shipped_at`, `tracking_number`, `eta = now() + estimatedDeliveryDays`
- Write outbox event `fulfillment.shipped`
- Idempotent: already SHIPPED → return 200 (no error)

**Done Criteria:**
- PENDING → SHIPPED transition succeeds; `shipped_at` set
- Already SHIPPED → 200 (idempotent)
- `fulfillment.shipped` outbox event written

---

### ORDERS-019 — POST /seller/fulfillments/:id/refund

**Estimate:** L (8h)  
**User Story:** US-S-07  
**Dependencies:** ORDERS-003  

**Implementation Notes:**
- `RefundDto`: `reason` (required)
- Allowed statuses: PENDING, SHIPPED
- If PENDING: also restore inventory (`stock.on_hand_qty += qty`; reservation CANCELLED)
- `refunded_at = now()`, `refund_reason`
- Write outbox event `fulfillment.refunded`

**Done Criteria:**
- Refunding PENDING → inventory restored; outbox event written
- Refunding SHIPPED → no inventory restore (already shipped)
- Refunding DELIVERED → 422 (cannot refund delivered in V1)

---

### ORDERS-020 — POST /seller/fulfillments/:id/cancel

**Estimate:** L (8h)  
**User Story:** US-S-11  
**Dependencies:** ORDERS-003  

**Implementation Notes:**
- Only PENDING can be cancelled by seller
- Restore inventory: `on_hand_qty += qty`; reservation CANCELLED
- `cancelled_at`, `cancel_reason`
- Write outbox event `fulfillment.cancelled`
- Mock refund: create `payment_attempt` with negative amount (SIMULATED_REFUND)

**Done Criteria:**
- PENDING → CANCELLED; inventory restored; mock refund created
- SHIPPED cancellation → 422 (seller cannot cancel after shipping)

---

### ORDERS-021 — Mock delivery scheduler

**Estimate:** M (4h)  
**User Story:** US-P-15  
**Dependencies:** ORDERS-003  

**Implementation Notes:**
- File: `apps/workers/src/schedulers/delivery-mock.scheduler.ts`
- `@Interval(DELIVERY_MOCK_INTERVAL_MS)` — default 60s
- Query SHIPPED fulfillments where `eta <= now()`
- Transition SHIPPED → DELIVERED; write outbox `fulfillment.delivered`
- After each transition: check if all fulfillments for order are DELIVERED → write outbox `order.completed`

**Done Criteria:**
- SHIPPED fulfillment with `eta` in past → auto-delivered within 60s
- All fulfillments delivered → `order.completed` event written

---

### ORDERS-022 — Auto-refund monitor scheduler

**Estimate:** M (4h)  
**User Story:** US-P-16  
**Dependencies:** ORDERS-003  

**Implementation Notes:**
- File: `apps/workers/src/schedulers/auto-refund.scheduler.ts`
- `@Interval(AUTO_REFUND_INTERVAL_MS)` — default 3600s
- Query PENDING fulfillments where `seller.suspension_status = 'SUSPENDED'` AND `placed_at + fulfillment_window_days < now()`
- For each: restore inventory + PENDING→REFUNDED + write outbox `fulfillment.refund_suspended_seller`
- Notifications module sends buyer email (ET-13) and seller email (ET-13b)

**Done Criteria:**
- PENDING fulfillment past window for suspended seller → auto-refunded
- Inventory restored on auto-refund
- `fulfillment.refund_suspended_seller` event (distinct from manual refund event)
