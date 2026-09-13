# EPIC: FE-AUTH — Frontend Authentication Flow

**Sprint:** 10  
**Total Tasks:** 9  

Authentication UI across all three portals: login, registration, email verification, password reset, and OAuth buttons. Angular reactive forms with inline validation. Shared auth components in `libs/shared/`; portal-specific routing in each app.

---

## FE-AUTH-001 — Login Page (Buyer)

- **US Ref:** US-B-01
- **Estimate:** M
- **Dependencies:** FE-SHARED-003, FE-SHARED-004
- **Spec References:** `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- Component: `libs/shared/src/auth/login/login.component.ts` (base component, reused by FE-AUTH-007/008 with portal-specific config — no OAuth buttons, no register link)
- Route: `/login` (buyer-app only; see `phase-1/ui-design/navigation-routing.md` §2)
- Reactive form:
  ```ts
  loginForm = this.fb.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', Validators.required],
  });
  ```
- On submit: calls `AuthStore.login({ email, password })`
- Success: redirect to `returnUrl` query param (or `/`)
- Error handling:
  - `EMAIL_NOT_VERIFIED` → show "Please verify your email" banner with "Resend" link
  - `ACCOUNT_LOCKED` → show "Account locked for 15 minutes due to failed attempts"
  - `ACCOUNT_SUSPENDED` → show "Account suspended. Contact support."
  - Generic 401 → "Invalid email or password"
- "Remember me" checkbox: no-op in V1 (tokens always in-memory; Phase 2 feature)
- OAuth buttons: "Continue with Google" and "Continue with Facebook" (redirect to `/auth/google` and `/auth/facebook`)
- "Don't have an account? Register" link → `/register`

**Done Criteria**

- Valid credentials → redirected to `/` (or `returnUrl`)
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
- Route: `/register` (buyer-app only; no self-registration for seller or admin). Screen/fields/password policy per `phase-1/ui-design/buyer-portal.md` §Screen 10
- On submit: `POST /auth/register`
- Success: navigate to `/auth/verify-email-sent?email=...`
- Error: `EMAIL_TAKEN` → "This email is already registered. Sign in instead."

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

Screens per `phase-1/ui-design/buyer-portal.md` §Screens 12–15. API wiring:
- `/verify-email?token=`: `GET /auth/verify-email?token=`; `INVALID_OR_EXPIRED_TOKEN` → resend option
- `/auth/verify-email-sent?email=`: `POST /auth/resend-verification { email }`; 429 → rate-limit message
- `/auth/forgot-password`: `POST /auth/forgot-password`; always shows success (enumeration prevention)
- `/auth/reset-password?token=`: `POST /auth/reset-password { token, newPassword }`

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

- `AuthLayoutComponent` in each portal wraps all auth routes; layout per each portal doc's Shell Layout section (`buyer-portal.md`/`seller-portal.md`/`admin-portal.md` §Shell Layout)
- After successful login: `guestGuard` prevents returning to login page
- Top navbar shows Sign In/Register when unauthenticated, avatar dropdown (Profile, Orders, Sign Out) when authenticated

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

- Route: `/account/profile` (buyer-app). Screen/fields per `phase-1/ui-design/buyer-portal.md` §Screen 11
- Password change section (separate form): `currentPassword`, `newPassword`, `confirmPassword`; calls `POST /auth/change-password`; on success shows "You have been signed out" + redirects to login
- Address book tab: delegates to `FE-BUYER-012` (address management component)

**Done Criteria**

- Password change: current password verified; success → session cleared; login page shown
- Wrong current password: inline error, no session change
- Profile field editing and avatar upload are owned by `FE-BUYER-011` (this task adds password-change + address-book delegation only)

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

---

## FE-AUTH-007 — Seller Login Page

- **US Ref:** US-S-00
- **Estimate:** M
- **Dependencies:** FE-AUTH-001
- **Spec References:** `phase-1/ui-design/seller-portal.md` §Screen 1 (Seller Login), `phase-1/ui-design/navigation-routing.md` §3

**Implementation Notes**

- Route: `/seller/login` (public; seller-app root — see navigation-routing.md §3, §5 guard matrix)
- Reuses `libs/shared/src/auth/login/login.component.ts` (FE-AUTH-001) configured per seller-portal.md §Screen 1: no OAuth buttons, email/password only, link to `/seller/register`
- On success: redirect per navigation-routing.md §10 (Navigation After Auth Events) — dashboard if approved, `/seller/kyc` if pending
- Error handling: same cases as FE-AUTH-001 (`EMAIL_NOT_VERIFIED`, `ACCOUNT_LOCKED`, generic 401); `SELLER_SUSPENDED` → `/seller/suspended` (FE-SELLER-012)

**Done Criteria**

- Screen matches `seller-portal.md` §Screen 1 exactly (fields, copy, error states)
- Login routes per navigation-routing.md §10 (approved → dashboard, pending KYC → `/seller/kyc`, suspended → `/seller/suspended`)
- No OAuth buttons rendered
- "Register" link → `/seller/register`

---

## FE-AUTH-008 — Admin Login Page

- **US Ref:** US-A-00b
- **Estimate:** M
- **Dependencies:** FE-AUTH-001
- **Spec References:** `phase-1/ui-design/admin-portal.md` §Screen 1 (Admin Login), `phase-1/ui-design/navigation-routing.md` §4

**Implementation Notes**

- Route: `/admin/login` (public; admin-app root — see navigation-routing.md §4, §5 guard matrix)
- Reuses `libs/shared/src/auth/login/login.component.ts` (FE-AUTH-001) configured per admin-portal.md §Screen 1: no OAuth buttons, no register link (admin accounts are seed-provisioned only, per US-A-00b)
- On success: redirect to `/admin/dashboard` (navigation-routing.md §10)

**Done Criteria**

- Screen matches `admin-portal.md` §Screen 1 exactly
- No OAuth buttons, no register link rendered
- Successful login → `/admin/dashboard`
- Non-admin credentials rejected with generic 401 (no role hint leaked)

---

## FE-AUTH-009 — Seller Registration Page

- **US Ref:** US-S-01
- **Estimate:** L
- **Dependencies:** FE-AUTH-007
- **Spec References:** `phase-1/ui-design/seller-portal.md` §Screen 2 (Seller Register), `phase-1/ui-design/navigation-routing.md` §3, §10

**Implementation Notes**

- Route: `/seller/register` (public; seller-app — see navigation-routing.md §3)
- Screen/fields/validation per `seller-portal.md` §Screen 2 (account step only: business name, email, password, confirm)
- On submit: `POST /auth/register` (accountType: SELLER)
- On success: redirect to `/seller/kyc` per navigation-routing.md §10 — KYC application intake itself is FE-SELLER-002 (status) / FE-SELLER-003 (document upload); this task does not duplicate that flow
- Error handling: `EMAIL_TAKEN` → inline field error (same pattern as FE-AUTH-002)

**Done Criteria**

- Screen matches `seller-portal.md` §Screen 2
- Valid submit → account created, redirected to `/seller/kyc`
- Duplicate email → inline error, no navigation
- Does not re-implement KYC document upload (delegates to FE-SELLER-002/003)
