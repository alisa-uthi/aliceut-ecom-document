# EPIC: IDENTITY — User Identity & Profiles

**Sprint:** 3  
**Total Tasks:** 6  
**Status:** Now  

User profile management, address book, business profile (B2B badge), profile image upload, and buyer-facing account settings. Depends on AUTH epic for the `user_account` table and JWT authentication.

---

## IDENTITY-001 — Identity Schema Migration (profile tables)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-02 |
| **Estimate** | M (1d) |
| **Dependencies** | AUTH-001 |

**Implementation Notes**

- File: `libs/identity/src/infrastructure/migrations/004_identity_profiles.sql`
- Extends `identity` schema with profile and address tables:

```sql
CREATE TABLE identity.user_profile (
  user_id         UUID PRIMARY KEY REFERENCES identity.user_account(id) ON DELETE CASCADE,
  avatar_url      TEXT,
  phone_number    VARCHAR(30),
  date_of_birth   DATE,
  -- B2B fields (populated when account_type = 'B2B')
  company_name    VARCHAR(200),
  tax_id          VARCHAR(100),
  business_address TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE identity.address (
  id              UUID PRIMARY KEY DEFAULT uuidv7(),
  user_id         UUID NOT NULL REFERENCES identity.user_account(id) ON DELETE CASCADE,
  label           VARCHAR(50),           -- e.g. 'Home', 'Office', custom
  recipient_name  VARCHAR(100) NOT NULL,
  line1           VARCHAR(200) NOT NULL,
  line2           VARCHAR(200),
  city            VARCHAR(100) NOT NULL,
  state           VARCHAR(100),
  postal_code     VARCHAR(20),
  country_code    CHAR(2) NOT NULL,      -- ISO 3166-1 alpha-2
  phone           VARCHAR(30),
  is_default      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_address_user ON identity.address (user_id);

-- Partial index: enforce at most one default address per user
CREATE UNIQUE INDEX idx_address_default ON identity.address (user_id)
  WHERE is_default = TRUE;
```

**Done Criteria**

- Migration runs clean; both tables exist in `identity` schema
- `idx_address_default` partial unique index prevents two `is_default=true` rows for same user
- Foreign keys cascade delete: deleting `user_account` removes all addresses and profile

---

## IDENTITY-002 — Get Profile Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-02 |
| **Estimate** | S (½d) |
| **Dependencies** | IDENTITY-001, AUTH-002 |

**Implementation Notes**

- `GET /profile` (protected)
- Returns combined `user_account` + `user_profile` (left join — profile row may not exist yet)
- Response DTO:
  ```ts
  class ProfileResponseDto {
    id: string;
    email: string;
    displayName: string;
    role: string;
    accountType: 'B2C' | 'B2B';
    accountStatus: string;
    isEmailVerified: boolean;
    avatarUrl: string | null;
    phoneNumber: string | null;
    dateOfBirth: string | null;  // ISO date string
    companyName: string | null;
    taxId: string | null;
    createdAt: string;
  }
  ```
- Exclude: `password_hash`, `failed_login_count`, `locked_until` (via `@Exclude()`)
- Cache: no caching (user expects real-time profile)

**Done Criteria**

- `GET /profile` returns current user's data
- `passwordHash` (and variants) never present in response body
- User with no `user_profile` row: returns null for profile fields (not 500)
- `@ApiResponse()` Swagger documentation present

---

## IDENTITY-003 — Update Profile Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-02 |
| **Estimate** | M (1d) |
| **Dependencies** | IDENTITY-002 |

**Implementation Notes**

- `PATCH /profile` (protected)
- `UpdateProfileDto`:
  ```ts
  class UpdateProfileDto {
    @IsOptional() @IsString() @MaxLength(100) displayName?: string;
    @IsOptional() @IsString() @MaxLength(30) phoneNumber?: string;
    @IsOptional() @IsDateString() dateOfBirth?: string;
    // B2B only (ignored if account_type = 'B2C')
    @IsOptional() @IsString() @MaxLength(200) companyName?: string;
    @IsOptional() @IsString() @MaxLength(100) taxId?: string;
  }
  ```
- Upsert `user_profile` row (INSERT ... ON CONFLICT DO UPDATE)
- Update `user_account.display_name` if provided
- `updated_at = now()` on both rows
- B2B fields only saved when `account_type = 'B2B'`; silently ignored for B2C
- Return updated profile (same shape as `GET /profile`)

**Done Criteria**

- `PATCH /profile { "displayName": "Alice" }` updates display name; returns updated profile
- `PATCH /profile {}` is a no-op; returns current profile (200)
- B2B field `companyName` ignored for B2C account type (no error; not persisted)
- Input with XSS payload (`<script>alert(1)</script>`) stored as-is (not HTML-rendered; `whitelist: true` strips unknown fields; actual sanitization is frontend responsibility per Angular's XSS protection)

---

## IDENTITY-004 — Profile Image Upload Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-02 |
| **Estimate** | M (1d) |
| **Dependencies** | IDENTITY-003, SHARED-006 |

**Implementation Notes**

- `POST /profile/avatar` (protected, multipart form)
- Accept: `image/jpeg`, `image/png`, `image/webp` only
- Max file size: 2MB (validated in NestJS `FileInterceptor` with `limits: { fileSize: 2 * 1024 * 1024 }`)
- Flow:
  1. Validate file type via magic bytes (not just extension): `file-type` npm package
  2. Resize to max 400×400px using `sharp` npm package; convert to webp
  3. Upload to `user-assets` bucket: key = `avatars/{userId}/{timestamp}.webp`
  4. Generate presigned URL (1h TTL) for response (private bucket)
  5. Update `user_profile.avatar_url` with the storage key (not the presigned URL)
  6. Return `{ avatarUrl: "<presigned-url>" }` (200)
- Old avatar: not deleted (clean-up job out of scope V1)
- `StorageService.getPresignedDownloadUrl` called fresh on each `GET /profile` to generate current presigned URL

**Done Criteria**

- Valid JPEG/PNG/WebP under 2MB: uploaded, resized, URL returned
- File over 2MB: 413 response
- Non-image file (e.g. PDF with `.jpg` extension): 400 `INVALID_FILE_TYPE` (magic byte check)
- `user_profile.avatar_url` stores storage key; not the full presigned URL

---

## IDENTITY-005 — Address Book CRUD

| Field | Value |
|-------|-------|
| **US Ref** | US-B-02 |
| **Estimate** | M (1d) |
| **Dependencies** | IDENTITY-001, AUTH-002 |

**Implementation Notes**

- `GET /profile/addresses` → list all addresses for current user (no pagination; max ~20 addresses)
- `POST /profile/addresses` → create address
- `PATCH /profile/addresses/:id` → update specific address
- `DELETE /profile/addresses/:id` → delete address (not allowed if it is the only address and user has pending orders — V1: allow delete always)
- `POST /profile/addresses/:id/set-default` → set as default (unsets previous default atomically)
- `AddressDto`:
  ```ts
  class AddressDto {
    @IsString() @MaxLength(50) @IsOptional() label?: string;
    @IsString() @MaxLength(100) recipientName: string;
    @IsString() @MaxLength(200) line1: string;
    @IsString() @MaxLength(200) @IsOptional() line2?: string;
    @IsString() @MaxLength(100) city: string;
    @IsString() @MaxLength(100) @IsOptional() state?: string;
    @IsString() @MaxLength(20) @IsOptional() postalCode?: string;
    @IsString() @Length(2, 2) countryCode: string;
    @IsString() @MaxLength(30) @IsOptional() phone?: string;
  }
  ```
- Setting a new default: use single UPDATE query with `CASE`:
  ```sql
  UPDATE identity.address
  SET is_default = (id = $1)
  WHERE user_id = $2
  ```
  (bypasses partial unique index issue with two-step update)
- Access control: all address operations scoped to `currentUser.id`; never query by address ID alone

**Done Criteria**

- `POST /profile/addresses` creates address; returns 201 with created address
- `POST /profile/addresses/:id/set-default` sets new default; previous default becomes false
- User A cannot read/modify User B's addresses (403)
- Deleting an address: 204; address gone from list
- Country code must be exactly 2 chars; invalid code returns 400

---

## IDENTITY-006 — Account Closure (Soft Delete) Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-02 |
| **Estimate** | S (½d) |
| **Dependencies** | IDENTITY-002, AUTH-009 |

**Implementation Notes**

- `POST /profile/close-account` (protected)
- Body: `{ password: string, reason?: string }` — password confirmation required
- Flow:
  1. Verify password matches current hash (argon2.verify)
  2. Check no active/pending orders (query `orders.fulfillment` where `user_id = ? AND status NOT IN ('DELIVERED', 'CANCELLED', 'REFUNDED')`)
  3. If active orders exist: return 409 `ACTIVE_ORDERS_EXIST` with count
  4. Set `user_account.account_status = 'CLOSED'`
  5. Revoke all refresh tokens + Redis revocation
  6. Return 200 `{ message: "Account closed" }`
- Closed accounts: all data retained for audit/legal; no physical delete in V1
- Admin can reopen accounts (ADMIN epic)

**Done Criteria**

- No active orders: account status set to `CLOSED`; all sessions invalidated
- Active orders exist: 409 with message
- Wrong password: 401
- Subsequent login attempt with closed account: 401 `ACCOUNT_CLOSED`
