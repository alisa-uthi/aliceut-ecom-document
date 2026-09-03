# Profile API

**Module:** `Profile`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.1](../../requirements/BRD.md), [ERD](../data-model-erd.md)

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
    "sellerStatus": "APPROVED | null"
  }
}
```

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

    A-->>C: 200 { data: { id, email, fullName, roles, emailVerified, accountType, sellerStatus } }
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
  "businessName": "string (max 120 chars, B2B accounts only) | null",
  "businessLogoUrl": "string | null"
}
```
**Response 200** — updated profile wrapped in `data`

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant PG as Postgres

    C->>G: PATCH /profile/me {fullName?, preferredCurrency?, businessName?, businessLogoUrl?} (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, account_type, ...}

    A->>A: Validate body (preferredCurrency enum, businessName max 120 chars)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    alt businessName or businessLogoUrl supplied AND user.account_type != 'B2B'
        A-->>C: 422 Unprocessable Entity "Business fields require B2B account"
    end

    A->>PG: UPDATE identity.user SET full_name=$1, preferred_currency=$2, business_name=$3, business_logo_storage_key=$4 WHERE id=JWT.sub

    A->>PG: SELECT identity.user WHERE id = JWT.sub
    A-->>C: 200 { data: { id, email, fullName, roles, emailVerified, accountType, sellerStatus, preferredCurrency, businessName } }
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
