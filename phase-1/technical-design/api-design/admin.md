# Admin API — Administration

**Module:** `Admin`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.1](../../requirements/BRD.md), [ERD](../data-model-erd.md)

> **Auth note:** Routes under `/admin/*` return `HTTP 403` for both unauthenticated requests (no/invalid token) and unauthorized requests (valid token but not ADMIN role), to avoid leaking the existence of admin-only routes.

---

## Summary

- [Endpoint Index](#endpoint-index)
- [DB Mapping](#db-mapping)
- [Endpoints](#endpoints)

<a id="endpoint-index"></a>
## Endpoint Index

> All `/admin/*` endpoints return `403` for both unauthenticated (missing/invalid token) and unauthorized (valid token, role ≠ ADMIN) requests.

| Group | Method | Path | Auth | Description |
|-------|--------|------|------|-------------|
| KYC | `GET` | [`/admin/kyc`](#list-kyc-applications) | ADMIN | List KYC applications (offset-paginated) |
| KYC | `GET` | [`/admin/kyc/:id`](#get-kyc-application-detail) | ADMIN | KYC detail — view logged to MongoDB |
| KYC | `POST` | [`/admin/kyc/:id/decide`](#decide-kyc-application) | ADMIN | Approve or reject KYC — decision logged to MongoDB |
| Sellers | `GET` | [`/admin/sellers`](#list-sellers) | ADMIN | List all sellers |
| Sellers | `GET` | [`/admin/sellers/:id`](#get-seller-detail-admin) | ADMIN | Seller detail |
| Sellers | `POST` | [`/admin/sellers/:id/suspend`](#suspend-seller) | ADMIN | Suspend seller — logged to MongoDB |
| Sellers | `POST` | [`/admin/sellers/:id/reinstate`](#reinstate-seller) | ADMIN | Reinstate suspended seller |
| Moderation | `GET` | [`/admin/moderation`](#list-moderation-queue) | ADMIN | List moderation queue |
| Moderation | `GET` | [`/admin/moderation/:id`](#get-moderation-case) | ADMIN | Moderation case detail |
| Moderation | `POST` | [`/admin/moderation/:id/decide`](#decide-moderation-case) | ADMIN | REMOVE or DISMISS listing |
| Moderation | `POST` | [`/admin/moderation`](#create-moderation-case-manual-flag) | ADMIN | Manually flag a listing |
| Stats | `GET` | [`/admin/dashboard/stats`](#admin-dashboard-stats) | ADMIN | Dashboard counts |

---

<a id="db-mapping"></a>
## DB Mapping

| Endpoint | Primary DB | Tables / Notes |
|----------|-----------|----------------|
| `GET /admin/kyc` | Postgres | `seller.kyc_application`, `seller.seller_profile` |
| `GET /admin/kyc/:id` | Postgres + **MongoDB** | `seller.kyc_application` (read); document view logged to `audit_logs` collection |
| `POST /admin/kyc/:id/decide` | Postgres + **MongoDB** | `seller.kyc_application`, `seller.seller_profile`, `platform.outbox_event` (`seller.kyc.decided`); decision logged to `audit_logs` |
| `GET /admin/sellers` | Postgres | `seller.seller_profile`, `identity.user`, `catalog.offer` (counts) |
| `GET /admin/sellers/:id` | Postgres | `seller.seller_profile`, `identity.user` |
| `POST /admin/sellers/:id/suspend` | Postgres + **MongoDB** | `seller.seller_profile`, `catalog.offer` (deactivate), `platform.outbox_event` (`seller.suspended`); logged to `audit_logs` |
| `POST /admin/sellers/:id/reinstate` | Postgres | `seller.seller_profile`, `catalog.offer` (re-enable), `platform.outbox_event` (`seller.reinstated`) |
| `GET /admin/moderation` | Postgres | `admin.moderation_case`, `catalog.offer` |
| `GET /admin/moderation/:id` | Postgres | `admin.moderation_case` |
| `POST /admin/moderation/:id/decide` | Postgres | `admin.moderation_case`, `catalog.offer` (status → REMOVED), `platform.outbox_event` (`moderation.listing.removed`); ES deindex async via consumer |
| `POST /admin/moderation` | Postgres | `admin.moderation_case` (manual flag insert) |
| `GET /admin/dashboard/stats` | Postgres | `seller.kyc_application`, `admin.moderation_case`, `seller.seller_profile` (counts) |

---

<a id="endpoints"></a>
## Endpoints

### List KYC applications

```
GET /admin/kyc
Tag: Admin
Auth: ADMIN
Pagination: offset
```
**Query params:** `status` (`PENDING | APPROVED | REJECTED`), `country` (ISO 3166-1 alpha-2 filter), `limit`, `offset`  
**Response 200**
```json
{
  "data": [{
    "id": "uuid",
    "sellerId": "uuid",
    "businessName": "string",
    "country": "string (ISO 3166-1)",
    "status": "PENDING",
    "submittedAt": "ISO8601"
  }],
  "meta": { "total": 15, "limit": 20, "offset": 0 }
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres

    C->>API: GET /admin/kyc
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: listKycApplications(filters, pagination)
        S->>PG: SELECT kyc_application JOIN seller_profile WHERE status=? LIMIT/OFFSET
        PG-->>S: rows + total count
        S-->>API: paginated list
        API-->>C: 200 { data[], meta }
    end
```

---

### Get KYC application detail

```
GET /admin/kyc/:applicationId
Tag: Admin
Auth: ADMIN
```
**Response 200**
```json
{
  "data": {
    "id": "uuid",
    "seller": { "id": "uuid", "businessName": "string", "taxId": "REDACTED_UNLESS_ADMIN" },
    "submittedData": {},
    "documentUrls": ["signed-url (short TTL)"],
    "status": "PENDING",
    "submittedAt": "ISO8601"
  }
}
```
Document view logged to MongoDB `audit_logs`.

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres
    participant MDB as MongoDB (audit_logs)

    C->>API: GET /admin/kyc/:applicationId
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: getKycDetail(applicationId)
        S->>PG: SELECT kyc_application JOIN seller_profile, generate presigned doc URLs
        PG-->>S: application data + document references
        S->>MDB: INSERT audit_logs { action: KYC_DOC_VIEW, actor: adminId, entity: applicationId }
        MDB-->>S: ack
        S-->>API: application with documentUrls
        API-->>C: 200 { data: { id, seller, submittedData, documentUrls, status } }
    end
```

---

### Decide KYC application

```
POST /admin/kyc/:applicationId/decide
Tag: Admin
Auth: ADMIN
```
**Request body**
```json
{ "decision": "APPROVED | REJECTED", "reason": "string (required if REJECTED)" }
```
**Response 200** `{ "data": { "status": "APPROVED | REJECTED" } }`  
Side effects: `seller.kyc.decided` event, `SellerProfile.kyc_status` updated  
**Errors:** 409 already decided

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres
    participant MDB as MongoDB (audit_logs)
    participant Relay as Kafka Relay

    C->>API: POST /admin/kyc/:applicationId/decide
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: decideKyc(applicationId, decision, reason)
        S->>PG: SELECT kyc_application.status
        alt status != PENDING
            PG-->>S: already decided
            S-->>C: 409 Conflict
        else status = PENDING
            Note over S,PG: Atomic Postgres transaction
            S->>PG: BEGIN TX
            S->>PG: UPDATE kyc_application SET status, reviewer_user_id, decided_at
            S->>PG: UPDATE seller_profile SET kyc_status = decision
            S->>PG: INSERT outbox_event (seller.kyc.decided)
            S->>PG: COMMIT TX
            S->>MDB: INSERT audit_logs { KYC_DECIDED, decision, reviewer }
            MDB-->>S: ack
            S-->>C: 200 { data: { status: APPROVED | REJECTED } }
            Note over Relay: async — independent of response
            Relay-)PG: poll outbox_event WHERE publication_status = PENDING
            Relay-)Relay: publish seller.kyc.decided to Kafka
        end
    end
```

---

### List sellers

```
GET /admin/sellers
Tag: Admin
Auth: ADMIN
Pagination: offset
```
**Query params:** `kycStatus` (`PENDING_KYC | APPROVED | REJECTED`), `suspensionStatus` (`ACTIVE | SUSPENDED`), `q` (free-text search across `business_name`, `email`, `tax_id`), `limit`, `offset`  
**Response 200**
```json
{
  "data": [{
    "id": "uuid",
    "businessName": "string",
    "email": "string",
    "country": "string (ISO 3166-1)",
    "kycStatus": "APPROVED",
    "suspensionStatus": "ACTIVE",
    "activeListingsCount": 0,
    "removedListingsCount": 0,
    "submittedAt": "ISO8601"
  }],
  "meta": { "total": 42, "limit": 20, "offset": 0 }
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres

    C->>API: GET /admin/sellers
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: listSellers(filters, pagination)
        S->>PG: SELECT seller_profile JOIN identity.user, COUNT(offer) WHERE filters LIMIT/OFFSET
        PG-->>S: rows + total count
        S-->>API: paginated list
        API-->>C: 200 { data[], meta }
    end
```

---

### Get seller detail (admin)

```
GET /admin/sellers/:sellerId
Tag: Admin
Auth: ADMIN
```
**Response 200**
```json
{
  "data": {
    "id": "uuid",
    "businessName": "string",
    "taxId": "string",
    "email": "string",
    "country": "string (ISO 3166-1)",
    "kycStatus": "APPROVED",
    "suspensionStatus": "ACTIVE",
    "rejectionReason": "string | null",
    "submittedData": {},
    "activeListingsCount": 0,
    "removedListingsCount": 0,
    "createdAt": "ISO8601"
  }
}
```
**Errors:** 404

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres

    C->>API: GET /admin/sellers/:sellerId
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: getSellerDetail(sellerId)
        S->>PG: SELECT seller_profile JOIN identity.user, COUNT(offer) WHERE id = ?
        alt not found
            PG-->>S: 0 rows
            S-->>C: 404 Not Found
        else found
            PG-->>S: seller row with listing counts
            S-->>API: seller detail
            API-->>C: 200 { data: { id, businessName, taxId, kycStatus, suspensionStatus, ... } }
        end
    end
```

---

### Suspend seller

```
POST /admin/sellers/:sellerId/suspend
Tag: Admin
Auth: ADMIN
```
**Request body**
```json
{
  "reason": "string",
  "durationDays": "number | null (null = permanent; valid values: 7, 30, 90, null)"
}
```
**Response 200** `{ "data": { "status": "SUSPENDED" } }`  
Side effects: `seller.suspended` event; moderation logged to MongoDB `audit_logs`  
**Errors:** 409 already suspended, 422 invalid `durationDays` value

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres
    participant MDB as MongoDB (audit_logs)
    participant Relay as Kafka Relay
    participant SC as search.seller-suspended
    participant ES as Elasticsearch

    C->>API: POST /admin/sellers/:sellerId/suspend
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: suspendSeller(sellerId, reason, durationDays)
        S->>PG: SELECT seller_profile.suspension_status
        alt already SUSPENDED
            PG-->>S: SUSPENDED
            S-->>C: 409 Conflict
        else ACTIVE
            PG-->>S: ACTIVE
            Note over S,PG: Atomic Postgres transaction
            S->>PG: BEGIN TX
            S->>PG: UPDATE seller_profile SET suspension_status=SUSPENDED, suspended_until, suspension_reason
            S->>PG: UPDATE catalog.offer SET status=INACTIVE, status_changed_reason=SUSPENSION WHERE seller_id=? AND status=ACTIVE
            S->>PG: INSERT outbox_event (seller.suspended, payload includes offer_ids)
            S->>PG: COMMIT TX
            S->>MDB: INSERT audit_logs { SELLER_SUSPENDED, actor, reason, duration }
            MDB-->>S: ack
            S-->>C: 200 { data: { status: SUSPENDED } }
            Note over Relay,ES: async cascade
            Relay-)PG: poll outbox_event WHERE publication_status = PENDING
            Relay-)Relay: publish seller.suspended to Kafka
            SC-)SC: consume seller.suspended
            SC->>ES: deindex all offer_ids from search index
        end
    end
```

---

### Reinstate seller

```
POST /admin/sellers/:sellerId/reinstate
Tag: Admin
Auth: ADMIN
```
**Response 200** `{ "data": { "suspensionStatus": "ACTIVE" } }`  
Side effects: `seller.reinstated` Kafka event emitted; search consumer re-enables seller's active offers in Elasticsearch  
**Errors:** 409 seller not currently suspended

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres
    participant Relay as Kafka Relay
    participant SC as search.seller-reinstated
    participant ES as Elasticsearch

    C->>API: POST /admin/sellers/:sellerId/reinstate
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: reinstateSeller(sellerId)
        S->>PG: SELECT seller_profile.suspension_status
        alt not suspended
            PG-->>S: ACTIVE
            S-->>C: 409 Conflict
        else SUSPENDED
            PG-->>S: SUSPENDED
            Note over S,PG: Atomic Postgres transaction
            S->>PG: BEGIN TX
            S->>PG: UPDATE seller_profile SET suspension_status=ACTIVE, suspended_until=NULL
            S->>PG: UPDATE catalog.offer SET status=ACTIVE WHERE seller_id=? AND status_changed_reason=SUSPENSION
            S->>PG: INSERT outbox_event (seller.reinstated, reactivated offer_ids)
            S->>PG: COMMIT TX
            S-->>C: 200 { data: { suspensionStatus: ACTIVE } }
            Note over Relay,ES: async cascade
            Relay-)PG: poll outbox_event WHERE publication_status = PENDING
            Relay-)Relay: publish seller.reinstated to Kafka
            SC-)SC: consume seller.reinstated
            SC->>ES: re-enable seller offers in search index
        end
    end
```

---

### List moderation queue

```
GET /admin/moderation
Tag: Admin
Auth: ADMIN
Pagination: offset
```
**Query params:** `status` (`OPEN | RESOLVED | DISMISSED`), `limit`, `offset`  
**Response 200**
```json
{
  "data": [{
    "id": "uuid",
    "offerId": "uuid",
    "productTitle": "string",
    "sellerName": "string",
    "reason": "string",
    "source": "AUTOMATED | MANUAL",
    "status": "OPEN",
    "createdAt": "ISO8601"
  }],
  "meta": { "total": 3, "limit": 20, "offset": 0 }
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres

    C->>API: GET /admin/moderation
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: listModerationCases(filters, pagination)
        S->>PG: SELECT moderation_case JOIN catalog.offer WHERE status=? LIMIT/OFFSET
        PG-->>S: rows + total count
        S-->>API: paginated list
        API-->>C: 200 { data[], meta }
    end
```

---

### Get moderation case

```
GET /admin/moderation/:caseId
Tag: Admin
Auth: ADMIN
```

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres

    C->>API: GET /admin/moderation/:caseId
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: getModerationCase(caseId)
        S->>PG: SELECT moderation_case WHERE id = ?
        PG-->>S: case row
        S-->>API: case detail
        API-->>C: 200 { data: { id, offerId, reason, source, status, decision, ... } }
    end
```

---

### Decide moderation case

```
POST /admin/moderation/:caseId/decide
Tag: Admin
Auth: ADMIN
```
**Request body** `{ "decision": "REMOVE | DISMISS", "reason": "string" }`  
**Response 200**  
Side effects: if `REMOVE` → `offer.status = REMOVED`, `moderation.listing.removed` Kafka event emitted; Elasticsearch deindex happens **async** via `search.listing-removed` consumer  
**Errors:** 409 already decided

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres
    participant Relay as Kafka Relay
    participant SC as search.listing-removed
    participant ES as Elasticsearch

    C->>API: POST /admin/moderation/:caseId/decide
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: decideModerationCase(caseId, decision, reason)
        S->>PG: SELECT moderation_case.status
        alt status != OPEN
            PG-->>S: already decided
            S-->>C: 409 Conflict
        else status = OPEN
            alt decision = REMOVE
                Note over S,PG: Atomic Postgres transaction
                S->>PG: BEGIN TX
                S->>PG: UPDATE moderation_case SET status=RESOLVED, decision=REMOVE, decided_at, decided_by_user_id
                S->>PG: UPDATE catalog.offer SET status=REMOVED
                S->>PG: INSERT outbox_event (moderation.listing.removed)
                S->>PG: COMMIT TX
                S-->>C: 200 { data: { decision: REMOVE } }
                Note over Relay,ES: async cascade
                Relay-)PG: poll outbox_event WHERE publication_status = PENDING
                Relay-)Relay: publish moderation.listing.removed to Kafka
                SC-)SC: consume moderation.listing.removed
                SC->>ES: deindex offer from search
            else decision = DISMISS
                Note over S,PG: Atomic Postgres transaction
                S->>PG: BEGIN TX
                S->>PG: UPDATE moderation_case SET status=DISMISSED, decided_at, decided_by_user_id
                S->>PG: UPDATE catalog.offer SET status=ACTIVE
                S->>PG: COMMIT TX
                S-->>C: 200 { data: { decision: DISMISS } }
            end
        end
    end
```

---

### Create moderation case (manual flag)

```
POST /admin/moderation
Tag: Admin
Auth: ADMIN
```
**Request body** `{ "offerId": "uuid", "reason": "string", "source": "MANUAL" }`  
**Response 201**

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres

    C->>API: POST /admin/moderation
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: createModerationCase(offerId, reason)
        Note over S,PG: Atomic Postgres transaction
        S->>PG: BEGIN TX
        S->>PG: INSERT moderation_case (offerId, reason, source=MANUAL, status=OPEN)
        S->>PG: UPDATE catalog.offer SET status=FLAGGED WHERE id = offerId
        S->>PG: COMMIT TX
        S-->>C: 201 { data: { id, offerId, reason, source, status: OPEN } }
    end
```

---

### Admin dashboard stats

```
GET /admin/dashboard/stats
Tag: Admin
Auth: ADMIN
```
**Response 200**
```json
{
  "data": {
    "pendingKyc": 0,
    "flaggedListings": 0,
    "activeSuspensions": 0,
    "openModerationCases": 0
  }
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant G as AdminGuard
    participant S as AdminService
    participant PG as Postgres

    C->>API: GET /admin/dashboard/stats
    API->>G: verify token + ADMIN role
    alt no valid ADMIN token
        G-->>C: 403 Forbidden
    else ADMIN role confirmed
        G-->>API: pass
        API->>S: getDashboardStats()
        par aggregate queries
            S->>PG: COUNT kyc_application WHERE status = PENDING
        and
            S->>PG: COUNT moderation_case WHERE status = OPEN
        and
            S->>PG: COUNT seller_profile WHERE suspension_status = SUSPENDED
        end
        PG-->>S: counts
        S-->>C: 200 { data: { pendingKyc, flaggedListings, activeSuspensions, openModerationCases } }
    end
```
