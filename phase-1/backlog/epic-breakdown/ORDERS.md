# Epic: ORDERS — Orders & Fulfillment

**Epic ID:** ORDERS  
**Sprint(s):** 13–14 (directional)  
**Total Tasks:** 23  

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
- Tables: `orders.order`, `orders.fulfillment`, `orders.fulfillment_item`, `orders.payment_attempt`, `orders.idempotency_key`
- Columns, types, enums, and FKs: exactly per `data-model-erd.md` §5 (orders schema) — do not re-derive here. Notably: `orders.order` has **no stored `status` column** (status is derived at read time, see ORDERS-002/ORDERS-009); `orders.fulfillment` includes `display_id`, `tracking_number`, `estimated_delivery_at` (all generated at insert — see ORDERS-005/ORDERS-007), plus `seller_name_snapshot`, `shipping_method`, `shipping_cost`, `tax_total`, `total_amount`; `orders.payment_attempt.status` uses the `payment_status` enum (`SIMULATED_SUCCESS`|`SIMULATED_FAILURE`) and is keyed by `fulfillment_id`, not `order_id`
- All amounts: NUMERIC(19,4); tax/FX rate: NUMERIC(19,8)
- Indexes: per data-model-erd.md §5

**Done Criteria:**
- All orders tables created exactly per data-model-erd.md §5; `order.display_id` and `fulfillment.display_id` unique constraints enforced

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
- `Order.aggregateStatus()`: derivation rules per `data-model-erd.md` §5 (derived order-status table) — do not re-derive here; this is what "order status" resolves to, since `orders.order` has no stored status column

**Done Criteria:**
- Unit test: `Order.aggregateStatus()` matches data-model-erd.md §5 exactly for each representative fulfillment mix

---

### ORDERS-003 — IdempotencyKey Entity + Checkout Idempotency

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** ORDERS-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `POST /orders` requires `Idempotency-Key` header (UUID, client-generated)
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
  3. Create `orders.order` row (no status column — see ORDERS-001)
  4. Create `orders.fulfillment` rows per seller group — generate `display_id`, `tracking_number`, and `estimated_delivery_at` at insert time (scheme per ORDERS-007 / data-model-erd.md §5); fulfillment starts in `PENDING`
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
- `fulfillment.tracking_number` and `estimated_delivery_at` are set here at creation and never regenerated later (see ORDERS-014)

---

### ORDERS-006 — Mock Payment (POST /orders internal flow)

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** ORDERS-005
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- V1: mock payment always succeeds (no real payment gateway)
- `MockPaymentService.charge(fulfillmentId, amount, currency, paymentMethod, paymentDetail): Promise<PaymentAttempt>`:
  - Create `orders.payment_attempt` row scoped to the fulfillment (per data-model-erd.md §5, `payment_attempt.fulfillment_id`, not `order_id`) with `status = 'SIMULATED_SUCCESS'` (`payment_status` enum)
  - `method` stores the buyer-supplied `paymentMethod` (`FAKE_CARD`) per api-design/orders.md
- Called inside the checkout transaction, one payment_attempt per fulfillment, after fulfillment creation but before commit
- Response contract owned by ORDERS-008 (`POST /orders`) — do not restate here
- NOTE: When real payment gateway added in V2, this service swaps out — no other code changes

**Done Criteria:**
- Checkout completes with each fulfillment's `payment_attempt.status = SIMULATED_SUCCESS`
- `orders.payment_attempt.fulfillment_id` set correctly (one row per fulfillment, not per order)

---

### ORDERS-007 — ID Generation (display_id, tracking_number)

- **US Ref:** US-B-09
- **Estimate:** S
- **Dependencies:** ORDERS-001
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Exact scheme (hex substring of the row's own UUID, generated at insert, no external counter): per `data-model-erd.md` §5 — do not re-derive here. Applies to `orders.order.display_id` (`ORD-` prefix), `orders.fulfillment.display_id` (`FUL-` prefix), `orders.fulfillment.tracking_number` (`TRK-` prefix)
- No Postgres sequence, no Redis `INCR` — generation is a pure function of the row's own id, so there is no shared-counter contention across concurrent checkouts
- Generated in the same transaction as the row insert (ORDERS-005)

**Done Criteria:**
- Every `orders.order` / `orders.fulfillment` row has a unique `display_id` matching the format in data-model-erd.md §5
- Every `orders.fulfillment` row has a unique `tracking_number` matching that format, set at creation (`PENDING`)
- Concurrent checkouts never produce duplicate ids (uniqueness follows from UUID uniqueness, not a shared counter)

---

### ORDERS-008 — POST /orders (controller + route)

- **US Ref:** US-B-09
- **Estimate:** M
- **Dependencies:** ORDERS-005, ORDERS-006
- **Spec References:** `phase-1/technical-design/api-design/orders.md`

**Implementation Notes:**
- `POST /orders` — `@JwtAuthGuard`, `@Roles('BUYER')` + `EMAIL_VERIFIED` guard
- Headers: `Idempotency-Key: <uuid>` (required; 400 if missing)
- Request DTO, response shape (`placementOutcome`, `orders[]`, `failedGroups[]`), and error cases (400 invalid body, 409 idempotency key reused with a different body, 409 `PRICE_CHANGED`, 422 no purchasable items remain): per `api-design/orders.md` exactly — do not re-derive here
- Controller delegates to: `CheckoutService.validateAndGroup → CheckoutService.executeTransaction → MockPaymentService`
- Clear cart after successful checkout (delete all `cart_item` rows for buyer's cart); response is returned after COMMIT, before any Kafka/email/ES/Mongo side effects

**Done Criteria:**
- Missing Idempotency-Key header → 400
- Idempotency-Key reused with a different request body → 409
- Successful checkout: cart cleared; response matches api-design/orders.md exactly (each element of `orders[]` is a fulfillment, `displayId` prefixed `FUL-`)

---

### ORDERS-009 — Order Aggregate Status Derivation

- **US Ref:** US-B-10
- **Estimate:** M
- **Dependencies:** ORDERS-002
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `OrderStatusService.deriveAndUpdate(orderId)`: loads all fulfillments for the order; calls `Order.aggregateStatus()` (ORDERS-002) to compute the derived status — **not persisted**, `orders.order` has no stored `status` column; this call checks for terminal-state transitions that trigger downstream events
- Called after: any fulfillment status change (ship, cancel, deliver, refund)
- Status derivation rules: per data-model-erd.md §5 (see ORDERS-002)
- Publish `order.finalized` event when the derived status reaches a terminal state (DELIVERED, CANCELLED, REFUNDED)

**Done Criteria:**
- Derived status for a representative fulfillment mix matches data-model-erd.md §5 exactly
- All fulfillments DELIVERED → derived status COMPLETED; `order.finalized` event published
- No write to an `orders.order.status` column anywhere (column does not exist)

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
- Filter: `?status=<derived order status>` — accepted values per data-model-erd.md §5 derived-status table
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
- Filters: `?status=PENDING|SHIPPED|DELIVERED|CANCELLED&cursor=&limit=20`
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
- `POST /seller/fulfillments/:id/ship { shippingMethod }` — ownership check
- Allowed only when fulfillment `status = 'PENDING'`
- Update: `status = 'SHIPPED'`, set `shipping_method`, `shipped_at = now()` — `tracking_number` and `estimated_delivery_at` are NOT set here; both were already generated at fulfillment creation (ORDERS-005/ORDERS-007) and are immutable
- Call `OrderStatusService.deriveAndUpdate(orderId)`
- Publish `fulfillment.shipped` outbox event: `{ fulfillmentId, orderId, buyerId, shippingMethod, trackingNumber, shippedAt }` (`trackingNumber` read from the existing row, not generated here)

**Done Criteria:**
- Ship PENDING fulfillment → status = SHIPPED; `fulfillment.shipped` event in Kafka
- Ship already SHIPPED → 422 invalid transition

---

### ORDERS-015 — POST /seller/fulfillments/:id/cancel

- **US Ref:** US-S-10
- **Estimate:** M
- **Dependencies:** ORDERS-013, ORDERS-009, INVENTORY-003
- **Spec References:** `phase-1/technical-design/api-design/orders.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- `POST /seller/fulfillments/:id/cancel { reason: string }` — ownership check
- Allowed only when `status = 'PENDING'`
- Update: `status = 'CANCELLED'`
- Release inventory reservations: `ReservationService.releaseReservation()` for each item's `reservation_id`
- Call `OrderStatusService.deriveAndUpdate(orderId)`
- Publish `fulfillment.cancelled` outbox event

**Done Criteria:**
- Cancel PENDING fulfillment: status = CANCELLED; inventory released; order status updated

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
- Publish `fulfillment.refunded` event (dedicated topic/schema, kafka-events.md §1.7 — distinct from `fulfillment.cancelled`)

**Done Criteria:**
- Refund SHIPPED fulfillment: status = REFUNDED; mock refund payment attempt created
- Refund PENDING fulfillment: 422 (use cancel instead)

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
- For each: publish `fulfillment.delivered` outbox event — this scheduler does **not** write `status = 'DELIVERED'` itself; that DB update is owned by the `orders.delivery-tracker` consumer (ORDERS-023) that consumes this event, per kafka-events.md §1.6
- `FOR UPDATE SKIP LOCKED` still applies so a fulfillment isn't re-selected on the next cron tick before its event is consumed

**Done Criteria:**
- Fulfillment shipped 3+ days ago: `fulfillment.delivered` published within 10min of cron run
- `orders.fulfillment.status` becomes `DELIVERED` only after ORDERS-023's consumer processes the event, not written by this scheduler

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
  - Find all PENDING fulfillments for `event.payload.sellerId`
  - For each: auto-refund (same logic as ORDERS-016) + release reservations
  - Publish `fulfillment.refund_suspended_seller` event (special event type for notification)
- V1: mock refund always succeeds
- Does NOT auto-refund SHIPPED fulfillments (goods already en route)

**Done Criteria:**
- Seller suspended: all their PENDING fulfillments cancelled + refunded
- SHIPPED fulfillments: unaffected (buyer keeps tracking info)

---

### ORDERS-019 — Fulfillment Events Outbox

- **US Ref:** FR-P-09
- **Estimate:** M
- **Dependencies:** SHARED-005, ORDERS-014
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Register Avro schemas for: `fulfillment.placed`, `fulfillment.shipped`, `fulfillment.delivered`, `fulfillment.cancelled`, `fulfillment.refunded`, `fulfillment.refund_suspended_seller`, `order.finalized`, `order.completed`
- Payload shapes: per `kafka-events.md` (relevant §1.x per event) — do not re-derive here; each payload must match its registered schema exactly (drift breaks BACKWARD compat)

**Done Criteria:**
- All 8 schemas registered in Schema Registry, matching kafka-events.md exactly
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

---

### ORDERS-023 — orders.delivery-tracker Consumer (order.completed)

- **US Ref:** US-B-10
- **Estimate:** M
- **Dependencies:** ORDERS-017, SHARED-005
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Consumer group: `orders.delivery-tracker` — consumes `fulfillment.delivered` (published by ORDERS-017's mock delivery scheduler)
- `handle(event)`:
  1. Update `orders.fulfillment.status = 'DELIVERED'` for `event.payload.fulfillmentId` — this consumer owns the DB write for delivery (ORDERS-017 only publishes the event; per kafka-events.md §1.6)
  2. `SELECT COUNT(*) FROM orders.fulfillment WHERE order_id = ? AND status != 'DELIVERED'`
  3. If count = 0 AND total fulfillments for the order ≥ 2: publish `order.completed` via outbox (kafka-events.md §1.9)
- Idempotent on `event_id` (per SHARED-005 outbox/consumer conventions)
- Single-fulfillment orders reaching DELIVERED do not emit `order.completed` — that case is covered by `order.finalized` (ORDERS-009)

**Done Criteria:**
- `fulfillment.delivered` consumed → `orders.fulfillment.status` updated to `DELIVERED` (write happens here, not in the scheduler)
- Multi-seller order, all fulfillments DELIVERED → `order.completed` published exactly once
- Multi-seller order, one fulfillment still SHIPPED → `order.completed` NOT published
- Single-fulfillment order DELIVERED → no `order.completed` (only `order.finalized`)
