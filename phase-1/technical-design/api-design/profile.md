# Profile API

**Module:** `Profile`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.2](../../requirements/BRD.md), [ERD](../data-model-erd.md)

---

## Summary

- [Endpoint Index](#endpoint-index)
- [DB Mapping](#db-mapping)
- [Endpoints](#endpoints)

<a id="endpoint-index"></a>
## Endpoint Index

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | [`/profile/me`](#get-own-profile) | JWT | Get authenticated user's profile |
| `PATCH` | [`/profile/me`](#update-profile) | JWT | Update profile fields |
| `POST` | [`/profile/me/logo`](#upload-business-logo) | JWT | Upload business logo to MinIO; returns storage key |
| `GET` | [`/profile/addresses`](#list-saved-addresses) | BUYER | List saved addresses |
| `POST` | [`/profile/addresses`](#create-address) | BUYER | Add new address (max 10) |
| `PATCH` | [`/profile/addresses/:id`](#update-address) | BUYER | Update address fields |
| `DELETE` | [`/profile/addresses/:id`](#delete-address) | BUYER | Remove address |
| `PATCH` | [`/profile/addresses/:id/default`](#set-default-address) | BUYER | Set address as default |

---

<a id="db-mapping"></a>
## DB Mapping

| Endpoint | Primary DB | Tables |
|----------|-----------|--------|
| `GET /profile/me` | Postgres | `identity.user` (read) |
| `PATCH /profile/me` | Postgres | `identity.user` (update) |
| `POST /profile/me/logo` | MinIO + Postgres | Upload logo to `user-assets` bucket; store object key in `identity.user.business_logo_storage_key` |
| `GET /profile/addresses` | Postgres | `identity.address` (read list) |
| `POST /profile/addresses` | Postgres | `identity.address` (insert; max 10 per user) |
| `PATCH /profile/addresses/:id` | Postgres | `identity.address` (update) |
| `DELETE /profile/addresses/:id` | Postgres | `identity.address` (hard delete) |
| `PATCH /profile/addresses/:id/default` | Postgres | `identity.address` (toggle `is_default`) |

---

<a id="endpoints"></a>
## Endpoints

### Get own profile

```
GET /profile/me
Tag: Profile
Auth: JWT
```
**Response 200**
```json
{
  "data": {
    "id": "uuid",
    "email": "string",
    "fullName": "string",
    "roles": ["BUYER"],
    "emailVerified": true,
    "accountType": "B2C",
    "sellerStatus": "APPROVED | null",
    "preferredCurrency": "USD | THB | JPY | SGD | AUTO | null",
    "businessName": "string | null",
    "businessLogoUrl": "string | null"
  }
}
```

**Notes:**
- `preferredCurrency` drives display currency resolution across buyer and seller portals. `null` and `"AUTO"` both resolve from `Accept-Language` at request time.
- `businessName` and `businessLogoUrl` are non-null only for `accountType = B2B`. `businessLogoUrl` is a presigned URL (1-hour TTL) generated from `identity.user.business_logo_storage_key`.

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant PG as Postgres

    C->>G: GET /profile/me (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, roles, ...}

    A->>PG: SELECT identity.user WHERE id = JWT.sub
    Note over A: If business_logo_storage_key is set, generate presigned URL (1h TTL) from user-assets bucket

    A-->>C: 200 { data: { id, email, fullName, roles, emailVerified, accountType, sellerStatus, preferredCurrency, businessName, businessLogoUrl } }
```

---

### Update profile

```
PATCH /profile/me
Tag: Profile
Auth: JWT
```
**Request body** (all optional)
```json
{
  "fullName": "string",
  "preferredCurrency": "USD | THB | JPY | SGD | AUTO | null",
  "businessName": "string (max 120 chars, B2B accounts only) | null"
}
```
**`preferredCurrency` semantics:**
- ISO 4217 code (`"USD"`, `"THB"`, `"JPY"`, `"SGD"`): display prices converted to that currency using live FX rates.
- `"AUTO"`: resolve display currency from `Accept-Language` header at each request.
- `null`: treated identically to `"AUTO"`.
- The display currency is resolved at checkout submission time and snapshotted as `fulfillment.buyer_display_currency` on each fulfillment. Subsequent profile changes do not alter historical order display.

**Response 200** — updated profile wrapped in `data`

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant PG as Postgres

    C->>G: PATCH /profile/me {fullName?, preferredCurrency?, businessName?} (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, account_type, ...}

    A->>A: Validate body (preferredCurrency enum, businessName max 120 chars)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    alt businessName supplied AND user.account_type != 'B2B'
        A-->>C: 422 Unprocessable Entity "Business fields require B2B account"
    end

    A->>PG: UPDATE identity.user SET full_name=$1, preferred_currency=$2, business_name=$3 WHERE id=JWT.sub

    A->>PG: SELECT identity.user WHERE id = JWT.sub
    A-->>C: 200 { data: { id, email, fullName, roles, emailVerified, accountType, sellerStatus, preferredCurrency, businessName } }
```

---

<a id="upload-business-logo"></a>
### Upload business logo

```
POST /profile/me/logo
Tag: Profile
Auth: JWT
```
**Request:** `multipart/form-data` — single file field `logo` (JPEG/PNG/WebP, max 2 MB).  
**Response 200** — updated profile with new `businessLogoUrl`
```json
{ "data": { "businessLogoUrl": "https://minio.../presigned-url" } }
```
**Errors:** 400 invalid file type or size, 422 non-B2B account

**Notes:**
- Server generates a UUID filename; client-supplied filename is ignored.
- File stored in `user-assets` bucket under key `user-assets/logos/{userId}/{uuid}.{ext}`.
- After upload, `identity.user.business_logo_storage_key` is updated in the same request.
- Presigned URL in response has 1-hour TTL.

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant PG as Postgres
    participant MinIO as MinIO (user-assets)

    C->>G: POST /profile/me/logo multipart/form-data {logo: file} (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, account_type, ...}

    alt account_type != B2B
        A-->>C: 422 Unprocessable Entity "Business logo requires B2B account"
    end

    A->>A: Validate file (MIME type, size <= 2 MB)
    alt validation fails
        A-->>C: 400 Bad Request
    end

    A->>MinIO: PUT user-assets/logos/{userId}/{uuid}.{ext}
    MinIO-->>A: object stored

    A->>PG: UPDATE identity.user SET business_logo_storage_key = :key WHERE id = JWT.sub

    A->>MinIO: Generate presigned GET URL (1h TTL)
    MinIO-->>A: presigned URL
    A-->>C: 200 { data: { businessLogoUrl: "presigned-url" } }
```

---

### List saved addresses

```
GET /profile/addresses
Tag: Profile
Auth: BUYER
Pagination: none (typically small list)
```
**Response 200**
```json
{
  "data": [{
    "id": "uuid",
    "label": "Home",
    "recipientName": "string",
    "addressLine1": "string",
    "addressLine2": "string | null",
    "city": "string",
    "stateRegion": "string | null",
    "postalCode": "string",
    "countryCode": "TH",
    "isDefault": true
  }]
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as Guard
    participant A as NestJS API
    participant PG as Postgres

    C->>G: GET /profile/addresses (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>G: Check roles contains 'BUYER'
    alt BUYER role missing
        G-->>C: 403 Forbidden
    end
    G->>A: proceed with decoded JWT {sub, roles, ...}

    A->>PG: SELECT identity.address WHERE user_id = JWT.sub ORDER BY is_default DESC, created_at ASC

    A-->>C: 200 {data: [address, ...]}
```

---

### Create address

```
POST /profile/addresses
Tag: Profile
Auth: BUYER
```
**Request body** — same fields as list item (minus `id`, `isDefault`)  
**Limit:** Max 10 addresses per user; returns HTTP 422 with message "Address limit reached (max 10)" when exceeded.  
**Response 201** — created address wrapped in `data`  
**Errors:** 422 address limit reached

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as Guard
    participant A as NestJS API
    participant PG as Postgres

    C->>G: POST /profile/addresses {label?, recipientName, addressLine1, city, postalCode, countryCode, ...} (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>G: Check roles contains 'BUYER'
    alt BUYER role missing
        G-->>C: 403 Forbidden
    end
    G->>A: proceed with decoded JWT {sub, roles, ...}

    A->>A: Validate body (recipientName, addressLine1, city, postalCode, countryCode required)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>PG: SELECT COUNT(*) FROM identity.address WHERE user_id = JWT.sub
    alt count >= 10
        A-->>C: 422 Unprocessable Entity "Address limit reached (max 10)"
    end

    A->>PG: INSERT identity.address (user_id, label, recipient_name, address_line_1, address_line_2, city, state_region, postal_code, country_code, is_default=false)

    A->>PG: SELECT identity.address WHERE id = inserted_id
    A-->>C: 201 { data: { id, label, recipientName, addressLine1, city, postalCode, countryCode, isDefault, ... } }
```

---

### Update address

```
PATCH /profile/addresses/:addressId
Tag: Profile
Auth: BUYER
```
**Request body** (all optional) — subset of address fields  
**Errors:** 404 not found, 403 not owner

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as Guard
    participant A as NestJS API
    participant PG as Postgres

    C->>G: PATCH /profile/addresses/:addressId {field?...} (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>G: Check roles contains 'BUYER'
    alt BUYER role missing
        G-->>C: 403 Forbidden
    end
    G->>A: proceed with decoded JWT {sub, roles, ...}

    A->>A: Validate body (at least one field present, field constraints)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>PG: SELECT identity.address WHERE id = addressId
    alt address not found
        A-->>C: 404 Not Found
    end
    alt address.user_id != JWT.sub
        A-->>C: 403 Forbidden
    end

    A->>PG: UPDATE identity.address SET ...changed_fields WHERE id = addressId

    A->>PG: SELECT identity.address WHERE id = addressId
    A-->>C: 200 { data: { id, label, recipientName, addressLine1, city, postalCode, countryCode, isDefault, ... } }
```

---

### Delete address

```
DELETE /profile/addresses/:addressId
Tag: Profile
Auth: BUYER
```
**Response 204**  
**Errors:** 404, 403

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as Guard
    participant A as NestJS API
    participant PG as Postgres

    C->>G: DELETE /profile/addresses/:addressId (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>G: Check roles contains 'BUYER'
    alt BUYER role missing
        G-->>C: 403 Forbidden
    end
    G->>A: proceed with decoded JWT {sub, roles, ...}

    A->>PG: SELECT identity.address WHERE id = addressId
    alt address not found
        A-->>C: 404 Not Found
    end
    alt address.user_id != JWT.sub
        A-->>C: 403 Forbidden
    end

    A->>PG: DELETE FROM identity.address WHERE id = addressId

    A-->>C: 204 No Content
```

---

### Set default address

```
PATCH /profile/addresses/:addressId/default
Tag: Profile
Auth: BUYER
```
**Response 200** — updated address with `isDefault: true`

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as Guard
    participant A as NestJS API
    participant PG as Postgres

    C->>G: PATCH /profile/addresses/:addressId/default (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>G: Check roles contains 'BUYER'
    alt BUYER role missing
        G-->>C: 403 Forbidden
    end
    G->>A: proceed with decoded JWT {sub, roles, ...}

    A->>PG: SELECT identity.address WHERE id = addressId
    alt address not found
        A-->>C: 404 Not Found
    end
    alt address.user_id != JWT.sub
        A-->>C: 403 Forbidden
    end

    A->>PG: BEGIN TRANSACTION
    A->>PG: UPDATE identity.address SET is_default=false WHERE user_id=JWT.sub AND is_default=true
    A->>PG: UPDATE identity.address SET is_default=true WHERE id=addressId
    A->>PG: COMMIT

    A->>PG: SELECT identity.address WHERE id = addressId
    A-->>C: 200 { data: { id, label, recipientName, addressLine1, city, postalCode, countryCode, isDefault: true, ... } }
```
