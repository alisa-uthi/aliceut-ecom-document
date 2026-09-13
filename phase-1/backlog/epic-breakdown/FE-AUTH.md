# EPIC: FE-AUTH — Frontend Authentication Flow

**Sprint:** 10  
**Total Tasks:** 6  

Authentication UI across all three portals: login, registration, email verification, password reset, and OAuth buttons. Angular reactive forms with inline validation. Shared auth components in `libs/shared/`; portal-specific routing in each app.

---

## FE-AUTH-001 — Login Page

- **US Ref:** US-B-01, US-S-01, US-A-00
- **Estimate:** M
- **Dependencies:** FE-SHARED-003, FE-SHARED-004
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- Component: `libs/shared/src/auth/login/login.component.ts` (shared; used in all 3 portals)
- Route: `/login` in buyer-app, `/login` in seller-app, `/login` in admin-app
- Reactive form:
  ```ts
  loginForm = this.fb.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', Validators.required],
  });
  ```
- On submit: calls `AuthStore.login({ email, password })`
- Success: redirect to `returnUrl` query param (or portal home)
- Error handling:
  - `EMAIL_NOT_VERIFIED` → show "Please verify your email" banner with "Resend" link
  - `ACCOUNT_LOCKED` → show "Account locked for 15 minutes due to failed attempts"
  - `ACCOUNT_SUSPENDED` → show "Account suspended. Contact support."
  - Generic 401 → "Invalid email or password"
- "Remember me" checkbox: no-op in V1 (tokens always in-memory; Phase 2 feature)
- OAuth buttons: "Continue with Google" and "Continue with Facebook" (redirect to `/auth/google` and `/auth/facebook`)
- Buyer portal only: "Don't have an account? Register" link
- Admin portal: no registration link; admin accounts seeded only

**Done Criteria**

- Valid credentials → redirected to portal home
- Invalid credentials → inline error message (no page reload)
- `EMAIL_NOT_VERIFIED` error → banner with resend link visible
- Google OAuth button redirects to correct backend URL
- Form shows validation errors on submit attempt with empty fields

---

## FE-AUTH-002 — Registration Page (Buyer Portal)

- **US Ref:** US-B-00
- **Estimate:** M
- **Dependencies:** FE-SHARED-003, FE-AUTH-001
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- Component: `buyer-app/src/app/auth/register/register.component.ts`
- Route: `/register` (buyer-app only; no self-registration for seller or admin)
- Reactive form:
  ```ts
  registerForm = this.fb.group({
    displayName: ['', [Validators.required, Validators.maxLength(100)]],
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(8), passwordStrengthValidator]],
    confirmPassword: ['', Validators.required],
    accountType: ['B2C'],    // radio: B2C (default) | B2B
  }, { validators: passwordMatchValidator });
  ```
- `passwordStrengthValidator`: checks 1 uppercase, 1 lowercase, 1 digit; shows inline hint
- B2B account type: shows additional `companyName` field (required for B2B)
- On submit: `POST /auth/register`
- Success: navigate to `/auth/verify-email-sent?email=...` (informational page)
- Error handling:
  - `EMAIL_TAKEN` → "This email is already registered. Sign in instead."
  - Validation errors → field-level error messages

**Done Criteria**

- Valid registration → "Verify your email" page shown
- Duplicate email → inline error on email field
- Weak password → strength indicator shows missing requirements
- Password mismatch → "Passwords do not match" error
- B2B selected → company name field appears (required)
- Account type toggle works; radio buttons styled correctly

---

## FE-AUTH-003 — Email Verification & Password Reset Pages

- **US Ref:** US-B-00
- **Estimate:** M
- **Dependencies:** FE-AUTH-002
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- `verify-email` page (`/verify-email?token=`): on load, extracts token from query param; calls `GET /auth/verify-email?token=`
  - Success: show "Email verified! Sign in now." with login button
  - Error `INVALID_OR_EXPIRED_TOKEN`: show "Link expired or invalid. Request a new one." with resend button
  - Loading state while API call in progress
- `verify-email-sent` page (`/auth/verify-email-sent?email=`): static informational page + resend form
  - Shows email address; "Resend verification email" button
  - Calls `POST /auth/resend-verification { email }`
  - Rate limit error (429): "You can request a new email in X minutes"
- `forgot-password` page (`/auth/forgot-password`): email input form; calls `POST /auth/forgot-password`; always shows success message (prevent enumeration)
- `reset-password` page (`/auth/reset-password?token=`): new password + confirm form; calls `POST /auth/reset-password { token, newPassword }`
  - Success: "Password changed. Sign in with your new password." + login link
  - Error: "Link expired" + link to request new reset

**Done Criteria**

- Valid verification token: "Email verified" message; login button works
- Invalid/expired token: "Link expired" message with resend option
- Forgot password: success message shown regardless of whether email exists (enumeration prevention)
- Reset password: form shows strength requirements; success → login redirect

---

## FE-AUTH-004 — Auth Layout & Navigation Integration

- **US Ref:** —
- **Estimate:** S
- **Dependencies:** FE-AUTH-001, FE-SHARED-005
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- Auth pages share a minimal layout (logo + centered card; no sidebar/nav):
  ```
  [AliceUT Logo]
  ┌─────────────────────────┐
  │     Login / Register    │
  │  [form content]         │
  └─────────────────────────┘
  ```
- `AuthLayoutComponent` in each portal wraps all `/auth/*` routes
- After successful login: `guestGuard` prevents returning to login page
- Top navbar (portal-specific) shows:
  - Unauthenticated: "Sign In" + (buyer: "Register") links
  - Authenticated: user avatar + dropdown (Profile, Orders, Sign Out)
- Avatar dropdown built with `MatMenu`; shows `displayName` and role badge

**Done Criteria**

- Auth pages use minimal centered layout (no sidebar)
- Top navbar shows correct links based on auth state
- Clicking "Sign Out" from dropdown calls logout; redirects to login
- `isAuthenticated` signal change triggers navbar update reactively

---

## FE-AUTH-005 — Profile Page

- **US Ref:** US-B-02
- **Estimate:** M
- **Dependencies:** FE-SHARED-002, FE-AUTH-004
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- Route: `/account/profile` (buyer-app); `/seller/profile` (seller-app)
- Fetches `GET /profile` on load
- Edit form (reactive):
  - `displayName`, `phoneNumber`, `dateOfBirth` (date picker)
  - B2B only: `companyName`, `taxId` fields (conditional)
- Avatar upload: `<input type="file">` (hidden) triggered by avatar click; calls `POST /profile/avatar`; shows preview before upload + upload progress
- Password change section (separate form): `currentPassword`, `newPassword`, `confirmPassword`; calls `POST /auth/change-password`; on success shows "You have been signed out" + redirects to login
- Address book tab: delegates to `FE-BUYER-004` (address management component)

**Done Criteria**

- Profile data loads; edits saved correctly
- Avatar upload: image preview shown before upload; uploaded image displayed after
- Password change: success → session cleared; login page shown
- B2B fields appear for B2B accounts; hidden for B2C
- `dateOfBirth` date picker works on mobile (native date input)

---

## FE-AUTH-006 — OAuth Callback Handler

- **US Ref:** US-B-00
- **Estimate:** S
- **Dependencies:** FE-AUTH-001, FE-SHARED-003
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- Route: `/auth/callback` (buyer-app)
- Backend redirects here after OAuth: `/auth/callback?token=<accessToken>&refresh=<refreshToken>&error=<errorCode>`
- Angular component reads query params on `ngOnInit`:
  ```ts
  const token = this.route.snapshot.queryParams['token'];
  const refresh = this.route.snapshot.queryParams['refresh'];
  const error = this.route.snapshot.queryParams['error'];
  
  if (error) {
    this.router.navigate(['/login'], { queryParams: { error } });
    return;
  }
  
  this.authStore.setTokens({ accessToken: token, refreshToken: refresh });
  // fetch user profile, then redirect
  this.authService.getProfile().subscribe(user => {
    this.authStore.setUser(user);
    this.router.navigate(['/']);
  });
  ```
- If guest cart exists (session ID in localStorage): call `POST /cart/merge { sessionId }` before redirect
- Error cases: `OAUTH_PROVIDER_ERROR`, `EMAIL_TAKEN_DIFFERENT_PROVIDER` → show error on login page

**Done Criteria**

- OAuth flow: redirect to `/auth/callback?token=...`; tokens set in store; user profile fetched; redirect to home
- Error in OAuth flow: redirect to `/login` with error query param; error message shown
- Guest cart merge: if `sessionId` in localStorage, cart merged before redirect
- No tokens visible in URL after successful OAuth (Angular clears query params after processing)
