# Auth API — Identity & Auth

**Module:** `Identity` / `Auth`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.1](../../requirements/BRD.md), [auth-jwt-design](../../../conventions/auth-jwt-design.md), [ERD](../data-model-erd.md)

---

## Endpoint Index

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | [`/auth/register`](#registration) | PUBLIC | Register new account |
| `POST` | [`/auth/login`](#login-local) | PUBLIC | Login with email + password |
| `POST` | [`/auth/refresh`](#refresh-token) | PUBLIC | Rotate refresh token pair |
| `POST` | [`/auth/logout`](#logout) | JWT | Revoke current session |
| `POST` | [`/auth/logout-all`](#logout-all-sessions) | JWT | Revoke all sessions |
| `POST` | [`/auth/verify-email`](#email-verification) | PUBLIC | Consume email verification token |
| `POST` | [`/auth/resend-verification`](#resend-verification-email) | JWT | Re-send verification email |
| `POST` | [`/auth/forgot-password`](#forgot-password) | PUBLIC | Request password reset link |
| `POST` | [`/auth/reset-password`](#reset-password) | PUBLIC | Consume reset token + set new password |
| `PATCH` | [`/auth/change-password`](#change-password-authenticated) | JWT | Change password while authenticated |
| `GET` | [`/auth/google`](#oauth--google-buyer-only) | PUBLIC | Initiate Google OAuth |
| `GET` | [`/auth/google/callback`](#oauth--google-buyer-only) | PUBLIC | Google OAuth callback |
| `GET` | [`/auth/facebook`](#oauth--facebook-buyer-only) | PUBLIC | Initiate Facebook OAuth |
| `GET` | [`/auth/facebook/callback`](#oauth--facebook-buyer-only) | PUBLIC | Facebook OAuth callback |
| `POST` | [`/auth/set-password`](#set-local-password-oauth-only-account) | JWT | Link local password to OAuth-only account |

---

## DB Mapping

| Endpoint | Primary DB | Tables / Notes |
|----------|-----------|----------------|
| `POST /auth/register` | Postgres | `identity.user`, `identity.email_verification_token` + `platform.outbox_event` (verification email event) |
| `POST /auth/login` | Postgres | `identity.user` (read), `identity.refresh_session` (insert) |
| `POST /auth/refresh` | Postgres | `identity.refresh_session` (rotate) |
| `POST /auth/logout` | Postgres | `identity.refresh_session` (revoke one) |
| `POST /auth/logout-all` | Postgres | `identity.refresh_session` (revoke all for user) |
| `POST /auth/verify-email` | Postgres | `identity.email_verification_token` (consume), `identity.user` (set `email_verified`) |
| `POST /auth/resend-verification` | Postgres | `identity.email_verification_token` (upsert) + `platform.outbox_event` |
| `POST /auth/forgot-password` | Postgres | `identity.password_reset_token` (insert) + `platform.outbox_event` |
| `POST /auth/reset-password` | Postgres | `identity.password_reset_token` (consume), `identity.user` (hash), `identity.refresh_session` (revoke all) |
| `PATCH /auth/change-password` | Postgres | `identity.user` (hash), `identity.refresh_session` (revoke others) |
| `GET /auth/google`, `GET /auth/google/callback` | Postgres | `identity.user` (upsert), `identity.oauth_identity` (upsert), `identity.refresh_session` (insert) |
| `GET /auth/facebook`, `GET /auth/facebook/callback` | Postgres | `identity.user` (upsert), `identity.oauth_identity` (upsert), `identity.refresh_session` (insert) |
| `POST /auth/set-password` | Postgres | `identity.user` (`password_hash`) |

---

## Endpoints

### Registration

```
POST /auth/register
Tag: Auth
Auth: PUBLIC
Rate limit: 5 attempts per IP per 15 min
```
**Request body**
```json
{
  "email": "string (email)",
  "password": "string (min 8)",
  "fullName": "string",
  "accountType": "B2C | B2B"
}
```
**Response 201**
```json
{
  "userId": "uuid",
  "email": "string",
  "message": "Verification email sent"
}
```
**Errors:** 400 validation, 409 email already registered

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres
    participant KO as Kafka Outbox
    participant KR as Kafka Relay

    C->>A: POST /auth/register {email, password, fullName, accountType}

    A->>A: Rate limit check (5 req / IP / 15 min)
    alt rate limit exceeded
        A-->>C: 429 Too Many Requests
    end

    A->>A: Validate body (email format, password min 8, fullName, accountType enum)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>IS: register(dto)
    IS->>PG: SELECT identity.user WHERE LOWER(email) = LOWER($1)
    alt email already registered
        IS-->>A: ConflictException
        A-->>C: 409 Conflict "Email already registered"
    end

    IS->>IS: argon2id.hash(password)
    IS->>IS: crypto.randomBytes(32) → raw_token — SHA-256(raw_token) → token_hash

    IS->>PG: BEGIN TRANSACTION
    IS->>PG: INSERT identity.user (email, password_hash, full_name, roles=['BUYER'], email_verified=false, account_type, status='ACTIVE')
    IS->>PG: INSERT identity.email_verification_token (user_id, token_hash, expires_at=NOW()+24h)
    IS->>PG: INSERT platform.outbox_event (topic='auth.email_verification_requested', payload={user_id, email, verification_token, expires_at})
    IS->>PG: COMMIT

    IS-->>A: {userId, email}
    A-->>C: 201 {userId, email, message: "Verification email sent"}

    Note over KO,KR: async — runs after TX commit, outside request cycle
    KR->>PG: Poll platform.outbox_event WHERE publication_status='PENDING'
    KR->>KO: Publish to auth.email_verification_requested topic
    KR->>PG: UPDATE platform.outbox_event SET publication_status='PUBLISHED'
    Note right of KO: notification.email-verification consumer sends ET-18 to user
```

---

### Login (local)

```
POST /auth/login
Tag: Auth
Auth: PUBLIC
Rate limit: 10 attempts per IP per 15 min (lockout after 10 failures)
```
**Request body**
```json
{ "email": "string", "password": "string" }
```
**Response 200**
```json
{
  "accessToken": "string (JWT, 15 min)",
  "refreshToken": "string (opaque, 7 days)",
  "user": {
    "id": "uuid",
    "email": "string",
    "fullName": "string",
    "roles": ["BUYER"],
    "emailVerified": true,
    "accountType": "B2C | B2B"
  }
}
```
**Errors:** 401 invalid credentials, 403 account suspended/banned

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres

    C->>A: POST /auth/login {email, password}

    A->>A: Rate limit check (10 req / IP / 15 min)
    alt rate limit exceeded
        A-->>C: 429 Too Many Requests
    end

    A->>A: Validate body (email, password required)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>IS: login(email, password, deviceMetadata)
    IS->>PG: SELECT identity.user WHERE LOWER(email) = LOWER($1)
    alt user not found
        IS-->>A: UnauthorizedException
        A-->>C: 401 Unauthorized "Invalid credentials"
    end

    IS->>IS: argon2id.verify(password, user.password_hash)
    alt password mismatch or password_hash IS NULL (OAuth-only account)
        IS-->>A: UnauthorizedException
        A-->>C: 401 Unauthorized "Invalid credentials"
    end

    alt user.status = 'SUSPENDED' or 'BANNED'
        IS-->>A: ForbiddenException
        A-->>C: 403 Forbidden "Account suspended"
    end

    IS->>IS: crypto.randomBytes(32) → refreshToken (opaque) — SHA-256(refreshToken) → token_hash
    IS->>IS: Sign JWT accessToken (sub, roles, email_verified, account_type, seller_kyc_status, seller_suspension_status, exp=NOW()+15min)

    IS->>PG: INSERT identity.refresh_session (user_id, token_hash, expires_at=NOW()+7d, device_metadata)

    IS-->>A: {accessToken, refreshToken, user}
    A-->>C: 200 {accessToken, refreshToken, user}
    Note right of C: refreshToken delivered via HttpOnly Secure SameSite=Strict cookie (path=/api/v1/auth/refresh)
```

---

### Refresh token

```
POST /auth/refresh
Tag: Auth
Auth: PUBLIC (refresh token in body)
```
**Request body**
```json
{ "refreshToken": "string" }
```
**Response 200** — same shape as login response (new access + refresh token pair). Old refresh token is immediately invalidated.  
**Errors:** 401 token expired/revoked/not found

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres

    C->>A: POST /auth/refresh {refreshToken}

    A->>IS: rotateRefreshToken(refreshToken)
    IS->>IS: SHA-256(refreshToken) → token_hash
    IS->>PG: SELECT identity.refresh_session WHERE token_hash = $1

    alt session not found (token never issued)
        IS-->>A: UnauthorizedException
        A-->>C: 401 Unauthorized
    end

    alt session found AND revoked_at IS NOT NULL (token reuse — possible attack)
        IS->>PG: UPDATE identity.refresh_session SET revoked_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL
        Note right of PG: revoke ALL active sessions for this user
        IS-->>A: UnauthorizedException
        A-->>C: 401 Unauthorized
        Note right of C: Full re-login required — all sessions revoked
    end

    alt session found AND expires_at <= NOW()
        IS-->>A: UnauthorizedException
        A-->>C: 401 Unauthorized "Token expired"
    end

    IS->>PG: SELECT identity.user WHERE id = session.user_id
    IS->>IS: crypto.randomBytes(32) → newRefreshToken — SHA-256 → new_token_hash
    IS->>IS: Sign new JWT accessToken (sub, roles, email_verified, account_type, seller_kyc_status, seller_suspension_status, exp=NOW()+15min)

    IS->>PG: BEGIN TRANSACTION
    IS->>PG: UPDATE identity.refresh_session SET replaced_at=NOW() WHERE id=$1
    IS->>PG: INSERT identity.refresh_session (user_id, new_token_hash, expires_at=NOW()+7d, device_metadata)
    IS->>PG: COMMIT

    IS-->>A: {accessToken, newRefreshToken, user}
    A-->>C: 200 {accessToken, refreshToken, user}
    Note right of C: new HttpOnly refreshToken cookie replaces old
```

---

### Logout

```
POST /auth/logout
Tag: Auth
Auth: JWT
```
**Request body**
```json
{ "refreshToken": "string" }
```
**Response 204** — revokes the provided refresh token.

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres

    C->>G: POST /auth/logout {refreshToken} (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, roles, ...}

    A->>IS: logout(refreshToken, userId)
    IS->>IS: SHA-256(refreshToken) → token_hash
    IS->>PG: UPDATE identity.refresh_session SET revoked_at=NOW() WHERE token_hash=$1 AND user_id=JWT.sub AND revoked_at IS NULL

    IS-->>A: success
    A-->>C: 204 No Content
```

---

### Logout all sessions

```
POST /auth/logout-all
Tag: Auth
Auth: JWT
```
No request body. Invalidates **all** refresh_sessions for the authenticated user.  
**Response 200** `{ "sessionsRevoked": number }`

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres

    C->>G: POST /auth/logout-all (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, roles, ...}

    A->>IS: logoutAll(userId)
    IS->>PG: UPDATE identity.refresh_session SET revoked_at=NOW() WHERE user_id=JWT.sub AND revoked_at IS NULL
    Note right of PG: returns count of rows updated

    IS-->>A: {sessionsRevoked: count}
    A-->>C: 200 {sessionsRevoked: count}
```

---

### Email verification

```
POST /auth/verify-email
Tag: Auth
Auth: PUBLIC
```
**Request body**
```json
{ "token": "string (single-use, 24h TTL)" }
```
**Response 200** `{ "message": "Email verified" }`  
**Errors:** 400 invalid/expired token, 409 already verified

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres

    C->>A: POST /auth/verify-email {token}

    A->>A: Validate body (token required)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>IS: verifyEmail(token)
    IS->>IS: SHA-256(token) → token_hash
    IS->>PG: SELECT identity.email_verification_token WHERE token_hash = $1

    alt token not found or expires_at <= NOW()
        IS-->>A: BadRequestException
        A-->>C: 400 Bad Request "Invalid or expired token"
    end

    IS->>PG: SELECT identity.user WHERE id = token.user_id
    alt user.email_verified = true
        IS-->>A: ConflictException
        A-->>C: 409 Conflict "Email already verified"
    end

    IS->>PG: BEGIN TRANSACTION
    IS->>PG: DELETE identity.email_verification_token WHERE user_id = $1
    IS->>PG: UPDATE identity.user SET email_verified=true WHERE id = $1
    IS->>PG: COMMIT

    IS-->>A: success
    A-->>C: 200 {message: "Email verified"}
```

---

### Resend verification email

```
POST /auth/resend-verification
Tag: Auth
Auth: JWT
Rate limit: 3 per hour per email address
```
**Response 202** `{ "message": "Verification email queued" }`  
**Errors:** 409 already verified, 429 rate limited

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres
    participant KO as Kafka Outbox
    participant KR as Kafka Relay

    C->>G: POST /auth/resend-verification (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, email, ...}

    A->>A: Rate limit check (3 req / user email / 1 hour)
    alt rate limit exceeded
        A-->>C: 429 Too Many Requests
    end

    A->>IS: resendVerification(userId)
    IS->>PG: SELECT identity.user WHERE id = JWT.sub
    alt user.email_verified = true
        IS-->>A: ConflictException
        A-->>C: 409 Conflict "Email already verified"
    end

    IS->>IS: crypto.randomBytes(32) → raw_token — SHA-256(raw_token) → token_hash

    IS->>PG: BEGIN TRANSACTION
    IS->>PG: DELETE identity.email_verification_token WHERE user_id = $1
    IS->>PG: INSERT identity.email_verification_token (user_id, token_hash, expires_at=NOW()+24h)
    IS->>PG: INSERT platform.outbox_event (topic='auth.email_verification_requested', payload={user_id, email, verification_token, expires_at})
    IS->>PG: COMMIT

    IS-->>A: success
    A-->>C: 202 {message: "Verification email queued"}

    Note over KO,KR: async — runs after TX commit
    KR->>PG: Poll platform.outbox_event WHERE publication_status='PENDING'
    KR->>KO: Publish to auth.email_verification_requested topic
    KR->>PG: UPDATE platform.outbox_event SET publication_status='PUBLISHED'
    Note right of KO: notification.email-verification consumer sends ET-18 to user
```

---

### Forgot password

```
POST /auth/forgot-password
Tag: Auth
Auth: PUBLIC
Rate limit: 3 per hour per email address
```
**Request body**
```json
{ "email": "string" }
```
**Response 202** `{ "message": "If the email exists, a reset link has been sent" }` (always 202 to prevent user enumeration)

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres
    participant KO as Kafka Outbox
    participant KR as Kafka Relay

    C->>A: POST /auth/forgot-password {email}

    A->>A: Rate limit check (3 req / email / 1 hour)
    alt rate limit exceeded
        A-->>C: 429 Too Many Requests
    end

    A->>A: Validate body (email format required)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>IS: forgotPassword(email)
    IS->>PG: SELECT identity.user WHERE LOWER(email) = LOWER($1)

    alt user found
        IS->>IS: crypto.randomBytes(32) → raw_token — SHA-256(raw_token) → token_hash
        IS->>PG: BEGIN TRANSACTION
        IS->>PG: INSERT identity.password_reset_token (user_id, token_hash, expires_at=NOW()+60min)
        IS->>PG: INSERT platform.outbox_event (topic='auth.password_reset_requested', payload={user_id, email, reset_token, expires_at})
        IS->>PG: COMMIT
        Note over KO,KR: async — runs after TX commit
        KR->>PG: Poll platform.outbox_event WHERE publication_status='PENDING'
        KR->>KO: Publish to auth.password_reset_requested topic
        KR->>PG: UPDATE platform.outbox_event SET publication_status='PUBLISHED'
        Note right of KO: notification.password-reset consumer sends ET-19 reset-link email
    else user not found
        Note over IS: no-op — same 202 response prevents user enumeration
    end

    IS-->>A: always success
    A-->>C: 202 {message: "If the email exists, a reset link has been sent"}
```

---

### Reset password

```
POST /auth/reset-password
Tag: Auth
Auth: PUBLIC
```
**Request body**
```json
{ "token": "string (single-use, 60 min TTL)", "newPassword": "string (min 8)" }
```
**Response 200** `{ "message": "Password updated. All sessions revoked." }`  
**Errors:** 400 invalid/expired token

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres
    participant KO as Kafka Outbox
    participant KR as Kafka Relay

    C->>A: POST /auth/reset-password {token, newPassword}

    A->>A: Validate body (token required, newPassword min 8)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>IS: resetPassword(token, newPassword)
    IS->>IS: SHA-256(token) → token_hash
    IS->>PG: SELECT identity.password_reset_token WHERE token_hash = $1

    alt token not found
        IS-->>A: BadRequestException
        A-->>C: 400 Bad Request "Invalid or expired token"
    end

    alt token.used_at IS NOT NULL
        IS-->>A: BadRequestException
        A-->>C: 400 Bad Request "Invalid or expired token"
    end

    alt token.expires_at <= NOW()
        IS-->>A: BadRequestException
        A-->>C: 400 Bad Request "Invalid or expired token"
    end

    IS->>IS: argon2id.hash(newPassword)

    IS->>PG: BEGIN TRANSACTION
    IS->>PG: UPDATE identity.password_reset_token SET used_at=NOW() WHERE id=$1
    IS->>PG: UPDATE identity.user SET password_hash=newHash WHERE id=token.user_id
    IS->>PG: UPDATE identity.refresh_session SET revoked_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL
    IS->>PG: INSERT platform.outbox_event (topic='auth.password_changed', payload={user_id, email, changed_at})
    IS->>PG: COMMIT

    IS-->>A: success
    A-->>C: 200 {message: "Password updated. All sessions revoked."}

    Note over KO,KR: async — runs after TX commit
    KR->>PG: Poll platform.outbox_event WHERE publication_status='PENDING'
    KR->>KO: Publish to auth.password_changed topic
    KR->>PG: UPDATE platform.outbox_event SET publication_status='PUBLISHED'
    Note right of KO: notification.password-changed consumer sends ET-20 confirmation email
```

---

### Change password (authenticated)

```
PATCH /auth/change-password
Tag: Auth
Auth: JWT
```
**Request body**
```json
{ "currentPassword": "string", "newPassword": "string (min 8)", "currentRefreshToken": "string" }
```
**Response 200** `{ "message": "Password changed. All other sessions revoked." }`  
**Errors:** 400 validation, 401 current password wrong

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres
    participant KO as Kafka Outbox
    participant KR as Kafka Relay

    C->>G: PATCH /auth/change-password {currentPassword, newPassword, currentRefreshToken} (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, ...}

    A->>A: Validate body (currentPassword, newPassword min 8, currentRefreshToken required)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>IS: changePassword(userId, currentPassword, newPassword, currentRefreshToken)
    IS->>PG: SELECT identity.user WHERE id = JWT.sub
    IS->>IS: argon2id.verify(currentPassword, user.password_hash)
    alt current password does not match
        IS-->>A: UnauthorizedException
        A-->>C: 401 Unauthorized "Current password is incorrect"
    end

    IS->>IS: argon2id.hash(newPassword)
    IS->>IS: SHA-256(currentRefreshToken) → current_token_hash

    IS->>PG: BEGIN TRANSACTION
    IS->>PG: UPDATE identity.user SET password_hash=newHash WHERE id=JWT.sub
    IS->>PG: UPDATE identity.refresh_session SET revoked_at=NOW() WHERE user_id=JWT.sub AND token_hash != current_token_hash AND revoked_at IS NULL
    Note right of PG: revokes all sessions except the caller's current session
    IS->>PG: INSERT platform.outbox_event (topic='auth.password_changed', payload={user_id, email, changed_at})
    IS->>PG: COMMIT

    IS-->>A: success
    A-->>C: 200 {message: "Password changed. All other sessions revoked."}

    Note over KO,KR: async — runs after TX commit
    KR->>PG: Poll platform.outbox_event WHERE publication_status='PENDING'
    KR->>KO: Publish to auth.password_changed topic
    KR->>PG: UPDATE platform.outbox_event SET publication_status='PUBLISHED'
    Note right of KO: notification.password-changed consumer sends ET-20 confirmation email
```

---

### OAuth — Google (buyer only)

```
GET /auth/google
Tag: Auth
Auth: PUBLIC
```
Redirects to Google OAuth consent screen. Passport.js handles the redirect.

```
GET /auth/google/callback
Tag: Auth
Auth: PUBLIC
```
Google redirects here with authorization code. On success, issues JWT pair and redirects to buyer app with tokens in query params or sets a short-lived code that the SPA exchanges.  
**Errors:** 400 OAuth error, 409 email linked to different provider without local password

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant A as NestJS API
    participant G as Google OAuth
    participant PG as Postgres

    C->>A: GET /auth/google
    A->>A: Passport GoogleStrategy generates state nonce — stores in short-lived session cookie
    A-->>C: 302 Redirect to Google consent URL (client_id, redirect_uri, scope, state)

    C->>G: User reviews and consents
    G-->>C: 302 Redirect to /auth/google/callback?code=...&state=...

    C->>A: GET /auth/google/callback?code=...&state=...
    A->>A: Validate state param against session cookie (CSRF check)
    alt state mismatch
        A-->>C: 400 Bad Request "OAuth state invalid"
    end

    A->>G: Exchange code for access_token + id_token (Passport GoogleStrategy)
    G-->>A: {sub: provider_subject, email, email_verified, name}

    alt OAuth error returned by Google
        A-->>C: 400 Bad Request "OAuth error"
    end

    A->>PG: SELECT identity.oauth_identity JOIN identity.user WHERE provider='GOOGLE' AND provider_subject=$1

    alt existing account — Google already linked
        A->>PG: INSERT identity.refresh_session (user_id, token_hash, expires_at=NOW()+7d)
        A->>A: Sign JWT accessToken
        A-->>C: 302 Redirect to buyer-app/auth/callback?accessToken=...
        Note right of C: HttpOnly Secure SameSite=Strict refreshToken cookie set
    else email exists but Google not yet linked
        A->>PG: SELECT identity.user WHERE LOWER(email) = LOWER(google_email)
        A->>PG: BEGIN TRANSACTION
        A->>PG: INSERT identity.oauth_identity (user_id, provider='GOOGLE', provider_subject, verified_email)
        A->>PG: UPDATE identity.user SET email_verified=true WHERE id=$1
        A->>PG: INSERT identity.refresh_session (user_id, token_hash, expires_at=NOW()+7d)
        A->>PG: COMMIT
        A->>A: Sign JWT accessToken
        A-->>C: 302 Redirect to buyer-app/auth/callback?accessToken=...
        Note right of C: HttpOnly Secure SameSite=Strict refreshToken cookie set
    else new email — create account
        A->>PG: BEGIN TRANSACTION
        A->>PG: INSERT identity.user (email, full_name=google_name, roles=['BUYER'], email_verified=true, password_hash=NULL, status='ACTIVE')
        A->>PG: INSERT identity.oauth_identity (user_id, provider='GOOGLE', provider_subject, verified_email)
        A->>PG: INSERT identity.refresh_session (user_id, token_hash, expires_at=NOW()+7d)
        A->>PG: COMMIT
        A->>A: Sign JWT accessToken
        A-->>C: 302 Redirect to buyer-app/auth/callback?accessToken=...
        Note right of C: HttpOnly Secure SameSite=Strict refreshToken cookie set
    end
```

---

### OAuth — Facebook (buyer only)

```
GET /auth/facebook
Tag: Auth
Auth: PUBLIC
```
Redirects to Facebook OAuth consent.

```
GET /auth/facebook/callback
Tag: Auth
Auth: PUBLIC
```
Same exchange flow as Google.

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant A as NestJS API
    participant FB as Facebook OAuth
    participant PG as Postgres

    Note over C,PG: Identical flow to Google OAuth above with provider='FACEBOOK' and passport-facebook strategy. Profile fields requested: id, email, name. If Facebook returns no email in the callback, the user is prompted to supply one before account creation proceeds.
    C->>A: GET /auth/facebook
    A-->>C: 302 Redirect to Facebook consent URL

    C->>FB: User consents
    FB-->>C: 302 Redirect to /auth/facebook/callback?code=...&state=...

    C->>A: GET /auth/facebook/callback?code=...&state=...
    A->>FB: Exchange code for tokens
    FB-->>A: {id: provider_subject, email (may be absent), name}

    alt no email returned by Facebook
        A-->>C: Prompt user to supply email before account creation
    end

    Note over A,PG: Same three-branch alt as Google — existing linked, email exists unlinked, new account — with provider='FACEBOOK'
    A->>PG: upsert identity.user, identity.oauth_identity (provider='FACEBOOK'), INSERT identity.refresh_session
    A->>A: Sign JWT accessToken
    A-->>C: 302 Redirect to buyer-app/auth/callback?accessToken=...
    Note right of C: HttpOnly Secure SameSite=Strict refreshToken cookie set
```

---

### Set local password (OAuth-only account)

Required before an OAuth user can apply as a seller.

```
POST /auth/set-password
Tag: Auth
Auth: JWT
```
**Request body**
```json
{ "newPassword": "string (min 8)" }
```
**Response 200** `{ "message": "Local password linked" }`  
**Errors:** 409 already has local password

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtGuard
    participant A as NestJS API
    participant IS as IdentityService
    participant PG as Postgres

    C->>G: POST /auth/set-password {newPassword} (Bearer accessToken)
    G->>G: Verify JWT signature + expiry
    alt token missing or invalid/expired
        G-->>C: 401 Unauthorized
    end
    G->>A: proceed with decoded JWT {sub, ...}

    A->>A: Validate body (newPassword min 8 required)
    alt validation fails
        A-->>C: 400 Bad Request {errors[]}
    end

    A->>IS: setLocalPassword(userId, newPassword)
    IS->>PG: SELECT identity.user WHERE id = JWT.sub
    alt user.password_hash IS NOT NULL
        IS-->>A: ConflictException
        A-->>C: 409 Conflict "Already has local password"
    end

    IS->>IS: argon2id.hash(newPassword)
    IS->>PG: UPDATE identity.user SET password_hash=newHash WHERE id=JWT.sub

    IS-->>A: success
    A-->>C: 200 {message: "Local password linked"}
```
