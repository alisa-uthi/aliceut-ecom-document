# EPIC: INVENTORY — Inventory Module

**Sprint:** 3  
**Lib:** `libs/inventory/`  
**Module:** `InventoryModule`  
**Controllers:** `InventoryController`  
**Kafka producers:** `inventory.changed`, `inventory.low_stock`, `inventory.reservation_expired`  
**Kafka consumers:** `fulfillment.placed`, `fulfillment.cancelled`  

Overview: Manages per-offer stock levels, reservations during checkout, and low-stock edge-trigger alerts. Reservations are soft-held during the 15-min checkout window; confirmed on fulfillment.placed or released on timeout/cancellation.

---

### INVENTORY-001 — inventory Schema Migrations

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- File: `libs/inventory/src/infrastructure/migrations/0001_inventory_schema.sql`
- Tables:
  - `inventory.stock`: id, offer_id FK (unique — one stock row per offer), available_qty INT (≥0 check constraint), reserved_qty INT DEFAULT 0, reorder_threshold INT nullable, updated_at
  - `inventory.stock_reservation`: id (UUIDv7 PK), offer_id FK, order_id nullable (set after checkout confirms), reserved_qty INT, status (`PENDING`|`CONFIRMED`|`RELEASED`|`EXPIRED`), expires_at TIMESTAMPTZ, created_at, released_at nullable
- Unique: `stock(offer_id)` (one stock row per offer)
- Check: `stock.available_qty >= 0` (prevent oversell at DB level)
- Index: `stock(offer_id)`, `stock_reservation(offer_id, status)`, `stock_reservation(expires_at) WHERE status = 'PENDING'`

**Done Criteria:**
- `INSERT INTO inventory.stock (available_qty = -1)` → fails check constraint
- Tables created; reservation FK to offer

---

### INVENTORY-002 — Stock Entity + InventoryService (read)

- **US Ref:** US-S-06
- **Estimate:** M
- **Dependencies:** INVENTORY-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/api-design/catalog.md`

**Implementation Notes:**
- TypeORM entity for `inventory.stock`
- `InventoryService.getAvailableQty(offerId): Promise<number>`:
  - Returns `available_qty - reserved_qty` (effective available)
  - Used by CartService (CART-004, CART-005) for availability checks
- `StockRepository`: `findByOfferId(offerId)`, `lockForUpdate(offerId, em)` (SELECT FOR UPDATE via TypeORM query runner)
- `InventoryController` (`/seller/inventory`): `@JwtAuthGuard` + `@Roles('SELLER')` + `SellerKycGuard`

**Done Criteria:**
- `getAvailableQty(offerId)` returns correct value (available - reserved)
- Returns 0 if no stock row exists

---

### INVENTORY-003 — StockReservation Entity + ReservationService

- **US Ref:** FR-P-07
- **Estimate:** L
- **Dependencies:** INVENTORY-001, SHARED-002
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- TypeORM entity for `inventory.stock_reservation`
- `ReservationService.createReservation(offerId, qty, expiresIn: 900s): Promise<StockReservation>`:
  - Within a transaction (SELECT FOR UPDATE on `inventory.stock`):
    1. Check `available_qty - reserved_qty >= qty`; throw `InsufficientStockException` if not
    2. Increment `stock.reserved_qty += qty`
    3. Insert `stock_reservation` row (status=`PENDING`, expires_at=`now() + expiresIn`)
  - Called by CheckoutService (ORDERS-004) — passes the outer transaction's EntityManager
- `ReservationService.confirmReservation(reservationId, orderId, em)` — set status=`CONFIRMED`, link `order_id`; decrement `available_qty`
- `ReservationService.releaseReservation(reservationId, em)` — set status=`RELEASED`; decrement `reserved_qty` back

**Done Criteria:**
- Reserve 5 items when only 3 available → throws InsufficientStockException
- Confirm reservation: `available_qty` decremented, `reserved_qty` decremented
- Release reservation: `reserved_qty` decremented only (available unchanged)
- Concurrent reservations for same offer: SELECT FOR UPDATE prevents race (test with 2 simultaneous requests)

---

### INVENTORY-004 — InventoryController (seller endpoints)

- **US Ref:** US-S-06
- **Estimate:** M
- **Dependencies:** INVENTORY-002
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- All endpoints: `@JwtAuthGuard` + `@Roles('SELLER')` + `SellerKycGuard`; offer ownership check
- `GET /seller/inventory` — paginated list of `stock` rows for seller's offers (join with `catalog.offer`)
- `GET /seller/inventory/:offerId` — single offer stock
- `PUT /seller/inventory/:offerId { availableQty, reorderThreshold? }`:
  - Set `available_qty = max(0, input)` (cannot set negative)
  - Upsert stock row if not exists (first time seller sets stock)
  - Publish `inventory.changed` outbox event after update
- Response includes: `offerId`, `availableQty`, `reservedQty`, `effectiveAvailable`, `reorderThreshold`

**Done Criteria:**
- PUT with qty=0 → available_qty=0, effective_available=0
- After PUT → `inventory.changed` event in outbox
- Access another seller's inventory → 404

---

### INVENTORY-005 — Low-Stock Edge-Trigger Detection

- **US Ref:** US-S-07
- **Estimate:** M
- **Dependencies:** INVENTORY-003
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- Low-stock trigger fires when: `available_qty - reserved_qty` transitions from `> reorder_threshold` to `<= reorder_threshold`
- **Edge trigger**: fires only on the transition, not on every update when already below threshold
- Detection in `InventoryEventService.detectAndPublishLowStock(offerId, prevAvailable, newAvailable)`:
  - Load `reorder_threshold` (default 10 if null)
  - If `prevAvailable > threshold && newAvailable <= threshold`: publish `inventory.low_stock` outbox event
- Called after: reservation confirmed, seller reduces stock, admin adjusts
- `inventory.low_stock` payload: `{ offer_id, current_available, threshold, seller_id, product_id }`
- Notifications module consumer sends low-stock email to seller (NOTIFICATIONS-006)

**Done Criteria:**
- Stock drops from 11 to 9 (threshold=10): `inventory.low_stock` event published once
- Stock drops from 9 to 8 (already below threshold): NO second event
- Stock replenished to 15, then drops to 9: event fires again (second transition)

---

### INVENTORY-006 — CSV Bulk Import (seller)

- **US Ref:** US-S-08
- **Estimate:** L
- **Dependencies:** INVENTORY-004
- **Spec References:** `phase-1/technical-design/api-design/catalog.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `POST /seller/inventory/bulk-import` — multipart CSV upload
- CSV format: `offer_id,available_qty,reorder_threshold`; header row required
- Validation: max 500 rows per import; CSV max 1MB
- Row-level validation: `offer_id` must exist and belong to seller; `available_qty` must be integer ≥ 0
- Processing: for each valid row, upsert `inventory.stock`; publish `inventory.changed` per row
- Response: `{ processed: N, failed: N, errors: [{ row, offerId, reason }] }` — partial success allowed
- Async not needed for 500 rows (process synchronously with 5s timeout)

**Done Criteria:**
- Valid CSV 100 rows → 100 stock rows updated
- Row with invalid offer_id → included in errors, rest processed
- CSV > 1MB → 400 before processing

---

### INVENTORY-007 — Reservation Expiry Scheduler

- **US Ref:** FR-P-07
- **Estimate:** M
- **Dependencies:** INVENTORY-003
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- File: `apps/workers/src/schedulers/reservation-expiry.scheduler.ts`
- Cron: every 60s
- Query: `SELECT * FROM inventory.stock_reservation WHERE status = 'PENDING' AND expires_at < now() LIMIT 100 FOR UPDATE SKIP LOCKED`
- For each expired: call `ReservationService.releaseReservation(id)`; publish `inventory.reservation_expired` outbox event
- `inventory.reservation_expired` payload: `{ offer_id, reservation_id, qty, expired_at }`
- ORDERS module consumer (ORDERS-012) handles order cancellation on reservation expiry

**Done Criteria:**
- PENDING reservation past `expires_at`: released within 60s of expiry
- `inventory.reservation_expired` event in Kafka after scheduler runs
- `FOR UPDATE SKIP LOCKED` prevents double-processing by concurrent scheduler instances

---

### INVENTORY-008 — Zero-Stock Offer Deactivation

- **US Ref:** US-S-06
- **Estimate:** S
- **Dependencies:** INVENTORY-003, CATALOG-011
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- After any operation that decrements `available_qty` (confirm reservation, bulk import sets 0):
  - If resulting `available_qty = 0`: set `catalog.offer.status = INACTIVE` (reason=`SELLER_DEACTIVATED`) via CatalogService
  - Publish `offer.changed` event (via CATALOG-012 outbox writer)
- After seller restores stock (`PUT /seller/inventory/:offerId` sets qty > 0):
  - If offer was INACTIVE with reason `SELLER_DEACTIVATED`: auto-reactivate to `ACTIVE`
  - Publish `offer.changed` event
- Do not auto-reactivate if `SUSPENSION` or `ADMIN_REMOVAL` was the deactivation reason

**Done Criteria:**
- Reserve last unit and confirm: offer status → INACTIVE
- Seller restores stock: offer status → ACTIVE
- SUSPENSION-deactivated offer: restoring stock does NOT reactivate

---

### INVENTORY-009 — Outbox Events: inventory.changed, inventory.low_stock, inventory.reservation_expired

- **US Ref:** FR-P-09
- **Estimate:** S
- **Dependencies:** SHARED-005, INVENTORY-004
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Register Avro schemas for all 3 events:
  - `inventory.changed` payload: `{ offer_id, seller_id, available_qty, reserved_qty, effective_available, changed_at }`
  - `inventory.low_stock` payload: `{ offer_id, seller_id, product_id, current_available, threshold, triggered_at }`
  - `inventory.reservation_expired` payload: `{ offer_id, reservation_id, qty, expired_at }`
- All written via `OutboxEventWriter.write()` in same transaction as stock mutation

**Done Criteria:**
- Schema Registry shows 3 new subjects
- Each event type appears in Kafka UI after corresponding action

---

### INVENTORY-010 — Kafka Consumer: fulfillment.placed

- **US Ref:** FR-P-09
- **Estimate:** M
- **Dependencies:** PLATFORM-003, INVENTORY-003
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- Consumer group: `inventory.fulfillment-placed`
- Topic: `fulfillment.placed`
- `handle(event)`:
  - For each item in `event.payload.items`: call `ReservationService.confirmReservation(item.reservationId, event.payload.orderId, em)` (decrements available_qty)
  - If reservation not found or already confirmed: log warning + skip (idempotent)
- Extends `BaseKafkaConsumer` (PLATFORM-003) for idempotency + DLQ

**Done Criteria:**
- `fulfillment.placed` event consumed: `available_qty` decremented, reservation status = `CONFIRMED`
- Duplicate event: no double-decrement (idempotent via processed_event table)

---

### INVENTORY-011 — Kafka Consumer: fulfillment.cancelled

- **US Ref:** FR-P-09
- **Estimate:** M
- **Dependencies:** PLATFORM-003, INVENTORY-003
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- Consumer group: `inventory.fulfillment-cancelled`
- Topic: `fulfillment.cancelled`
- `handle(event)`:
  - Load `stock_reservation` by `event.payload.reservationId`
  - If status = `CONFIRMED`: call `releaseReservation()` (add back to available_qty); check and reactivate offer if needed
  - If status = `RELEASED`|`EXPIRED`: skip (already released)
- Also trigger zero-stock reactivation check if qty restored (INVENTORY-008)

**Done Criteria:**
- `fulfillment.cancelled` consumed: `available_qty` incremented; offer reactivated if previously zero-stock
- Duplicate event: no double-increment (idempotent)
