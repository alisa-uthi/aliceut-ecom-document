# EPIC: FE-SHARED — Frontend Shared Libraries

**Sprint:** 9–10  
**Total Tasks:** 7  
**Status:** Planned  

Shared Angular libraries used by all three portals: API client, Angular Material theme, auth state management, common UI components, HTTP interceptors, guards, and error handling. Must be in place before any portal-specific feature work begins.

---

## FE-SHARED-001 — Angular Material Theme Setup

| Field | Value |
|-------|-------|
| **US Ref** | — |
| **Estimate** | M (1d) |
| **Dependencies** | INFRA-002 |

**Implementation Notes**

- File: `libs/shared/src/styles/theme.scss`
- Angular Material 3 custom theme using M3 `mat.define-theme()`:
  ```scss
  @use '@angular/material' as mat;
  
  $aliceut-theme: mat.define-theme((
    color: (
      theme-type: light,
      primary: mat.$violet-palette,    // adjust per Figma design
      tertiary: mat.$blue-palette,
    ),
    typography: (
      brand-family: 'Roboto, sans-serif',
    ),
    density: (
      scale: 0,
    ),
  ));
  
  html {
    @include mat.all-component-themes($aliceut-theme);
  }
  ```
- Dark mode: `prefers-color-scheme: dark` variant using `mat.define-theme(theme-type: dark)`
- Import `theme.scss` in each app's `styles.scss`
- Google Fonts: `Roboto:300,400,500,700` loaded in each app's `index.html`
- Global reset: `body { margin: 0; font-family: Roboto, sans-serif; }`
- Reference Figma file (`F69ukaWjsqx4adgo26vDFQ`) via `aliceut-design-system` skill when finalizing colors

**Done Criteria**

- Angular Material components render with AliceUT theme in all three portals
- No console warnings about missing theme providers
- Light/dark mode switching works with `prefers-color-scheme`
- Figma color tokens mapped to Material palette tokens

---

## FE-SHARED-002 — API Client (OpenAPI-Generated)

| Field | Value |
|-------|-------|
| **US Ref** | — |
| **Estimate** | M (1d) |
| **Dependencies** | INFRA-001, INFRA-002 |

**Implementation Notes**

- Package: `@openapitools/openapi-generator-cli`
- Generator: `typescript-angular` generator
- npm script: `"api:generate": "openapi-generator-cli generate -i http://localhost:3000/api/docs-json -g typescript-angular -o libs/api-client/src"`
- `libs/api-client/` is DO-NOT-EDIT (regenerated from OpenAPI spec)
- Generated services available as Angular `Injectable` services; use `provideHttpClient()` in all portals
- Base URL configured in each portal's `environment.ts`:
  ```ts
  export const environment = {
    apiBaseUrl: '/api',  // proxied to localhost:3000 in dev
    production: false,
  };
  ```
- `ApiModule.forRoot(() => new Configuration({ basePath: environment.apiBaseUrl }))` in each app's `AppModule`
- Manual interim: hand-write API services for Sprint 9-10 features; regenerate once backend is stable (Sprint 10)

**Done Criteria**

- `npm run api:generate` runs without error when backend is running
- Generated `AuthService`, `CartService`, `SearchService` inject correctly in Angular
- API base URL correctly points to backend in dev (proxied) and prod (nginx)
- Regenerating does not break existing portal code (check for breaking changes before committing)

---

## FE-SHARED-003 — Auth State Service (NgRx/Signal Store)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-01 |
| **Estimate** | L (2d) |
| **Dependencies** | FE-SHARED-002 |

**Implementation Notes**

- Use Angular Signals (Angular 17+) or NgRx Signal Store (simpler than full NgRx for V1)
- `AuthStore` in `libs/shared/src/auth/auth.store.ts`:
  ```ts
  export const AuthStore = signalStore(
    { providedIn: 'root' },
    withState({
      user: null as UserProfile | null,
      accessToken: null as string | null,
      refreshToken: null as string | null,
      isLoading: false,
      error: null as string | null,
    }),
    withMethods((store) => ({
      login: rxMethod<LoginCredentials>(...),    // calls POST /auth/login
      logout: rxMethod<void>(...),               // calls POST /auth/logout
      refresh: rxMethod<void>(...),              // calls POST /auth/refresh
      restoreSession: rxMethod<void>(...),       // called on app init; reads tokens from memory
    })),
    withComputed((store) => ({
      isAuthenticated: computed(() => !!store.accessToken()),
      userRole: computed(() => store.user()?.role ?? null),
    }))
  );
  ```
- Token storage: **in-memory only** (not localStorage) for security; refresh token also in memory
- Session persistence: re-login required on page refresh (acceptable for V1; localStorage persistence in Phase 2)
- Auto-refresh: `HttpInterceptor` catches 401 responses; calls `refresh()`; retries original request once

**Done Criteria**

- Login sets `accessToken` and `user` in store
- Logout clears all state; calls `POST /auth/logout`
- Page refresh loses session (by design in V1)
- `isAuthenticated` signal returns true after login, false after logout
- Token not in `localStorage` or `sessionStorage` (confirmed via browser DevTools)

---

## FE-SHARED-004 — HTTP Interceptors

| Field | Value |
|-------|-------|
| **US Ref** | — |
| **Estimate** | M (1d) |
| **Dependencies** | FE-SHARED-003 |

**Implementation Notes**

- `authInterceptor` (`libs/shared/src/interceptors/auth.interceptor.ts`): adds `Authorization: Bearer {accessToken}` to all requests (if token present); skips for `/auth/login`, `/auth/register`, `/auth/refresh`
- `refreshInterceptor`: catches 401 responses; attempts token refresh via `AuthStore.refresh()`; retries original request with new token; on second 401, logs out user
- `errorInterceptor`: catches 4xx/5xx; maps to user-friendly messages; shows `MatSnackBar` notification for common errors (403 = "Access denied", 404 = "Not found", 500 = "Server error")
- `loadingInterceptor`: tracks pending requests; updates `LoadingService.isLoading` signal; used by global loading spinner
- Apply all interceptors in `provideHttpClient(withInterceptors([...]))` in each portal's `app.config.ts`

**Done Criteria**

- API request includes `Authorization` header with valid token
- 401 response triggers refresh; original request retried with new token
- Second consecutive 401: user logged out; redirected to login page
- Error snackbar appears on 500 response
- Loading spinner visible during API requests

---

## FE-SHARED-005 — Route Guards

| Field | Value |
|-------|-------|
| **US Ref** | — |
| **Estimate** | S (½d) |
| **Dependencies** | FE-SHARED-003 |

**Implementation Notes**

- `authGuard` (`canActivate`): redirects to `/login` if `!isAuthenticated`; stores `returnUrl` in query param
- `roleGuard` (`canActivate`): factory function `roleGuard(['seller'])` → checks `userRole`; redirects to `/unauthorized` if wrong role
- `guestGuard` (`canActivate`): redirects authenticated users away from login/register pages (to appropriate portal home)
- `sellerActiveGuard`: additionally checks `sellerStatus === 'ACTIVE'` (from seller profile API call); redirects to `/seller/pending-kyc` if not active
- Use functional guards (Angular 15+ style):
  ```ts
  export const authGuard: CanActivateFn = (route, state) => {
    const auth = inject(AuthStore);
    return auth.isAuthenticated() ? true : inject(Router).parseUrl(`/login?returnUrl=${state.url}`);
  };
  ```

**Done Criteria**

- Unauthenticated user navigating to `/orders`: redirected to `/login?returnUrl=/orders`
- After login: redirected back to `/orders` (via `returnUrl`)
- Buyer navigating to `/seller/dashboard`: redirected to `/unauthorized`
- Authenticated user navigating to `/login`: redirected to home

---

## FE-SHARED-006 — Common UI Components

| Field | Value |
|-------|-------|
| **US Ref** | — |
| **Estimate** | L (2d) |
| **Dependencies** | FE-SHARED-001 |

**Implementation Notes**

- `libs/shared/src/components/`:
- `<app-loading-spinner>`: full-page overlay spinner using `LoadingService.isLoading` signal; `MatProgressSpinner`
- `<app-error-page>`: generic error page (404, 403, 500); accepts `@Input() code` and `@Input() message`
- `<app-pagination>`: cursor-based pagination controls; emits `(pageChange)` event with cursor; `@Input() hasMore`, `@Input() loading`
- `<app-money>`: renders monetary value correctly; `@Input() amount: string`, `@Input() currency: string`; formats using `Intl.NumberFormat`; never accepts `number` input
- `<app-notification-badge>`: unread count badge for notification bell icon; subscribes to `NotificationStore`
- `<app-avatar>`: user/seller avatar with fallback initial; accepts `@Input() imageUrl`, `@Input() name`
- All components use `OnPush` change detection strategy
- All components are standalone (`standalone: true`)

**Done Criteria**

- `<app-money amount="1234.5600" currency="JPY">` renders `¥1,235` (JPY no decimals)
- `<app-money amount="25.9900" currency="USD">` renders `$25.99`
- Loading spinner shows/hides correctly with active HTTP requests
- All components lint-clean; no `any` types

---

## FE-SHARED-007 — Error Handling & Notification Toast

| Field | Value |
|-------|-------|
| **US Ref** | — |
| **Estimate** | S (½d) |
| **Dependencies** | FE-SHARED-004 |

**Implementation Notes**

- `NotificationService` wraps `MatSnackBar`:
  ```ts
  @Injectable({ providedIn: 'root' })
  export class NotificationService {
    success(message: string): void { /* green snackbar, 3s */ }
    error(message: string): void   { /* red snackbar, 5s */ }
    info(message: string): void    { /* blue snackbar, 3s */ }
    warning(message: string): void { /* yellow snackbar, 4s */ }
  }
  ```
- `GlobalErrorHandler`: Angular `ErrorHandler` implementation; catches unhandled component errors; shows generic error toast; logs to console
- Register in all portals: `{ provide: ErrorHandler, useClass: GlobalErrorHandler }`
- API error mapping (in `errorInterceptor`): map HTTP error codes to user messages:
  - 400 `INSUFFICIENT_STOCK` → "Some items are out of stock"
  - 409 `EMAIL_TAKEN` → "This email is already registered"
  - 403 `SELLER_SUSPENDED` → "This seller is currently suspended"
  - 422 validation errors → show first field error from `error.details`
  - 5xx → "Something went wrong. Please try again."

**Done Criteria**

- `notificationService.success('Order placed!')` shows green snackbar
- HTTP 500 response: generic error toast shown; no stack trace to user
- Form validation error (400): correct field error message displayed
- `GlobalErrorHandler` prevents white screen on uncaught component errors
