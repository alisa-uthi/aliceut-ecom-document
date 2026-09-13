# Epic: ORDERS — Orders & Fulfillment

**Epic ID:** ORDERS  
**Sprint(s):** 4–5  
**Total Tasks:** 22  

## Epic Goal

Complete order lifecycle: checkout (cart validation → inventory reservation → price snapshot → mock payment → order creation), fulfillment management per seller, delivery simulation, and auto-refund for suspended sellers. Order data is immutable after capture.

---

## Tasks

### ORDERS-001 — orders Schema Migrations

- **US Ref:** —
- **Estimate:** L
- **Dependencies:** PLATFORM-001, CATALOG-001, SELLER-001, INVENTORY-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes:**
- File: `libs/orders/src/infrastructure/migrations/0001_orders_schema.sql`
- Tables:
  - `orders.order`: id (UUIDv7), display_id (varchar unique, human-readable format: `ORD-YYYYMMDD-XXXX`), buyer_id FK, status (enum: `PROCESSING`|`PARTIALLY_SHIPPED`|`SHIPPED`|`DELIVERED`|`CANCELLED`|`REFUNDED`), total_amount NUMERIC(19,4), currency CHAR(3), shipping_snapshot JSONB, created_at
  - `orders.fulfillment`: id (UUIDv7), order_id FK, seller_id FK, status (enum: `PROCESSING`|`SHIPPED`|`DELIVERED`|`CANCELLED`|`REFUNDED`), shipping_carrier nullable, tracking_number nullable, shipped_at nullable, delivered_at nullable
  - `orders.fulfillment_item`: id (UUIDv7), fulfillment_id FK, offer_id FK, variant_id FK nullable, product_snapshot JSONB, qty INT, unit_price NUMERIC(19,4), currency CHAR(3), tax NUMERIC(19,4), fx_rate_used_at_capture NUMERIC(19,8), subtotal NUMERIC(19,4), reservation_id FK → inventory.stock_reservation
  - `orders.payment_attempt`: id (UUIDv7), order_id FK, status (`PENDING`|`SUCCEEDED`|`FAILED`), method (`MOCK`), amount NUMERIC(19,4), currency CHAR(3), gateway_ref varchar nullable, attempted_at
  - `orders.idempotency_key`: key varchar PK, order_id FK, created_at (used to prevent duplicate checkout requests)
- All amounts: NUMERIC(19,4); tax/FX rate: NUMERIC(19,8)
- Indexes: `order(buyer_id)`, `order(status)`, `fulfillment(order_id)`, `fulfillment(seller_id)`, `fulfillment_item(fulfillment_id)`, `idempotency_key(key)`

**Done Criteria:**
- All orders tables created; `order.display_id` unique constraint enforced

---

### ORDERS-002 — Order Entity + FulfillmentItem Entity

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** ORDERS-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- TypeORM entities for `orders.order`, `orders.fulfillment`, `orders.fulfillment_item`, `orders.payment_attempt`
- `FulfillmentItem.product_snapshot JSONB`: captures at checkout time: `{ productId, title, sku, variantLabel, imageUrl }`
- `FulfillmentItem.unit_price`, `currency`, `tax`, `fx_rate_used_at_capture`: immutable after creation (NFR: order immutability)
- No `@BeforeUpdate` that can change financial fields
- `Order.aggregateStatus()`: derived from fulfillments:
  - All DELIVERED → DELIVERED
  - All CANCELLED → CANCELLED
  - Any SHIPPED (and rest not CANCELLED) → PARTIALLY_SHIPPED or SHIPPED
  - Any PROCESSING → PROCESSING

**Done Criteria:**
- Unit test: `Order.aggregateStatus()` returns PARTIALLY_SHIPPED when one fulfillment SHIPPED, one PROCESSING

---

### ORDERS-003 — IdempotencyKey Entity + Checkout Idempotency

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** ORDERS-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `POST /orders/checkout` requires `Idempotency-Key` header (UUID, client-generated)
- Before processing: check `orders.idempotency_key` table:
  - If found → return existing `order_id` (200, not 201)
  - If not found → process checkout, insert key in same transaction as order creation
- Expiry: idempotency keys expire after 24h (scheduler cleans up or TTL-based)
- Client must use same key for retries (network timeout scenario)
- Error scenario: if checkout failed, idempotency_key row is NOT inserted (allow retry)

**Done Criteria:**
- POST checkout with same key twice: second call returns same order (no duplicate)
- Failed checkout: key not stored; retry with same key processes fresh

---

### ORDERS-004 — CheckoutService: Cart Validation + Seller Grouping

- **US Ref:** US-B-09
- **Estimate:** L
- **Dependencies:** CART-003, CATALOG-008, PRICING-004, INVENTORY-002
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- File: `libs/orders/src/application/checkout.service.ts`
- `CheckoutService.validateAndGroup(cartId, buyerId)`:
  1. Load all cart items with offers (join catalog.offer, catalog.product, pricing.offer_price)
  2. For each item:
     - `offer.status = ACTIVE` (skip stale; add to `skippedItems` list)
     - `available_qty >= item.quantity` (throw `InsufficientStockException` if not)
     - Resolve effective price via `EffectivePriceService.resolve()`
  3. Group valid items by `offer.seller_id` → one `Fulfillment` per seller
  4. Group fulfillments by currency (sellers can price in different currencies; V1 does not mix — each fulfillment is one currency)
  5. Return: `{ fulfillmentGroups: [{ sellerId, items: [...], subtotal }], skippedItems, totalAmount }`
- `skippedItems`: items with stale/inactive offers — excluded from checkout, returned in response for UI display

**Done Criteria:**
- Cart with stale item + 2 valid items → stale item in `skippedItems`; order created for 2 valid items only
- Cart with insufficient stock → 422 `INSUFFICIENT_STOCK` with item details
- Items from 2 sellers → 2 Fulfillment groups

---

### ORDERS-005 — CheckoutService: Atomic Reservation + Snapshot Transaction

- **US Ref:** US-B-09, FR-P-03
- **Estimate:** XL
- **Dependencies:** ORDERS-004, INVENTORY-003, SHARED-001, SHARED-005
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- Single atomic `dataSource.transaction(async (em) => { ... })`:
  1. For each valid cart item: `ReservationService.createReservation(offerId, qty, 900, em)` (15min window)
  2. Capture price snapshot per FulfillmentItem: `unit_price`, `currency`, `tax` (0 for V1), `fx_rate_used_at_capture` (from `platform.fx_rate` at this moment)
  3. Create `orders.order` row (status=`PROCESSING`)
  4. Create `orders.fulfillment` rows per seller group
  5. Create `orders.fulfillment_item` rows (immutable snapshot)
  6. Create `orders.idempotency_key` row
  7. Write `fulfillment.placed` outbox event per fulfillment group
- On any failure: entire transaction rolls back (reservations, order, fulfillments all un-created)
- `product_snapshot JSONB` captured here: `{ productId, title, imageUrl, variantLabel, sku }`
- `FulfillmentItem.unit_price` = result of `EffectivePriceService.resolve()` at THIS moment (immutable)

**Done Criteria:**
- Integration test: mock Kafka produce to fail → entire TX rolled back (no order, no reservations)
- Two buyers checkout same last item simultaneously: one succeeds, one gets InsufficientStockException (SELECT FOR UPDATE prevents race)
- `fulfillment_item.unit_price` is immutable: changing offer price does not affect historical items

---

### ORDERS-006 — Mock Payment (POST /orders/checkout internal flow)

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** ORDERS-005
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- V1: mock payment always succeeds (no real payment gateway)
- `MockPaymentService.charge(orderId, amount, currency): Promise<PaymentAttempt>`:
  - Create `orders.payment_attempt` row with `status = 'SUCCEEDED'`
  - Returns `{ status: 'SUCCEEDED', gatewayRef: 'MOCK-{uuid}' }`
- Called inside checkout transaction (step 8) after order creation but before commit
- Response from `POST /orders/checkout`: `{ orderId, displayId, status: 'PROCESSING', fulfillments: [...], paymentStatus: 'SUCCEEDED', skippedItems }`
- NOTE: When real payment gateway added in V2, this service swaps out — no other code changes

**Done Criteria:**
- Checkout completes with `paymentStatus: 'SUCCEEDED'`
- `orders.payment_attempt` row created with status SUCCEEDED
- `skippedItems` array present in response (empty if all items valid)

---

### ORDERS-007 — display_id Generation (ORD-YYYYMMDD-XXXX)

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** ORDERS-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Format: `ORD-YYYYMMDD-XXXX` where XXXX is zero-padded sequential number per day
- PostgreSQL sequence per day: `CREATE SEQUENCE orders.daily_seq_YYYYMMDD START 1` created lazily on first order of each day
- Alternatively (simpler): use Redis `INCR orders:seq:{YYYY-MM-DD}` with expiry 48h
- Redis approach preferred: `INCR orders:seq:2026-09-13` → pad to 4 digits → `ORD-20260913-0001`
- Collision safety: Redis INCR is atomic; no duplicate display_ids
- Insert generated `display_id` in same TX as order creation

**Done Criteria:**
- First order of the day: `ORD-YYYYMMDD-0001`
- Second order: `ORD-YYYYMMDD-0002`
- No duplicates under concurrent checkout (Redis INCR atomicity test)

---

### ORDERS-008 — POST /orders/checkout (controller + route)

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** ORDERS-005, ORDERS-006
- **Spec References:** `phase-1/technical-design/api-design/orders.md`

**Implementation Notes:**
- `POST /orders/checkout` — `@JwtAuthGuard`, `@Roles('BUYER'|'SELLER'|'ADMIN')` (any authenticated user can buy)
- Headers: `Idempotency-Key: <uuid>` (required; 400 if missing)
- DTO: `CheckoutDto { shippingAddressId: string }` — address must belong to authenticated user
- Controller delegates to: `CheckoutService.validateAndGroup → CheckoutService.executeTransaction → MockPaymentService`
- Clear cart after successful checkout (delete all `cart_item` rows for buyer's cart)
- Response 201: `CheckoutResponseDto { orderId, displayId, fulfillments, paymentStatus, totalAmount, currency, skippedItems }`

**Done Criteria:**
- Missing Idempotency-Key header → 400
- Invalid shipping address (not owned by buyer) → 404
- Successful checkout: cart cleared; order in DB; response has displayId

---

### ORDERS-009 — Order Aggregate Status Derivation

- **US Ref:** US-B-10
- **Estimate:** M
- **Dependencies:** ORDERS-002
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `OrderStatusService.deriveAndUpdate(orderId)`: loads all fulfillments for order; calls `Order.aggregateStatus()`; updates `orders.order.status` if changed
- Called after: any fulfillment status change (ship, cancel, deliver, refund)
- Status derivation rules (from ORDERS-002)
- Also updates `order.status = 'REFUNDED'` when all fulfillments are `REFUNDED`
- Publish `order.finalized` event when order reaches terminal state (DELIVERED or CANCELLED or REFUNDED)

**Done Criteria:**
- All fulfillments SHIPPED → order.status = SHIPPED
- One fulfillment SHIPPED, one PROCESSING → order.status = PARTIALLY_SHIPPED
- All DELIVERED → order.status = DELIVERED; `order.finalized` event published

---

### ORDERS-010 — GET /orders (buyer order history)

- **US Ref:** US-B-10
- **Estimate:** M
- **Dependencies:** ORDERS-002
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /orders` — `@JwtAuthGuard`; returns buyer's orders (paginated, cursor-based)
- Response: `PaginatedResponseDto<OrderSummaryDto>` where `OrderSummaryDto = { orderId, displayId, status, totalAmount, currency, createdAt, itemCount, firstItemTitle, firstItemImageUrl }`
- Default sort: `created_at DESC`
- Filter: `?status=PROCESSING|SHIPPED|DELIVERED|CANCELLED`
- Page size: 20

**Done Criteria:**
- Returns only authenticated buyer's orders (not other buyers')
- Filter by status works
- Cursor pagination returns next page correctly

---

### ORDERS-011 — GET /orders/:id (buyer order detail)

- **US Ref:** US-B-10
- **Estimate:** M
- **Dependencies:** ORDERS-002
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /orders/:id` — `@JwtAuthGuard`; ownership check: `order.buyer_id = authenticated user`
- Returns: full order with all fulfillments, fulfillment items (from snapshot), payment attempt, shipping info
- `FulfillmentItem.product_snapshot.imageUrl`: rendered from snapshot (not re-queried from product)
- Response includes: `{ order, fulfillments: [{ ...fulfillment, items: [...], sellerName }], paymentAttempt, shippingSnapshot }`

**Done Criteria:**
- Access another buyer's order → 404
- Response contains product_snapshot data (not live product data)

---

### ORDERS-012 — Seller Fulfillment: GET /seller/fulfillments

- **US Ref:** US-S-10
- **Estimate:** M
- **Dependencies:** ORDERS-002
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /seller/fulfillments` — `@JwtAuthGuard` + `@Roles('SELLER')`; returns seller's own fulfillments
- Filters: `?status=PROCESSING|SHIPPED|DELIVERED|CANCELLED&cursor=&limit=20`
- Response: paginated list of `FulfillmentSummaryDto { id, orderId, displayOrderId, buyerName, status, itemCount, subtotal, currency, createdAt }`
- No KYC guard (seller needs to see orders even if suspended)

**Done Criteria:**
- Seller sees only their own fulfillments (not other sellers')
- Filter by status returns correct subset

---

### ORDERS-013 — Seller Fulfillment: GET /seller/fulfillments/:id

- **US Ref:** US-S-10
- **Estimate:** S
- **Dependencies:** ORDERS-012
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `GET /seller/fulfillments/:id` — ownership check: `fulfillment.seller_id = authenticated seller`
- Returns: `{ ...fulfillment, items: [{ product_snapshot, qty, unit_price, currency }], buyerShippingAddress }`
- `buyerShippingAddress` from order's `shipping_snapshot` (captured at checkout)

**Done Criteria:**
- Access another seller's fulfillment → 404

---

### ORDERS-014 — POST /seller/fulfillments/:id/ship

- **US Ref:** US-S-10
- **Estimate:** M
- **Dependencies:** ORDERS-013, ORDERS-009
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /seller/fulfillments/:id/ship { carrier, trackingNumber }` — ownership check
- Allowed only when fulfillment `status = 'PROCESSING'`
- Update: `status = 'SHIPPED'`, set `shipping_carrier`, `tracking_number`, `shipped_at = now()`
- Call `OrderStatusService.deriveAndUpdate(orderId)`
- Publish `fulfillment.shipped` outbox event: `{ fulfillmentId, orderId, buyerId, carrier, trackingNumber, shippedAt }`

**Done Criteria:**
- Ship PROCESSING fulfillment → status = SHIPPED; `fulfillment.shipped` event in Kafka
- Ship already SHIPPED → 422 invalid transition

---

### ORDERS-015 — POST /seller/fulfillments/:id/cancel

- **US Ref:** US-S-10
- **Estimate:** M
- **Dependencies:** ORDERS-013, ORDERS-009, INVENTORY-003
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /seller/fulfillments/:id/cancel { reason: string }` — ownership check
- Allowed only when `status = 'PROCESSING'`
- Update: `status = 'CANCELLED'`
- Release inventory reservations: `ReservationService.releaseReservation()` for each item's `reservation_id`
- Call `OrderStatusService.deriveAndUpdate(orderId)`
- Publish `fulfillment.cancelled` outbox event

**Done Criteria:**
- Cancel PROCESSING fulfillment: status = CANCELLED; inventory released; order status updated

---

### ORDERS-016 — POST /seller/fulfillments/:id/refund (mock)

- **US Ref:** US-S-10, US-A-07
- **Estimate:** M
- **Dependencies:** ORDERS-013, ORDERS-009
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /seller/fulfillments/:id/refund { reason: string }` — ownership check
- Allowed when `status = 'SHIPPED'` (after ship, before delivery) or `status = 'DELIVERED'`
- V1: mock refund always succeeds (create payment_attempt row with `status = 'SUCCEEDED'`, `method = 'MOCK_REFUND'`)
- Update fulfillment `status = 'REFUNDED'`
- Call `OrderStatusService.deriveAndUpdate(orderId)`
- Publish `fulfillment.cancelled` event (same topic; consumers handle refund case)

**Done Criteria:**
- Refund SHIPPED fulfillment: status = REFUNDED; mock refund payment attempt created
- Refund PROCESSING fulfillment: 422 (use cancel instead)

---

### ORDERS-017 — Mock Delivery Scheduler (auto-deliver after 3 days)

- **US Ref:** US-B-10
- **Estimate:** M
- **Dependencies:** ORDERS-014
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- File: `apps/workers/src/schedulers/mock-delivery.scheduler.ts`
- Cron: every 10 minutes
- Query: `SELECT * FROM orders.fulfillment WHERE status = 'SHIPPED' AND shipped_at < now() - interval '3 days' LIMIT 50 FOR UPDATE SKIP LOCKED`
- For each: set `status = 'DELIVERED'`, `delivered_at = now()`
- Call `OrderStatusService.deriveAndUpdate(orderId)`
- Publish `fulfillment.delivered` outbox event

**Done Criteria:**
- Fulfillment shipped 3+ days ago: auto-delivered within 10min of cron run
- `fulfillment.delivered` event published; order.status updated

---

### ORDERS-018 — Auto-Refund on Seller Suspension

- **US Ref:** US-A-07
- **Estimate:** M
- **Dependencies:** ORDERS-016, PLATFORM-003
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- Consumer group: `orders.seller-suspended-refund`
- Topic: `seller.suspended`
- `handle(event)`:
  - Find all PROCESSING fulfillments for `event.payload.sellerId`
  - For each: auto-refund (same logic as ORDERS-016) + release reservations
  - Publish `fulfillment.refund_suspended_seller` event (special event type for notification)
- V1: mock refund always succeeds
- Does NOT auto-refund SHIPPED fulfillments (goods already en route)

**Done Criteria:**
- Seller suspended: all their PROCESSING fulfillments cancelled + refunded
- SHIPPED fulfillments: unaffected (buyer keeps tracking info)

---

### ORDERS-019 — Fulfillment Events Outbox

- **US Ref:** FR-P-09
- **Estimate:** M
- **Dependencies:** SHARED-005, ORDERS-014
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Register Avro schemas for: `fulfillment.placed`, `fulfillment.shipped`, `fulfillment.delivered`, `fulfillment.cancelled`, `fulfillment.refund_suspended_seller`, `order.finalized`
- `fulfillment.placed` payload: `{ fulfillmentId, orderId, sellerId, buyerId, items: [{ offerId, reservationId, qty, unitPrice, currency }] }`
- `fulfillment.shipped` payload: `{ fulfillmentId, orderId, buyerId, carrier, trackingNumber, shippedAt }`
- `fulfillment.cancelled` payload: `{ fulfillmentId, orderId, buyerId, sellerId, reason, cancelledAt }`
- `fulfillment.delivered` payload: `{ fulfillmentId, orderId, buyerId, deliveredAt }`
- `order.finalized` payload: `{ orderId, buyerId, status, totalAmount, currency, finalizedAt }`

**Done Criteria:**
- All 6 schemas registered in Schema Registry
- Each event appears in Kafka UI within 2s of action

---

### ORDERS-020 — Activity Log (MongoDB)

- **US Ref:** US-B-10, US-S-10
- **Estimate:** M
- **Dependencies:** PLATFORM-004, ORDERS-014
- **Spec References:** `phase-1/technical-design/data-model-mongodb.md`, `phase-1/technical-design/api-design/orders.md`

**Implementation Notes:**
- On each order state transition: call `AuditLogService.log()` (PLATFORM-004)
- Events logged: checkout created, fulfillment shipped, fulfillment delivered, fulfillment cancelled, refund issued
- `targetType: 'Order'`, `targetId: orderId`, `actorId: userId` (seller or system for auto-events)
- `GET /orders/:id/activity` — returns audit log for a single order (BUYER ownership check); queries MongoDB `audit_logs` by `targetType=Order, targetId=orderId`

**Done Criteria:**
- Ship fulfillment → audit log entry in MongoDB
- GET /orders/:id/activity returns timeline of status changes

---

### ORDERS-021 — GET /seller/fulfillments/:id/activity

- **US Ref:** US-S-10
- **Estimate:** S
- **Dependencies:** ORDERS-020
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes:**
- `GET /seller/fulfillments/:id/activity` — seller view of audit log for a fulfillment
- Ownership check: fulfillment.seller_id = seller
- Queries MongoDB by `targetId = fulfillmentId`
- Returns same structure as buyer activity log but scoped to fulfillment

**Done Criteria:**
- Seller sees only their fulfillment activity
- Access another seller's fulfillment → 404

---

### ORDERS-022 — Kafka Consumer: order events for notifications

- **US Ref:** FR-P-09
- **Estimate:** M
- **Dependencies:** PLATFORM-003, ORDERS-019
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/orders.md`

**Implementation Notes:**
- This task covers the ORDERS side of the notification chain — publishing events correctly
- Notifications module (NOTIFICATIONS-006) handles the consumer side
- Verify: after `fulfillment.placed` published → INVENTORY-010 consumer confirms reservation
- Verify: after `fulfillment.shipped` published → buyer notification sent (NOTIFICATIONS-006)
- Integration test: end-to-end checkout → fulfillment placed event → inventory confirmed → notification sent

**Done Criteria:**
- E2E: checkout → `fulfillment.placed` in Kafka → inventory confirmed within 2s
- `fulfillment.shipped` event → buyer email notification sent (verify NOTIFICATIONS consumer)
