# Navigation & Routing Design
## All Three Angular Portals — Phase 1

**Status:** Draft  
**Stack:** Angular Router 22+ with `provideRouter()`, lazy-loaded feature modules, standalone components

---

## Summary

- [1. Router Strategy](#router-strategy)
- [2. Buyer App — Route Tree (`buyer-app`)](#buyer-app-route-tree)
- [3. Seller App — Route Tree (`seller-app`)](#seller-app-route-tree)
- [4. Admin App — Route Tree (`admin-app`)](#admin-app-route-tree)
- [5. Auth Guard Matrix](#auth-guard-matrix)
- [6. Navigation Patterns](#navigation-patterns)
- [7. Lazy-Loaded Feature Module Boundaries](#lazy-loaded-feature-module-boundaries)
- [8. Deep Link Behavior](#deep-link-behavior)
- [9. Error Pages](#error-pages)
- [10. Navigation After Auth Events](#navigation-after-auth-events)
- [11. Query Param Conventions](#query-param-conventions)
- [12. Title Strategy](#title-strategy)
- [13. Scroll Behavior](#scroll-behavior)

<a id="router-strategy"></a>
## 1. Router Strategy

All three apps use **HTML5 History mode** (`withRouterConfig({ useHash: false })`). Each nginx container serves `index.html` as the fallback for any unmatched path (required for SPA routing on hard refresh/deep link).

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
        canActivate: [GuestGuard],  // redirects authenticated users to /
      },
      {
        path: 'register',
        loadComponent: () => import('./features/auth/register/register.component'),
        canActivate: [GuestGuard],
      },
      {
        path: 'forgot-password',
        loadComponent: () => import('./features/auth/forgot-password/forgot-password.component'),
      },
      {
        path: 'email-verification-pending',
        loadComponent: () => import('./features/auth/email-verification-pending/email-verification-pending.component'),
      },
      {
        path: 'verify-email',
        loadComponent: () => import('./features/auth/verify-email/verify-email.component'),
        // Handles ?token= from email link; navigates to login on success/failure
      },
      {
        path: 'reset-password',
        loadComponent: () => import('./features/auth/reset-password/reset-password.component'),
        // Handles ?token= from email link
      },
      // Protected routes — require authenticated + email-verified buyer
      {
        path: 'cart',
        loadComponent: () => import('./features/cart/cart.component'),
        // No auth guard — guest cart is displayed; checkout is guarded separately
      },
      {
        path: 'checkout',
        loadChildren: () => import('./features/checkout/checkout.routes'),
        canActivate: [AuthGuard, EmailVerifiedGuard],
      },
      {
        path: 'orders',
        loadChildren: () => import('./features/orders/orders.routes'),
        canActivate: [AuthGuard],
      },
      {
        path: 'account',
        loadChildren: () => import('./features/account/account.routes'),
        canActivate: [AuthGuard],
      },
      {
        path: 'notifications',
        loadComponent: () => import('./features/notifications/buyer-notifications.component'),
        canActivate: [AuthGuard],
        // Linked from <aliceut-notification-bell> 'View all' link in buyer shell
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
/checkout               → CheckoutComponent (4-step mat-stepper)
/checkout/confirmation  → OrderConfirmationComponent
```

**`orders.routes.ts`**
```
/orders        → OrderHistoryComponent
/orders/:id    → OrderDetailComponent
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
  // Auth routes (no shell / sidenav)
  {
    path: 'seller/login',
    loadComponent: () => import('./features/auth/seller-login/seller-login.component'),
    canActivate: [GuestGuard],
  },
  {
    path: 'seller/register',
    loadComponent: () => import('./features/auth/seller-register/seller-register.component'),
    canActivate: [GuestGuard],
  },
  {
    path: 'seller/forgot-password',
    loadComponent: () => import('./features/auth/seller-forgot-password/seller-forgot-password.component'),
    // Public — no canActivate guard
  },
  {
    path: 'seller/reset-password',
    loadComponent: () => import('./features/auth/seller-reset-password/seller-reset-password.component'),
    // Public — handles ?token= query param; no canActivate guard
  },
  // Protected seller routes (with sidenav shell)
  {
    path: 'seller',
    loadComponent: () => import('./shell/seller-shell.component'),
    canActivate: [SellerAuthGuard],  // requires SELLER role + valid JWT
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      {
        path: 'kyc',
        loadComponent: () => import('./features/kyc/kyc-application/kyc-application.component'),
        // Accessible to all SELLER role holders; shows appropriate state per KYC status
      },
      {
        path: 'dashboard',
        loadComponent: () => import('./features/dashboard/seller-dashboard.component'),
        canActivate: [KycAwareGuard],  // shows KYC overlay but doesn't block route
      },
      {
        path: 'listings',
        loadChildren: () => import('./features/listings/listings.routes'),
        canActivate: [KycApprovedGuard, NotSuspendedGuard],
      },
      {
        path: 'orders',
        loadChildren: () => import('./features/orders/seller-orders.routes'),
        canActivate: [KycApprovedGuard],
        // Does NOT use NotSuspendedGuard (SellerActiveGuard).
        // Suspended sellers retain read-only access to the Pending Orders tab to mark shipment (US-A-05 exception).
        // Tab restriction (Pending-tab-only for suspended sellers) is enforced at component level
        // within SellerOrderQueueComponent, not via a route guard.
      },
      {
        path: 'inventory',
        loadChildren: () => import('./features/inventory/inventory.routes'),
        canActivate: [KycApprovedGuard, NotSuspendedGuard],
      },
      {
        path: 'notifications',
        loadComponent: () => import('./features/notifications/seller-notifications.component'),
        canActivate: [KycApprovedGuard],
        // Linked from <aliceut-notification-bell> 'View all' link in seller shell
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
/seller/listings/:id/edit           → CreateEditListingComponent (isNew=false)
/seller/listings/:id/pricing        → OfferPricingComponent
```

**`seller-orders.routes.ts`**
```
/seller/orders         → SellerOrderQueueComponent (mat-tab-group per status)
/seller/orders/:id     → SellerOrderDetailComponent
```

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
  // Auth routes (no shell)
  {
    path: 'admin/login',
    loadComponent: () => import('./features/auth/admin-login/admin-login.component'),
    canActivate: [GuestGuard],
  },
  // Protected admin routes (with sidenav shell)
  {
    path: 'admin',
    loadComponent: () => import('./shell/admin-shell.component'),
    canActivate: [AdminAuthGuard],  // requires ADMIN role
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
        path: 'notifications',
        loadComponent: () => import('./features/notifications/admin-notifications.component'),
        // No extra canActivate — parent admin route already applies AdminAuthGuard
        // Linked from <aliceut-notification-bell> 'View all' link in admin shell
      },
    ],
  },
  { path: '403', loadComponent: () => import('./shared/error/forbidden.component') },
  { path: '404', loadComponent: () => import('./shared/error/not-found.component') },
  { path: '', redirectTo: 'admin/login', pathMatch: 'full' },
  { path: '**', redirectTo: '404' },
];
```

### Feature Route Sub-trees

**`kyc.routes.ts`**
```
/admin/kyc        → KycQueueComponent
/admin/kyc/:id    → KycApplicationDetailComponent
```

**`moderation.routes.ts`**
```
/admin/moderation        → ModerationQueueComponent
/admin/moderation/:id    → ModerationCaseDetailComponent
```

**`sellers.routes.ts`**
```
/admin/sellers        → SellerManagementComponent
/admin/sellers/:id    → SellerDetailComponent
```

---

<a id="auth-guard-matrix"></a>
## 5. Auth Guard Matrix

### Shared Guards (`libs/auth/`)

| Guard class | Condition checked | On fail |
|-------------|-------------------|---------|
| `AuthGuard` | Valid JWT present; not expired (silent refresh attempted first) | Redirect to portal login + `returnUrl` |
| `GuestGuard` | No valid JWT (or expired) | Redirect to portal home / dashboard |
| `EmailVerifiedGuard` | `email_verified: true` in JWT payload | Redirect to `/email-verification-pending` |
| `RoleGuard(role)` | JWT `roles` array contains required role | Redirect to `/403` |
| `SellerAuthGuard` | `AuthGuard` + `RoleGuard('SELLER')` | Redirect to `/seller/login` |
| `AdminAuthGuard` | `AuthGuard` + `RoleGuard('ADMIN')` | Redirect to `/admin/login` |
| `KycApprovedGuard` | `seller_kyc_status` claim from decoded JWT access token — synchronous, no API round-trip; reads from `AuthService.currentToken` store | Show KYC overlay component within route; does not redirect |
| `NotSuspendedGuard` | `seller_suspension_status` claim from decoded JWT access token — synchronous, no API round-trip; reads from `AuthService.currentToken` store | Show suspension message component; does not redirect |
| `KycAwareGuard` | Always passes; injects `kycStatus` into component via router data | — |

### Route-level Guard Summary

| Route | Guards | Notes |
|-------|--------|-------|
| `/` (buyer home) | None | Guest allowed |
| `/search` | None | Guest allowed |
| `/products/:id` | None | Guest allowed |
| `/cart` | None | Guest cart displayed |
| `/checkout/**` | `AuthGuard`, `EmailVerifiedGuard` | Redirect to `/login?returnUrl=/checkout` |
| `/orders/**` | `AuthGuard` | Email verification not required to view orders |
| `/account/**` | `AuthGuard` | — |
| `/seller/**` | `SellerAuthGuard` | Exception: `/seller/login`, `/seller/register` use `GuestGuard` |
| `/seller/listings/**` | `SellerAuthGuard`, `KycApprovedGuard`, `NotSuspendedGuard` | — |
| `/seller/orders/**` | `SellerAuthGuard`, `KycApprovedGuard` | No `NotSuspendedGuard` — suspended sellers retain read-only Pending tab access; tab restriction enforced at component level in `SellerOrderQueueComponent` (US-A-05) |
| `/seller/inventory/**` | `SellerAuthGuard`, `KycApprovedGuard`, `NotSuspendedGuard` | — |
| `/notifications` | `AuthGuard` | Buyer notifications page; bell "View all" link target |
| `/seller/notifications` | `SellerAuthGuard`, `KycApprovedGuard` | Seller notifications page; bell "View all" link target |
| `/seller/forgot-password` | None (public) | No auth guard — accessible from any state |
| `/seller/reset-password` | None (public) | Handles `?token=` query param; no auth guard |
| `/admin/**` | `AdminAuthGuard` | Exception: `/admin/login` uses `GuestGuard` |

---

<a id="navigation-patterns"></a>
## 6. Navigation Patterns

### 6.1 Buyer Portal

**Top toolbar navigation:** Logo → `/`, Search bar → `/search?q=`, Cart icon → `/cart`, User menu → account pages.

**Breadcrumbs (PDP and checkout):**
- PDP: `Home > Category > Subcategory > Product Title` — each segment is a routerLink.
- Breadcrumb service resolves from router data; `ActivatedRouteSnapshot.data.breadcrumb` provides label.
- Mobile: breadcrumbs truncate to show only parent category and product title.

**Back navigation:** Back button (`mat-icon-button` with `arrow_back`) on detail/checkout pages uses `Location.back()` — preserves scroll position and filter state.

**Pagination:** All paginated lists encode `page` and `pageSize` as query params for shareable deep-links:
- `/search?q=laptop&page=2&pageSize=24&sort=price_asc`
- `/orders?page=1&status=SHIPPED`

**Filter state persistence:** Active filters encoded in URL query params. Angular Router subscription in components re-applies filters on browser back/forward navigation.

### 6.2 Seller Portal

**Sidenav navigation:** Persistent sidebar on desktop (mode=side), overlay drawer on mobile (mode=over). Active route highlighted with `routerLinkActive="active"` CSS class (`background: primary-50; border-left: 3px solid primary`).

**Breadcrumbs (detail pages):**
- Order detail: `Orders > ORD-XXXXXXXX`
- Edit listing: `Listings > [Product Title] > Edit`
- Breadcrumb rendered as `mat-nav-list` in page header area.

**Tab state persistence:** Active tab in Order Queue (`/seller/orders?tab=pending`) and Inventory (`/seller/inventory?filter=all`) encoded as query params so refresh restores active tab.

### 6.3 Admin Portal

**Sidenav navigation:** Same pattern as seller portal. Badge counts on KYC and Moderation nav items.

**Queue navigation:** After approving/rejecting a KYC application, navigate back to `/admin/kyc` with `MatSnackBar` success notification. [DESIGN DECISION: Auto-advance to next item not implemented in V1 to keep navigation predictable.]

---

<a id="lazy-loaded-feature-module-boundaries"></a>
## 7. Lazy-Loaded Feature Module Boundaries

Each feature area is a separate lazy-loaded chunk. Rationale: admin/seller portals are visited less frequently than buyer storefront; lazy loading avoids loading seller/admin code in the buyer app's initial bundle.

| App | Feature chunk | Loaded when |
|-----|---------------|-------------|
| buyer-app | `home` | Initial route (eager as of first navigation) |
| buyer-app | `search` | `/search` navigated to |
| buyer-app | `product` | `/products/:id` opened |
| buyer-app | `checkout` | `/checkout` navigated to |
| buyer-app | `orders` | `/orders` navigated to |
| buyer-app | `account` | `/account` navigated to |
| seller-app | `kyc` | `/seller/kyc` navigated to |
| seller-app | `listings` | `/seller/listings` navigated to |
| seller-app | `orders` | `/seller/orders` navigated to |
| seller-app | `inventory` | `/seller/inventory` navigated to |
| admin-app | `kyc` | `/admin/kyc` navigated to |
| admin-app | `moderation` | `/admin/moderation` navigated to |
| admin-app | `sellers` | `/admin/sellers` navigated to |

**Preloading strategy:** `PreloadAllModules` for buyer-app (catalog browsing benefits from preload). `NoPreloading` for seller-app and admin-app (small user base; load on demand).

---

<a id="deep-link-behavior"></a>
## 8. Deep Link Behavior

| Scenario | Behavior |
|----------|----------|
| Guest visits `/checkout` | Redirect to `/login?returnUrl=/checkout`; after login, redirect back to `/checkout` with merged cart |
| Authenticated buyer visits `/seller/login` | buyer-app has no `/seller/login` route; served by separate origin (port 4201) |
| Buyer visits `/orders/abc123` with invalid orderId | API returns 404; component shows `EmptyState` with "Order not found" |
| Admin visits `/admin/kyc/abc123` with invalid kycId | API returns 404; component shows `EmptyState` with "Application not found" |
| Email verification link `?token=xxx` | `/verify-email?token=xxx` → API validates; on success redirect to `/login?verified=true`; on failure show inline error with resend option |
| Password reset link `?token=xxx` | `/reset-password?token=xxx` → API validates token type; renders correct form variant |
| Seller app visited without `/seller` prefix (e.g., `/`) | Redirects to `/seller/dashboard` if authenticated, else to `/seller/login` |

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

`homeRoute` resolves per app: buyer-app → `/`, seller-app → `/seller/dashboard`, admin-app → `/admin/dashboard`.

### 403 Forbidden

```
div.error-page [text-align: center; padding: 80px 24px]
  mat-icon [font-size: 80px; color: warn] — lock_outline
  h1 mat-h3 — Access Denied
  p mat-body-1 — You don't have permission to view this page.
  button mat-flat-button color="primary" [routerLink]="homeRoute" — Go to Home
```

### API Service Unavailable (Search)

Not a routed page — displayed inline in the search results component as a `mat-card.error-banner`. See buyer-portal.md Screen 2.

---

<a id="navigation-after-auth-events"></a>
## 10. Navigation After Auth Events

| Event | Navigation |
|-------|------------|
| Buyer login success | Redirect to `returnUrl` (if set); else `/` |
| Buyer login via OAuth (Google/Facebook) | Same as above |
| Buyer registration success | Redirect to `/email-verification-pending` (email/password) or `/` (OAuth) |
| Email verified | Redirect to `/login?verified=true` (shows success snackbar on login page) |
| Seller login success | Redirect to `/seller/dashboard` (KYC state determines overlay) |
| Seller registration + KYC redirect | Redirect to `/seller/kyc` |
| Admin login success | Redirect to `/admin/dashboard` |
| Logout (any portal) | Clear JWT; redirect to portal login page |
| All-sessions logout | Same as Logout for current browser |
| JWT expiry + refresh fails | Redirect to portal login with `returnUrl` preserved |
| Account suspended (detected via 403 response) | Show suspension banner in shell; nav items restricted |

---

<a id="query-param-conventions"></a>
## 11. Query Param Conventions

| Param | Used by | Example | Purpose |
|-------|---------|---------|---------|
| `q` | Search | `?q=laptop` | Keyword search |
| `category` | Search | `?category=electronics` | Category filter |
| `minPrice` | Search | `?minPrice=100` | Price filter (in preferred currency) |
| `maxPrice` | Search | `?maxPrice=1500` | Price filter |
| `minRating` | Search | `?minRating=4` | Rating filter |
| `inStock` | Search | `?inStock=true` | In-stock filter |
| `sort` | Search, Orders | `?sort=price_asc` | Sort order |
| `page` | Search, Orders, KYC, Moderation, Sellers | `?page=2` | Pagination (1-based) |
| `pageSize` | Search | `?pageSize=24` | Items per page |
| `status` | Orders, KYC, Moderation, Sellers | `?status=PENDING` | Status filter |
| `tab` | Seller Orders | `?tab=pending` | Active tab |
| `filter` | Inventory | `?filter=lowstock` | Inventory filter |
| `returnUrl` | Login pages | `?returnUrl=%2Fcheckout` | Post-auth redirect |
| `verified` | Buyer Login | `?verified=true` | Post-verification success toast trigger |
| `sla` | Admin KYC | `?sla=breached` | SLA breach filter pre-applied |
| `token` | Verify email, Reset password | `?token=xxx` | One-time link token |
| `orderId` | Checkout confirmation | `?orderId=xxx` | Loads confirmation state |

All array-valued params (e.g. multiple categories) use repeated params: `?category=electronics&category=books`.

---

<a id="title-strategy"></a>
## 12. Title Strategy

Each portal uses `TitleStrategy` to set meaningful `<title>` values for browser tabs and history.

```typescript
// libs/auth/src/lib/page-title.strategy.ts
@Injectable({ providedIn: 'root' })
export class AppTitleStrategy extends TitleStrategy {
  updateTitle(snapshot: RouterStateSnapshot): void {
    const title = this.buildTitle(snapshot);
    this.title.setTitle(title ? `${title} — AliceUT` : 'AliceUT');
  }
}
```

Route data title examples:

| Route | Title |
|-------|-------|
| `/` (buyer home) | `AliceUT` |
| `/search?q=laptop` | `Results for "laptop" — AliceUT` |
| `/products/:id` | `[Product Name] — AliceUT` |
| `/cart` | `Cart — AliceUT` |
| `/checkout` | `Checkout — AliceUT` |
| `/checkout/confirmation` | `Order Confirmed — AliceUT` |
| `/orders` | `My Orders — AliceUT` |
| `/seller/dashboard` | `Dashboard — Seller Hub` |
| `/seller/listings` | `My Listings — Seller Hub` |
| `/seller/orders` | `Orders — Seller Hub` |
| `/admin/dashboard` | `Dashboard — Admin` |
| `/admin/kyc` | `KYC Queue — Admin` |
| `/admin/moderation` | `Moderation — Admin` |

---

<a id="scroll-behavior"></a>
## 13. Scroll Behavior

Use `withInMemoryScrollingOptions({ scrollPositionRestoration: 'enabled', anchorScrolling: 'enabled' })`.

- Browser back/forward: restores scroll position on list pages (search results, order history).
- Navigation to new route: scrolls to top.
- Anchor links (e.g. `#description` tab on PDP): enabled.
- Exception: checkout stepper scroll — programmatically scroll to top of active step via `ViewportScroller.scrollToPosition([0, 0])` on step change.

---

*Last updated: phase-1 design*
