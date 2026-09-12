# MongoDB Data Model — Phase 1

**Status:** Draft  
**Source of truth:** [BRD v1.2](../requirements/BRD.md)

Collections used for high-write append data: audit accountability and domain lifecycle events. All writes come from the single `audit` Kafka consumer group (see [kafka-events.md](kafka-events.md)).

**Modelling convention:** All MongoDB `_id` fields use UUIDv7 in standard UUID binary representation (BinData subtype 4). Do not use `ObjectId` for domain or audit documents. This aligns with the Postgres UUIDv7 convention and enables correlation across stores.

---

## Summary

- [Consumer routing](#consumer-routing)
- [1. `audit_logs`](#audit-logs)
- [2. `activity_events`](#activity-events)

<a id="consumer-routing"></a>
## Consumer routing

The `audit` consumer group subscribes to all topics and routes by `event_type`:

| Route | Collection | Event types |
|---|---|---|
| Admin accountability | `audit_logs` | `seller.kyc.*`, `seller.suspended`, `seller.reinstated`, `seller.suspension_expired`, `moderation.listing.removed` |
| Domain lifecycle | `activity_events` | All `fulfillment.*`, `order.*`, `product.*`, `offer.*`, `inventory.*`, `listing.*` |

---

<a id="audit-logs"></a>
## 1. `audit_logs`

Admin/moderation actions. Answers: *who did what, and why.*

| Field | Type | Notes |
|---|---|---|
| `_id` | UUID (UUIDv7, BinData subtype 4) | |
| `event_id` | string | UUID; unique index — idempotency key |
| `event_type` | string | indexed |
| `occurred_at` | Date | indexed |
| `correlation_id` | string | |
| `actor_id` | string | Admin user UUID; `SYSTEM` literal for automated expiry |
| `entity_type` | `SELLER` \| `LISTING` | |
| `entity_id` | string | indexed — `seller_id` or `offer_id` |
| `action` | string | `KYC_SUBMITTED` \| `KYC_APPROVED` \| `KYC_REJECTED` \| `SELLER_SUSPENDED` \| `SELLER_REINSTATED` \| `SUSPENSION_EXPIRED` \| `LISTING_REMOVED` |
| `decision_reason` | string \| null | rejection/suspension reason text |
| `payload` | object | full Kafka payload snapshot |

**Indexes**
```javascript
db.audit_logs.createIndex({ event_id: 1 }, { unique: true })
db.audit_logs.createIndex({ entity_id: 1, occurred_at: -1 })
db.audit_logs.createIndex({ event_type: 1, occurred_at: -1 })
db.audit_logs.createIndex({ actor_id: 1, occurred_at: -1 })
db.audit_logs.createIndex({ occurred_at: 1 }, { expireAfterSeconds: 63072000 }) // 2-year TTL
```

---

<a id="activity-events"></a>
## 2. `activity_events`

Domain lifecycle events. Answers: *what happened to this order/product/offer.*

| Field | Type | Notes |
|---|---|---|
| `_id` | UUID (UUIDv7, BinData subtype 4) | |
| `event_id` | string | UUID; unique index — idempotency key |
| `event_type` | string | indexed |
| `occurred_at` | Date | indexed |
| `correlation_id` | string | indexed — traces full request flow |
| `entity_type` | `ORDER` \| `FULFILLMENT` \| `PRODUCT` \| `OFFER` \| `INVENTORY` | |
| `entity_id` | string | indexed — `order_id` / `fulfillment_id` / `product_id` / `offer_id` |
| `actor_id` | string \| null | `buyer_id` or `seller_id`; null for SYSTEM-initiated events |
| `actor_role` | `BUYER` \| `SELLER` \| `SYSTEM` \| null | |
| `payload` | object | full Kafka payload snapshot |

**Indexes**
```javascript
db.activity_events.createIndex({ event_id: 1 }, { unique: true })
db.activity_events.createIndex({ entity_id: 1, occurred_at: -1 })
db.activity_events.createIndex({ actor_id: 1, occurred_at: -1 })
db.activity_events.createIndex({ correlation_id: 1 })
db.activity_events.createIndex({ event_type: 1, occurred_at: -1 })
db.activity_events.createIndex({ occurred_at: 1 }, { expireAfterSeconds: 7776000 }) // 90-day TTL
```
