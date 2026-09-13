# EPIC: IDENTITY — User Identity & Profile

**Sprint:** 2  
**Total Tasks:** 6  

Buyer/seller profile management: display name + preferred currency, B2B business name/logo, and address book CRUD. Profile data lives in `identity.user` / `identity.address` (schema owned by AUTH-001 — see `epic-breakdown/AUTH.md` AUTH-001; this epic adds no migrations of its own).

---

## IDENTITY-001 — GET /profile/me + PATCH /profile/me

- **US Ref:** US-B-15
- **Estimate:** M
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/profile.md`

**Implementation Notes**

- Both endpoints: `@JwtAuthGuard` (any role)
- Path is `/profile/me` (not `/profile`) per spec
- Request/response field shapes, `preferredCurrency` semantics (ISO code | `AUTO` | `null`), and `identity.user` DB mapping exactly per spec — see spec, don't restate here
- `businessName` is one of `PATCH /profile/me`'s optional fields; B2B-only validation covered in IDENTITY-005
- File: `libs/identity/src/api/profile.controller.ts`

**Done Criteria**

- `GET /profile/me` returns `identity.user` fields wrapped in `data`, per spec's response shape
- `PATCH /profile/me` with invalid `preferredCurrency` → 400
- `PATCH /profile/me` with no fields → 200 (idempotent)

---

## IDENTITY-002 — Address Book CRUD (GET/POST/PATCH/DELETE /profile/addresses)

- **US Ref:** US-B-14
- **Estimate:** M
- **Dependencies:** AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/profile.md`

**Implementation Notes**

- Four endpoints, all `@JwtAuthGuard` + BUYER role check (403 if role missing)
- Uses `PATCH` for partial update (not `PUT`)
- Request/response field shapes and `identity.address` DB mapping exactly per spec — see spec, don't restate here
- Ownership check on `PATCH`/`DELETE`: 404 if address not found, 403 if found but not owned by caller (distinct codes per spec's sequences)
- File: `libs/identity/src/api/address.controller.ts`

**Done Criteria**

- CRUD round-trip works; `PATCH` partial update only changes supplied fields
- Address not found → 404; address owned by another user → 403
- `DELETE` returns 204

---

## IDENTITY-003 — Address Limit Enforcement (max 10 per user)

- **US Ref:** US-B-14
- **Estimate:** S
- **Dependencies:** IDENTITY-002
- **Spec References:** `phase-1/technical-design/api-design/profile.md`

**Implementation Notes**

- Enforced in `POST /profile/addresses` handler (service layer, not a DB constraint)
- Count existing `identity.address` rows for the user; at 10, reject with 422 `"Address limit reached (max 10)"` — exact message per spec

**Done Criteria**

- 10 addresses already saved: `POST` → 422 with spec's exact message
- 9 addresses saved: `POST` succeeds (201)

---

## IDENTITY-004 — Default Address Logic

- **US Ref:** US-B-14
- **Estimate:** S
- **Dependencies:** IDENTITY-002
- **Spec References:** `phase-1/technical-design/api-design/profile.md`

**Implementation Notes**

- `PATCH /profile/addresses/:id/default` — transactional unset-then-set (only one default at a time); exact sequence per spec, don't restate here
- New addresses are always created with `isDefault: false` (`POST /profile/addresses`) — no auto-default-on-first-address logic in spec
- `DELETE` of the current default address does **not** auto-promote another address to default in spec — no server-side reassignment on delete (FE-side "pick a new default" prompt, if any, is a frontend concern, not this task)

**Done Criteria**

- `PATCH .../default` unsets any previous default before setting the new one
- `POST /profile/addresses` never returns `isDefault: true`
- Deleting the default address leaves no address marked default (no auto-reassignment)

---

## IDENTITY-005 — B2B Business Name Field

- **US Ref:** US-B-15
- **Estimate:** S
- **Dependencies:** IDENTITY-001
- **Spec References:** `phase-1/technical-design/api-design/profile.md`

**Implementation Notes**

- No separate `/profile/business` endpoint — `businessName` is validated and persisted as part of `PATCH /profile/me` (IDENTITY-001)
- 422 if `businessName` supplied for a non-`B2B` `accountType`; max 120 chars — exact validation per spec's Update profile sequence
- Column: `identity.user.business_name`

**Done Criteria**

- B2B account: `PATCH /profile/me { businessName }` → 200, persisted
- B2C account: `PATCH /profile/me { businessName }` → 422

---

## IDENTITY-006 — Business Logo Upload (POST /profile/me/logo)

- **US Ref:** US-B-15
- **Estimate:** M
- **Dependencies:** IDENTITY-005, SHARED-006
- **Spec References:** `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/docker-compose-topology.md`

**Implementation Notes**

- `POST /profile/me/logo` — multipart, single `logo` file field; JPEG/PNG/WebP only, max 2MB
- 422 if `accountType != B2B`
- Upload via SHARED-006's `StorageService` to the `user-assets` bucket; key pattern and `identity.user.business_logo_storage_key` column exactly per spec — see spec, don't restate here
- Response: presigned URL (1h TTL), per spec

**Done Criteria**

- B2B account, valid image → 200, `businessLogoUrl` returned as a presigned URL
- Non-B2B account → 422
- File > 2MB or non-image MIME → 400
