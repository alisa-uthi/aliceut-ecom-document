# EPIC: AUTH — Authentication & Authorization

**Sprint:** 2–3  
**Total Tasks:** 19  
**Status:** Now  

Full auth stack: local JWT (access + refresh rotation), Google OAuth, Facebook OAuth, email verification, password reset, logout/revocation, role-based guards, and the NestJS Passport integration. Produces the `auth:email_verification_requested`, `auth:password_reset_requested`, and `auth:password_changed` Kafka events for the Notifications module.

---

## AUTH-001 — Identity Schema Migration (auth tables)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00, US-S-00 |
| **Estimate** | M (1d) |
| **Dependencies** | INFRA-004 |

**Implementation Notes**

- File: `libs/identity/src/infrastructure/migrations/002_identity_schema.sql`
- Creates `identity` schema and all auth-related tables:

```sql
CREATE SCHEMA IF NOT EXISTS identity;

CREATE TYPE identity.account_type AS ENUM ('B2C', 'B2B');
CREATE TYPE identity.account_status AS ENUM ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED', 'CLOSED');
CREATE TYPE identity.auth_provider AS ENUM ('LOCAL', 'GOOGLE', 'FACEBOOK');

CREATE TABLE identity.user_account (
  id                  UUID PRIMARY KEY DEFAULT uuidv7(),
  email               VARCHAR(254) UNIQUE NOT NULL,
  display_name        VARCHAR(100) NOT NULL,
  account_type        identity.account_type NOT NULL DEFAULT 'B2C',
  account_status      identity.account_status NOT NULL DEFAULT 'PENDING_VERIFICATION',
  is_email_verified   BOOLEAN NOT NULL DEFAULT FALSE,
  role                VARCHAR(50) NOT NULL DEFAULT 'buyer',  -- 'buyer'|'seller'|'admin'
  password_hash       TEXT,           -- NULL for OAuth-only accounts
  failed_login_count  SMALLINT NOT NULL DEFAULT 0,
  locked_until        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_user_account_email ON identity.user_account (email);
CREATE INDEX idx_user_account_status ON identity.user_account (account_status);

CREATE TABLE identity.oauth_connection (
  id              UUID PRIMARY KEY DEFAULT uuidv7(),
  user_id         UUID NOT NULL REFERENCES identity.user_account(id) ON DELETE CASCADE,
  provider        identity.auth_provider NOT NULL,
  provider_id     VARCHAR(255) NOT NULL,
  access_token    TEXT,
  refresh_token   TEXT,
  connected_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_id)
);
CREATE INDEX idx_oauth_user ON identity.oauth_connection (user_id);

CREATE TABLE identity.refresh_token (
  id              UUID PRIMARY KEY DEFAULT uuidv7(),
  user_id         UUID NOT NULL REFERENCES identity.user_account(id) ON DELETE CASCADE,
  token_hash      VARCHAR(64) NOT NULL UNIQUE,  -- SHA-256 of token value
  family          UUID NOT NULL,               -- rotation family for theft detection
  is_revoked      BOOLEAN NOT NULL DEFAULT FALSE,
  revoked_reason  VARCHAR(100),
  expires_at      TIMESTAMPTZ NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at    TIMESTAMPTZ
);
CREATE INDEX idx_refresh_token_user ON identity.refresh_token (user_id);
CREATE INDEX idx_refresh_token_family ON identity.refresh_token (family);

CREATE TABLE identity.verification_token (
  id          UUID PRIMARY KEY DEFAULT uuidv7(),
  user_id     UUID NOT NULL REFERENCES identity.user_account(id) ON DELETE CASCADE,
  token_hash  VARCHAR(64) NOT NULL UNIQUE,
  purpose     VARCHAR(50) NOT NULL,  -- 'EMAIL_VERIFICATION' | 'PASSWORD_RESET'
  expires_at  TIMESTAMPTZ NOT NULL,
  used_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_verification_token_user ON identity.verification_token (user_id);
```

**Done Criteria**

- Migration runs clean on fresh DB; all tables created in `identity` schema
- `UNIQUE (provider, provider_id)` prevents duplicate OAuth link
- `token_hash` columns sized for SHA-256 hex output (64 chars)

---

## AUTH-002 — NestJS Passport Config + JWT Strategy

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00, US-S-00 |
| **Estimate** | M (1d) |
| **Dependencies** | AUTH-001, SHARED-007 |

**Implementation Notes**

- File: `libs/identity/src/infrastructure/passport/jwt.strategy.ts`
- Packages: `passport passport-jwt @nestjs/passport @nestjs/jwt`
- JWT access token payload:
  ```ts
  interface JwtPayload {
    sub: string;         // user_account.id
    email: string;
    role: 'buyer' | 'seller' | 'admin';
    iat: number;
    exp: number;
  }
  ```
- `JwtStrategy` extends `PassportStrategy(Strategy)`:
  - `secretOrKey`: `JWT_SECRET` env var
  - `jwtFromRequest`: `ExtractJwt.fromAuthHeaderAsBearerToken()`
  - `validate(payload)`: check `JwtRevocationService.isRevoked(payload.sub, payload.iat)`; throw 401 if revoked; return user object
- `@Public()` decorator marks endpoints that skip JWT guard (e.g. `/auth/login`, `/auth/register`, `/health`)
- `JwtAuthGuard` as global guard in `AppModule`; checks for `@Public()` decorator to skip
- Access token TTL: 900s (`JWT_ACCESS_TTL_SECONDS`); refresh token TTL: 30 days (`JWT_REFRESH_TTL_DAYS`)

**Done Criteria**

- Valid JWT: request proceeds to handler
- Expired JWT: 401 response
- Revoked user (via `revokeAllForUser`): 401 even with technically valid JWT
- `@Public()` endpoint accessible without `Authorization` header

---

## AUTH-003 — Local Auth Strategy (Email + Password)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00, US-S-00 |
| **Estimate** | M (1d) |
| **Dependencies** | AUTH-002 |

**Implementation Notes**

- File: `libs/identity/src/infrastructure/passport/local.strategy.ts`
- `LocalStrategy` extends `PassportStrategy(Strategy, 'local')`:
  - Find user by email; check `account_status != 'CLOSED'`
  - Check `locked_until`: if account locked, throw 401 with `ACCOUNT_LOCKED` code
  - Verify password: `argon2.verify(user.password_hash, password)` — use argon2id
  - On failure: increment `failed_login_count`; if `>= 5`, set `locked_until = now() + 15 minutes`
  - On success: reset `failed_login_count = 0`, `locked_until = null`
- Password hashing config: `argon2.hash(password, { type: argon2.argon2id, memoryCost: 65536, timeCost: 3, parallelism: 4 })`
- Return minimal user object (id, email, role) to `AuthController.login()`

**Done Criteria**

- Correct credentials: returns user object to controller
- Wrong password 5× in a row: account locked; correct password returns 401 `ACCOUNT_LOCKED`
- Lock expires after 15 minutes
- Password comparison uses `argon2.verify` (not bcrypt; not plain comparison)
- `password_hash` never returned in API response

---

## AUTH-004 — Register Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00, US-S-00 |
| **Estimate** | M (1d) |
| **Dependencies** | AUTH-003, PLATFORM-002 |

**Implementation Notes**

- `POST /auth/register` (public)
- `RegisterDto`: `{ email: string, password: string, displayName: string, accountType?: 'B2C' | 'B2B' }` — default `B2C`
- Password validation: min 8 chars, at least 1 uppercase, 1 lowercase, 1 digit
- Flow:
  1. Check email uniqueness (throw `ConflictException('EMAIL_TAKEN', ...)` if exists)
  2. Hash password with argon2id
  3. Insert `user_account` row with `account_status = 'PENDING_VERIFICATION'`, `is_email_verified = false`
  4. Generate verification token (random 32 bytes, store SHA-256 hash in `verification_token` table, 24h TTL)
  5. Write `auth.email_verification_requested` outbox event with token in payload
  6. Return `{ message: "Verification email sent" }` (201)
- Never return the verification token in the API response (email only)
- Registration creates `role = 'buyer'` by default; seller role assigned separately via seller onboarding (SELLER epic)

**Done Criteria**

- `POST /auth/register` with valid body returns 201
- Duplicate email returns 409 `EMAIL_TAKEN`
- Weak password returns 400 with validation message
- `user_account` row created with `account_status = 'PENDING_VERIFICATION'`
- `auth.email_verification_requested` outbox event written in same transaction as user row

---

## AUTH-005 — Email Verification Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-004 |

**Implementation Notes**

- `GET /auth/verify-email?token=<raw-token>` (public)
- Flow:
  1. Hash input token: `SHA-256(token)`
  2. Find `verification_token` row where `token_hash = hash AND purpose = 'EMAIL_VERIFICATION' AND used_at IS NULL AND expires_at > now()`
  3. Not found: return 400 `INVALID_OR_EXPIRED_TOKEN`
  4. Found: mark `used_at = now()`; update `user_account` set `is_email_verified = true`, `account_status = 'ACTIVE'`
  5. Return `{ message: "Email verified successfully" }` (200)
- Token is single-use (checking `used_at IS NULL`)
- Return same 400 error whether token invalid or already used (prevent token enumeration)

**Done Criteria**

- Valid token: `is_email_verified = true`, `account_status = 'ACTIVE'`, `used_at` populated
- Expired token: 400 `INVALID_OR_EXPIRED_TOKEN`
- Reusing same token: 400 (already used)
- Using a fake token: 400 (not found)

---

## AUTH-006 — Email Verification Resend Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-005, SHARED-007 |

**Implementation Notes**

- `POST /auth/resend-verification` (public)
- Body: `{ email: string }`
- Rate limit: `EmailResendRateLimitGuard` (max 3 per hour per email address via Redis)
- Flow:
  1. Find user by email; if not found or already verified: return 200 (prevent email enumeration)
  2. Invalidate any existing unused `EMAIL_VERIFICATION` tokens for this user
  3. Generate new token (same as AUTH-004 flow)
  4. Write `auth.email_verification_requested` outbox event
  5. Return 200 `{ message: "If your email is registered and unverified, a new verification email has been sent" }`

**Done Criteria**

- Unverified user: new token generated in DB; event emitted
- Already-verified user: silent 200 (no new token)
- 4th request within 1 hour: 429 Too Many Requests
- Rate limit resets after 1 hour

---

## AUTH-007 — Login Endpoint (Token Issue)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-01, US-S-01, US-A-00 |
| **Estimate** | M (1d) |
| **Dependencies** | AUTH-003 |

**Implementation Notes**

- `POST /auth/login` (public, uses `LocalAuthGuard`)
- `LoginDto`: `{ email: string, password: string }`
- Flow (after LocalStrategy validates credentials):
  1. Check `account_status = 'ACTIVE'`; if `PENDING_VERIFICATION` return 403 `EMAIL_NOT_VERIFIED`
  2. Generate access token: `jwtService.sign(payload, { expiresIn: JWT_ACCESS_TTL_SECONDS })`
  3. Generate refresh token: cryptographic random 48 bytes → base64url string
  4. Hash refresh token: SHA-256; store in `identity.refresh_token` with `family = uuidv7()`, `expires_at = now() + JWT_REFRESH_TTL_DAYS`
  5. Return:
     ```json
     {
       "accessToken": "eyJ...",
       "refreshToken": "base64url-random-string",
       "expiresIn": 900,
       "user": { "id": "uuid", "email": "...", "role": "buyer", "displayName": "..." }
     }
     ```
- Refresh token returned in body (not httpOnly cookie) — SPA architecture; client stores in memory

**Done Criteria**

- Valid credentials: returns both tokens
- Unverified account: 403 `EMAIL_NOT_VERIFIED`
- Suspended account: 403 `ACCOUNT_SUSPENDED`
- Closed account: 401 `ACCOUNT_CLOSED`
- `refresh_token` row created in DB; `token_hash` is SHA-256 of returned token

---

## AUTH-008 — Refresh Token Endpoint (Rotation)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-01 |
| **Estimate** | M (1d) |
| **Dependencies** | AUTH-007 |

**Implementation Notes**

- `POST /auth/refresh` (public)
- Body: `{ refreshToken: string }`
- Flow:
  1. Hash incoming token; find `refresh_token` row where `token_hash = hash`
  2. If not found: return 401 `INVALID_REFRESH_TOKEN`
  3. If `is_revoked = true`: **token theft detected** — revoke entire family (`UPDATE refresh_token SET is_revoked=true WHERE family = ?`); return 401 `REFRESH_TOKEN_REUSE`
  4. If `expires_at < now()`: return 401 `REFRESH_TOKEN_EXPIRED`
  5. Revoke current token (`is_revoked = true`)
  6. Issue new access token + new refresh token (same `family`); store new token hash
  7. Return same shape as `POST /auth/login` response (without user object)
- Refresh token rotation: every refresh issues a new refresh token and revokes the old one
- Token family theft detection: if a revoked token is presented, entire family is invalidated

**Done Criteria**

- Valid refresh token: new access + refresh tokens returned; old refresh token revoked in DB
- Revoked refresh token: entire family revoked; 401 returned
- Expired refresh token: 401
- Non-existent token: 401
- Re-using new token (not old): works correctly

---

## AUTH-009 — Logout Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-01 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-007, SHARED-007 |

**Implementation Notes**

- `POST /auth/logout` (protected — requires JWT)
- Body: `{ refreshToken?: string }` — if provided, revoke specific refresh token; if omitted, revoke all tokens for user
- Flow:
  1. If `refreshToken` provided: hash it; mark that row `is_revoked = true`
  2. Always: call `JwtRevocationService.revokeAllForUser(userId)` to set Redis key `auth:revoke_before:{userId}` with current timestamp
  3. Return 200 `{ message: "Logged out successfully" }`
- Client should discard access token and refresh token from memory after this call
- All in-flight access tokens are invalidated immediately via Redis TTL key (not just on next refresh)

**Done Criteria**

- After logout: subsequent request with old access token returns 401 (Redis revocation check)
- Specific refresh token revoked if provided
- Redis key `auth:revoke_before:{userId}` set with correct timestamp

---

## AUTH-010 — Password Reset Request Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-004, SHARED-007 |

**Implementation Notes**

- `POST /auth/forgot-password` (public)
- Body: `{ email: string }`
- Rate limit: reuse `EmailResendRateLimitGuard` (max 3 per hour per email)
- Flow:
  1. Find user by email; if not found: silent 200 (prevent enumeration)
  2. If found: invalidate existing unused `PASSWORD_RESET` tokens for user
  3. Generate token (32 random bytes); store SHA-256 hash with `purpose='PASSWORD_RESET'`, 1h TTL
  4. Write `auth.password_reset_requested` outbox event
  5. Return 200 `{ message: "If that email is registered, a reset link has been sent" }`
- Notifications module consumes event and sends email with reset URL: `{FRONTEND_URL}/reset-password?token=<raw>`

**Done Criteria**

- Known email: token created; event emitted
- Unknown email: 200 response; no DB write; no event
- Rate limit: 4th request in 1h returns 429
- Token TTL is 1 hour (not 24h like email verification)

---

## AUTH-011 — Password Reset Confirm Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-010, SHARED-007 |

**Implementation Notes**

- `POST /auth/reset-password` (public)
- Body: `{ token: string, newPassword: string }`
- Flow:
  1. Hash token; find `verification_token` row where `purpose='PASSWORD_RESET' AND used_at IS NULL AND expires_at > now()`
  2. Not found: 400 `INVALID_OR_EXPIRED_TOKEN`
  3. Validate new password strength (same rules as registration)
  4. Hash new password with argon2id; update `user_account.password_hash`
  5. Mark token `used_at = now()`
  6. Revoke all refresh tokens for user: `UPDATE identity.refresh_token SET is_revoked=true WHERE user_id=?`
  7. Call `JwtRevocationService.revokeAllForUser(userId)` (Redis)
  8. Write `auth.password_changed` outbox event
  9. Return 200 `{ message: "Password changed successfully" }`

**Done Criteria**

- Valid token + valid password: password updated; all sessions invalidated
- Expired token: 400
- Weak new password: 400 with validation error
- After reset: old refresh tokens rejected; old access tokens rejected (Redis revocation)

---

## AUTH-012 — Change Password Endpoint (Authenticated)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-009 |

**Implementation Notes**

- `POST /auth/change-password` (protected)
- Body: `{ currentPassword: string, newPassword: string }`
- Flow:
  1. Verify `currentPassword` matches existing hash; if no `password_hash` (OAuth user), return 400 `NO_PASSWORD_SET`
  2. Validate new password strength
  3. Hash new password; update `user_account.password_hash`
  4. Revoke all refresh tokens + Redis revocation
  5. Write `auth.password_changed` outbox event
  6. Return 200 `{ message: "Password changed. Please log in again." }`

**Done Criteria**

- Correct current password: password updated; sessions invalidated
- Wrong current password: 401 `INVALID_CREDENTIALS`
- OAuth-only user (no `password_hash`): 400 `NO_PASSWORD_SET`

---

## AUTH-013 — Google OAuth Strategy + Callback

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | M (1d) |
| **Dependencies** | AUTH-007 |

**Implementation Notes**

- Package: `passport-google-oauth20`
- `GET /auth/google` (public) → redirect to Google
- `GET /auth/google/callback` (public) → Passport callback
- `GoogleStrategy` extends `PassportStrategy(GoogleStrategy)`:
  - Config: `clientID: GOOGLE_CLIENT_ID`, `clientSecret: GOOGLE_CLIENT_SECRET`, `callbackURL: /auth/google/callback`
  - `validate(accessToken, refreshToken, profile, done)`:
    1. Find `oauth_connection` where `provider='GOOGLE' AND provider_id = profile.id`
    2. If found: return linked `user_account`
    3. If not found: check if email already exists in `user_account`
       - If exists: create `oauth_connection` linking to existing account (merge)
       - If not exists: create new `user_account` with `is_email_verified=true`, `account_status='ACTIVE'` (Google guarantees verified email)
- Callback endpoint: issue JWT tokens same as `POST /auth/login`; redirect to `{FRONTEND_URL}/auth/callback?token=<accessToken>&refresh=<refreshToken>`
- Skip if `GOOGLE_CLIENT_ID` not set in env (feature disabled)

**Done Criteria**

- Google OAuth flow completes end-to-end; new user created with `ACTIVE` status
- Returning user (same Google ID): existing account retrieved; new tokens issued
- Email collision (Google email matches local account): accounts merged without creating duplicate
- Feature gracefully disabled when `GOOGLE_CLIENT_ID` env var absent

---

## AUTH-014 — Facebook OAuth Strategy + Callback

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | M (1d) |
| **Dependencies** | AUTH-013 |

**Implementation Notes**

- Package: `passport-facebook`
- `GET /auth/facebook` → redirect; `GET /auth/facebook/callback` → callback
- Same flow as `AUTH-013` but using Facebook provider
- Facebook profile: request `email` scope; if Facebook doesn't return email (user denied), create account without email (requires email to be added later via profile settings — US-B-02)
- Facebook ID: `provider_id = profile.id`
- Skip if `FACEBOOK_CLIENT_ID` not set

**Done Criteria**

- Facebook OAuth creates user or links to existing account
- User without Facebook email: account created with null email; profile update required before purchasing
- Feature disabled when `FACEBOOK_CLIENT_ID` absent

---

## AUTH-015 — RBAC Guard (`@Roles()` Decorator)

| Field | Value |
|-------|-------|
| **US Ref** | US-A-00 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-002 |

**Implementation Notes**

- File: `libs/identity/src/auth/roles.guard.ts`
- `@Roles('admin')`, `@Roles('seller')`, `@Roles('buyer', 'seller')` — composite roles allowed
- `RolesGuard` reads `role` from JWT payload; throws 403 if user's role not in allowed list
- Applied AFTER `JwtAuthGuard` (guards execute in registration order in NestJS)
- Register as global guard in `AppModule` at lower priority than `JwtAuthGuard`
- `@Roles()` on controller class applies to all methods; method-level decorator overrides class-level
- Admin portal endpoints all require `@Roles('admin')`

**Done Criteria**

- Buyer accessing `@Roles('seller')` endpoint: 403
- Seller accessing `@Roles('admin')` endpoint: 403
- Admin accessing `@Roles('buyer', 'seller', 'admin')` endpoint: 200
- No `@Roles()` decorator + `@Public()`: accessible by anyone
- No `@Roles()` decorator without `@Public()`: requires valid JWT of any role

---

## AUTH-016 — Seller Role Upgrade Handler

| Field | Value |
|-------|-------|
| **US Ref** | US-S-00 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-015 |

**Implementation Notes**

- File: `libs/identity/src/application/commands/upgrade-to-seller.command.ts`
- Called by `SellerModule` when KYC is approved (`seller.kyc.decided` event with `decision='APPROVED'`)
- Updates `user_account.role = 'seller'` for the given `userId`
- New JWT must be obtained after role upgrade (access token still carries old `role = 'buyer'` until re-login or refresh)
- `POST /auth/seller-onboard` endpoint (public, requires active account): creates seller profile stub, triggers KYC flow — see SELLER epic
- Redis revocation: `JwtRevocationService.revokeAllForUser(userId)` forces re-login after role upgrade

**Done Criteria**

- After KYC approval event consumed: `user_account.role = 'seller'`
- Existing access token (with `role='buyer'`) rejected via Redis revocation
- User re-logs in, receives token with `role='seller'`

---

## AUTH-017 — Admin Account Seeding

| Field | Value |
|-------|-------|
| **US Ref** | US-A-00 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-001 |

**Implementation Notes**

- File: `libs/identity/src/infrastructure/migrations/003_admin_seed.sql`
  ```sql
  INSERT INTO identity.user_account (
    id, email, display_name, account_type, account_status,
    is_email_verified, role, password_hash
  ) VALUES (
    uuidv7(),
    'admin@aliceut.local',
    'Platform Admin',
    'B2C',
    'ACTIVE',
    TRUE,
    'admin',
    '$argon2id$...'   -- pre-hashed from ADMIN_DEFAULT_PASSWORD env var; NOT hardcoded
  )
  ON CONFLICT (email) DO NOTHING;
  ```
- NEVER hardcode the admin password in SQL; generate hash at migration time from `ADMIN_DEFAULT_PASSWORD` env var OR use a separate seed script
- Preferred approach: seed script `libs/identity/src/infrastructure/seeds/admin.seed.ts` run separately via `npm run db:seed:admin`
- Seed only creates admin if no admin account exists; idempotent

**Done Criteria**

- Running seed creates `admin@aliceut.local` with `role='admin'`
- Running seed twice: no error, no duplicate (idempotent)
- Admin can log in via `POST /auth/login` with seeded credentials
- Admin password is not committed to git in plaintext anywhere

---

## AUTH-018 — Auth Events (Notifications Integration)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | S (½d) |
| **Dependencies** | PLATFORM-002, AUTH-004 |

**Implementation Notes**

- Verify all three auth events written via outbox pattern (not direct Kafka produce):
  - `auth.email_verification_requested`: payload `{ userId, email, verificationUrl }` — written in same TX as user creation
  - `auth.password_reset_requested`: payload `{ userId, email, resetUrl }` — written in same TX as token creation
  - `auth.password_changed`: payload `{ userId, email, changedAt }` — written in same TX as password hash update
- Avro payload schemas registered with Schema Registry (partial — full schemas in PLATFORM-008)
- `verificationUrl` and `resetUrl` constructed from `FRONTEND_URL` env var + raw token (not hashed)
- Notifications module consumers (NOTIFICATIONS epic) send the actual emails

**Done Criteria**

- `POST /auth/register` writes `auth.email_verification_requested` event; relay publishes to Kafka
- `POST /auth/forgot-password` writes `auth.password_reset_requested` event
- `POST /auth/reset-password` writes `auth.password_changed` event
- Events appear in Kafka UI under correct topics
- Events contain correct payload fields

---

## AUTH-019 — JWT Security Hardening

| Field | Value |
|-------|-------|
| **US Ref** | US-P-08 |
| **Estimate** | S (½d) |
| **Dependencies** | AUTH-002 |

**Implementation Notes**

- `JWT_SECRET` minimum 32 chars validated at startup (INFRA-011 Joi schema)
- Access token 900s TTL hardcoded maximum (not overrideable to > 900s via env)
- Algorithm: `HS256` explicitly configured (don't rely on default); consider `RS256` for Phase 2 (key rotation)
- Do NOT return `passwordHash`, `failedLoginCount`, `lockedUntil` in ANY API response
- `ClassSerializerInterceptor` + `@Exclude()` on sensitive fields in `UserAccount` entity
- All auth endpoints in Swagger grouped under `Authentication` tag
- `POST /auth/*` endpoints not rate-limited globally (individual guards handle per-operation limits)
- Response headers: `Cache-Control: no-store` on token-issuing endpoints (prevent browser caching)

**Done Criteria**

- `JWT_SECRET` shorter than 32 chars causes startup failure
- `password_hash` never appears in `GET /profile` or any auth response
- `Cache-Control: no-store` header present on `/auth/login`, `/auth/refresh` responses
- Swagger UI shows `Authentication` group with all auth endpoints documented
