# EPIC: AUTH — Authentication & Authorization

**Sprint:** 2  
**Total Tasks:** 19  

Full authentication and authorization system: JWT with refresh rotation, local + Google + Facebook OAuth, email verification, password reset, RBAC, seller role upgrade, and Kafka event publishing for auth-triggered notifications.

---

## AUTH-001 — auth Schema Migrations

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/auth/src/infrastructure/migrations/0001_auth_schema.sql`
- Creates `auth` schema and tables:
  - `auth.user`: id (UUIDv7 PK), email (unique), password_hash, email_verified, role enum (`BUYER`|`SELLER`|`ADMIN`), status (`ACTIVE`|`SUSPENDED`|`CLOSED`), created_at, updated_at
  - `auth.refresh_token`: id, user_id FK, token_hash (indexed), expires_at, revoked_at nullable, family (for rotation chain detection), created_at
  - `auth.email_verification_token`: id, user_id FK, token_hash, expires_at, used_at nullable
  - `auth.password_reset_token`: id, user_id FK, token_hash, expires_at, used_at nullable
  - `auth.oauth_provider`: id, user_id FK, provider (`google`|`facebook`), provider_user_id, access_token_enc nullable, refresh_token_enc nullable, linked_at
- Indexes: `user(email)`, `refresh_token(token_hash)`, `refresh_token(user_id, revoked_at)`, `oauth_provider(provider, provider_user_id)`

**Done Criteria**

- All auth tables created in `auth` schema
- `INSERT INTO auth.user` with duplicate email fails unique constraint

---

## AUTH-002 — Passport JWT Strategy + JwtAuthGuard

- **US Ref:** US-P-02
- **Estimate:** M
- **Dependencies:** AUTH-001, SHARED-007
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `JwtStrategy extends PassportStrategy(Strategy, 'jwt')`:
  - `secretOrKey`: `JWT_ACCESS_SECRET` env var
  - `jwtFromRequest`: `ExtractJwt.fromAuthHeaderAsBearerToken()`
  - `ignoreExpiration: false`
  - `validate(payload)`: load user by `payload.sub`; check user status = `ACTIVE`; check `JwtRevocationService.isRevoked(userId, payload.iat)` (Redis blacklist)
- Access token payload: `{ sub: userId, email, role, iat, exp }`
- Access token TTL: `JWT_ACCESS_EXPIRES_IN` (default `15m`)
- `@JwtAuthGuard()` → `@UseGuards(AuthGuard('jwt'))` — use as class-level guard
- `@Public()` decorator to exempt endpoints:
  ```ts
  export const Public = () => SetMetadata('isPublic', true);
  ```
  Guard checks `reflector.get('isPublic', ...)` and skips if true
- File: `libs/auth/src/infrastructure/strategies/jwt.strategy.ts`

**Done Criteria**

- Protected endpoint with valid JWT: 200
- Expired token: 401
- Revoked user (blacklisted via JwtRevocationService): 401
- `@Public()` endpoint: 200 without token

---

## AUTH-003 — Local Auth (Passport + LoginDto)

- **US Ref:** US-B-01, US-S-01, US-A-00
- **Estimate:** M
- **Dependencies:** AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `LocalStrategy extends PassportStrategy(Strategy, 'local')`:
  - `usernameField: 'email'`
  - `validate(email, password)`: find user by email; `bcrypt.compare(password, user.password_hash)`; throw `UnauthorizedException` if invalid; return user object
- `LoginDto { email: string, password: string, guestCart?: GuestCartItemDto[] }` — `guestCart` for merge on login (CART-008)
- Password hashing: `bcrypt` with `saltRounds: 12`
- Never store plaintext password; log nothing sensitive

**Done Criteria**

- Wrong password: 401 `INVALID_CREDENTIALS`
- Correct password: user object returned to controller
- `console.log` shows no password values anywhere in auth flow

---

## AUTH-004 — POST /auth/register

- **US Ref:** US-B-01
- **Estimate:** M
- **Dependencies:** AUTH-001, SHARED-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `RegisterDto { email, password (8–72 chars, min 1 uppercase + 1 digit + 1 special), name, accountType ('buyer'|'seller') }`
- Check duplicate email → 409 `EMAIL_ALREADY_REGISTERED`
- Hash password with bcrypt (saltRounds=12); create `auth.user` (role=`accountType`, email_verified=false)
- Create `identity.user_profile` record (linked by same id) — call IdentityService directly (same process, no HTTP)
- Generate email verification token (random 32-byte hex, expires 24h); store hash in `auth.email_verification_token`
- Publish `auth.email_verification_requested` outbox event: `{ userId, email, tokenHash, expiresAt }`
- Response: `{ message: "Registration successful. Check your email to verify your account." }` (201 no auto-login to force verification flow)

**Done Criteria**

- Duplicate email → 409
- Weak password → 400 with validation detail
- Valid registration → user row + profile row created; outbox event written
- No auto-login token returned on register

---

## AUTH-005 — Email Verification (verify + resend)

- **US Ref:** US-B-02
- **Estimate:** M
- **Dependencies:** AUTH-004, SHARED-007
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /auth/verify-email { token: string }`:
  - Hash incoming token; find unexpired, unused row in `auth.email_verification_token`
  - Mark `used_at = now()`; set `auth.user.email_verified = true`
  - Return `{ message: "Email verified. You can now log in." }`
- `POST /auth/resend-verification { email: string }`:
  - Rate limited: `EmailResendRateLimitGuard` (max 3/hour per email, Redis-backed — see SHARED-007)
  - If user already verified: 200 `{ message: "Email already verified." }` (idempotent)
  - Otherwise: invalidate previous tokens; generate new; publish outbox event
- Security: expired/used/invalid token → 400 `INVALID_OR_EXPIRED_TOKEN` (same message regardless — no user enumeration)

**Done Criteria**

- Valid token → email_verified = true
- Expired token → 400
- 4th resend in 1h → 429
- Already verified → 200 (not 400)

---

## AUTH-006 — POST /auth/login (access + refresh tokens)

- **US Ref:** US-B-01, US-S-01, US-A-00
- **Estimate:** M
- **Dependencies:** AUTH-003, AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /auth/login` uses `LocalGuard` (Passport local strategy validates credentials first)
- After strategy validates: generate access token (JWT 15min) + refresh token (random 32-byte hex, hash stored in DB, TTL 14 days)
- Refresh token response: `Set-Cookie: refreshToken=<token>; HttpOnly; SameSite=Strict; Max-Age=1209600` (DO NOT return in JSON body)
- Response JSON: `{ accessToken, user: { id, email, role }, cartMergeResult? }`
- If `guestCart` sent in body → call `CartService.mergeGuestCart()` (CART-008); include `cartMergeResult` in response
- Unverified email → 403 `EMAIL_NOT_VERIFIED` with message directing to resend

**Done Criteria**

- Valid login: access token in body, refresh token in HttpOnly cookie
- Unverified email: 403 (not 401)
- Response never contains refresh token in JSON body
- `cartMergeResult` present when guestCart sent

---

## AUTH-007 — Refresh Token Rotation (POST /auth/refresh)

- **US Ref:** US-P-02
- **Estimate:** L
- **Dependencies:** AUTH-006
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /auth/refresh` reads refresh token from `Cookie: refreshToken`
- Validate: hash cookie value; find active (non-revoked, non-expired) row in `auth.refresh_token`
- On valid: revoke old token (`revoked_at = now()`); issue new refresh token (new DB row, same `family`); issue new access token
- **Token reuse detection**: if incoming token is already revoked but `family` exists → revoke ALL tokens in that family (compromise response); return 401 `TOKEN_FAMILY_COMPROMISED`
- Refresh token TTL: 14 days; sliding expiry (reset on each refresh)
- Set-Cookie same as login

**Done Criteria**

- Valid refresh → new access token + new refresh token cookie
- Expired refresh → 401
- Replaying a previously rotated refresh token → ALL family tokens revoked; 401

---

## AUTH-008 — POST /auth/logout

- **US Ref:** US-B-01
- **Estimate:** S
- **Dependencies:** AUTH-007, SHARED-007
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- `POST /auth/logout` requires valid access token (`@JwtAuthGuard`)
- Revoke current refresh token (from cookie)
- Add `auth:revoke_before:{userId} = now()` in Redis (TTL = remaining access token life; max 16min) — invalidates all previously issued access tokens for this user
- Clear refresh token cookie: `Set-Cookie: refreshToken=; Max-Age=0; HttpOnly; SameSite=Strict`
- Response: 204 No Content

**Done Criteria**

- After logout: access token (still valid TTL) rejected by JWT strategy (Redis revocation check)
- Refresh token cookie cleared in response headers
- 204 response

---

## AUTH-009 — Password Reset (request + confirm)

- **US Ref:** US-B-03
- **Estimate:** M
- **Dependencies:** AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /auth/password-reset/request { email: string }`:
  - Always 200 `{ message: "If that email is registered, a reset link has been sent." }` (no user enumeration)
  - Generate reset token (32-byte random); hash; store in `auth.password_reset_token` (TTL 1h)
  - Publish `auth.password_reset_requested` outbox event
- `POST /auth/password-reset/confirm { token: string, newPassword: string }`:
  - Validate token (hash match, unexpired, unused); update `password_hash`; mark token `used_at`
  - Revoke all refresh tokens for user (force re-login everywhere)
  - Publish `auth.password_changed` outbox event (triggers security notification email)

**Done Criteria**

- Invalid email → still 200 (enumeration-safe)
- Expired token → 400
- Valid confirm → password updated; all existing sessions invalidated
- `auth.password_changed` event in outbox

---

## AUTH-010 — POST /auth/change-password (authenticated)

- **US Ref:** US-B-03
- **Estimate:** S
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- `POST /auth/change-password { currentPassword, newPassword }` — requires `@JwtAuthGuard`
- Verify `currentPassword` against stored hash; 401 if wrong
- Validate `newPassword` meets complexity rules; hash and update
- Revoke all refresh tokens; `auth.password_changed` outbox event

**Done Criteria**

- Wrong current password → 401
- Successful change → other device sessions invalidated within 15min (access token TTL)

---

## AUTH-011 — Google OAuth (GET /auth/google + callback)

- **US Ref:** US-B-04
- **Estimate:** L
- **Dependencies:** AUTH-001, AUTH-006
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `GET /auth/google` — redirects to Google consent screen
- `GET /auth/google/callback` — Passport Google strategy processes code exchange
- On callback: check `auth.oauth_provider` for existing `(provider='google', provider_user_id)`
  - Found: log in as that user
  - Not found: check if email matches existing `auth.user`; if yes, link; if no, create new user (email_verified=true, no password_hash)
- Access + refresh token issued same as login; redirect to frontend with `?token=<accessToken>` (SPA reads from URL and discards from history)
- Credentials: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` env vars; callback URL: `${API_URL}/auth/google/callback`

**Done Criteria**

- New user via Google: user + profile + oauth_provider rows created
- Existing email linked: same user account, new oauth_provider row added
- Redirect back to frontend with access token in query param

---

## AUTH-012 — Facebook OAuth (GET /auth/facebook + callback)

- **US Ref:** US-B-04
- **Estimate:** L
- **Dependencies:** AUTH-001, AUTH-006
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- Same pattern as Google OAuth (AUTH-011) but `provider='facebook'`
- `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET` env vars
- Request fields: `email`, `name`, `picture`
- Same account-linking logic as Google

**Done Criteria**

- Same acceptance criteria as AUTH-011 with Facebook provider

---

## AUTH-013 — RBAC Guard (`@Roles` decorator + RolesGuard)

- **US Ref:** US-P-02
- **Estimate:** M
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- `@Roles('SELLER', 'ADMIN')` decorator: `SetMetadata('roles', roles)`
- `RolesGuard implements CanActivate`:
  - Extract user from request (set by JwtStrategy)
  - Check `user.role` against required roles from metadata
  - Return false (403) if not in allowed roles
- Applied globally after JwtAuthGuard; no explicit guard needed per endpoint
- `@JwtAuthGuard` + `@Roles('ADMIN')` combination: only admin can access
- File: `libs/auth/src/guards/roles.guard.ts`, `libs/auth/src/decorators/roles.decorator.ts`

**Done Criteria**

- `@Roles('ADMIN')` endpoint called by BUYER user → 403
- `@Roles('SELLER', 'ADMIN')` endpoint called by SELLER → 200
- Unauthenticated call → 401 (from JwtAuthGuard, before RolesGuard runs)

---

## AUTH-014 — Seller Role Upgrade (POST /auth/upgrade-to-seller)

- **US Ref:** US-S-01
- **Estimate:** S
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /auth/upgrade-to-seller` — requires `@JwtAuthGuard`, current role must be `BUYER`
- Set `auth.user.role = 'SELLER'`
- Triggers implicit creation of `seller.seller_profile` (if not already exists) — call SellerService directly
- Re-issue access token with updated role claim (or instruct client to call `/auth/refresh`)
- Response: `{ message: "Account upgraded to seller.", accessToken }` — new token with role=SELLER

**Done Criteria**

- BUYER calls → role updated to SELLER; new access token includes role=SELLER
- SELLER calls → 409 `ALREADY_SELLER`

---

## AUTH-015 — Admin Seeding (bootstrap ADMIN user)

- **US Ref:** US-A-00
- **Estimate:** S
- **Dependencies:** AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `apps/workers/src/startup/admin-seeder.service.ts` — runs on workers startup
- Check if any user with `role = 'ADMIN'` exists; if not, create:
  - Email: `ADMIN_EMAIL` env var
  - Password: `ADMIN_PASSWORD` env var (bcrypt hashed)
  - `email_verified = true`, `role = 'ADMIN'`, `status = 'ACTIVE'`
- Idempotent: no-op if admin exists
- Identity profile created: `{ name: 'Admin', avatarUrl: null }`

**Done Criteria**

- First workers startup: admin user created; can login with `ADMIN_EMAIL` + `ADMIN_PASSWORD`
- Second startup: no duplicate, no error

---

## AUTH-016 — Auth Events Outbox (Kafka)

- **US Ref:** FR-P-09
- **Estimate:** M
- **Dependencies:** SHARED-005, AUTH-004
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- Events published via outbox (SHARED-005) from auth service methods:
  - `auth.email_verification_requested` — on register + resend (payload: `{ userId, email, verificationUrl, expiresAt }`)
  - `auth.password_reset_requested` — on password-reset/request (payload: `{ userId, email, resetUrl, expiresAt }`)
  - `auth.password_changed` — on confirm-reset + change-password (payload: `{ userId, email, changedAt }`)
- Notifications module consumes these events to send emails (NOTIFICATIONS-005)
- All three events published inside the same transaction as the state change (token creation/update)

**Done Criteria**

- Register → `auth.email_verification_requested` in outbox
- Password reset request → `auth.password_reset_requested` in outbox
- Change/confirm password → `auth.password_changed` in outbox
- Kafka UI shows messages within 2s of TX commit

---

## AUTH-017 — JWT Hardening (algorithm, audience, issuer)

- **US Ref:** US-P-02
- **Estimate:** S
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- Algorithm: `RS256` for production readiness (asymmetric); use `HS256` for dev (single service — symmetric ok)
- V1 uses HS256 with strong random secret (not default 'secret'); document migration path to RS256 for V2
- JWT must include: `iss` (issuer: `aliceut-api`), `aud` (audience: `aliceut-client`), `iat`, `exp`, `sub`, `role`
- Validate `iss` and `aud` in JwtStrategy `validate()` — reject tokens with wrong issuer/audience
- `JWT_ACCESS_SECRET` min length enforced: Joi validation requires ≥32 chars

**Done Criteria**

- Token from different issuer → 401
- JWT_ACCESS_SECRET shorter than 32 chars → startup fails
- All issued tokens include `iss`, `aud`, `iat`, `exp`, `sub`, `role`

---

## AUTH-018 — SellerKycGuard

- **US Ref:** US-S-03
- **Estimate:** S
- **Dependencies:** AUTH-013, SELLER-007
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/api-design/seller.md`

**Implementation Notes**

- `SellerKycGuard implements CanActivate`:
  - Requires user has `role = 'SELLER'` (checked after RolesGuard)
  - Load seller profile; check `kyc_status = 'APPROVED'` and seller `status = 'ACTIVE'`
  - If not KYC approved → 403 `KYC_NOT_APPROVED` with `message: "KYC verification required"`
  - If suspended → 403 `SELLER_SUSPENDED` with suspension expiry date
- Apply to all seller catalog, inventory, pricing endpoints

**Done Criteria**

- SELLER without KYC approval → 403 `KYC_NOT_APPROVED`
- SUSPENDED seller → 403 `SELLER_SUSPENDED` with expiry in response body

---

## AUTH-019 — POST /auth/admin/users/:id/force-logout

- **US Ref:** US-A-00
- **Estimate:** S
- **Dependencies:** AUTH-008
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- `POST /auth/admin/users/:id/force-logout` — requires `@Roles('ADMIN')`
- Revoke ALL refresh tokens for target user
- Set Redis `auth:revoke_before:{userId}` (access token blacklist)
- Used by admin during suspension flow (ADMIN-009 triggers this)
- Response: 204

**Done Criteria**

- Admin force-logout: target user's next API call with existing access token → 401
- Admin force-logout: refresh attempt → 401
