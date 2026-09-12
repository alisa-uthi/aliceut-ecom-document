# Notifications API

**Module:** `Notifications`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.1](../../requirements/BRD.md), [ERD](../data-model-erd.md)

---

## Summary

- [Endpoint Index](#endpoint-index)
- [DB Mapping](#db-mapping)
- [Endpoints](#endpoints)
- [Notification Creation (Async)](#notification-creation-async)

<a id="endpoint-index"></a>
## Endpoint Index

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | [`/notifications`](#list-in-app-notifications) | JWT | List notifications (cursor-paginated, optional unread filter) |
| `PATCH` | [`/notifications/:id/read`](#mark-notification-read) | JWT | Mark single notification read |
| `PATCH` | [`/notifications/read-all`](#mark-all-notifications-read) | JWT | Bulk mark all unread notifications read |

See [Notification Creation (Async)](#notification-creation-async) for the Kafka consumer write path — notifications are never written by API handlers.

---

<a id="db-mapping"></a>
## DB Mapping

| Endpoint | Primary DB | Tables / Notes |
|----------|-----------|----------------|
| `GET /notifications` | Postgres | `notifications.in_app_notification` (filter by `recipient_user_id`; index on `(recipient_user_id, read_at)`) |
| `PATCH /notifications/:id/read` | Postgres | `notifications.in_app_notification` (set `read_at`) |
| `PATCH /notifications/read-all` | Postgres | `notifications.in_app_notification` (bulk update `read_at` where `recipient_user_id = ?` and `read_at IS NULL`) |

**Write path (async):** Notification rows are created by Kafka consumers reacting to domain events — never written inline by API handlers. See kafka-events convention for event → notification type mapping.

---

<a id="endpoints"></a>
## Endpoints

### List in-app notifications

```
GET /notifications
Tag: Notifications
Auth: JWT
Pagination: cursor
```
**Query params:** `unreadOnly` (boolean), `limit`, `cursor`  
**Response 200**
```json
{
  "data": [{
    "id": "uuid",
    "type": "ORDER_PLACED | SHIPMENT_UPDATE | DELIVERY_UPDATE | KYC_DECIDED | KYC_SUBMITTED | LOW_STOCK | LISTING_FLAGGED | LISTING_REMOVED | SELLER_SUSPENDED | SELLER_REINSTATED | REFUND_ISSUED | ORDER_COMPLETED | FULFILLMENT_CANCELLED | SUSPENSION_EXPIRED",
    "payload": {},
    "readAt": "ISO8601 | null",
    "createdAt": "ISO8601"
  }],
  "meta": { "nextCursor": "string | null", "hasMore": false, "unreadCount": 3 }
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant JG as JwtAuthGuard
    participant S as NotificationService
    participant PG as Postgres

    C->>API: GET /notifications?unreadOnly=true&limit=20&cursor=...
    API->>JG: verify JWT
    alt invalid or missing token
        JG-->>C: 401 Unauthorized
    else valid JWT
        JG-->>API: userId
        API->>S: listNotifications(userId, filters, cursor)
        S->>PG: SELECT in_app_notification WHERE recipient_user_id=? ORDER BY created_at DESC cursor-paginated
        PG-->>S: rows + unread count
        S-->>C: 200 { data[], meta: { nextCursor, hasMore, unreadCount } }
    end
```

---

### Mark notification read

```
PATCH /notifications/:notificationId/read
Tag: Notifications
Auth: JWT
```
**Response 200** `{ "data": { "readAt": "ISO8601" } }`  
**Errors:** 404, 403

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant JG as JwtAuthGuard
    participant S as NotificationService
    participant PG as Postgres

    C->>API: PATCH /notifications/:notificationId/read
    API->>JG: verify JWT
    alt invalid or missing token
        JG-->>C: 401 Unauthorized
    else valid JWT
        JG-->>API: userId
        API->>S: markRead(notificationId, userId)
        S->>PG: SELECT in_app_notification WHERE id = ?
        alt not found
            PG-->>S: 0 rows
            S-->>C: 404 Not Found
        else recipient_user_id != userId
            PG-->>S: row belongs to different user
            S-->>C: 403 Forbidden
        else found and owned
            PG-->>S: notification row
            S->>PG: UPDATE in_app_notification SET read_at = NOW() WHERE id = ?
            PG-->>S: updated row
            S-->>C: 200 { data: { readAt } }
        end
    end
```

---

### Mark all notifications read

```
PATCH /notifications/read-all
Tag: Notifications
Auth: JWT
```
**Response 200** `{ "data": { "markedCount": 5 } }`

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant JG as JwtAuthGuard
    participant S as NotificationService
    participant PG as Postgres

    C->>API: PATCH /notifications/read-all
    API->>JG: verify JWT
    alt invalid or missing token
        JG-->>C: 401 Unauthorized
    else valid JWT
        JG-->>API: userId
        API->>S: markAllRead(userId)
        S->>PG: UPDATE in_app_notification SET read_at=NOW() WHERE recipient_user_id=? AND read_at IS NULL
        PG-->>S: affected row count
        S-->>C: 200 { data: { markedCount } }
    end
```

---

<a id="notification-creation-async"></a>
## Notification Creation (Async)

Notification rows are never written by API handlers. They are created exclusively by Kafka consumers reacting to domain events. The diagram below shows the full async path, including consumer-side idempotency using `platform.processed_event`.

```mermaid
sequenceDiagram
    participant DS as Domain Service
    participant PG as Postgres
    participant Relay as Kafka Relay
    participant Kafka as Kafka Topic
    participant NC as NotificationConsumer
    participant PE as platform.processed_event

    Note over DS,PG: Any state-changing operation (e.g. order placed, KYC decided, seller suspended)
    DS->>PG: BEGIN TX — domain rows + INSERT outbox_event
    PG-->>DS: COMMIT TX
    DS-->>DS: return API response to caller immediately

    Note over Relay,Kafka: Outbox relay loop (background)
    Relay-)PG: poll outbox_event WHERE publication_status = PENDING
    Relay-)Kafka: publish event (e.g. fulfillment.placed, seller.kyc.decided)

    Note over NC,PE: Consumer group (e.g. notification.fulfillment-placed)
    NC-)Kafka: consume event
    NC->>PE: SELECT processed_event WHERE consumer_group = ? AND event_id = ?
    alt event_id already processed
        PE-->>NC: row exists
        NC-)Kafka: commit offset (idempotent skip — no side effect)
    else not yet processed
        PE-->>NC: no row
        NC->>PG: BEGIN TX
        NC->>PG: INSERT in_app_notification (recipient_user_id, type, payload, source_event_id=event_id)
        NC->>PE: INSERT processed_event (consumer_group, event_id, processed_at, outcome)
        NC->>PG: COMMIT TX
        NC-)Kafka: commit offset
    end
```

**Notification types and their source events**

| Notification type | Source event |
|---|---|
| `ORDER_PLACED` | `fulfillment.placed` |
| `SHIPMENT_UPDATE` | `fulfillment.shipped` |
| `DELIVERY_UPDATE` | `fulfillment.delivered` |
| `KYC_DECIDED` | `seller.kyc.decided` |
| `KYC_SUBMITTED` | `seller.kyc.submitted` |
| `LOW_STOCK` | `inventory.low_stock` |
| `LISTING_REMOVED` | `moderation.listing.removed` |
| `SELLER_SUSPENDED` | `seller.suspended` |
| `SELLER_REINSTATED` | `seller.reinstated` |
| `REFUND_ISSUED` | `fulfillment.refunded`, `fulfillment.refund_suspended_seller` (§1.17 — distinct topic for auto-refunds triggered by seller suspension) |
| `ORDER_COMPLETED` | `order.completed` |
| `LISTING_FLAGGED` | `listing.flagged` |
| `FULFILLMENT_CANCELLED` | `fulfillment.cancelled` |
| `SUSPENSION_EXPIRED` | `seller.suspension_expired` |
