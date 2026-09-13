# EPIC: INVENTORY — Inventory Module

**Sprint:** 3–4
**Lib:** `libs/inventory/`
**Module:** `InventoryModule`
**Controllers:** `InventoryController` (via Seller module)
**Kafka producers:** `inventory.changed`, `inventory.low_stock`, `inventory.reservation_expired`
**Kafka consumers:** `fulfillment.placed` (group: `inventory.fulfillment-placed`), `fulfillment.cancelled` (group: `inventory.fulfillment-cancelled`)

Overview: Manages per-offer stock levels, checkout reservations, and the reservation lifecycle. Critical path for checkout correctness. Optimistic locking (version column) prevents overselling. The zero-stock deactivation rule integrates with the search module via events.

---

### INVENTORY-001 — inventory Schema Migrations
**US Ref:** —
**Estimate:** M
**Dependencies:** PLATFORM-001
**Implementation Notes:**
- File: `libs/inventory/src/infrastructure/migrations/0001_inventory_schema.sql`
- Tables: `inventory.stock`, `inventory.stock_reservation`
- `inventory.stock` PK is `offer_id` (FK → catalog.offer(id)) — one row per offer; created when offer is created
- `inventory.stock.version BIGINT DEFAULT 0` — optimistic lock; incremented on every update
- `inventory.stock_reservation.status` uses `reservation_status` enum (from PLATFORM-001)
- FK: `stock.offer_id → catalog.offer(id)`, `reservation.offer_id → inventory.stock(offer_id)`, `reservation.order_id → orders.order(id)` (cross-schema; applied after orders schema)
- Index: `stock_reservation(offer_id, status)`, `stock_reservation(order_id)`, `stock_reservation(expires_at)` where status='ACTIVE'

**Done Criteria:**
- Tables created; `SELECT on_hand_qty, reserved_qty, (on_hand_qty - reserved_qty) AS available FROM inventory.stock` works

---

### INVENTORY-002 — Stock Entity + Repository Interface
**US Ref:** US-S-08
**Estimate:** M
**Dependencies:** INVENTORY-001
**Implementation Notes:**
- TypeORM entity for `inventory.stock`
- `StockRepository` interface: `findByOffer(offerId)`, `findByOfferForUpdate(offerId)` (SELECT FOR UPDATE), `save(stock)`, `incrementVersion(offerId, expectedVersion)`
- `Stock.availableQty(): number` — `on_hand_qty - reserved_qty`; always ≥ 0
- Optimistic lock: `incrementVersion` does `UPDATE SET version = version+1 WHERE offer_id = ? AND version = ?`; returns 0 rows updated on version mismatch → throw `OptimisticLockException`
- `StockService.adjustOnHand(offerId, qty, reason)`: update `on_hand_qty`; check low-stock threshold; publish `inventory.changed` + conditionally `inventory.low_stock` events

**Done Criteria:**
- Optimistic lock test: concurrent updates with same version → one succeeds, one throws

---

### INVENTORY-003 — StockReservation Entity + Repository Interface
**US Ref:** US-B-09
**Estimate:** M
**Dependencies:** INVENTORY-001
**Implementation Notes:**
- TypeORM entity for `inventory.stock_reservation`
- `StockReservationRepository`: `findActiveByOffer(offerId)`, `findByOrder(orderId)`, `save(reservation)`, `updateStatus(id, status)`
- Reservation TTL: `expires_at = now() + RESERVATION_TTL_MINUTES` (default 15 min from env)
- `reservation_status` enum: `ACTIVE`, `CONSUMED`, `RELEASED`, `EXPIRED`

**Done Criteria:**
- Can create reservation; `findActiveByOffer` excludes CONSUMED/RELEASED/EXPIRED rows

---

### INVENTORY-004 — InventoryController (Seller)
**US Ref:** US-S-08
**Estimate:** M
**Dependencies:** INVENTORY-002, SELLER-008
**Implementation Notes:**
- `GET /seller/inventory` — returns table: `[{ offerId, productTitle, sku, onHandQty, reservedQty, availableQty, lowStockThreshold }]`; paginated
- `PUT /seller/inventory/:offerId` — update `on_hand_qty` (manual adjust); DTO: `UpdateStockDto { onHandQty: number (≥0), adjustmentReason: string }`; reason logged to audit; fires `inventory.changed` event
- `PUT /seller/inventory/:offerId/threshold` — update `low_stock_threshold`; DTO: `UpdateThresholdDto { threshold: number (≥1) }`
- Ownership: seller can only view/update offers they own; 404 on not-owned

**Done Criteria:**
- Seller can update on_hand_qty with reason; `inventory.changed` event appears in outbox
- Non-owned offer → 404

---

### INVENTORY-005 — Low-Stock Edge-Trigger Detection
**US Ref:** US-S-08
**Estimate:** M
**Dependencies:** INVENTORY-002
**Implementation Notes:**
- Low-stock alert is edge-triggered: fires only when `available_qty` crosses from `≥ threshold` to `< threshold`
- Implementation in `StockService.adjustOnHand()` and `StockService.consumeReservation()`:
  1. Compute `old_available = old_on_hand - old_reserved`
  2. Compute `new_available = new_on_hand - new_reserved`
  3. If `old_available >= threshold AND new_available < threshold` → publish `inventory.low_stock` outbox event
  4. If `new_available >= threshold` → low_stock re-armed (no event on re-arm; just reset state)
- State tracking: implicit from DB values (no separate `alert_armed` flag needed)
- `inventory.low_stock` payload: `{ offer_id, seller_id, product_title, available_qty, threshold, as_of }`

**Done Criteria:**
- Decrement stock from 6→4 with threshold=5: `inventory.low_stock` event fires
- Decrement from 4→3 (already below threshold): no second event fires
- Increment from 4→6 then decrement to 4: event fires again (re-armed)

---

### INVENTORY-006 — CSV Bulk Import
**US Ref:** US-S-09
**Estimate:** L
**Dependencies:** INVENTORY-002
**Implementation Notes:**
- `POST /seller/inventory/bulk-import/preview` — multipart CSV upload; parse, validate, compute diff; return `{ rows: [{ sku, offerId, currentQty, newQty, threshold, status: 'ok'|'error'|'warning', message }] }`
- `POST /seller/inventory/bulk-import/confirm` — apply changes from a previously submitted preview session (session stored in Redis with TTL 10 min)
- CSV format: `sku,on_hand,low_stock_threshold` (threshold optional)
- Validation: CSV ≤5MB, ≤10,000 rows; malformed CSV → 400 with downloadable error report
- Row validation:
  - SKU not owned by seller → error "SKU not found or not yours"
  - Deleted/inactive variant → warning (excluded)
  - `new_on_hand - reserved_qty < 0` → warning (requires explicit confirmation)
- Apply: wrap all updates in one transaction; fire `inventory.changed` per offer updated

**Done Criteria:**
- CSV with invalid SKU shows error row; can still confirm remaining valid rows
- Preview returns diff: before → after quantities
- Confirmation applies all valid rows atomically

---

### INVENTORY-007 — Reservation Creation + Release Service
**US Ref:** US-B-09
**Estimate:** M
**Dependencies:** INVENTORY-003
**Implementation Notes:**
- `ReservationService.reserve(offerId, orderId, qty, entityManager)`: atomic operation:
  1. `SELECT ... FROM inventory.stock WHERE offer_id = ? FOR UPDATE` (pessimistic lock for checkout)
  2. Check `available_qty >= qty`; if not throw `InsufficientStockException`
  3. `UPDATE inventory.stock SET reserved_qty = reserved_qty + qty, version = version + 1`
  4. `INSERT INTO inventory.stock_reservation(offer_id, order_id, qty, status='ACTIVE', expires_at)`
  5. Publish `inventory.changed` outbox event (in same transaction)
- `ReservationService.release(reservationId, reason: 'EXPIRED'|'REFUNDED'|'CANCELLED')`:
  1. `UPDATE reservation SET status = RELEASED/EXPIRED`
  2. `UPDATE stock SET reserved_qty = reserved_qty - qty`
  3. Publish `inventory.changed` outbox event
- Both operations require `EntityManager` passed from calling service (participate in caller's transaction)

**Done Criteria:**
- Concurrent reserve of last unit: one succeeds, one gets InsufficientStockException
- Release restores reserved_qty correctly

---

### INVENTORY-008 — Reservation Expiry Scheduler
**US Ref:** US-P-17
**Estimate:** M
**Dependencies:** INVENTORY-007
**Implementation Notes:**
- File: `apps/workers/src/schedulers/reservation-expiry.scheduler.ts`
- `@Interval(RESERVATION_EXPIRY_INTERVAL_MS)` (default 60s; configurable)
- Query: `SELECT * FROM inventory.stock_reservation WHERE status = 'ACTIVE' AND expires_at < now() FOR UPDATE SKIP LOCKED`
- For each expired reservation: call `ReservationService.release(id, 'EXPIRED')` in a transaction
- Idempotent: re-running against already-RELEASED/EXPIRED reservations is a no-op
- Publish `inventory.reservation_expired` outbox event per released reservation
- Concurrency safety: `FOR UPDATE SKIP LOCKED` prevents double-release races

**Done Criteria:**
- Expired ACTIVE reservation transitions to EXPIRED; `reserved_qty` on stock decremented
- `inventory.reservation_expired` event in outbox
- Re-running against already-EXPIRED reservation: no error, no duplicate event

---

### INVENTORY-009 — Zero-Stock Deactivation
**US Ref:** US-S-03
**Estimate:** M
**Dependencies:** INVENTORY-002, CATALOG-012
**Implementation Notes:**
- When `available_qty` transitions to 0: publish `inventory.changed` event with `is_available: false`
- When `available_qty` rises above 0: publish `inventory.changed` event with `is_available: true`
- The `inventory.changed` event is consumed by Search module (SEARCH-007) which updates the `is_available` field on the ES product document
- No offer status change needed — visibility is purely based on ES index; the offer remains ACTIVE in the DB
- Zero-stock rule applies: listing is "hidden" from search results but still accessible via direct URL (GET /products/:id still returns the product with OOS badge)

**Done Criteria:**
- When all variants of a product reach zero available stock, `is_available: false` in `inventory.changed` event
- Search results exclude the product when `is_available = false` (tested via Search integration)

---

### INVENTORY-010 — Outbox Events: inventory.*
**US Ref:** US-P-10
**Estimate:** M
**Dependencies:** PLATFORM-004
**Implementation Notes:**
- Register Avro schemas:
  - `inventory.changed` (v1): `{ offer_id, seller_id, on_hand_qty, reserved_qty, available_qty, is_available, changed_at }`
  - `inventory.low_stock` (v1): `{ offer_id, seller_id, product_title, available_qty, threshold, as_of }`
  - `inventory.reservation_expired` (v1): `{ reservation_id, offer_id, order_id, released_qty, released_at }`
- All events published inside domain transactions (same PG TX as inventory update)
- Partition key for all: `offer_id` (ensures per-offer ordering)

**Done Criteria:**
- All 3 schemas registered in Schema Registry
- Events published transactionally (roll back TX → no event in outbox)

---

### INVENTORY-011 — Kafka Consumers: fulfillment.placed + fulfillment.cancelled
**US Ref:** US-B-09
**Estimate:** M
**Dependencies:** PLATFORM-007, INVENTORY-007
**Implementation Notes:**
- Consumer group: `inventory.fulfillment-placed`
- Payload: `{ order_id, fulfillment_id, seller_id, items: [{ offer_id, quantity }] }`
- Side effect: for each item, call `StockService.consumeReservation(orderId, offerId)` — transitions reservation from ACTIVE→CONSUMED, decrements `on_hand_qty` by quantity (goods officially committed to order)
- Idempotent: `@IdempotentConsumer('inventory.fulfillment-placed')`
- Note: the reservation was created during checkout (ORDERS-009); this consumer finalizes it
- Consumer group `inventory.fulfillment-cancelled`: on `fulfillment.cancelled` — release reservation (restore stock)

**Done Criteria:**
- `fulfillment.placed` event → reservation ACTIVE→CONSUMED; `on_hand_qty` decremented
- `fulfillment.cancelled` event → stock restored (reservation ACTIVE→RELEASED)
- Replaying same event: idempotent; no double-decrement
