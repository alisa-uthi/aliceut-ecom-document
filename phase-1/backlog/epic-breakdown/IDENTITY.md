# EPIC: IDENTITY — User Identity & Profile

**Sprint:** 2  
**Total Tasks:** 6  

User profile management: editable display name/avatar, address book CRUD, and soft-delete account closure. Identity data lives in the `identity` schema, separate from auth credentials.

---

## IDENTITY-001 — identity Schema Migrations

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/identity/src/infrastructure/migrations/0001_identity_schema.sql`
- Tables:
  - `identity.user_profile`: id (same PK as `auth.user.id`), name, avatar_url nullable, bio nullable, preferred_currency (default `USD`), created_at, updated_at
  - `identity.user_address`: id (UUIDv7 PK), user_id FK → `auth.user(id)`, label (Home/Work/Other), full_name, phone, line1, line2 nullable, city, state nullable, postal_code, country_code (ISO 3166-1 alpha-2), is_default boolean, created_at
- FK: `identity.user_profile.id → auth.user.id` (1:1; created together at registration)
- Index: `user_address(user_id)`, `user_address(user_id, is_default)`
- Max 5 addresses per user (enforced in service layer, not DB)

**Done Criteria**

- All identity tables created
- `user_profile.id` FK references `auth.user(id)`; deleting user cascades to profile

---

## IDENTITY-002 — GET /profile + PATCH /profile

- **US Ref:** US-B-08, US-S-02
- **Estimate:** M
- **Dependencies:** IDENTITY-001
- **Spec References:** `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- Both endpoints: `@JwtAuthGuard` (any role)
- `GET /profile` — returns `{ id, email, role, name, avatarUrl, bio, preferredCurrency, emailVerified }`; joins `auth.user` + `identity.user_profile`
- `PATCH /profile { name?, bio?, preferredCurrency? }` — partial update; `preferredCurrency` must be in allowed set (`USD`|`THB`|`JPY`|`SGD`)
- `name`: 2–100 chars; `bio`: max 500 chars
- Response: updated profile object
- File: `libs/identity/src/api/profile.controller.ts`

**Done Criteria**

- GET /profile returns merged auth + identity fields
- PATCH with invalid preferredCurrency → 400
- PATCH with no fields → 200 (idempotent)

---

## IDENTITY-003 — POST /profile/avatar (avatar upload)

- **US Ref:** US-B-08
- **Estimate:** M
- **Dependencies:** IDENTITY-001, SHARED-006
- **Spec References:** `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/docker-compose-topology.md`

**Implementation Notes**

- `POST /profile/avatar` — multipart, single image file
- Constraints: JPEG/PNG/WebP only; max 2MB
- Upload to MinIO `user-assets` bucket; key: `avatars/{userId}/{uuid}.{ext}`
- Update `identity.user_profile.avatar_url` with presigned URL or storage key
- Delete old avatar from MinIO on overwrite (if previous `avatar_url` exists)
- Response: `{ avatarUrl: string }` — presigned URL (900s TTL for private bucket)

**Done Criteria**

- Upload PNG → avatar_url updated; presigned URL returns image
- File > 2MB → 400
- Non-image MIME → 400
- Uploading new avatar removes old file from MinIO

---

## IDENTITY-004 — Address Book CRUD

- **US Ref:** US-B-08
- **Estimate:** M
- **Dependencies:** IDENTITY-001
- **Spec References:** `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `GET /profile/addresses` — list all addresses for authenticated user (max 5)
- `POST /profile/addresses { label, fullName, phone, line1, line2?, city, state?, postalCode, countryCode, isDefault }`:
  - Max 5 addresses → 422 `ADDRESS_LIMIT_REACHED` if at limit
  - If `isDefault: true`: unset `is_default` on all other addresses for user
  - Returns created address (201)
- `PUT /profile/addresses/:id { ...fields }` — full replacement; ownership check
- `DELETE /profile/addresses/:id` — hard delete; if was default and others exist, set first remaining as default
- Ownership check: address must belong to authenticated user (404 if not found or not owned)
- File: `libs/identity/src/api/address.controller.ts`

**Done Criteria**

- 5 addresses already: POST → 422
- `isDefault: true` on new address → all others `is_default = false`
- Delete default address → first remaining set as default
- Access another user's address → 404

---

## IDENTITY-005 — Account Closure (POST /profile/close-account)

- **US Ref:** US-B-08
- **Estimate:** M
- **Dependencies:** IDENTITY-001, AUTH-008
- **Spec References:** `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /profile/close-account { password: string }` — requires `@JwtAuthGuard` (any authenticated user)
- Verify password (same as LOCAL auth — must call local strategy validate)
- Precondition checks:
  - If role = `SELLER`: reject if seller has any PENDING orders → 422 `PENDING_ORDERS_EXIST`
  - If role = `ADMIN`: reject → 422 `ADMIN_CANNOT_CLOSE` (must be removed by another admin)
- Soft-close: set `auth.user.status = 'CLOSED'`; anonymize `identity.user_profile { name: 'Deleted User', avatarUrl: null, bio: null }`
- Force-logout: revoke all refresh tokens + Redis blacklist
- Data retained for legal hold (order history etc.)
- Response: 200 `{ message: "Account closed." }`

**Done Criteria**

- Wrong password → 401
- SELLER with pending orders → 422
- ADMIN → 422
- Valid closure: user status = CLOSED; profile anonymized; can no longer login

---

## IDENTITY-006 — GET /profile/:id (public profile view)

- **US Ref:** US-B-05
- **Estimate:** S
- **Dependencies:** IDENTITY-001
- **Spec References:** `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `GET /profile/:id` — public endpoint (`@Public()`); returns limited public view
- Response: `{ id, name, avatarUrl, memberSince }` — no email, no addresses, no private fields
- CLOSED accounts → 404 (not found)
- Used on product detail page "Sold by [seller name]" link + seller profile view
- File: `libs/identity/src/api/profile.controller.ts`

**Done Criteria**

- Public call returns name + avatar only; no email
- Closed account → 404
- Requires no auth token
