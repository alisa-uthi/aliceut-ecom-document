# EPIC: AUTH — Authentication & Authorization

**Sprint:** 2  
**Total Tasks:** 21  

Full authentication and authorization system: JWT with refresh rotation, local + Google + Facebook OAuth, email verification, password reset, RBAC, seller role upgrade, and Kafka event publishing for auth-triggered notifications.

---

## AUTH-001 — identity Schema Migrations

- **US Ref:** —
- **Estimate:** L
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/api-design/auth.md` DB Mapping §, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/identity/src/infrastructure/migrations/0001_identity_schema.sql`
- Creates `identity` schema, raw-SQL, per backlog.md AUTH-001: `identity.user`, `identity.oauth_identity`, `identity.refresh_session`, `identity.address`, `identity.email_verification_token`, `identity.password_reset_token`.
- Exact columns/indexes per `api-design/auth.md` DB Mapping + `data-model-erd.md` — see spec, don't restate here. Single `identity.user` table holds auth + profile fields together (no separate `auth.user` / `identity.user_profile` split).

**Done Criteria**

- All six `identity.*` tables created per spec
- `INSERT INTO identity.user` with duplicate email fails unique constraint

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
  - `validate(email, password)`: find user by email; `argon2id.verify(password, user.password_hash)`; throw `UnauthorizedException` if invalid or `password_hash IS NULL` (OAuth-only account); return user object
- `LoginDto { email: string, password: string, guestCart?: GuestCartItemDto[] }` — `guestCart` for merge on login (CART-008)
- Password hashing: **argon2id** per `conventions/auth-jwt-design.md` §7 (`memoryCost: 65536`, `timeCost: 3`, `parallelism: 4`) — not bcrypt
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

- `RegisterDto { email, password (min 8), fullName, accountType: 'B2C' | 'B2B' }` per `api-design/auth.md` Registration section
- Check duplicate email → 409 `EMAIL_ALREADY_REGISTERED`
- Hash password with argon2id (per AUTH-003 params); insert single `identity.user` row (roles=['BUYER'], email_verified=false, status='ACTIVE') — no separate profile table
- Generate email verification token; store hash in `identity.email_verification_token` (expires 24h)
- Publish `auth.email_verification_requested` outbox event via `platform.outbox_event` — exact payload shape per spec sequence diagram
- Response 201: `{ data: { userId, email, message: "Verification email sent" } }` — no auto-login, forces verification flow

**Done Criteria**

- Duplicate email → 409
- Invalid body → 400
- Valid registration → `identity.user` row + `identity.email_verification_token` row created; outbox event written in same transaction
- No auto-login token returned on register

---

## AUTH-005 — Email Verification (verify + resend)

- **US Ref:** US-B-02
- **Estimate:** M
- **Dependencies:** AUTH-004, SHARED-007
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /auth/verify-email { token: string }`:
  - Hash incoming token; find unexpired row in `identity.email_verification_token`
  - Delete token; set `identity.user.email_verified = true`
  - Return `{ data: { message: "Email verified" } }`
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

- `POST /auth/login` uses `LocalGuard` (AUTH-003 strategy validates credentials first)
- On success: insert `identity.refresh_session` row, sign JWT access token — exact cookie attributes, TTLs (access 15min, refresh 7d) and response shape per `api-design/auth.md` Login section — see spec, don't restate here
- If `guestCart` sent in body → call `CartService.mergeGuestCart()` (CART-008); include `cartMergeResult` in response (extension beyond base spec contract)
- Suspended/banned account → 403 per spec

**Done Criteria**

- Valid login: access token in body, refresh token in HttpOnly cookie, never in JSON
- Suspended/banned account: 403
- `cartMergeResult` present when guestCart sent

---

## AUTH-007 — Refresh Token Rotation (POST /auth/refresh)

- **US Ref:** US-P-02
- **Estimate:** L
- **Dependencies:** AUTH-006
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /auth/refresh` reads refresh token from `Cookie: refreshToken`; validates against `identity.refresh_session` and rotates (revoke old row, insert new) per `api-design/auth.md` Refresh token sequence — see spec for exact flow, don't restate here
- **Token reuse detection**: presenting an already-revoked token revokes ALL sessions for that user (`identity.refresh_session.revoked_at`), forcing full re-login — no separate "family" concept, per spec

**Done Criteria**

- Valid refresh → new access token + new refresh token cookie
- Expired refresh → 401
- Replaying a previously rotated refresh token → all sessions for that user revoked; 401

---

## AUTH-008 — POST /auth/logout

- **US Ref:** US-B-01
- **Estimate:** S
- **Dependencies:** AUTH-007, SHARED-007
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- `POST /auth/logout` requires valid access token (`@JwtAuthGuard`); revokes the one `identity.refresh_session` row matching the request body's `refreshToken` (not the cookie — see `api-design/auth.md` Logout section)
- Response: 204 No Content (no cookie-clear or Redis revocation per current spec — that's `/auth/logout-all`'s job, AUTH-020)

**Done Criteria**

- Logout revokes only the matching `identity.refresh_session` row; other sessions for the user remain valid
- Missing/invalid `refreshToken` in body → session not found, still returns 204 (idempotent) or per spec error handling
- 204 response

---

## AUTH-009 — Password Reset (forgot-password + reset-password)

- **US Ref:** US-B-03
- **Estimate:** M
- **Dependencies:** AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `POST /auth/forgot-password { email }` — always 202 (enumeration-safe); on match: insert `identity.password_reset_token` (TTL 60min), publish `auth.password_reset_requested` outbox event
- `POST /auth/reset-password { token, newPassword }` — validate + consume token, update `identity.user.password_hash`, revoke all `identity.refresh_session` rows for user, publish `auth.password_changed` outbox event
- Exact request/response shapes per `api-design/auth.md` Forgot password / Reset password sections — see spec, don't restate here

**Done Criteria**

- Unknown email → still 202 (enumeration-safe)
- Expired/used token → 400
- Valid reset → password updated; all existing sessions invalidated
- `auth.password_changed` event in outbox

---

## AUTH-010 — PATCH /auth/change-password (authenticated)

- **US Ref:** US-B-03
- **Estimate:** S
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- `PATCH /auth/change-password { currentPassword, newPassword, currentRefreshToken }` — requires `@JwtAuthGuard`; note method is **PATCH**, not POST
- Verify `currentPassword` via argon2id against stored hash; 401 if wrong
- Revokes all `identity.refresh_session` rows **except the caller's current session** (identified by `currentRefreshToken`) — not a full revoke-all; `auth.password_changed` outbox event
- Exact flow per `api-design/auth.md` Change password section

**Done Criteria**

- Wrong current password → 401
- Successful change → other sessions revoked immediately; caller's current session remains valid

---

## AUTH-011 — Google OAuth (GET /auth/google + callback)

- **US Ref:** US-B-04
- **Estimate:** L
- **Dependencies:** AUTH-001, AUTH-006
- **Spec References:** `phase-1/technical-design/api-design/auth.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- `GET /auth/google` — redirects to Google consent screen (Passport GoogleStrategy, CSRF state nonce)
- `GET /auth/google/callback` — three-branch flow per `api-design/auth.md` OAuth — Google section: existing `identity.oauth_identity` linked / email exists unlinked / new account — see spec for exact branch logic, don't restate here
- Access + refresh token issued same as login (`identity.refresh_session` insert); redirect to `buyer-app/auth/callback?accessToken=...`
- Credentials: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` env vars; callback URL: `${API_URL}/auth/google/callback`

**Done Criteria**

- New user via Google: `identity.user` + `identity.oauth_identity` rows created
- Existing email linked: same user account, new `identity.oauth_identity` row added
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
- Add `'SELLER'` to `identity.user.roles` array (roles is multi-valued per DB Mapping — user keeps BUYER too)
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
- Check if any `identity.user` row has `'ADMIN'` in `roles`; if not, create one:
  - Email: `ADMIN_EMAIL` env var
  - Password: `ADMIN_PASSWORD` env var (argon2id hashed, per AUTH-003 params)
  - `email_verified = true`, `roles = ['ADMIN']`, `status = 'ACTIVE'`
- Idempotent: no-op if admin exists

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

- Events published via outbox (SHARED-005) from auth service methods: `auth.email_verification_requested` (register + resend-verification), `auth.password_reset_requested` (forgot-password), `auth.password_changed` (reset-password + change-password) — exact payload field names per `api-design/auth.md` sequence diagrams, don't restate here
- Notifications module consumes these events to send emails (NOTIFICATIONS-005)
- All events published inside the same transaction as the state change (token creation/update)

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
- Used by admin during suspension flow (ADMIN-008 triggers this)
- Response: 204

**Done Criteria**

- Admin force-logout: target user's next API call with existing access token → 401
- Admin force-logout: refresh attempt → 401

---

## AUTH-020 — POST /auth/logout-all

- **US Ref:** US-B-01
- **Estimate:** S
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- `POST /auth/logout-all` — requires `@JwtAuthGuard`, no request body
- Revokes ALL `identity.refresh_session` rows for the authenticated user; returns count revoked
- Exact response shape per `api-design/auth.md` Logout all sessions section

**Done Criteria**

- All sessions for the user revoked; response includes `sessionsRevoked` count
- A previously issued refresh token for this user now returns 401 on `/auth/refresh`

---

## AUTH-021 — POST /auth/set-password

- **US Ref:** US-S-01
- **Estimate:** S
- **Dependencies:** AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- `POST /auth/set-password { newPassword }` — requires `@JwtAuthGuard`; lets an OAuth-only account (`identity.user.password_hash IS NULL`) link a local password
- Required before an OAuth-only user can apply as a seller (seller application requires local credentials)
- 409 if `password_hash` already set; hash new password with argon2id (AUTH-003 params)

**Done Criteria**

- OAuth-only account: sets password_hash, can subsequently log in via `/auth/login`
- Account with existing local password: 409
