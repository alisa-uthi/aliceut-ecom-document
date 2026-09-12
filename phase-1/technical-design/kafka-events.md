# Kafka Events — Phase 1

**Status:** Draft  
**Source of truth:** [BRD v1.1](../requirements/BRD.md), [implementation-specs](implementation-specs.md)

Event envelope conventions, schema registry, consumer idempotency template (including processing flow diagram and per-family step patterns), DLQ topology, and BACKWARD compat protocol: see [conventions/kafka-events.md](../../conventions/kafka-events.md).

Consumer group tables below list **Side effects** (the unique business logic per group). For the generic processing loop and retry/DLQ rules, see conventions §4. The **Pattern** column maps each group to its family pattern in conventions §4.2.

MongoDB audit collection schemas (`audit_logs`, `activity_events`): see [data-model-mongodb.md](data-model-mongodb.md).

---

## Summary

- [1. Topic Summary](#topic-summary)
- [2. Topics](#topics)

<a id="topic-summary"></a>
## 1. Topic Summary

| Topic | Partition key | Producer | Consumer groups |
|-------|--------------|---------|----------------|
| [`seller.kyc.submitted`](#11-sellerkycsubmitted) | `seller_id` | Seller | notification.kyc-submitted, audit |
| [`seller.kyc.decided`](#12-sellerkycdecided) | `seller_id` | Admin | notification.kyc-decided, audit |
| [`seller.suspended`](#13-sellersuspended) | `seller_id` | Admin | notification.seller-suspended, search.seller-suspended, audit |
| [`seller.suspension_expired`](#118-sellersuspension_expired) | `seller_id` | Workers | notification.suspension-expired, search.suspension-expired, audit |
| [`seller.reinstated`](#115-sellerreinstated) | `seller_id` | Admin | notification.seller-reinstated, search.seller-reinstated, audit |
| [`fulfillment.placed`](#14-fulfillmentplaced) | `order_id` | Orders | notification.fulfillment-placed, notification.fulfillment-seller-alert, inventory.fulfillment-placed, audit |
| [`fulfillment.shipped`](#15-fulfillmentshipped) | `order_id` | Orders | notification.fulfillment-shipped, audit |
| [`fulfillment.delivered`](#16-fulfillmentdelivered) | `order_id` | Workers | notification.fulfillment-delivered, orders.delivery-tracker, audit |
| [`fulfillment.refunded`](#17-fulfillmentrefunded) | `order_id` | Orders | notification.fulfillment-refunded, audit |
| [`fulfillment.cancelled`](#116-fulfillmentcancelled) | `order_id` | Orders | notification.fulfillment-cancelled, inventory.fulfillment-cancelled, audit |
| [`fulfillment.refund_suspended_seller`](#117-fulfillmentrefund_suspended_seller) | `order_id` | Workers | notification.refund-suspended-seller-buyer, notification.refund-suspended-seller-seller, audit |
| [`order.finalized`](#18-orderfinalized) | `idempotency_key_id` | Orders | notification.order-summary, audit |
| [`order.completed`](#19-ordercompleted) | `order_id` | Workers | notification.order-completed, audit |
| [`product.changed`](#110-productchanged) | `product_id` | Catalog | search.product-changed, audit |
| [`offer.changed`](#111-offerchanged) | `offer_id` | Catalog/Seller | search.offer-changed, audit |
| [`listing.soft_deleted`](#121-listingsoft_deleted) | `offer_id` | Catalog | search.listing-soft-deleted, audit |
| [`inventory.changed`](#112-inventorychanged) | `offer_id` | Inventory | search.inventory-changed, audit |
| [`inventory.low_stock`](#113-inventorylow_stock) | `offer_id` | Inventory | notification.low-stock, audit |
| [`inventory.reservation_expired`](#119-inventoryreservation_expired) | `offer_id` | Workers | search.reservation-expired, audit |
| [`fx_rate.updated`](#120-fx_rateupdated) | `base_currency` | Workers | search.fx-rate-updated |
| [`listing.flagged`](#125-listingflagged) | `offer_id` | Admin | notification.listing-flagged, search.listing-flagged, audit |
| [`moderation.listing.removed`](#114-moderationlistingremoved) | `offer_id` | Admin | notification.listing-removed, search.listing-removed, audit |
| [`auth.email_verification_requested`](#122-authemail_verification_requested) | `user_id` | Auth | notification.email-verification, audit |
| [`auth.password_reset_requested`](#123-authpassword_reset_requested) | `user_id` | Auth | notification.password-reset, audit |
| [`auth.password_changed`](#124-authpassword_changed) | `user_id` | Auth | notification.password-changed, audit |

---

<a id="topics"></a>
## 2. Topics

### 1.1 `seller.kyc.submitted`

| Property | Value |
|----------|-------|
| Partition key | `seller_id` |
| Producer | Seller module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.seller",
  "type": "record",
  "name": "SellerKycSubmitted",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "seller.kyc.submitted" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "SellerKycSubmittedPayload",
        "fields": [
          { "name": "seller_id",             "type": "string", "doc": "UUID of seller_profile" },
          { "name": "user_id",               "type": "string", "doc": "UUID of identity.user" },
          { "name": "kyc_application_id",    "type": "string" },
          { "name": "business_name",         "type": "string" },
          { "name": "submitted_at",          "type": "string", "doc": "ISO 8601" },
          { "name": "seller_email",          "type": "string" },
          { "name": "is_resubmission",       "type": "boolean" },
          { "name": "prior_application_id",  "type": ["null","string"], "default": null },
          { "name": "prior_rejection_date",  "type": ["null","string"], "default": null, "doc": "ISO 8601; null on first submission" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.kyc-submitted` | `notification.*` | Sends ET-14 to seller; sends ET-21 to admin. Creates in-app notification for admins (type `KYC_SUBMITTED`). |
| `audit` | `audit` | Writes `audit_logs` (action=`KYC_SUBMITTED`, entity_type=`SELLER`, actor_id=seller_id). |

---

### 1.2 `seller.kyc.decided`

| Property | Value |
|----------|-------|
| Partition key | `seller_id` |
| Producer | Administration module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.seller",
  "type": "record",
  "name": "SellerKycDecided",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "seller.kyc.decided" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "SellerKycDecidedPayload",
        "fields": [
          { "name": "seller_id",           "type": "string" },
          { "name": "kyc_application_id",  "type": "string" },
          { "name": "decision",            "type": { "type": "enum", "name": "KycDecision", "symbols": ["APPROVED","REJECTED"] } },
          { "name": "reason",              "type": ["null","string"], "default": null, "doc": "Required for REJECTED" },
          { "name": "reviewer_user_id",    "type": "string" },
          { "name": "decided_at",          "type": "string" },
          { "name": "seller_email",        "type": "string" },
          { "name": "seller_name",         "type": "string" },
          { "name": "business_name",       "type": "string" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.kyc-decided` | `notification.*` | Sends ET-06 to seller when `decision = APPROVED`; sends ET-07 when `REJECTED`. Creates in-app notification (type `KYC_DECIDED`). |
| `audit` | `audit` | Writes `audit_logs` (action=`KYC_APPROVED`/`KYC_REJECTED`, entity_type=`SELLER`, actor_id=reviewer_user_id). |

---

### 1.3 `seller.suspended`

| Property | Value |
|----------|-------|
| Partition key | `seller_id` |
| Producer | Administration module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.seller",
  "type": "record",
  "name": "SellerSuspended",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "seller.suspended" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "SellerSuspendedPayload",
        "fields": [
          { "name": "seller_id",        "type": "string" },
          { "name": "reason",           "type": "string" },
          { "name": "admin_user_id",    "type": "string" },
          { "name": "suspended_at",     "type": "string" },
          { "name": "offer_ids",        "type": { "type": "array", "items": "string" }, "doc": "All ACTIVE offers to deindex" },
          { "name": "is_permanent",     "type": "boolean" },
          { "name": "suspended_until",  "type": ["null","string"], "default": null, "doc": "ISO 8601; null for permanent suspension" },
          { "name": "duration_label",   "type": "string", "doc": "e.g. '7 days' or 'permanent'" },
          { "name": "seller_name",      "type": "string" },
          { "name": "seller_email",     "type": "string" },
          { "name": "business_name",    "type": "string" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.seller-suspended` | `notification.*` | Sends ET-10 to seller. Creates in-app notification (type `SELLER_SUSPENDED`). |
| `search.seller-suspended` | `search.*` | Deindexes all `offer_ids` from Elasticsearch (marks offers as inactive in search index). |
| `audit` | `audit` | Writes `audit_logs` (action=`SELLER_SUSPENDED`, entity_type=`SELLER`, actor_id=admin_user_id). |

---

### 1.4 `fulfillment.placed`

| Property | Value |
|----------|-------|
| Partition key | `order_id` |
| Producer | Orders module (checkout transaction) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.orders",
  "type": "record",
  "name": "FulfillmentPlaced",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "fulfillment.placed" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "FulfillmentPlacedPayload",
        "fields": [
          { "name": "order_id",        "type": "string" },
          { "name": "fulfillment_id",  "type": "string", "doc": "UUID of orders.fulfillment" },
          { "name": "display_id",      "type": "string", "doc": "e.g. FUL-3F2A1B9C — fulfillment display ID" },
          { "name": "buyer_id",        "type": "string" },
          { "name": "seller_id",       "type": "string" },
          { "name": "currency_code",   "type": "string", "doc": "ISO 4217 — fulfillment-level seller's native pricing currency (mirrors orders.fulfillment.currency)" },
          { "name": "tracking_number", "type": "string" },
          { "name": "estimated_delivery_at", "type": "string" },
          { "name": "placed_at",       "type": "string" },
          { "name": "ship_by",         "type": "string", "doc": "ISO 8601 date — computed at checkout as placed_at + 3 calendar days; used by notification.fulfillment-seller-alert for ET-17 ship-by date" },
          {
            "name": "items",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "FulfillmentItem",
                "fields": [
                  { "name": "offer_id",        "type": "string" },
                  { "name": "product_title",   "type": "string" },
                  { "name": "variant_label",   "type": ["null","string"], "default": null },
                  { "name": "quantity",        "type": "int" },
                  { "name": "unit_price",      "type": "string", "doc": "NUMERIC(19,4) as string; seller's native currency amount snapshotted at checkout" },
                  { "name": "currency",        "type": "string", "doc": "ISO 4217 — seller's native pricing currency for this item; pairs with unit_price" },
                  { "name": "tax",             "type": "string" },
                  { "name": "fx_rate_used_at_capture", "type": ["null","string"], "default": null, "doc": "NUMERIC(19,8) as string; rate applied at checkout to convert unit_price to buyer's display currency. Null when no conversion was needed (buyer preferred_currency == seller native currency)" }
                ]
              }
            }
          },
          { "name": "shipping_cost",   "type": "string" },
          { "name": "tax_total",       "type": "string" },
          { "name": "total_amount",    "type": "string" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.fulfillment-placed` | `notification.*` | Creates in-app notification for buyer (type `ORDER_PLACED`). No email (covered by `order.finalized` ET-01). |
| `notification.fulfillment-seller-alert` | `notification.*` | Sends ET-17 to seller (looks up seller email via `seller_id` from payload). `ship_by` is included directly in the payload (placed_at + 3 calendar days, computed at checkout). |
| `audit` | `audit` | Writes `activity_events` (entity_type=`FULFILLMENT`, entity_id=fulfillment_id, actor_id=buyer_id, actor_role=`BUYER`). |
| `inventory.fulfillment-placed` | `inventory.*` | Marks stock reservations as CONSUMED for this order. |

---

### 1.5 `fulfillment.shipped`

| Property | Value |
|----------|-------|
| Partition key | `order_id` |
| Producer | Orders module (seller marks shipped) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.orders",
  "type": "record",
  "name": "FulfillmentShipped",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "fulfillment.shipped" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "FulfillmentShippedPayload",
        "fields": [
          { "name": "order_id",        "type": "string" },
          { "name": "fulfillment_id",  "type": "string" },
          { "name": "display_id",      "type": "string" },
          { "name": "buyer_id",        "type": "string" },
          { "name": "seller_id",       "type": "string" },
          { "name": "tracking_number", "type": "string" },
          { "name": "estimated_delivery_at", "type": "string" },
          { "name": "shipped_at",      "type": "string" },
          {
            "name": "items",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "ShippedItem",
                "fields": [
                  { "name": "offer_id",      "type": "string" },
                  { "name": "product_title", "type": "string" },
                  { "name": "variant_label", "type": ["null","string"], "default": null },
                  { "name": "quantity",      "type": "int" }
                ]
              }
            }
          }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.fulfillment-shipped` | `notification.*` | Sends ET-02 email to buyer. Creates in-app notification (type `SHIPMENT_UPDATE`). Note: consumer resolves `seller_name` via `seller_id` lookup from `seller_profile` table before rendering ET-02 (payload carries only `seller_id`). |
| `audit` | `audit` | Writes `activity_events` (entity_type=`FULFILLMENT`, entity_id=fulfillment_id, actor_id=seller_id, actor_role=`SELLER`). |

---

### 1.6 `fulfillment.delivered`

| Property | Value |
|----------|-------|
| Partition key | `order_id` |
| Producer | Workers module (mock delivery scheduler) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.orders",
  "type": "record",
  "name": "FulfillmentDelivered",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "fulfillment.delivered" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "FulfillmentDeliveredPayload",
        "fields": [
          { "name": "order_id",        "type": "string" },
          { "name": "fulfillment_id",  "type": "string" },
          { "name": "display_id",      "type": "string" },
          { "name": "buyer_id",        "type": "string" },
          { "name": "seller_id",       "type": "string" },
          { "name": "delivered_at",    "type": "string" },
          { "name": "seller_name",     "type": "string" },
          {
            "name": "items",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "DeliveredItem",
                "fields": [
                  { "name": "product_title", "type": "string" },
                  { "name": "quantity",      "type": "int" }
                ]
              }
            }
          }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.fulfillment-delivered` | `notification.*` | Sends ET-03 email. Creates in-app notification (type `DELIVERY_UPDATE`). |
| `orders.delivery-tracker` | `orders.*` | Updates `orders.fulfillment.status = DELIVERED` for the `fulfillment_id` in the event; then queries `SELECT COUNT(*) FROM orders.fulfillment WHERE order_id = ? AND status != 'DELIVERED'` — if count = 0 AND total fulfillments ≥ 2, emits `order.completed` via outbox. |
| `audit` | `audit` | Writes `activity_events` (entity_type=`FULFILLMENT`, entity_id=fulfillment_id, actor_role=`SYSTEM`). |

---

### 1.7 `fulfillment.refunded`

| Property | Value |
|----------|-------|
| Partition key | `order_id` |
| Producer | Orders module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.orders",
  "type": "record",
  "name": "FulfillmentRefunded",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "fulfillment.refunded" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "FulfillmentRefundedPayload",
        "fields": [
          { "name": "order_id",        "type": "string" },
          { "name": "fulfillment_id",  "type": "string" },
          { "name": "display_id",      "type": "string" },
          { "name": "buyer_id",        "type": "string" },
          { "name": "seller_id",       "type": "string" },
          { "name": "refunded_at",               "type": "string" },
          { "name": "refund_amount",             "type": "string", "doc": "NUMERIC(19,4) as string; total refund amount in seller's native currency (currency_code below)" },
          { "name": "currency_code",             "type": "string", "doc": "ISO 4217 — seller's native currency; matches fulfillment.placed.currency_code. Refund amount is always in this currency." },
          { "name": "prior_status",              "type": { "type": "enum", "name": "PriorStatus", "symbols": ["PENDING","SHIPPED"] }, "doc": "Stock restored only if PENDING" },
          { "name": "stock_restored",            "type": "boolean" },
          { "name": "seller_name",               "type": "string" },
          { "name": "buyer_preferred_currency",  "type": "string", "doc": "ISO 4217 — buyer's display preference currency at time of order; used for notification display only, never for refund arithmetic" },
          {
            "name": "items",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "RefundedItem",
                "fields": [
                  { "name": "product_title",           "type": "string" },
                  { "name": "variant_label",           "type": ["null","string"], "default": null },
                  { "name": "quantity",                "type": "int" },
                  { "name": "unit_price",              "type": "string", "doc": "NUMERIC(19,4) as string; seller's native currency amount from fulfillment_item snapshot" },
                  { "name": "currency_code",           "type": "string", "doc": "ISO 4217 — seller's native pricing currency; mirrors fulfillment_item.currency at capture" },
                  { "name": "fx_rate_used_at_capture", "type": ["null","string"], "default": null, "doc": "NUMERIC(19,8) as string; snapshot from fulfillment_item. Null when buyer preferred_currency == seller native (no FX conversion was applied)" }
                ]
              }
            }
          }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.fulfillment-refunded` | `notification.*` | Sends ET-04 email. Creates in-app notification (type `REFUND_ISSUED`). |
| `audit` | `audit` | Writes `activity_events` (entity_type=`FULFILLMENT`, entity_id=fulfillment_id, actor_role=`SYSTEM`). |

---

### 1.8 `order.finalized`

| Property | Value |
|----------|-------|
| Partition key | `idempotency_key_id` (groups orders from the same checkout session) |
| Producer | Orders module (post-checkout, same tx as idempotency key resolution) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.orders",
  "type": "record",
  "name": "OrderFinalized",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "order.finalized" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "OrderFinalizedPayload",
        "fields": [
          { "name": "idempotency_key_id",  "type": "string" },
          { "name": "buyer_id",            "type": "string" },
          { "name": "placement_outcome",   "type": { "type": "enum", "name": "PlacementOutcome", "symbols": ["FULLY_PLACED","PARTIALLY_PLACED"] } },
          {
            "name": "placed_fulfillments",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "PlacedFulfillmentRef",
                "fields": [
                  { "name": "order_id",       "type": "string", "doc": "Parent order UUID" },
                  { "name": "fulfillment_id",  "type": "string" },
                  { "name": "display_id",      "type": "string", "doc": "FUL-XXXX fulfillment display ID" },
                  { "name": "seller_id",       "type": "string" }
                ]
              }
            }
          },
          {
            "name": "failed_groups",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "FailedGroup",
                "fields": [
                  { "name": "seller_id", "type": "string" },
                  { "name": "reason",    "type": "string" },
                  {
                    "name": "items",
                    "type": {
                      "type": "array",
                      "items": {
                        "type": "record", "name": "FailedItem",
                        "fields": [
                          { "name": "offer_id",      "type": "string" },
                          { "name": "product_title", "type": "string" }
                        ]
                      }
                    }
                  }
                ]
              }
            }
          },
          { "name": "finalized_at", "type": "string" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.order-summary` | `notification.*` | Sends ET-01 order summary email to buyer (includes placed and failed groups). Note: per-fulfillment `ORDER_PLACED` in-app notifications fire from the `fulfillment.placed` consumer (§1.4); this consumer focuses on the ET-01 order summary email only. Consumer reads `fulfillment`, `fulfillment_item`, `seller_profile`, and `identity.user` rows from the same Postgres instance to build the full order summary context before sending ET-01. |
| `audit` | `audit` | Writes `activity_events` (entity_type=`ORDER`, entity_id=idempotency_key_id, actor_id=buyer_id, actor_role=`BUYER`). |

---

### 1.9 `order.completed`

Fires when all fulfillments under the same `order_id` reach DELIVERED state, but **only when there were ≥ 2 fulfillments** in that order (multi-seller checkout).

| Property | Value |
|----------|-------|
| Partition key | `order_id` |
| Producer | Workers module (`orders.delivery-tracker` consumer, after confirming all fulfillments delivered) |
| Event version | 1 |

**[DESIGN DECISION]** `order.completed` is emitted by the `orders.delivery-tracker` consumer after it verifies that every `fulfillment` under the same `order_id` has reached DELIVERED. The consumer queries `SELECT COUNT(*) FROM orders.fulfillment WHERE order_id = ? AND status != 'DELIVERED'` after each delivery event; if count = 0 AND total fulfillments ≥ 2, it emits `order.completed`. This avoids a dedicated "checkout session" table while still supporting the multi-fulfillment completion signal.

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.orders",
  "type": "record",
  "name": "OrderCompleted",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "order.completed" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "OrderCompletedPayload",
        "fields": [
          { "name": "order_id",            "type": "string", "doc": "Parent order UUID (one per checkout)" },
          { "name": "buyer_id",            "type": "string" },
          { "name": "fulfillment_ids",     "type": { "type": "array", "items": "string" }, "doc": "UUIDs of all fulfillments under this order" },
          { "name": "completed_at",        "type": "string" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.order-completed` | `notification.*` | Sends ET-05 "All items delivered" email to buyer. Creates in-app notification (type `ORDER_COMPLETED`). |
| `audit` | `audit` | Writes `activity_events` (entity_type=`ORDER`, entity_id=order_id, actor_role=`SYSTEM`). |

---

### 1.10 `product.changed`

| Property | Value |
|----------|-------|
| Partition key | `product_id` |
| Producer | Catalog module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.catalog",
  "type": "record",
  "name": "ProductChanged",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "product.changed" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "ProductChangedPayload",
        "fields": [
          { "name": "product_id",   "type": "string" },
          { "name": "change_type",  "type": { "type": "enum", "name": "ProductChangeType", "symbols": ["CREATED","UPDATED","REMOVED"] } },
          { "name": "category_id",  "type": "string" },
          { "name": "title",        "type": "string" },
          { "name": "brand",        "type": ["null","string"], "default": null },
          { "name": "description",  "type": ["null","string"], "default": null },
          { "name": "status",       "type": "string" },
          {
            "name": "variants",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "ProductVariantRef",
                "fields": [
                  { "name": "variant_id",   "type": "string" },
                  { "name": "sku",          "type": "string" },
                  { "name": "attributes",   "type": "string", "doc": "JSON-encoded attributes" }
                ]
              }
            }
          },
          {
            "name": "images",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "ProductImageRef",
                "fields": [
                  { "name": "storage_key", "type": "string" },
                  { "name": "position",    "type": "int" }
                ]
              }
            }
          }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `search.product-changed` | `search.*` | Upserts or deletes the product document in Elasticsearch. On REMOVED: removes from index. |
| `audit` | `audit` | Writes `activity_events` (entity_type=`PRODUCT`, entity_id=product_id, actor_role=`SYSTEM`). |

---

### 1.11 `offer.changed`

| Property | Value |
|----------|-------|
| Partition key | `offer_id` |
| Producer | Catalog module / Seller module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.catalog",
  "type": "record",
  "name": "OfferChanged",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "offer.changed" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "OfferChangedPayload",
        "fields": [
          { "name": "offer_id",    "type": "string" },
          { "name": "product_id",  "type": "string" },
          { "name": "seller_id",   "type": "string" },
          { "name": "variant_id",  "type": ["null","string"], "default": null },
          { "name": "change_type", "type": { "type": "enum", "name": "OfferChangeType", "symbols": ["CREATED","UPDATED","DEACTIVATED","REMOVED"] } },
          { "name": "status",      "type": "string" },
          {
            "name": "prices",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "OfferPriceRef",
                "fields": [
                  { "name": "currency_code", "type": "string", "doc": "ISO 4217 — seller's native pricing currency for this price row" },
                  { "name": "amount",        "type": "string" },
                  { "name": "price_type",    "type": "string" },
                  { "name": "min_qty",       "type": "int" },
                  { "name": "starts_at",     "type": ["null","string"], "default": null },
                  { "name": "ends_at",       "type": ["null","string"], "default": null }
                ]
              }
            }
          }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `search.offer-changed` | `search.*` | Updates the offer's price fields in the Elasticsearch product document. On DEACTIVATED/REMOVED: removes offer from search or marks product as out-of-stock if no active offers remain. |
| `audit` | `audit` | Writes `activity_events` (entity_type=`OFFER`, entity_id=offer_id, actor_id=seller_id, actor_role=`SELLER`). |

---

### 1.12 `inventory.changed`

| Property | Value |
|----------|-------|
| Partition key | `offer_id` |
| Producer | Inventory module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.inventory",
  "type": "record",
  "name": "InventoryChanged",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "inventory.changed" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "InventoryChangedPayload",
        "fields": [
          { "name": "offer_id",       "type": "string" },
          { "name": "seller_id",      "type": "string" },
          { "name": "on_hand_qty",    "type": "int" },
          { "name": "reserved_qty",   "type": "int" },
          { "name": "available_qty",  "type": "int" },
          { "name": "change_reason",  "type": { "type": "enum", "name": "InventoryChangeReason", "symbols": ["MANUAL_UPDATE","BULK_UPDATE","RESERVATION","REFUND_RESTORE"] } }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `search.inventory-changed` | `search.*` | Updates `available_qty` and `in_stock` flag in Elasticsearch. |
| `audit` | `audit` | Writes `activity_events` (entity_type=`INVENTORY`, entity_id=offer_id, actor_role=`SELLER`/`SYSTEM` per change_reason). |

---

### 1.13 `inventory.low_stock`

| Property | Value |
|----------|-------|
| Partition key | `offer_id` |
| Producer | Inventory module (emitted when `available_qty` drops below `low_stock_threshold`) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.inventory",
  "type": "record",
  "name": "InventoryLowStock",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "inventory.low_stock" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "InventoryLowStockPayload",
        "fields": [
          { "name": "offer_id",            "type": "string" },
          { "name": "seller_id",           "type": "string" },
          { "name": "product_title",       "type": "string" },
          { "name": "available_qty",       "type": "int" },
          { "name": "low_stock_threshold", "type": "int", "default": 5 },
          { "name": "sku_label",           "type": "string" },
          { "name": "sku_id",              "type": "string" },
          { "name": "on_hand_qty",         "type": "int" },
          { "name": "reserved_qty",        "type": "int" },
          { "name": "seller_email",        "type": "string" },
          { "name": "seller_name",         "type": "string" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.low-stock` | `notification.*` | Sends ET-15 to seller. Creates in-app notification (type `LOW_STOCK`). |
| `audit` | `audit` | Writes `activity_events` (entity_type=`INVENTORY`, entity_id=offer_id, actor_role=`SYSTEM`). |

---

### 1.14 `moderation.listing.removed`

| Property | Value |
|----------|-------|
| Partition key | `offer_id` |
| Producer | Administration module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.admin",
  "type": "record",
  "name": "ModerationListingRemoved",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "moderation.listing.removed" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "ModerationListingRemovedPayload",
        "fields": [
          { "name": "offer_id",            "type": "string" },
          { "name": "product_id",          "type": "string" },
          { "name": "seller_id",           "type": "string" },
          { "name": "product_title",       "type": "string" },
          { "name": "removal_category",    "type": { "type": "enum", "name": "RemovalCategory", "symbols": ["PROHIBITED_CATEGORY","IP_VIOLATION","MISLEADING","OTHER"] } },
          { "name": "removal_reason_text", "type": "string" },
          { "name": "admin_user_id",       "type": "string" },
          { "name": "moderation_case_id",  "type": "string" },
          { "name": "removed_at",          "type": "string" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.listing-removed` | `notification.*` | Writes to `pending_listing_removal_digest` table for daily cron batch send (ET-09), not direct email. Creates in-app notification (type `LISTING_REMOVED`). |
| `search.listing-removed` | `search.*` | Removes offer from Elasticsearch index immediately. |
| `audit` | `audit` | Writes `audit_logs` (action=`LISTING_REMOVED`, entity_type=`LISTING`, actor_id=admin_user_id). |

---

### 1.15 `seller.reinstated`

Fires when an admin lifts a seller's suspension (sets `suspension_status = ACTIVE`).

| Property | Value |
|----------|-------|
| Partition key | `seller_id` |
| Producer | Admin module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.seller",
  "type": "record",
  "name": "SellerReinstated",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "seller.reinstated" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "SellerReinstatedPayload",
        "fields": [
          { "name": "seller_id",      "type": "string", "doc": "UUID of the reinstated seller" },
          { "name": "seller_email",   "type": "string" },
          { "name": "seller_name",    "type": "string" },
          { "name": "business_name",  "type": "string" },
          { "name": "admin_id",       "type": "string", "doc": "UUID of the admin who lifted the suspension" },
          { "name": "reinstated_at",  "type": "string", "doc": "ISO 8601 UTC" },
          { "name": "reason",         "type": ["null", "string"], "default": null, "doc": "Optional admin note" },
          { "name": "offer_ids",      "type": { "type": "array", "items": "string" }, "doc": "IDs of offers reactivated by reinstatement" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.seller-reinstated` | `notification.*` | Sends ET-12 to seller. Creates in-app notification (type `SELLER_REINSTATED`). |
| `search.seller-reinstated` | `search.*` | Re-enables seller's active offers in Elasticsearch index (sets `seller_active = true` on all offer docs). |
| `audit` | `audit` | Writes `audit_logs` (action=`SELLER_REINSTATED`, entity_type=`SELLER`, actor_id=admin_id). |

---

### 1.16 `fulfillment.cancelled`

| Property | Value |
|----------|-------|
| Partition key | `order_id` |
| Producer | Orders module (seller cancel action) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.orders",
  "type": "record",
  "name": "FulfillmentCancelled",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "fulfillment.cancelled" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "FulfillmentCancelledPayload",
        "fields": [
          { "name": "order_id",                  "type": "string" },
          { "name": "fulfillment_id",            "type": "string" },
          { "name": "display_id",                "type": "string", "doc": "e.g. FUL-3F2A1B9C" },
          { "name": "seller_id",                 "type": "string" },
          { "name": "seller_name",               "type": "string" },
          { "name": "buyer_id",                  "type": "string" },
          { "name": "buyer_preferred_currency",  "type": "string", "doc": "ISO 4217 — buyer's display preference currency at order time; used for email display only, never for refund arithmetic" },
          { "name": "cancelled_at",              "type": "string", "doc": "ISO 8601" },
          { "name": "reason",                    "type": "string" },
          { "name": "currency_code",             "type": "string", "doc": "ISO 4217 — seller's native pricing currency; pairs with total_amount and item.unit_price" },
          { "name": "total_amount",              "type": "string", "doc": "NUMERIC(19,4) as string; fulfillment total in seller's native currency (currency_code)" },
          {
            "name": "items",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "CancelledItem",
                "fields": [
                  { "name": "offer_id",                  "type": "string" },
                  { "name": "product_title",             "type": "string" },
                  { "name": "variant_label",             "type": ["null","string"], "default": null },
                  { "name": "quantity",                  "type": "int" },
                  { "name": "unit_price",                "type": "string", "doc": "NUMERIC(19,4) as string; seller's native currency amount from fulfillment_item snapshot" },
                  { "name": "currency_code",             "type": "string", "doc": "ISO 4217 — seller's native pricing currency; mirrors fulfillment_item.currency at capture" },
                  { "name": "tax",                       "type": "string", "doc": "NUMERIC(19,4) as string" },
                  { "name": "fx_rate_used_at_capture",   "type": ["null","string"], "default": null, "doc": "NUMERIC(19,8) as string; null when no FX conversion applied" }
                ]
              }
            }
          }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.fulfillment-cancelled` | `notification.*` | Sends ET-16 email to buyer. Creates in-app notification (type `FULFILLMENT_CANCELLED`). |
| `inventory.fulfillment-cancelled` | `inventory.*` | Restores reserved stock for the cancelled fulfillment. |
| `audit` | `audit` | Writes `activity_events` (entity_type=`FULFILLMENT`, entity_id=fulfillment_id, actor_id=seller_id, actor_role=`SELLER`). |

---

### 1.17 `fulfillment.refund_suspended_seller`

| Property | Value |
|----------|-------|
| Partition key | `order_id` |
| Producer | Workers module (auto-refund monitor, US-P-16) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.orders",
  "type": "record",
  "name": "FulfillmentRefundSuspendedSeller",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "fulfillment.refund_suspended_seller" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "FulfillmentRefundSuspendedSellerPayload",
        "fields": [
          { "name": "order_id",       "type": "string" },
          { "name": "fulfillment_id", "type": "string" },
          { "name": "seller_id",      "type": "string" },
          { "name": "buyer_id",       "type": "string" },
          { "name": "buyer_email",    "type": "string" },
          { "name": "buyer_name",     "type": "string" },
          { "name": "refunded_at",    "type": "string", "doc": "ISO 8601" },
          {
            "name": "items",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "SuspendedSellerRefundItem",
                "fields": [
                  { "name": "offer_id",      "type": "string" },
                  { "name": "product_title", "type": "string" },
                  { "name": "variant_label", "type": ["null","string"], "default": null },
                  { "name": "quantity",      "type": "int" },
                  { "name": "unit_price",    "type": "string", "doc": "NUMERIC(19,4) as string; seller's native currency amount from fulfillment_item snapshot" },
                  { "name": "currency_code", "type": "string", "doc": "ISO 4217 — seller's native pricing currency for this item" }
                ]
              }
            }
          },
          { "name": "refund_amount",              "type": "string", "doc": "NUMERIC(19,4) as string; total refund in seller's native currency (currency_code below)" },
          { "name": "currency_code",              "type": "string", "doc": "ISO 4217 — seller's native currency; matches fulfillment_item.currency at capture" },
          { "name": "seller_name",                "type": "string" },
          { "name": "buyer_preferred_currency",   "type": "string", "doc": "ISO 4217 — buyer's display preference currency at order time; used for notification display only, never for refund arithmetic" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.refund-suspended-seller-buyer` | `notification.*` | Sends ET-13 email to buyer. Creates in-app notification (type `REFUND_ISSUED`). |
| `notification.refund-suspended-seller-seller` | `notification.*` | Sends ET-13b email to seller. |
| `audit` | `audit` | Writes `activity_events` (entity_type=`FULFILLMENT`, entity_id=fulfillment_id, actor_role=`SYSTEM`). |

---

### 1.18 `seller.suspension_expired`

| Property | Value |
|----------|-------|
| Partition key | `seller_id` |
| Producer | Workers module (suspension expiry scheduler, US-P-18) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.seller",
  "type": "record",
  "name": "SellerSuspensionExpired",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "seller.suspension_expired" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "SellerSuspensionExpiredPayload",
        "fields": [
          { "name": "seller_id",       "type": "string" },
          { "name": "seller_email",    "type": "string" },
          { "name": "seller_name",     "type": "string" },
          { "name": "business_name",   "type": "string" },
          { "name": "suspended_at",    "type": "string", "doc": "ISO 8601" },
          { "name": "suspended_until", "type": "string", "doc": "ISO 8601; the expiry timestamp that triggered this event" },
          { "name": "expired_at",      "type": "string", "doc": "ISO 8601; when the expiry was processed" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.suspension-expired` | `notification.*` | Sends ET-11 email to seller. Creates in-app notification (type `SUSPENSION_EXPIRED`). |
| `audit` | `audit` | Writes `audit_logs` (action=`SUSPENSION_EXPIRED`, entity_type=`SELLER`, actor_role=`SYSTEM`). |
| `search.suspension-expired` | `search.*` | Re-enables seller's SUSPENSION-deactivated offers in Elasticsearch. |

---

### 1.19 `inventory.reservation_expired`

| Property | Value |
|----------|-------|
| Partition key | `offer_id` |
| Producer | Workers module (reservation expiry scheduler, US-P-17) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.inventory",
  "type": "record",
  "name": "InventoryReservationExpired",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "inventory.reservation_expired" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "InventoryReservationExpiredPayload",
        "fields": [
          { "name": "reservation_id", "type": "string" },
          { "name": "offer_id",       "type": "string" },
          { "name": "order_id",       "type": "string" },
          { "name": "released_qty",   "type": "int" },
          { "name": "released_at",    "type": "string", "doc": "ISO 8601" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `audit` | `audit` | Writes `activity_events` (entity_type=`INVENTORY`, entity_id=offer_id, actor_role=`SYSTEM`). |
| `search.reservation-expired` | `search.*` | Updates `available_qty` in Elasticsearch offer document. |

---

### 1.20 `fx_rate.updated`

| Property | Value |
|----------|-------|
| Partition key | `base_currency` |
| Producer | Workers module (FX rate refresh cron, US-P-19) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.fx",
  "type": "record",
  "name": "FxRateUpdated",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "fx_rate.updated" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "FxRateUpdatedPayload",
        "fields": [
          { "name": "base_currency", "type": "string", "doc": "ISO 4217 — seller pricing currency (one of USD, THB, JPY, SGD); the currency being repriced" },
          {
            "name": "rates",
            "type": {
              "type": "array",
              "items": {
                "type": "record", "name": "FxRateEntry",
                "fields": [
                  { "name": "currency_code", "type": "string", "doc": "ISO 4217 — display/quote currency (buyer's display target)" },
                  { "name": "rate",          "type": "string", "doc": "NUMERIC(19,8) as string; base_currency → currency_code conversion rate" },
                  { "name": "fetched_at",    "type": "string", "doc": "ISO 8601" }
                ]
              }
            }
          }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `search.fx-rate-updated` | `search.*` | Refreshes `display_prices` map across all offer documents in Elasticsearch for the updated currency pair. |

---

### 1.21 `listing.soft_deleted`

| Property | Value |
|----------|-------|
| Partition key | `offer_id` |
| Producer | Catalog module (seller soft-delete action, US-P-11) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.catalog",
  "type": "record",
  "name": "ListingSoftDeleted",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "listing.soft_deleted" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "ListingSoftDeletedPayload",
        "fields": [
          { "name": "product_id",  "type": "string" },
          { "name": "offer_id",    "type": "string" },
          { "name": "seller_id",   "type": "string" },
          { "name": "deleted_at",  "type": "string", "doc": "ISO 8601" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `search.listing-soft-deleted` | `search.*` | Removes product document from Elasticsearch index. |
| `audit` | `audit` | Writes `activity_events` (entity_type=`OFFER`, entity_id=offer_id, actor_id=seller_id, actor_role=`SELLER`). |

---

### 1.22 `auth.email_verification_requested`

| Property | Value |
|----------|-------|
| Partition key | `user_id` |
| Producer | Auth module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.auth",
  "type": "record",
  "name": "AuthEmailVerificationRequested",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "auth.email_verification_requested" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "AuthEmailVerificationRequestedPayload",
        "fields": [
          { "name": "user_id",            "type": "string" },
          { "name": "email",              "type": "string" },
          { "name": "verification_token", "type": "string" },
          { "name": "expires_at",         "type": "string", "doc": "ISO 8601" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.email-verification` | `notification.*` | Sends ET-18 verification email to user. |
| `audit.auth-email-verification` | `audit` | Writes `audit_logs` (action=`EMAIL_VERIFICATION_REQUESTED`, entity_type=`USER`, actor_id=user_id). |

---

### 1.23 `auth.password_reset_requested`

| Property | Value |
|----------|-------|
| Partition key | `user_id` |
| Producer | Auth module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.auth",
  "type": "record",
  "name": "AuthPasswordResetRequested",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "auth.password_reset_requested" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "AuthPasswordResetRequestedPayload",
        "fields": [
          { "name": "user_id",      "type": "string" },
          { "name": "email",        "type": "string" },
          { "name": "reset_token",  "type": "string" },
          { "name": "expires_at",   "type": "string", "doc": "ISO 8601" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.password-reset` | `notification.*` | Sends ET-19 password-reset email to user. |
| `audit.auth-password-reset` | `audit` | Writes `audit_logs` (action=`PASSWORD_RESET_REQUESTED`, entity_type=`USER`, actor_id=user_id). |

---

### 1.24 `auth.password_changed`

| Property | Value |
|----------|-------|
| Partition key | `user_id` |
| Producer | Auth module |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.auth",
  "type": "record",
  "name": "AuthPasswordChanged",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "auth.password_changed" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "AuthPasswordChangedPayload",
        "fields": [
          { "name": "user_id",    "type": "string" },
          { "name": "email",      "type": "string" },
          { "name": "changed_at", "type": "string", "doc": "ISO 8601" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.password-changed` | `notification.*` | Sends ET-20 password-changed confirmation email to user. |
| `audit.auth-password-changed` | `audit` | Writes `audit_logs` (action=`PASSWORD_CHANGED`, entity_type=`USER`, actor_id=user_id). |

---

### 1.25 `listing.flagged`

Fires when an admin manually creates a moderation case against an active listing via `POST /admin/moderation`. Triggers seller notification (ET-08) so the seller knows their listing is under review.

| Property | Value |
|----------|-------|
| Partition key | `offer_id` |
| Producer | Administration module (`POST /admin/moderation`) |
| Event version | 1 |

**Avro schema**
```json
{
  "namespace": "com.aliceut.events.admin",
  "type": "record",
  "name": "ListingFlagged",
  "fields": [
    { "name": "event_id",       "type": "string" },
    { "name": "event_type",     "type": "string", "default": "listing.flagged" },
    { "name": "event_version",  "type": "int",    "default": 1 },
    { "name": "occurred_at",    "type": "string" },
    { "name": "correlation_id", "type": "string" },
    {
      "name": "payload",
      "type": {
        "type": "record", "name": "ListingFlaggedPayload",
        "fields": [
          { "name": "offer_id",             "type": "string" },
          { "name": "product_id",           "type": "string" },
          { "name": "product_title",        "type": "string" },
          { "name": "seller_id",            "type": "string" },
          { "name": "seller_email",         "type": "string" },
          { "name": "seller_name",          "type": "string" },
          { "name": "moderation_case_id",   "type": "string" },
          { "name": "flag_reason",          "type": "string", "doc": "Admin-provided reason text" },
          { "name": "admin_user_id",        "type": "string" },
          { "name": "flagged_at",           "type": "string", "doc": "ISO 8601" }
        ]
      }
    }
  ]
}
```

**Consumer groups**

| Consumer group | Pattern | Side effects |
|---------------|---------|--------------|
| `notification.listing-flagged` | `notification.*` | Sends ET-08 to seller. Creates in-app notification (type `LISTING_FLAGGED`). |
| `search.listing-flagged` | `search.*` | Deindexes `offer_id` from Elasticsearch (hides offer while under review). Re-indexing on admin clear (DISMISS decision) occurs via `offer.changed` consumer when `POST /admin/moderation/:id/decide` emits `offer.changed` with `status: ACTIVE`. |
| `audit` | `audit` | Writes `audit_logs` (action=`LISTING_FLAGGED`, entity_type=`LISTING`, actor_id=admin_user_id). |

---

