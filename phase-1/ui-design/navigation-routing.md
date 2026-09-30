# Navigation & Routing Design
## All Three Angular Portals — Phase 1

**Status:** Complete  
**Stack:** Angular Router 22+ with `provideRouter()`, standalone components, lazily-loaded feature routes  
**Conventions:** [frontend-coding-standards.md § 7](../../conventions/frontend-coding-standards.md#7-routing-and-guards) (routing and guards), [api-conventions.md § Pagination](../../conventions/api-conventions.md#pagination) (cursor pagination), [auth-jwt-design.md](../../conventions/auth-jwt-design.md) (claims and token storage)

---

## Summary

- [1. Router Strategy](#router-strategy)
- [2. Buyer App — Route Tree (`buyer-app`)](#buyer-app-route-tree)
- [3. Seller App — Route Tree (`seller-app`)](#seller-app-route-tree)
- [4. Admin App — Route Tree (`admin-app`)](#admin-app-route-tree)
- [5. Auth Guard Matrix](#auth-guard-matrix)
- [6. Navigation Patterns](#navigation-patterns)
- [7. Lazy-Loaded Feature Boundaries](#lazy-loaded-feature-module-boundaries)
- [8. Deep Link Behavior](#deep-link-behavior)
- [9. Error Pages](#error-pages)
- [10. Navigation After Auth Events](#navigation-after-auth-events)
- [11. Query Param Conventions](#query-param-conventions)
- [12. Title Strategy](#title-strategy)
- [13. Scroll Behavior](#scroll-behavior)

<a id="router-strategy"></a>
## 1. Router Strategy

### Three applications, not one

Phase 1 ships **three separate Angular applications** in one Nx workspace (BRD § 12 #12): `buyer-app` on 4200, `seller-app` on 4201, `admin-app` on 4202. Each is built independently, served by its own nginx container on its own origin, and has its own `app.routes.ts` — the three route trees below are three files in three applications, not three branches of one.

Nothing is role-switched at runtime. There is no single router configuration that decides between a buyer and an admin tree, and no portal contains another portal's routes: `buyer-app` has no `/seller/login` route to guard, because that path does not exist in its bundle. Shared code — the generated API client, the shared UI composites, pure utilities — lives in `libs/`; the shell, routing and guards of each portal live in that portal's own `apps/<portal>/src/app/` ([frontend-coding-standards.md § 1](../../conventions/frontend-coding-standards.md#1-project-structure)).

A role mismatch is therefore never a route problem. An ADMIN token presented to a seller-portal route fails that portal's role guard and the API answers `403`; the user is not silently redirected into a portal they do not belong to.

### History mode

All three apps use **HTML5 History mode** (`withRouterConfig({ useHash: false })`). Each nginx container serves `index.html` as the fallback for any unmatched path, which is what makes a hard refresh or a pasted deep link work.

```nginx
# nginx fallback rule (applied to all three nginx confs)
location / {
  try_files $uri $uri/ /index.html;
}
```

---

<a id="buyer-app-route-tree"></a>
## 2. Buyer App — Route Tree (`buyer-app`)

### Root Routes (`app.routes.ts`)

```typescript
export const appRoutes: Routes = [
  // Public routes — no auth required
  {
    path: '',
    loadComponent: () => import('./shell/shell.component'),
    children: [
      {
        path: '',
        loadChildren: () => import('./features/home/home.routes'),
      },
      {
        path: 'search',
        loadChildren: () => import('./features/search/search.routes'),
      },
      {
        path: 'products/:id',
        loadChildren: () => import('./features/product/product.routes'),
      },
      // Auth routes — redirect to home if already authenticated
      {
        path: 'login',
        loadComponent: () => import('./features/auth/login/login.component'),
        canActivate: [guestGuard],  // redirects authenticated users to /
      },
      {
        path: 'register',
        loadComponent: () => import('./features/auth/register/register.component'),
        canActivate: [guestGuard],
      },
      {
        path: 'forgot-password',
        loadComponent: () => import('./features/auth/forgot-password/forgot-password.component'),
        canActivate: [guestGuard],
      },
      {
        path: 'email-verification-pending',
        loadComponent: () => import('./features/auth/email-verification-pending/email-verification-pending.component'),
        canActivate: [authGuard],
        // Resending a verification mail is an authenticated call, so this page requires a session
      },
      {
        path: 'verify-email',
        loadComponent: () => import('./features/auth/verify-email/verify-email.component'),
        // Public — handles ?token= from the email link; navigates to login on success/failure
      },
      {
        path: 'auth/callback',
        loadComponent: () => import('./features/auth/oauth-callback/oauth-callback.component'),
        // Public — the redirect target of GET /auth/google/callback and /auth/facebook/callback.
        // Exchanges ?code= (opaque, single-use, 60s TTL) via POST /auth/oauth/exchange, or renders
        // the failure named by ?error=. No access or refresh token ever appears in this URL.
        // Buyer portal only: OAuth is not offered on the seller or admin portals.
      },
      {
        path: 'reset-password',
        loadComponent: () => import('./features/auth/reset-password/reset-password.component'),
        // Public — handles ?token= from the email link
      },
      {
        path: 'cart',
        loadComponent: () => import('./features/cart/cart.component'),
        // Deliberately unguarded — see the guest-cart note in §5
      },
      {
        path: 'checkout',
        loadChildren: () => import('./features/checkout/checkout.routes'),
        canActivate: [authGuard, emailVerifiedGuard],
      },
      {
        path: 'orders',
        loadChildren: () => import('./features/orders/orders.routes'),
        canActivate: [authGuard],
      },
      {
        path: 'account',
        loadChildren: () => import('./features/account/account.routes'),
        canActivate: [authGuard],
      },
      {
        path: 'notifications',
        loadComponent: () => import('./features/notifications/buyer-notifications.component'),
        canActivate: [authGuard],
        // Linked from the notification bell's 'View all' item in the buyer shell
      },
    ],
  },
  // Error pages
  { path: '403', loadComponent: () => import('./shared/error/forbidden.component') },
  { path: '404', loadComponent: () => import('./shared/error/not-found.component') },
  { path: '**', redirectTo: '404' },
];
```

### Feature Route Sub-trees

**`search.routes.ts`**
```
/search     → SearchResultsComponent
```

**`product.routes.ts`**
```
/products/:id     → ProductDetailComponent
```

**`checkout.routes.ts`**
```
/checkout               → CheckoutComponent (3-step mat-stepper: address, payment, review)
/checkout/confirmation  → OrderConfirmationComponent
```

**`orders.routes.ts`**
```
/orders        → OrderHistoryComponent
/orders/:id    → OrderDetailComponent      (:id is an order id — ORD-, not a fulfillment)
```

**`account.routes.ts`**
```
/account            → AccountSettingsComponent (shell with mat-tab-group)
/account/profile    → ProfileTabComponent     (routed tab)
/account/addresses  → AddressesTabComponent
/account/security   → SecurityTabComponent
```

---

<a id="seller-app-route-tree"></a>
## 3. Seller App — Route Tree (`seller-app`)

### Root Routes (`app.routes.ts`)

```typescript
export const appRoutes: Routes = [
  // Auth routes (no shell / sidenav) — all public
  {
    path: 'seller/login',
    loadComponent: () => import('./features/auth/seller-login/seller-login.component'),
    canActivate: [guestGuard],
  },
  {
    path: 'seller/register',
    loadComponent: () => import('./features/auth/seller-register/seller-register.component'),
    canActivate: [guestGuard],
    // PUBLIC endpoint — POST /seller/register takes no token. A prospective seller
    // may hold no AliceUT account at all.
  },
  {
    path: 'seller/forgot-password',
    loadComponent: () => import('./features/auth/seller-forgot-password/seller-forgot-password.component'),
    canActivate: [guestGuard],
  },
  {
    path: 'seller/reset-password',
    loadComponent: () => import('./features/auth/seller-reset-password/seller-reset-password.component'),
    // Public — handles ?token=; a signed-in seller may also be redeeming a link
  },
  // Authenticated seller routes (with sidenav shell)
  {
    path: 'seller',
    loadComponent: () => import('./shell/seller-shell.component'),
    canActivate: [sellerAuthGuard],  // valid JWT + SELLER role
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      {
        path: 'kyc',
        loadComponent: () => import('./features/kyc/kyc-application/kyc-application.component'),
        // No approval guard — this route is how approval is obtained, so gating it on
        // approval makes onboarding unreachable. No suspension guard either:
        // GET /seller/kyc is one of the reads a suspended seller keeps.
      },
      {
        path: 'profile',
        loadComponent: () => import('./features/profile/seller-profile.component'),
        // Readable while suspended — it carries the suspension reason and end date
      },
      {
        path: 'dashboard',
        loadComponent: () => import('./features/dashboard/seller-dashboard.component'),
        // No approval or suspension guard: this is the landing screen that explains
        // a pending KYC or an active suspension. The component decides whether to
        // request GET /seller/dashboard/summary, which is SELLER_ACTIVE-only.
      },
      {
        path: 'listings',
        loadChildren: () => import('./features/listings/listings.routes'),
        canActivate: [sellerApprovedGuard, sellerNotSuspendedGuard],
      },
      {
        path: 'orders',
        loadChildren: () => import('./features/orders/seller-orders.routes'),
        // No suspension guard — the obligation to fulfil orders placed before the
        // suspension survives it, so list, detail and ship stay reachable.
      },
      {
        path: 'inventory',
        loadChildren: () => import('./features/inventory/inventory.routes'),
        canActivate: [sellerApprovedGuard, sellerNotSuspendedGuard],
      },
      {
        path: 'notifications',
        loadComponent: () => import('./features/notifications/seller-notifications.component'),
        // GET /notifications is plain JWT, and a suspended or unapproved seller has
        // notifications to read — the suspension notice among them.
      },
    ],
  },
  { path: '403', loadComponent: () => import('./shared/error/forbidden.component') },
  { path: '404', loadComponent: () => import('./shared/error/not-found.component') },
  { path: '', redirectTo: 'seller/dashboard', pathMatch: 'full' },
  { path: '**', redirectTo: '404' },
];
```

### Feature Route Sub-trees

**`listings.routes.ts`**
```
/seller/listings                    → ListingsTableComponent
/seller/listings/new                → CreateEditListingComponent (isNew=true)
/seller/listings/:offerId/edit      → CreateEditListingComponent (isNew=false)
/seller/listings/:offerId/pricing   → OfferPricingComponent
```

A row in the seller's listings table is an **offer**, so `:offerId` is an offer id throughout this sub-tree. Editing the listing's product content is `PATCH /seller/products/:productId` against the product the offer points at, and the component resolves that product id from the offer it loaded — the route never carries both.

**`seller-orders.routes.ts`**
```
/seller/orders                  → SellerOrderQueueComponent (mat-tab-group per status)
/seller/orders/:fulfillmentId   → SellerOrderDetailComponent
```

Every id under `/seller/orders` is a **fulfillment** id. The path keeps the seller-facing word "orders", but one row is one seller's group within a buyer's checkout ([seller.md § Endpoint Index](../technical-design/api-design/seller.md#endpoint-index)).

**`inventory.routes.ts`**
```
/seller/inventory      → InventoryTableComponent
```

---

<a id="admin-app-route-tree"></a>
## 4. Admin App — Route Tree (`admin-app`)

### Root Routes (`app.routes.ts`)

```typescript
export const appRoutes: Routes = [
  // Auth route (no shell)
  {
    path: 'admin/login',
    loadComponent: () => import('./features/auth/admin-login/admin-login.component'),
    canActivate: [guestGuard],
  },
  // Authenticated admin routes (with sidenav shell)
  {
    path: 'admin',
    loadComponent: () => import('./shell/admin-shell.component'),
    canActivate: [adminAuthGuard],  // valid JWT + ADMIN role
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      {
        path: 'dashboard',
        loadComponent: () => import('./features/dashboard/admin-dashboard.component'),
      },
      {
        path: 'kyc',
        loadChildren: () => import('./features/kyc/kyc.routes'),
      },
      {
        path: 'moderation',
        loadChildren: () => import('./features/moderation/moderation.routes'),
      },
      {
        path: 'sellers',
        loadChildren: () => import('./features/sellers/sellers.routes'),
      },
      {
        path: 'keyword-blocklist',
        loadComponent: () => import('./features/blocklist/keyword-blocklist.component'),
      },
      {
        path: 'notifications',
        loadComponent: () => import('./features/notifications/admin-notifications.component'),
        // No extra guard — the parent admin route already applies adminAuthGuard
      },
    ],
  },
  { path: '403', loadComponent: () => import('./shared/error/forbidden.component') },
  { path: '404', loadComponent: () => import('./shared/error/not-found.component') },
  { path: '', redirectTo: 'admin/login', pathMatch: 'full' },
  { path: '**', redirectTo: '404' },
];
```

There is **no admin registration route and no admin password-reset route.** Admin accounts are seeded (`admin@aliceut.dev`); a password change is a direct database update by the developer in V1 ([auth-jwt-design.md § 3](../../conventions/auth-jwt-design.md)).

### Feature Route Sub-trees

**`kyc.routes.ts`**
```
/admin/kyc                   → KycQueueComponent
/admin/kyc/:applicationId    → KycApplicationDetailComponent
```

**`moderation.routes.ts`**
```
/admin/moderation            → ModerationQueueComponent
/admin/moderation/:caseId    → ModerationCaseDetailComponent
```

**`sellers.routes.ts`**
```
/admin/sellers                     → SellerManagementComponent
/admin/sellers/:sellerProfileId    → SellerDetailComponent
```

`:caseId` is a moderation **case** id, not an offer id, and `:sellerProfileId` is a `seller.seller_profile` id, not a user id — both match the path parameters in [admin.md](../technical-design/api-design/admin.md#endpoint-index).

There is **no admin inventory route.** No admin surface writes `inventory.stock` in V1: the admin scope is KYC decisions, moderation and the keyword blocklist.

---

<a id="auth-guard-matrix"></a>
## 5. Auth Guard Matrix

### Guard implementation

All guards are **functional `CanActivateFn`** — no class-based guards ([frontend-coding-standards.md § 7](../../conventions/frontend-coding-standards.md#7-routing-and-guards)). Each portal owns its own guards under `apps/<portal>/src/app/core/guards/`, named `kebab-case.guard.ts`; `libs/` holds no guards, because a guard reads `AuthService`, which is app-level state rather than shared UI.

```typescript
export const authGuard: CanActivateFn = (route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (auth.isAuthenticated()) return true;
  return router.createUrlTree(['/login'], { queryParams: { returnUrl: state.url } });
};
```

Every guard reads the decoded access token held in memory by `AuthService` — `roles`, `email_verified`, `seller_kyc_status`, `seller_suspension_status` are all claims on the token, so no guard makes an API round-trip ([auth-jwt-design.md § 1.1](../../conventions/auth-jwt-design.md)). A status change reaches the token within one request through the server's Redis revocation key, not by a guard re-reading a row.

A `CanActivateFn` can only allow or deny. A guard therefore never "shows a component inside the route" — where a screen has to explain a state rather than block it, there is **no guard** and the component branches on the claim it reads from `AuthService`. That is why `/seller/dashboard` and `/seller/kyc` carry no approval guard.

| Guard | Condition checked | On fail |
|-------|-------------------|---------|
| `authGuard` | Valid access token in `AuthService` (a silent `POST /auth/refresh` is attempted first) | `UrlTree` to the portal login with `returnUrl` |
| `guestGuard` | No valid access token | `UrlTree` to the portal home / dashboard |
| `emailVerifiedGuard` | `email_verified === true` | `UrlTree` to `/email-verification-pending` |
| `roleGuard(role)` | `roles` contains the required role | `UrlTree` to `/403` |
| `sellerAuthGuard` | `authGuard` + `roleGuard('SELLER')` | `UrlTree` to `/seller/login` |
| `adminAuthGuard` | `authGuard` + `roleGuard('ADMIN')` | `UrlTree` to `/admin/login` |
| `sellerApprovedGuard` | `seller_kyc_status === 'APPROVED'` | `UrlTree` to `/seller/kyc` |
| `sellerNotSuspendedGuard` | `seller_suspension_status !== 'SUSPENDED'` | `UrlTree` to `/seller/profile` — the one screen that states the reason and the end date |

### Route-level guard summary

| Route | Guards | Notes |
|-------|--------|-------|
| `/` (buyer home) | — | Guest allowed |
| `/search` | — | Guest allowed |
| `/products/:id` | — | Guest allowed |
| `/cart` | — | Guest cart is a requirement, not an oversight — see below |
| `/checkout/**` | `authGuard`, `emailVerifiedGuard` | Guest is redirected to login and returned to `/checkout` after the guest cart merges |
| `/orders/**` | `authGuard` | Email verification is not required to read past orders |
| `/account/**` | `authGuard` | — |
| `/notifications` | `authGuard` | Buyer notifications page; bell "View all" target |
| `/auth/callback` | — | Public; exchanges the one-time OAuth code, then follows the buyer-login rules above |
| `/seller/login`, `/seller/register`, `/seller/forgot-password` | `guestGuard` | All three are public endpoints |
| `/seller/reset-password` | — | Public; reads `?token=` |
| `/seller/**` (shell) | `sellerAuthGuard` | Everything inside the shell needs a SELLER token |
| `/seller/kyc` | *(shell only)* | Reachable before approval, and while suspended |
| `/seller/profile` | *(shell only)* | Readable while suspended; the save action is what a suspension blocks, and the API answers `403` |
| `/seller/dashboard` | *(shell only)* | Renders the KYC or suspension state; fetches the four counts only when approved and unsuspended |
| `/seller/orders/**` | *(shell only)* | No suspension guard — list, detail and ship survive a suspension |
| `/seller/notifications` | *(shell only)* | `GET /notifications` is plain JWT |
| `/seller/listings/**` | `sellerApprovedGuard`, `sellerNotSuspendedGuard` | Includes the pricing sub-route |
| `/seller/inventory/**` | `sellerApprovedGuard`, `sellerNotSuspendedGuard` | — |
| `/admin/login` | `guestGuard` | — |
| `/admin/**` | `adminAuthGuard` | One guard on the shell covers every child |

**Guest cart is deliberate.** `/cart` carries no `authGuard` because US-B-08 requires a guest cart to survive reloads and tabs, and US-B-07 merges it into the server cart at login. Checkout is where authentication is required, and that is guarded separately. A convention example showing `authGuard` on `/cart` is superseded here by the user story.

**Suspension is not a blanket gate.** A suspended seller keeps the profile read, the KYC status read, the order list, the order detail and the ship action, and loses everything else ([seller.md § Suspended-seller access restriction](../technical-design/api-design/seller.md#sequence-diagram-conventions)). The route tree mirrors that split rather than drawing one "account suspended" wall across the portal, and the shell renders a persistent suspension banner so the restriction is legible from any of the surviving screens.

**KYC approval and suspension are independent.** They are two separate columns, not two stages of one chain: a suspended seller can be KYC-approved, and an approved one can be suspended. `sellerApprovedGuard` and `sellerNotSuspendedGuard` are therefore listed separately on every route that needs both, and neither implies the other.

---

<a id="navigation-patterns"></a>
## 6. Navigation Patterns

### 6.1 Buyer Portal

**Top toolbar navigation:** logo → `/`, search field → `/search?q=`, cart icon → `/cart`, notification bell → `/notifications`, user menu → the account pages.

**Breadcrumbs (PDP and checkout):**
- PDP: `Home > Category > Subcategory > Product Title` — each segment is a `routerLink`.
- The breadcrumb service resolves labels from `ActivatedRouteSnapshot.data.breadcrumb`.
- On handset widths the trail truncates to the parent category plus the product title.

**Back navigation:** the `arrow_back` icon button on detail and checkout pages calls `Location.back()`, which preserves scroll position and the query-encoded filter state.

**Filter state persistence:** active filters live in the URL query string. Components subscribe to the router's query-param stream so browser back and forward re-apply them.

### 6.2 Seller Portal

**Sidenav navigation:** persistent sidebar on desktop (`mode="side"`), overlay drawer on handset (`mode="over"`). The active item is highlighted with `routerLinkActive="active"` (`background: primary-50; border-left: 3px solid primary`). The Orders item carries a badge with the pending-fulfillment count from `GET /seller/dashboard/summary`.

**Breadcrumbs (detail pages):**
- Order detail: `Orders > FUL-000003871`. A row under `/seller/orders` is one `orders.fulfillment`, so the breadcrumb carries the **fulfillment** display id — `FUL-` plus nine zero-padded digits. The buyer's order id (`ORD-000001042`) is shown beside it on the detail body, where the seller may need to quote the id the buyer sees, but the breadcrumb identifies the record the screen is actually about.
- Listing edit: `Listings > [Product Title] > Edit`.
- Offer pricing: `Listings > [Product Title] > Pricing`.

**Tab state:** the Order Queue's active tab is its status filter, so it is encoded as `?status=PENDING` and a refresh restores it. There is no separate `tab` parameter duplicating the same fact.

### 6.3 Admin Portal

**Sidenav navigation:** same pattern as the seller portal. The KYC item badges `pendingKyc` and the Moderation item badges `openModerationCases`, both from `GET /admin/dashboard/stats`.

**Queue navigation:** after deciding a KYC application or a moderation case, navigate back to the queue and show a `MatSnackBar` confirmation. The queue is re-fetched from the first page rather than resumed from a cursor, because the decision removed the row that the cursor was issued against. Auto-advance to the next item is not implemented: the admin returns to the queue and chooses, which keeps the back button meaningful.

---

<a id="lazy-loaded-feature-module-boundaries"></a>
## 7. Lazy-Loaded Feature Boundaries

Every feature route is lazily loaded with `loadComponent` or `loadChildren`; eager loading a feature route is a lint failure ([frontend-coding-standards.md § 11](../../conventions/frontend-coding-standards.md#11-performance)). The seller and admin portals are visited far less often than the buyer storefront, so their chunks are also kept out of any preload pass.

| App | Feature chunk | Loaded when |
|-----|---------------|-------------|
| buyer-app | `home` | First navigation to `/` |
| buyer-app | `search` | `/search` |
| buyer-app | `product` | `/products/:id` |
| buyer-app | `cart` | `/cart` |
| buyer-app | `checkout` | `/checkout` |
| buyer-app | `orders` | `/orders` |
| buyer-app | `account` | `/account` |
| buyer-app | `auth` | any of the login / register / verify / reset / OAuth-callback routes |
| buyer-app | `notifications` | `/notifications` |
| seller-app | `auth` | any of the seller login / register / reset routes |
| seller-app | `kyc` | `/seller/kyc` |
| seller-app | `profile` | `/seller/profile` |
| seller-app | `dashboard` | `/seller/dashboard` |
| seller-app | `listings` | `/seller/listings` |
| seller-app | `orders` | `/seller/orders` |
| seller-app | `inventory` | `/seller/inventory` |
| seller-app | `notifications` | `/seller/notifications` |
| admin-app | `auth` | `/admin/login` |
| admin-app | `dashboard` | `/admin/dashboard` |
| admin-app | `kyc` | `/admin/kyc` |
| admin-app | `moderation` | `/admin/moderation` |
| admin-app | `sellers` | `/admin/sellers` |
| admin-app | `blocklist` | `/admin/keyword-blocklist` |
| admin-app | `notifications` | `/admin/notifications` |

**Preloading strategy:** `PreloadAllModules` for `buyer-app`, where catalogue browsing usually continues into search and the PDP. `NoPreloading` for `seller-app` and `admin-app` — a small, task-driven user base, so loading on demand costs one short wait and saves the initial payload.

---

<a id="deep-link-behavior"></a>
## 8. Deep Link Behavior

### What a shared link carries

A shared, bookmarked or refreshed URL carries everything that defines **which** list is being viewed, and nothing about position within it:

- `q`, the filters, and `sortBy` / `sortDir` are all in the query string. They are stable, idempotent and meaningful to whoever receives the link.
- **A shared link always opens at the first page of the named list.** Position is not encoded, so the recipient sees the same filtered, sorted list from the top.
- **No cursor ever appears in a URL, a bookmark or a shared link.** A cursor is an opaque server-issued token, it is invalidated by any change to the sort or filter set ([api-conventions.md § Pagination](../../conventions/api-conventions.md#pagination)), and a pasted stale one produces a plain `400` for the recipient rather than a list.

There is consequently **no `page` and no `pageSize` parameter** on any route. Under cursor pagination there is no page number to encode, and `limit` is not user-facing — it is the client's fixed request size. This is the accepted cost of cursor pagination, recorded here so the absence reads as a decision rather than a regression to be repaired by reintroducing `page`.

### Scenarios

| Scenario | Behavior |
|----------|----------|
| Guest visits `/checkout` | Redirect to `/login?returnUrl=/checkout`; after login the guest cart merges and the buyer is forwarded to `/checkout` |
| Authenticated buyer visits `/seller/login` | `buyer-app` has no such route — the seller portal is a separate origin on 4201 |
| Buyer visits `/orders/<unknown>` | API answers `404`; the component renders `EmptyState` "Order not found" |
| Admin visits `/admin/kyc/<unknown>` | API answers `404`; the component renders `EmptyState` "Application not found" |
| Admin visits `/admin/moderation/<unknown>` | API answers `404`; the component renders `EmptyState` "Case not found" |
| Seller visits `/seller/orders/<another seller's id>` | API answers `404`, not `403` — the lookup is seller-scoped, so a foreign id is indistinguishable from a missing one and cannot be used to enumerate order volume |
| Email verification link | `/verify-email?token=xxx` → the API validates; success redirects to `/login?verified=true`, failure shows an inline error with a resend route |
| Password reset link | `/reset-password?token=xxx` renders the form; the token is validated on submit. Reset tokens are portal-scoped — a seller link is not redeemable on the buyer portal, and the mismatch returns the same generic failure as an unknown token rather than confirming which portal it belongs to |
| Seller app visited without the `/seller` prefix | Redirects to `/seller/dashboard` when authenticated, `/seller/login` otherwise |
| Any portal, wrong role | The API answers `403`; the router shows `/403` |

---

<a id="error-pages"></a>
## 9. Error Pages

### 404 Not Found

```
div.error-page [text-align: center; padding: 80px 24px]
  mat-icon [font-size: 80px; color: disabled] — search_off
  h1 mat-h3 — Page Not Found
  p mat-body-1 — The page you're looking for doesn't exist or has been moved.
  button mat-flat-button color="primary" [routerLink]="homeRoute" — Go to Home
```

`homeRoute` resolves per app: `buyer-app` → `/`, `seller-app` → `/seller/dashboard`, `admin-app` → `/admin/dashboard`.

### 403 Forbidden

```
div.error-page [text-align: center; padding: 80px 24px]
  mat-icon [font-size: 80px; color: warn] — lock_outline
  h1 mat-h3 — Access Denied
  p mat-body-1 — You don't have permission to view this page.
  button mat-flat-button color="primary" [routerLink]="homeRoute" — Go to Home
```

Reached by `roleGuard` and by a `403` from the API — including the portal-role mismatch case, where a token valid for another portal is presented here.

### Service unavailable

Not a routed page. A failed data request renders the component's own `error` state — the third arm of its `ViewState` — inside the screen, with a Retry action. Search is the one with a bespoke message, an inline `mat-card.error-banner` in the results area.

---

<a id="navigation-after-auth-events"></a>
## 10. Navigation After Auth Events

| Event | Navigation |
|-------|------------|
| Buyer login success | `returnUrl` when set and relative, else `/` |
| Buyer login via Google or Facebook | Provider → `GET /auth/{provider}/callback` → redirect to `/auth/callback?code=`; the SPA exchanges the code, then follows the row above. A `?error=` instead renders the failure on that page with a link back to `/login` |
| Buyer registration success | `/email-verification-pending` for email/password, `/` for OAuth |
| Email verified | `/login?verified=true` — the login page shows a success snackbar |
| Buyer password reset success | `/login?passwordReset=true` |
| Seller registration success | `/seller/kyc` — step 2 of onboarding, using the SELLER session the registration response opened |
| Seller registration, email already has an OAuth-only account | Stay on the form; the `409 PASSWORD_REQUIRED_FOR_LINK` response is rendered as an inline banner pointing at the buyer portal's set-password flow |
| Seller login success | `/seller/dashboard` — the dashboard itself renders the KYC or suspension state |
| Seller password reset success | `/seller/login?passwordReset=true` |
| Admin login success | `/admin/dashboard` |
| Logout, any portal | Clear the in-memory access token, then the portal login page |
| All-sessions logout | Same as logout for this browser; other devices fail on their next request |
| Access token expiry, refresh succeeds | No navigation — the original request is replayed |
| Access token expiry, refresh fails | Portal login with `returnUrl` preserved |
| Seller suspended while signed in | The next request answers `403`; the shell shows the suspension banner and the router leaves the seller on a surviving screen, redirecting to `/seller/profile` if the current route is now guarded |
| Rate limit hit on an auth form | No navigation; the `429` renders as an inline error on the form |

`returnUrl` is validated as a relative path beginning with `/` before it is used, so an absolute URL cannot turn the login page into an open redirect.

---

<a id="query-param-conventions"></a>
## 11. Query Param Conventions

Every parameter below is passed through to an API query parameter of the same name, so the registry and the endpoint specs cannot drift. Names are camelCase ([api-conventions.md § Naming](../../conventions/api-conventions.md#naming)).

### Search and catalogue

| Param | Example | Purpose |
|-------|---------|---------|
| `q` | `?q=laptop` | Full-text query |
| `categoryId` | `?categoryId=<uuid>` | Category filter, subcategories included. A UUID, not a slug |
| `priceMin` | `?priceMin=100.00` | Lower bound, a **decimal string** in `currency` |
| `priceMax` | `?priceMax=1500.00` | Upper bound, a decimal string |
| `currency` | `?currency=THB` | Currency the price bounds and displayed amounts are in; defaults to USD |
| `inStock` | `?inStock=true` | In-stock offers only |
| `sortBy` | `?sortBy=priceAsc` | `relevance` (default), `priceAsc`, `priceDesc`, `newest` |

There is **no `minRating`** and no rating sort. Reviews and ratings are out of V1 scope (BRD § 3.2), so no rating field exists in the search index, the ERD, or any response object.

### Lists and queues

| Param | Used by | Example | Purpose |
|-------|---------|---------|---------|
| `status` | Buyer orders, seller orders | `?status=PENDING` | Fulfillment status — `PENDING`, `SHIPPED`, `DELIVERED`, `REFUNDED`, `CANCELLED`. On the seller queue this is the active tab |
| `status` | Admin KYC | `?status=PENDING` | KYC application status — `PENDING`, `UNDER_REVIEW`, `APPROVED`, `REJECTED` |
| `status` | Admin moderation | `?status=OPEN` | Moderation case status — `OPEN`, `RESOLVED`, `DISMISSED` |
| `source` | Admin moderation | `?source=KEYWORD_MATCH` | Flag source — `KEYWORD_MATCH`, `PROHIBITED_CATEGORY`, `ADMIN_MANUAL` |
| `kycStatus` | Admin sellers | `?kycStatus=APPROVED` | Seller profile KYC standing — `PENDING_KYC`, `APPROVED`, `REJECTED` |
| `suspensionStatus` | Admin sellers | `?suspensionStatus=SUSPENDED` | `ACTIVE` or `SUSPENDED`. Independent of `kycStatus`, so the two are separate parameters and never merged into one |
| `status` | Seller listings | `?status=FLAGGED` | Offer status — `ACTIVE`, `INACTIVE`, `REMOVED`, `FLAGGED`. There is no `DRAFT`: a listing goes live on submit |
| `caseStatus` | Seller listings | `?caseStatus=OPEN` | Moderation-case filter on the seller's own offers |
| `country` | Admin KYC | `?country=TH` | ISO 3166-1 alpha-2 |
| `q` | Seller orders, admin sellers, blocklist | `?q=FUL-000003871` | Display-id search on the seller queue; free-text across business name, email and tax ID on the admin seller list; substring match on the term in the blocklist |
| `placedFrom`, `placedTo` | Seller orders | `?placedFrom=2026-09-01` | Placement date range |
| `sortDir` | Admin KYC | `?sortDir=desc` | `asc` (default, oldest first) or `desc` |
| `unreadOnly` | Notifications | `?unreadOnly=true` | Unread filter |
| `isActive` | Blocklist | `?isActive=true` | Active-terms filter |

There is **no `page`, `pageSize`, `offset` or `total`** on any route, and `limit` and `cursor` never appear in a URL — see [§ 8](#deep-link-behavior).

### Flow parameters

| Param | Used by | Example | Purpose |
|-------|---------|---------|---------|
| `returnUrl` | Login pages | `?returnUrl=%2Fcheckout` | Post-auth redirect; validated as a relative path |
| `verified` | Buyer login | `?verified=true` | Triggers the post-verification success snackbar |
| `passwordReset` | Buyer and seller login | `?passwordReset=true` | Triggers the post-reset success banner |
| `token` | Verify email, reset password | `?token=xxx` | One-time link token from an email. This is the only token that ever appears in a URL; an access or refresh token never does |
| `orderId` | Checkout confirmation | `?orderId=<uuid>` | The order the checkout created — an order id, never a fulfillment id, because a checkout produces one order containing one fulfillment per seller and currency group |
| `code` | Buyer `/auth/callback` | `?code=<opaque>` | The one-time OAuth authorization code, single-use with a 60-second TTL, exchanged by `POST /auth/oauth/exchange`. It is not a session token |
| `error` | Buyer `/auth/callback` | `?error=oauth_state_invalid` | The failure the provider callback redirected with, in place of `code` |

No V1 query parameter is array-valued. Every filter above takes a single value, so there is no repeated-parameter convention to apply; a multi-select filter would need the endpoint to accept a list first.

---

<a id="title-strategy"></a>
## 12. Title Strategy

Each portal registers a `TitleStrategy` so browser tabs and history entries are distinguishable.

```typescript
// apps/<portal>/src/app/core/page-title.strategy.ts
@Injectable({ providedIn: 'root' })
export class AppTitleStrategy extends TitleStrategy {
  updateTitle(snapshot: RouterStateSnapshot): void {
    const title = this.buildTitle(snapshot);
    this.title.setTitle(title ? `${title} — AliceUT` : 'AliceUT');
  }
}
```

| Route | Title |
|-------|-------|
| `/` (buyer home) | `AliceUT` |
| `/search?q=laptop` | `Results for "laptop" — AliceUT` |
| `/products/:id` | `[Product Name] — AliceUT` |
| `/cart` | `Cart — AliceUT` |
| `/checkout` | `Checkout — AliceUT` |
| `/checkout/confirmation` | `Order Confirmed — AliceUT` |
| `/orders` | `My Orders — AliceUT` |
| `/notifications` | `Notifications — AliceUT` |
| `/seller/dashboard` | `Dashboard — Seller Hub` |
| `/seller/kyc` | `Business Verification — Seller Hub` |
| `/seller/profile` | `Business Profile — Seller Hub` |
| `/seller/listings` | `My Listings — Seller Hub` |
| `/seller/notifications` | `Notifications — Seller Hub` |
| `/seller/orders` | `Orders — Seller Hub` |
| `/seller/inventory` | `Inventory — Seller Hub` |
| `/admin/dashboard` | `Dashboard — Admin` |
| `/admin/kyc` | `KYC Queue — Admin` |
| `/admin/moderation` | `Moderation — Admin` |
| `/admin/sellers` | `Sellers — Admin` |
| `/admin/keyword-blocklist` | `Keyword Blocklist — Admin` |
| `/admin/notifications` | `Notifications — Admin` |

---

<a id="scroll-behavior"></a>
## 13. Scroll Behavior

`withInMemoryScrolling({ scrollPositionRestoration: 'enabled', anchorScrolling: 'enabled' })` in each portal's router configuration.

- Browser back and forward restore the scroll position on list pages — search results, order history, and the admin queues.
- Navigation to a new route scrolls to the top.
- Anchor links (the PDP's `#description` tab, for instance) are honoured.
- Exception: the checkout stepper scrolls to the top of the newly active step via `ViewportScroller.scrollToPosition([0, 0])` on step change, rather than leaving the viewport where the previous step ended.
- Advancing a cursor-paginated table scrolls the table container to its first row, since a Next that leaves the viewport mid-list reads as nothing having happened.

---

*Last updated: 2026-09-14 (design alignment)*
