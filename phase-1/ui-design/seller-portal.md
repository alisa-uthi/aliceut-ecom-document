# Seller Portal — UI Design Specification
## seller-app (port 4201)

**Status:** Draft  
**Stack:** Angular 22+ + Angular Material + `libs/ui/` (`@aliceut/shared-ui`) composite components  
**Auth:** Email/password only (no OAuth). JWT with SELLER role.  
**API contracts:** [seller.md](../technical-design/api-design/seller.md), [auth.md](../technical-design/api-design/auth.md), [notifications.md](../technical-design/api-design/notifications.md), [pricing.md](../technical-design/api-design/pricing.md)

Component contracts are owned by [conventions/design-system.md § 8](../../conventions/design-system.md#8-shared-component-library-libsui) — in particular the prop surfaces of [`PriceDisplay` § 8.3](../../conventions/design-system.md#83-pricedisplay) and `CurrencyInput` § 8.4, which every `<aliceut-price-display>` and `<aliceut-currency-input>` below binds against and which this document does not restate. Phase-1 binding sources per input, including the rule that a seller price input's `currencyCode` is the parent offer's `nativeCurrencyCode`, are in [shared-components.md § 4.3](shared-components.md#43-pricedisplay) and [§ 4.4](shared-components.md#44-currencyinput). The cross-cutting rules every screen below follows — standalone + OnPush, `ViewState<T>`, reactive forms (no `[(ngModel)]`, including inline table edits), cursor pagination, accessibility — are in [shared-components.md § 7](shared-components.md#7-rules-every-screen-follows) and are not repeated per screen. The auth screens follow [§ 8](shared-components.md#8-auth-screen-pattern) and the notifications page follows [§ 9](shared-components.md#9-notifications-page-pattern).

**Ids on this portal.** A row under `/seller/orders` is one `orders.fulfillment` — one seller's group within a buyer's checkout — so its id is `:fulfillmentId` and its display id is `FUL-` plus nine zero-padded digits. The buyer's `ORD-` id travels with it as `orderDisplayId` and is shown where the seller may need to quote what the buyer sees, but the record the screen is about is the fulfillment. A row under `/seller/listings` is an **offer**, so its id is `:offerId` ([seller.md § Endpoint Index](../technical-design/api-design/seller.md#endpoint-index), [navigation-routing.md § 3](navigation-routing.md#seller-app-route-tree)).

---

## Summary

- [Shell Layout](#shell-layout)
- [Screen 1 — Seller Login](#screen-1-seller-login)
- [Screen 2 — Seller Register](#screen-2-seller-register)
- [Screen 3 — KYC Application](#screen-3-kyc-application)
- [Screen 4 — Seller Dashboard](#screen-4-seller-dashboard)
- [Screen 5 — Product Listings](#screen-5-product-listings)
- [Screen 6 — Create / Edit Product](#screen-6-create-edit-product)
- [Screen 7 — Order Queue](#screen-7-order-queue)
- [Screen 8 — Fulfillment Detail](#screen-8-order-detail)
- [Screen 9 — Inventory](#screen-9-inventory)
- [Screen 10 — Offer Pricing](#screen-10-offer-pricing)
- [Screen 11 — Seller Forgot Password](#screen-11-seller-forgot-password)
- [Screen 12 — Seller Reset Password](#screen-12-seller-reset-password)
- [Screen 13 — Seller Notifications](#screen-13-seller-notifications)
- [Appendix — Seller Notification Types](#appendix-seller-notifications)

**Not a screen on this portal.** The notification bell in the toolbar is the shared `NotificationBellComponent`, whose contract is [design-system.md § 8.7](../../conventions/design-system.md#8-shared-component-library-libsui) and whose Phase-1 bindings are [shared-components.md § 4.1](shared-components.md#41-notificationbell); the types it renders are the appendix table below. `/seller/profile` is a route this portal serves — it is the redirect target of `sellerNotSuspendedGuard` and the one screen that states a suspension's reason and end date — and it has **no wireframe here yet**.

<a id="shell-layout"></a>
## Shell Layout

```
a.skip-link href="#main-content" — Skip to main content     ← first focusable element in the DOM

mat-sidenav-container [fullscreen]
  mat-sidenav #drawer [mode]="isDesktop ? 'side' : 'over'" [opened]="isDesktop" [fixedInViewport]
    div.brand [padding: 16px 24px; display: flex; align-items: center; gap: 12px]
      mat-icon [color=primary; font-size: 28px] — storefront
      span mat-h6 — Seller Hub

    mat-nav-list
      a mat-list-item routerLink="/seller/dashboard" routerLinkActive="active"
        mat-icon matListItemIcon — dashboard
        span matListItemTitle — Dashboard
      a mat-list-item routerLink="/seller/listings" routerLinkActive="active"
        mat-icon matListItemIcon — inventory_2
        span matListItemTitle — My Listings
      a mat-list-item routerLink="/seller/orders" routerLinkActive="active"
        mat-icon matListItemIcon — receipt_long
        span matListItemTitle — Orders
        mat-badge *ngIf="pendingOrderCount > 0" [matBadgeColor]="'warn'" — {{ pendingOrderCount }}
      a mat-list-item routerLink="/seller/inventory" routerLinkActive="active"
        mat-icon matListItemIcon — inventory
        span matListItemTitle — Inventory
      mat-divider
      a mat-list-item (click)="logout()"
        mat-icon matListItemIcon — logout
        span matListItemTitle — Sign Out

  mat-sidenav-content
    mat-toolbar [color=primary] [position: sticky; top: 0; z-index: 100]
      button mat-icon-button (click)="drawer.toggle()" *ngIf="!isDesktop" aria-label="Toggle menu"
        mat-icon — menu
      span — AliceUT Seller Hub
      span.spacer [flex: 1]
      <aliceut-notification-bell [notifications]="notifications" [unreadCount]="unreadCount"
        (markAsRead)="markRead($event)" (markAllRead)="markAllRead()">
      button mat-button [matMenuTriggerFor]="profileMenu"
        mat-icon — account_circle
        span — {{ sellerProfile.businessName || sellerName }}
      mat-menu #profileMenu
        button mat-menu-item routerLink="/seller/profile" — store icon — Business Profile
        button mat-menu-item routerLink="/seller/kyc" *ngIf="!isApproved" — assignment icon — KYC Application
        mat-divider
        button mat-menu-item (click)="logout()" — logout icon — Sign Out

    main#main-content.seller-content [padding: 24px]
      <!-- Suspension banner — shown when seller is SUSPENDED -->
      mat-card.error-banner *ngIf="isSuspended" [margin-bottom: 16px]
        mat-icon color="warn" — block
        h4 mat-h6 — Your account is suspended
        p mat-body-2 — Reason: {{ suspensionReason }}
        p mat-body-2 *ngIf="suspendedUntil" — Suspended until: {{ suspendedUntil | date:'mediumDate' }}
        p mat-body-2 *ngIf="!suspendedUntil" — Suspension: Permanent
        p mat-caption — You can still view and manage orders that were placed before the suspension.

      <!-- KYC pending/rejected banner -->
      mat-card.warning-banner *ngIf="kycStatus === 'PENDING_KYC'" [margin-bottom: 16px]
        mat-icon — hourglass_empty
        span — Your KYC application is under review. You'll be notified once a decision is made.

      mat-card.error-banner *ngIf="kycStatus === 'REJECTED'" [margin-bottom: 16px]
        mat-icon color="warn" — cancel
        div
          p mat-body-2 — Your application was rejected: {{ rejectionReason }}
          button mat-flat-button color="primary" routerLink="/seller/kyc" — Update and Resubmit

      router-outlet
```

**Shell data.** `notifications` is the first page of `GET /notifications?limit=20`, `unreadCount` is `GET /notifications/unread-count`, and `pendingOrderCount` on the Orders nav item is the pending count from `GET /seller/dashboard/summary` — which is `SELLER_ACTIVE`-only, so the badge is absent for an unapproved or suspended seller. The bell polls on page focus and on a 60 s interval; there is no WebSocket in V1.

**Sidebar navigation during suspension.** Nav items stay **visible and greyed out** rather than being hidden, so the seller keeps their orientation. Clicking a guarded item does not render its screen: `sellerNotSuspendedGuard` redirects to `/seller/profile`, the one screen that states the suspension reason and end date, and the shell's suspension banner stays visible from every surviving screen. Orders, KYC, profile, dashboard and notifications survive a suspension; listings and inventory do not ([navigation-routing.md § 5](navigation-routing.md#auth-guard-matrix)).

---

<a id="screen-1-seller-login"></a>
## Screen 1 — Seller Login

**Route:** `/seller/login`  
**Auth:** None (redirect to dashboard if authenticated)

The card shell, the two fields with their visibility toggle, the error banner and the submit button are [shared-components.md § 8.1–8.3](shared-components.md#8-auth-screen-pattern). Portal mark `mat-icon storefront` at 48px, title "Seller Portal Sign In", subtitle "Manage your listings and orders". What this screen adds:

```
mat-card-content
  [shared form: email + password + error banner + "Sign In" submit]

  div [text-align: right; margin: 4px 0 16px]
    a mat-button routerLink="/seller/forgot-password" — Forgot password?

  p mat-body-2 [text-align: center; margin-top: 24px]
    span — New seller?
    a mat-button color="primary" routerLink="/seller/register" — Create seller account

  p mat-caption [text-align: center; margin-top: 8px]
    span — Looking for the buyer store?
    a mat-button [href]="buyerAppUrl" — Visit AliceUT     ← absolute cross-origin link, so href and not routerLink
```

`buyerAppUrl` is the buyer portal's origin from the app's environment configuration; the buyer store is a separate application on a separate origin, so it is never reachable through the router.

**No Google/Facebook OAuth buttons.** `POST /auth/login` here carries `portal: "SELLER"`, and OAuth is buyer-only (US-B-00, [shared-components.md § 8.5](shared-components.md#8-auth-screen-pattern)).

---

<a id="screen-2-seller-register"></a>
## Screen 2 — Seller Register

**Route:** `/seller/register`

The card shell (at the 480px width), the fields, the error banner and the submit button are [shared-components.md § 8.1–8.4](shared-components.md#8-auth-screen-pattern) — including the password hint and the policy behind it. Title "Create a Seller Account", subtitle "Sell on AliceUT. Reach global buyers." What this screen adds:

```
mat-card-content
  form [formGroup]="registerForm" (ngSubmit)="register()"
    h4 mat-h6 [margin-bottom: 16px] — Step 1: Account Details
    mat-form-field [appearance=outline; fullWidth] — mat-label "Full Name" — formControlName="fullName" autocomplete="name"
    [shared email field]
      mat-hint — If this email already has a buyer account, you'll be asked to sign in to link roles.
    [shared password field]  +  [shared confirm-password field]

    <!-- Existing account detected state -->
    mat-card.info-banner *ngIf="existingAccountDetected" [margin-bottom: 16px]
      mat-icon — info_outline
      span — This email already has an account. Sign in with your password to add the Seller role.
      mat-form-field [appearance=outline; fullWidth; margin-top: 12px]
        mat-label — Your Password
        input matInput type="password" formControlName="existingPassword" autocomplete="current-password"

    [shared submit — label "Create Account & Continue to KYC"]

  p mat-body-2 [text-align: center; margin-top: 16px]
    span — Already a seller?
    a mat-button routerLink="/seller/login" — Sign in
```

`POST /seller/register` is **public** — it takes no token, because a prospective seller may hold no AliceUT account at all. A new email creates the account; an email that already holds one proves ownership with `existingPassword` in the body, not with a buyer JWT, and the SELLER role is linked to it. An **OAuth-only** buyer account has no local password to prove: the response is `409 PASSWORD_REQUIRED_FOR_LINK`, rendered as an inline banner pointing at the buyer portal's set-password flow (US-B-15), and the form stays where it is.

On success the response opens a SELLER session and the client redirects to `/seller/kyc` for step 2.

---

<a id="screen-3-kyc-application"></a>
## Screen 3 — KYC Application

**Route:** `/seller/kyc`  
**Auth:** SELLER role; shown when `kycStatus === 'PENDING_KYC'` or `'REJECTED'`

### Layout

```
h1 mat-h3 — KYC Application
p mat-body-2 — Complete your business verification to start listing products.

<!-- Status header for resubmissions -->
mat-card.info-banner *ngIf="kycStatus === 'REJECTED'" [margin-bottom: 24px]
  mat-icon — info_outline
  span — Your previous application was rejected: {{ rejectionReason }}. Update your documents and resubmit.

<!-- Shown when kycStatus === 'APPROVED' -->
ng-container *ngIf="kycStatus === 'APPROVED'"
  <aliceut-empty-state
    icon="verified_user"
    title="Your account is already verified"
    message="Your KYC application has been approved. You can create listings from your dashboard.">
    <button mat-flat-button color="primary" routerLink="/seller/dashboard">Go to Dashboard</button>
  </aliceut-empty-state>

mat-stepper [linear] [orientation]="isDesktop ? 'horizontal' : 'vertical'"
  mat-step label="Business Details" [stepControl]="businessForm"
    form [formGroup]="businessForm" [max-width: 600px]
      mat-form-field [appearance=outline; fullWidth]
        mat-label — Legal Business Name
        input matInput formControlName="businessName"
        mat-error — Business name is required
      mat-form-field [appearance=outline; fullWidth]
        mat-label — Business Type
        mat-select formControlName="businessType"
          mat-option value="SOLE_PROP" — Sole Proprietorship
          mat-option value="LLC" — Limited Liability Company (LLC)
          mat-option value="CORP" — Corporation
          mat-option value="PARTNERSHIP" — Partnership
      mat-form-field [appearance=outline; fullWidth]
        mat-label — Tax ID / Business Registration Number
        input matInput formControlName="taxId"
        mat-hint — Your tax ID or business registration number
        <!-- V1 validation policy: required, maxLength(50). No country-specific format validation.
             Backend stores as-is. Placeholder: "Enter your tax ID number" -->
        mat-error *ngIf="taxId.hasError('required')" — Tax ID is required
        mat-error *ngIf="taxId.hasError('maxlength')" — Tax ID must not exceed 50 characters
      mat-form-field [appearance=outline; fullWidth]
        mat-label — Country
        mat-select formControlName="country"
          mat-option *ngFor="let c of countries" [value]="c.code" — {{ c.name }}
      mat-form-field [appearance=outline; fullWidth] — mat-label "Business Address Line 1" — formControlName="addressLine1"
      mat-form-field [appearance=outline; fullWidth] — mat-label "Business Address Line 2 (optional)" — formControlName="addressLine2"
      div.two-col
        mat-form-field — mat-label "City" — formControlName="city"
        mat-form-field — mat-label "Postal Code" — formControlName="postalCode"
      mat-form-field [appearance=outline; fullWidth] — mat-label "Business Phone" — formControlName="phone"
      div [text-align: right; margin-top: 16px]
        button mat-flat-button color="primary" matStepperNext [disabled]="businessForm.invalid" — Next: Documents

  mat-step label="Documents" [stepControl]="docsForm"
    p mat-body-2 [margin-bottom: 16px] — Upload the following documents. Accepted: PDF, JPG, PNG (max 10MB each).

    div.doc-section [margin-bottom: 24px]
      h4 mat-h6 — Business License / Registration Certificate *
      <aliceut-file-upload [accept]="'application/pdf,image/jpeg,image/png'" [maxSizeMb]="10" [multiple]="false" [maxFiles]="1"
        (filesChange)="businessLicenseFile = $event[0]">
      mat-error *ngIf="docsSubmitted && !businessLicenseFile" — Business license document is required.

    div.doc-section [margin-bottom: 24px]
      h4 mat-h6 — Government-Issued ID (Passport / National ID) *
      <aliceut-file-upload [accept]="'application/pdf,image/jpeg,image/png'" [maxSizeMb]="10" [multiple]="false" [maxFiles]="1"
        (filesChange)="idDocFile = $event[0]">
      mat-error *ngIf="docsSubmitted && !idDocFile" — Identity document is required.

    div.doc-section [margin-bottom: 24px]
      h4 mat-h6 — Bank Statement or Proof of Address *
      <aliceut-file-upload [accept]="'application/pdf,image/jpeg,image/png'" [maxSizeMb]="10" [multiple]="false" [maxFiles]="1"
        (filesChange)="bankStatementFile = $event[0]">
      mat-error *ngIf="docsSubmitted && !bankStatementFile" — Bank statement / proof of address is required.

    mat-card.info-banner [margin-top: 16px]
      mat-icon — lock
      span mat-body-2 — Documents are encrypted at rest. Access is logged for compliance (NFR-09).

    div [display: flex; gap: 8px; justify-content: flex-end; margin-top: 16px]
      button mat-button matStepperPrevious — Back
      button mat-flat-button color="primary" matStepperNext
        [disabled]="!businessLicenseFile || !idDocFile || !bankStatementFile"
        (click)="docsSubmitted = true"
        — Next: Review

  mat-step label="Review & Submit"
    div [max-width: 600px]
      mat-list
        mat-list-item
          mat-icon matListItemIcon — business
          span mat-list-item-title — {{ businessForm.value.businessName }}
          span mat-list-item-line — {{ businessForm.value.businessType | titlecase }}
        mat-list-item
          mat-icon matListItemIcon — receipt
          span mat-list-item-title — Tax ID: {{ businessForm.value.taxId }}
        mat-list-item
          mat-icon matListItemIcon — location_on
          span mat-list-item-title — {{ businessForm.value.city }}, {{ businessForm.value.country }}
        mat-list-item
          mat-icon matListItemIcon — upload_file
          span mat-list-item-title — 3 documents ready to submit
      mat-divider [margin: 16px 0]
      mat-checkbox [formControl]="agreeTerms" — I confirm that all submitted information is accurate and my documents are genuine.
      div [display: flex; gap: 8px; justify-content: flex-end; margin-top: 16px]
        button mat-button matStepperPrevious — Back
        button mat-flat-button color="primary" [disabled]="!agreeTerms.value || isSubmitting" (click)="submit()"
          mat-spinner *ngIf="isSubmitting" [diameter]="20"
          span *ngIf="!isSubmitting" — Submit Application
```

### Post-Submit State

Shows success card: "Application submitted. We'll review it within 3 business days and notify you by email." Links back to Dashboard. KYC status shows as "PENDING_KYC" in dashboard banner.

**Already-approved state note:** Guards do not redirect from this route — the component handles the already-approved case with the `aliceut-empty-state` block above. Prevents re-submission per US-S-01.

---

<a id="screen-4-seller-dashboard"></a>
## Screen 4 — Seller Dashboard

**Route:** `/seller/dashboard`  
**Auth:** SELLER role + APPROVED (otherwise show KYC overlay)

### KYC Overlay (PENDING_KYC)

When KYC is pending, show the dashboard structure but with a `mat-card.info-overlay` covering the stats area:

```
mat-card [padding: 48px; text-align: center; border: 2px dashed divider]
  mat-icon [font-size: 48px; color: amber] — hourglass_empty
  h3 mat-h5 — KYC Under Review
  p mat-body-1 — Your application is being reviewed. This typically takes 1–3 business days.
  p mat-body-2 — You'll receive an email notification once a decision is made.
  button mat-stroked-button routerLink="/seller/kyc" — View Application
```

### Dashboard Layout (Approved Seller)

```
h1 mat-h4 — Welcome back, {{ sellerName }}

<!-- First-approval onboarding banner -->
<!-- Shown once after KYC first transitions to APPROVED; dismissed and stored in localStorage -->
mat-card.success-banner *ngIf="showFirstApprovalBanner" [margin-bottom: 24px]
  mat-icon — celebration
  span — Your account is approved — create your first listing
  button mat-button routerLink="/seller/listings/new" — Create Listing
  button mat-icon-button (click)="dismissFirstApprovalBanner()"
    mat-icon — close

<!-- Stats cards row -->
div.stats-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px]

  mat-card.stat-card [cursor: pointer] (click)="navigate('/seller/orders', { status: 'PENDING' })"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: flex-start]
        div
          p mat-caption [margin-bottom: 4px] — Pending Orders
          p mat-headline-5 — {{ stats.pendingOrders }}
        mat-icon [font-size: 32px; color: amber] — receipt_long
    mat-card-footer [padding: 8px 16px; background: primary-50]
      span mat-caption — View all pending →

  mat-card.stat-card (click)="navigate('/seller/inventory')"     ← see the low-stock note below
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: flex-start]
        div
          p mat-caption — Low Stock SKUs
          p mat-headline-5 [color]="stats.lowStockSkus > 0 ? 'warn' : 'default'" — {{ stats.lowStockSkus }}
        mat-icon [font-size: 32px; color: warn] *ngIf="stats.lowStockSkus > 0" — warning_amber
        mat-icon [font-size: 32px; color: success] *ngIf="stats.lowStockSkus === 0" — inventory_2
    mat-card-footer [padding: 8px 16px; background: primary-50]
      span mat-caption — Manage inventory →

  mat-card.stat-card (click)="navigate('/seller/listings')"
    mat-card-content
      div [display: flex; justify-content: space-between]
        div
          p mat-caption — Active Listings
          p mat-headline-5 — {{ stats.activeListings }}
        mat-icon [font-size: 32px; color: primary] — inventory_2
    mat-card-footer [padding: 8px 16px; background: primary-50]
      span mat-caption — Manage listings →

  mat-card.stat-card (click)="navigate('/seller/listings', { status: 'FLAGGED' })"
    mat-card-content
      div [display: flex; justify-content: space-between]
        div
          p mat-caption — Flagged / Removed
          p mat-headline-5 [color]="stats.flaggedListings > 0 ? 'warn' : 'default'" — {{ stats.flaggedListings }}
        mat-icon [font-size: 32px; color: warn] *ngIf="stats.flaggedListings > 0" — flag
        mat-icon [font-size: 32px; color: success] *ngIf="stats.flaggedListings === 0" — check_circle_outline
    mat-card-footer [padding: 8px 16px; background: primary-50]
      span mat-caption — View flagged →

<!-- Low stock alerts banner -->
mat-card.warning-banner *ngIf="lowStockAlerts.length > 0" [margin-bottom: 24px]
  mat-icon color="warn" — warning_amber
  h4 mat-h6 — Low Stock Alert
  mat-chip-listbox aria-label="Low stock SKUs" [margin-top: 8px]
    mat-chip *ngFor="let sku of lowStockAlerts; trackBy: trackBySkuId" [removable]="false" color="warn"
      {{ sku.skuName }}: {{ sku.available }} left

<!-- Quick actions -->
div.quick-actions [display: flex; gap: 12px; margin-bottom: 24px; flex-wrap: wrap]
  button mat-flat-button color="primary" routerLink="/seller/listings/new" [disabled]="isSuspended"
    mat-icon — add
    span — Create New Listing
  button mat-stroked-button routerLink="/seller/orders"
    mat-icon — receipt_long
    span — View Orders
  button mat-stroked-button routerLink="/seller/inventory"
    mat-icon — inventory
    span — Manage Inventory

<!-- Recent pending orders (last 5) -->
div.recent-orders *ngIf="recentPendingOrders.length > 0"
  h2 mat-h5 [margin-bottom: 16px] — Recent Pending Orders
  mat-list
    mat-list-item *ngFor="let f of recentPendingFulfillments; trackBy: trackByFulfillmentId"
      mat-icon matListItemIcon — receipt_long
      span mat-list-item-title — {{ f.displayId }}            ← FUL-000003871
      span mat-list-item-line — {{ f.itemCount }} item(s) · {{ f.placedAt | timeAgo }}
      <aliceut-status-badge matListItemMeta [status]="f.status" [statusType]="'fulfillment'">
      button mat-icon-button matListItemMeta [routerLink]="['/seller/orders', f.id]"
             aria-label="View fulfillment" — chevron_right
```

**Stats and the recent list come from `GET /seller/dashboard/summary`** — the four US-S-00 counts plus the recent pending fulfillments. The guard is `SELLER_ACTIVE`, which is why the dashboard route carries no approval or suspension guard of its own and the component decides whether to make the call at all ([navigation-routing.md § 3](navigation-routing.md#seller-app-route-tree)).

**Low-stock card.** It navigates to `/seller/inventory` with no filter: `GET /seller/offers` accepts `status` and `caseStatus` and no low-stock parameter, so a `?filter=lowstock` query would be a URL the API cannot honour. The inventory screen's own low-stock banner and its per-row warning are the affordance.

**First-approval banner.** `showFirstApprovalBanner` is true when `kycStatus === 'APPROVED'` and `localStorage.getItem('firstApprovalBannerDismissed') !== 'true'`; `dismissFirstApprovalBanner()` writes that key. This is a per-viewer convenience, which is the one thing browser storage is used for on this portal — no domain state lives there.

---

<a id="screen-5-product-listings"></a>
## Screen 5 — Product Listings

**Route:** `/seller/listings`  
**Auth:** SELLER + APPROVED

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — My Listings
  button mat-flat-button color="primary" routerLink="/seller/listings/new" [disabled]="isSuspended"
    mat-icon — add
    span — Create Listing

<aliceut-data-table [dataSource]="listings" [loading]="loading" emptyMessage="No listings yet. Create your first product to get started.">

  <!-- Table actions slot -->
  ng-template [table-actions]
    mat-form-field [appearance=outline; subscriptSizing=dynamic]
      mat-label — Status
      mat-select [formControl]="statusFilter"
        mat-option value="" — All statuses
        mat-option value="ACTIVE" — Active
        mat-option value="FLAGGED" — Flagged
        mat-option value="REMOVED" — Removed

  ng-container matColumnDef="select"
    th mat-header-cell
      mat-checkbox [formControl]="selectAllControl" aria-label="Select all listings on this page"
    td mat-cell
      mat-checkbox [checked]="selection.isSelected(row)" (change)="selection.toggle(row)"
        [aria-label]="'Select ' + row.title"

  ng-container matColumnDef="image"
    th mat-header-cell — Image
    td mat-cell
      img [src]="imageUrl(row.primaryImage)" alt="" [width="48px" height="48px" border-radius="4px" object-fit="cover"]

  ng-container matColumnDef="title" [sticky]
    th mat-header-cell mat-sort-header — Title
    td mat-cell — {{ row.title }}

  ng-container matColumnDef="category"
    th mat-header-cell — Category
    td mat-cell — {{ row.category }}

  ng-container matColumnDef="status"
    th mat-header-cell — Status
    td mat-cell
      <aliceut-status-badge [status]="row.status" [statusType]="'listing'">
      div *ngIf="row.status === 'FLAGGED'" [margin-top: 4px]
        p mat-caption color="warn" — {{ row.flagReason }}
      div *ngIf="row.status === 'REMOVED'" [margin-top: 4px]
        p mat-caption color="warn" — Removed by admin: {{ row.removalReason }}

  ng-container matColumnDef="price"
    th mat-header-cell — Prices
    td mat-cell
      div *ngFor="let price of row.prices; trackBy: trackByPriceType"
        <aliceut-price-display [amount]="price.amount" [currency]="row.nativeCurrencyCode" [priceType]="price.priceType">

  ng-container matColumnDef="inventory"
    th mat-header-cell — Available Stock
    td mat-cell
      span [color]="row.availableStock <= 5 ? 'warn' : 'default'" — {{ row.availableStock }}
      mat-icon *ngIf="row.availableStock <= 5 && row.availableStock > 0" [matTooltip]="'Low stock'" color="warn" [font-size: 14px] — warning_amber
      span *ngIf="row.availableStock === 0" color="warn" — Out of stock

  ng-container matColumnDef="actions"
    th mat-header-cell — —
    td mat-cell
      button mat-icon-button [matMenuTriggerFor]="rowMenu" [matMenuTriggerData]="{row: row}"
        mat-icon — more_vert
  mat-menu #rowMenu
    ng-template matMenuContent let-row="row"
      button mat-menu-item [routerLink]="['/seller/listings', row.offerId, 'edit']" [disabled]="row.status === 'REMOVED'"
        mat-icon — edit
        span — Edit Listing
      button mat-menu-item [routerLink]="['/seller/listings', row.offerId, 'pricing']"
        mat-icon — currency_exchange
        span — Manage Pricing
      mat-divider
      button mat-menu-item (click)="deleteListing(row)" color="warn" [disabled]="row.hasPendingOrders"
        mat-icon color="warn" — delete_outline
        span — Delete Listing

  [rowDef for all columns]
</aliceut-data-table>
```

### Data source

`GET /seller/offers?status=&caseStatus=&limit=&cursor=` — one row is one **offer**, and the status filter above is `offer_status` (`ACTIVE | INACTIVE | REMOVED | FLAGGED`; there is no `DRAFT`, because a listing goes live on submit). The same endpoint also accepts `caseStatus` (`OPEN | RESOLVED | DISMISSED`) for filtering on the offer's own moderation cases. Paging is the `DataTable` Previous/Next footer over the cursor stack ([shared-components.md § 4.6](shared-components.md#46-datatable)).

---

<a id="screen-6-create-edit-product"></a>
## Screen 6 — Create / Edit Product

**Route:** `/seller/listings/new` and `/seller/listings/:offerId/edit`  
**Auth:** SELLER + APPROVED (and not suspended)

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/seller/listings" — arrow_back
  h1 mat-h4 — {{ isNew ? 'Create Listing' : 'Edit Listing' }}
  <aliceut-status-badge *ngIf="!isNew" [status]="listing.status" [statusType]="'listing'">

form [formGroup]="listingForm" (ngSubmit)="save()"

<!-- Section 1: Basic Info -->
mat-card [margin-bottom: 24px; padding: 24px]
  h2 mat-h5 [margin-bottom: 16px] — Basic Information
  mat-form-field [appearance=outline; fullWidth]
    mat-label — Product Title
    input matInput formControlName="title" maxlength="200"
    mat-hint align="end" — {{ title.value.length }}/200
    mat-error — Title must be 10–200 characters
  mat-form-field [appearance=outline; fullWidth]
    mat-label — Description (Markdown supported)
    textarea matInput formControlName="description" matTextareaAutosize [matAutosizeMinRows]="5" [matAutosizeMaxRows]="15"
    mat-hint align="end" — {{ description.value.length }}/5000
    mat-error — Description cannot exceed 5000 characters
  mat-form-field [appearance=outline; fullWidth]
    mat-label — Brand (optional)
    input matInput formControlName="brand"
  mat-form-field [appearance=outline; fullWidth]
    mat-label — Category
    mat-select formControlName="categoryId"
      mat-optgroup *ngFor="let group of categoryTree" [label]="group.name"
        mat-option *ngFor="let leaf of group.children" [value]="leaf.id" — {{ leaf.name }}
    mat-error *ngIf="categoryId.hasError('prohibited')" color="warn"
      mat-icon — block
      span — This category is prohibited. Weapons, drugs, and adult content are not permitted.

<!-- Section 2: Images -->
mat-card [margin-bottom: 24px; padding: 24px]
  h2 mat-h5 [margin-bottom: 8px] — Product Images
  p mat-body-2 color="secondary" [margin-bottom: 16px] — Upload 1–10 images. First image is the primary. Drag to reorder.
  <aliceut-file-upload [accept]="'image/jpeg,image/png,image/webp'" [maxSizeMb]="5" [multiple]="true" [maxFiles]="10"
    (filesChange)="onImagesChange($event)">
  <!-- Uploaded image thumbnails with drag-to-reorder -->
  div.image-preview-list [display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px]
    div.image-thumb *ngFor="let img of uploadedImages; let i = index; trackBy: trackByStorageKey"
      [draggable]="true" (dragstart)="onDragStart(i)" (drop)="onDrop(i)" (dragover)="$event.preventDefault()"
      [position: relative; cursor: grab]
      img [src]="img.previewUrl || img.url" [width="80px" height="80px" border-radius="4px" object-fit="cover"]
      mat-chip *ngIf="i === 0" [position: absolute; top: 4px; left: 4px; font-size: 10px] color="primary" — Primary
      button mat-icon-button [position: absolute; top: 0; right: 0; background: rgba(0,0,0,0.5)] (click)="removeImage(i)"
        mat-icon [color=white] — close
      mat-icon.drag-handle [position: absolute; bottom: 0; left: 50%; transform: translateX(-50%); color: white] — drag_handle
  mat-error *ngIf="imageError" — {{ imageError }}

<!-- Section 3: Variants (optional) -->
mat-card [margin-bottom: 24px; padding: 24px]
  h2 mat-h5 [margin-bottom: 8px] — Variants (Optional)
  p mat-body-2 color="secondary" [margin-bottom: 16px] — Add variants if your product comes in different sizes, colors, etc.
  mat-accordion
    mat-expansion-panel *ngFor="let group of variantGroups; let gi = index; trackBy: trackByIndex" [formArrayName]="'variantGroups'"
      mat-expansion-panel-header
        mat-panel-title — {{ group.controls.name.value || 'Variant Group ' + (gi+1) }}
        mat-panel-description — {{ group.controls.options.value.length }} option(s)
      form [formGroupName]="gi"
        mat-form-field [appearance=outline; fullWidth] — mat-label "Variant Name (e.g. Size, Color)" — formControlName="name"
        mat-chip-grid formControlName="options" aria-label="Options"
          mat-chip-row *ngFor="let opt of group.controls.options.value" [removable]="true" (removed)="removeOption(gi, opt)"
            {{ opt.value }}
          input [matChipInputFor]="chipList" (matChipInputTokenEnd)="addOption(gi, $event)">
        button mat-button color="warn" (click)="removeVariantGroup(gi)" — Remove group
  button mat-stroked-button (click)="addVariantGroup()" [margin-top: 8px]
    mat-icon — add
    span — Add Variant Group

<!-- Section 4: Offer Pricing -->
mat-card [margin-bottom: 24px; padding: 24px]
  h2 mat-h5 [margin-bottom: 8px] — Pricing
  p mat-body-2 color="secondary" [margin-bottom: 16px] — Set the offer price. Currency is the offer's native currency — to sell in a second currency, create a separate offer. At least one LIST price is required.
  mat-card.info-banner *ngIf="listing?.hasPendingOrders && listingForm.dirty" [margin-bottom: 12px]
    mat-icon — info_outline
    span — Price changes do not affect orders that have already been placed.

  mat-form-field [appearance=outline; min-width: 160px; margin-bottom: 16px]
    mat-label — Currency
    mat-select formControlName="nativeCurrencyCode" [disabled]="!isNew"
      mat-option value="USD" — USD
      mat-option value="THB" — THB
      mat-option value="JPY" — JPY
      mat-option value="SGD" — SGD
    mat-hint *ngIf="isNew" — Currency cannot be changed after the offer is created.
    mat-hint *ngIf="!isNew" color="primary" — Currency is fixed at offer creation. To sell in another currency, create a separate offer.

  div [formArrayName]="'prices'"]
    div.price-row *ngFor="let priceGroup of pricesArray.controls; let pi = index" [formGroupName]="pi"
      mat-card [padding: 16px; margin-bottom: 12px; background: surface]
        div [display: flex; gap: 16px; align-items: flex-start; flex-wrap: wrap]
          mat-form-field [appearance=outline; min-width: 120px]
            mat-label — Type
            mat-select formControlName="priceType"
              mat-option value="LIST" — LIST (Regular)
              mat-option value="SALE" — SALE (Discount)
          <!-- Currency comes from the select above, not from the loaded entity: `listing` is
               null on a new listing, which is exactly when that select is enabled. -->
          <aliceut-currency-input [currencyCode]="listingForm.get('nativeCurrencyCode')?.value" formControlName="amount" [required]="true">
          <!-- SALE fields -->
          ng-container *ngIf="priceGroup.value.priceType === 'SALE'"
            mat-form-field [appearance=outline]
              mat-label — Sale Start
              input matInput [matDatepicker]="saleStart" formControlName="startsAt"
              mat-datepicker-toggle matSuffix [for]="saleStart"
              mat-datepicker #saleStart
            mat-form-field [appearance=outline]
              mat-label — Sale End
              input matInput [matDatepicker]="saleEnd" formControlName="endsAt"
              mat-datepicker-toggle matSuffix [for]="saleEnd"
              mat-datepicker #saleEnd
          button mat-icon-button color="warn" (click)="removePrice(pi)" *ngIf="priceGroup.value.priceType !== 'LIST'"
            mat-icon — delete_outline
        mat-error *ngIf="priceGroup.errors?.['duplicate']" — A LIST price already exists for this offer. Edit or delete it before creating a new one.
        mat-error *ngIf="priceGroup.errors?.['saleRange']" — Sale start must be before sale end.

  button mat-stroked-button (click)="addPrice()" [margin-top: 8px]
    mat-icon — add
    span — Add Price Row

<!-- Section 5: Inventory (per SKU) -->
mat-card [margin-bottom: 24px; padding: 24px]
  h2 mat-h5 [margin-bottom: 16px] — Inventory
  p mat-body-2 color="secondary" [margin-bottom: 16px] — Set initial stock per SKU. SKUs are auto-generated from variant combinations.
  <!-- One FormGroup per SKU inside a 'skus' FormArray — reactive forms only, no ngModel -->
  mat-table [dataSource]="skuRows" [formArrayName]="'skus'"
    ng-container matColumnDef="sku"
      th mat-header-cell — SKU
      td mat-cell — {{ row.value.sku }}
    ng-container matColumnDef="variantLabel"
      th mat-header-cell — Variant
      td mat-cell — {{ row.value.label }}
    ng-container matColumnDef="onHand"
      th mat-header-cell — On Hand
      td mat-cell [formGroupName]="rowIndex"
        mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 100px]
          mat-label — On hand
          input matInput type="number" min="0" formControlName="onHand"
    ng-container matColumnDef="threshold"
      th mat-header-cell — Low-Stock Alert At
      td mat-cell [formGroupName]="rowIndex"
        mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 100px]
          mat-label — Alert at
          input matInput type="number" min="0" formControlName="lowStockThreshold"
          mat-hint — Default: 5
    [rowDef]

<!-- Save actions -->
div.form-actions [display: flex; justify-content: flex-end; gap: 12px; padding: 16px 0]
  button mat-button routerLink="/seller/listings" — Cancel
  button mat-flat-button color="primary" [disabled]="listingForm.invalid || isSaving || hasUploadsPending" type="submit"
    mat-spinner *ngIf="isSaving" [diameter]="20"
    span *ngIf="!isSaving" — {{ isNew ? 'Create Listing' : 'Save Changes' }}
  mat-hint *ngIf="hasUploadsPending" — Please wait — images are uploading…
```

### Prohibited-content outcomes on save

The listing-time scan reads the chosen taxonomy node plus the title and description, and produces **two distinct outcomes**. The tier comes from the **stored `enforcement` of the blocklist term that matched** — `BLOCK` or `FLAG` — not from how precisely the text matched; `match_type` (`SUBSTRING` / `WORD` / `REGEX`) is an independent column and every matching mode exists on both tiers. The strictest matched tier wins (FR-P-06c, [BRD § Amendments](../requirements/BRD.md#amendments); [diagram 04](../diagrams/04-admin-moderation.md)).

| Outcome | Trigger | What the seller sees |
|---|---|---|
| **Hard tier — rejected at submit** | A prohibited taxonomy node, or a matched term whose `enforcement` is `BLOCK` | `422`. **No listing is created and no edit is persisted.** The form stays where it is with its values intact, and a page-level `mat-card.error-banner` above the actions names what was rejected: "This listing cannot be published. Weapons, drugs and adult content are not permitted." A prohibited category additionally sets the `prohibited` error on the category field. Nothing appears in My Listings. |
| **Soft tier — created and held** | A matched term whose `enforcement` is `FLAG` | `201` / `200`. The listing **is** created or saved, with `offer_status = FLAGGED`, hidden from search, and an `admin.moderation_case` row is opened — this is the moderation queue's only input (FR-A-03). A `MatSnackBar` says "Your listing was saved and flagged for review — it will not be visible to buyers until an admin clears it.", and the row shows the `FLAGGED` badge with its flag reason. |

The two must not be collapsed into one message: a `422` leaves the seller with nothing to find in My Listings, and telling them it was "flagged for review" would send them looking for a row that does not exist.

### API flow — create a new listing

1. `POST /seller/products` with the product fields (title, description, category, images, variants) → returns `productId`.
2. `POST /seller/offers` with that `productId` plus `nativeCurrencyCode` and the price rows.

The hard tier can reject either call. If step 2 fails the page shows "Your product was saved but pricing could not be set — please try again from the Listings page." and retains the `productId` from step 1, so a retry does not duplicate the product. Editing an existing listing is `PATCH /seller/products/:productId` against the product the loaded offer points at; the route carries the offer id only and the component resolves the product id from it ([navigation-routing.md § 3](navigation-routing.md#seller-app-route-tree)).

---

<a id="screen-7-order-queue"></a>
## Screen 7 — Order Queue

**Route:** `/seller/orders`  
**Auth:** SELLER (partial access when SUSPENDED — Pending tab only)

### Layout

```
h1 mat-h4 — Orders

mat-tab-group [formControl]="activeTab"
  mat-tab label="Pending ({{ counts.pending }})"
  mat-tab label="Shipped"
  mat-tab label="Delivered"
  mat-tab label="Refunded"
  mat-tab label="Cancelled"

<!-- Filter row -->
div [display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 16px; align-items: flex-end]
  mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 260px]
    mat-label — Search by order ID
    input matInput [formControl]="searchCtrl"
    mat-icon matPrefix — search
  mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 200px]
    mat-label — Date from
    input matInput [matDatepicker]="fromDate" [formControl]="fromDateCtrl"
    mat-datepicker-toggle matSuffix [for]="fromDate"
    mat-datepicker #fromDate
  mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 200px]
    mat-label — Date to
    input matInput [matDatepicker]="toDate" [formControl]="toDateCtrl"
    mat-datepicker-toggle matSuffix [for]="toDate"
    mat-datepicker #toDate

<aliceut-data-table [dataSource]="fulfillments" [loading]="loading" [emptyMessage]="tabEmptyMessage"
  [hasMore]="hasMore" [hasPrevious]="hasPrevious"
  (nextPage)="next()" (previousPage)="previous()" (sortChange)="onSort($event)">
  ng-container matColumnDef="displayId"
    th mat-header-cell scope="col" — Fulfillment
    td mat-cell
      div — {{ row.displayId }}                      ← FUL-000003871
      p mat-caption color="secondary" — Order {{ row.orderDisplayId }}
  ng-container matColumnDef="placedAt"
    th mat-header-cell scope="col" mat-sort-header — Date
    td mat-cell — {{ row.placedAt | date:'mediumDate' }}
  ng-container matColumnDef="buyer"
    th mat-header-cell scope="col" — Buyer
    td mat-cell — {{ row.buyerNameMasked }}   ← e.g. "J. Doe"
  ng-container matColumnDef="itemCount"
    th mat-header-cell scope="col" — Items
    td mat-cell — {{ row.itemCount }}
  ng-container matColumnDef="total"
    th mat-header-cell scope="col" — Total
    td mat-cell
      <aliceut-price-display [amount]="row.totalAmount" [currency]="row.currencyCode" [priceType]="'LIST'">
      p mat-caption color="secondary" *ngIf="row.currencyCode !== row.buyerDisplayCurrency"
        — Buyer paid {{ row.buyerCurrencyTotal | currencyDisplay:row.buyerDisplayCurrency }}
  ng-container matColumnDef="status"
    th mat-header-cell scope="col" — Status
    td mat-cell
      <aliceut-status-badge [status]="row.status" [statusType]="'fulfillment'">
      mat-chip *ngIf="row.hasRemovedListing" [color=warn; font-size: 10px] — Listing removed
  ng-container matColumnDef="actions"
    th mat-header-cell scope="col" — <span class="cdk-visually-hidden">Actions</span>
    td mat-cell
      button mat-flat-button color="primary" [routerLink]="['/seller/orders', row.id]" — View
      button mat-flat-button color="accent" (click)="markShipped(row)" *ngIf="row.status === 'PENDING'" — Mark Shipped
```

### Data source

`GET /seller/orders?status=&placedFrom=&placedTo=&q=&limit=&cursor=`, default sort `placed_at DESC`. Every column above is a field of the list row: `id`, `displayId`, `orderDisplayId`, `status`, `placedAt`, `buyerNameMasked`, `itemCount`, `hasRemovedListing`, `totalAmount`, `currencyCode`, `buyerCurrencyTotal`, `buyerDisplayCurrency`.

The active tab **is** the `status` filter, encoded as `?status=PENDING` so a refresh restores it; there is no separate `tab` parameter duplicating the same fact ([navigation-routing.md § 6.2](navigation-routing.md#navigation-patterns)). Switching tabs discards the cursor stack. The search box maps to `q`, a display-id search, and the two date pickers to `placedFrom` / `placedTo`.

The seller's own amounts are the captured native figures (`totalAmount` in `currencyCode`); `buyerCurrencyTotal` is shown as a secondary caption only where the two differ. Neither is re-derived and neither is summed in the client.

**Empty states per tab (US-S-05):**
- Pending → "No pending orders — new orders appear here."
- Shipped / Delivered / Refunded / Cancelled → "No orders in this status."

---

<a id="screen-8-order-detail"></a>
## Screen 8 — Fulfillment Detail

**Route:** `/seller/orders/:fulfillmentId`  
**Auth:** SELLER (owns this fulfillment; suspended sellers keep the read and the ship action)

This screen is one **fulfillment** — `f` below. Its heading carries the `FUL-` id, with the buyer's `ORD-` id beside it so the seller can quote what the buyer sees.

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/seller/orders" aria-label="Back to orders" — arrow_back
  h1 mat-h4 — Fulfillment {{ f.displayId }}
  span mat-body-2 color="secondary" — Order {{ f.orderDisplayId }}
  <aliceut-status-badge [status]="f.status" [statusType]="'fulfillment'">

div.detail-grid [display: grid; grid-template-columns: 1fr 340px; gap: 24px]
  <!-- Left: Items -->
  div
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Items
      mat-list
        mat-list-item *ngFor="let item of f.items; trackBy: trackByOfferId"
          img matListItemAvatar [src]="imageUrl(item.primaryImage)" alt=""
          span mat-list-item-title — {{ item.productTitle }}
          span mat-list-item-line — {{ item.variantLabel }} · Qty: {{ item.quantity }}
          span mat-list-item-line — Unit price (snapshotted at checkout):
          <aliceut-price-display mat-list-item-line [amount]="item.unitPrice" [currency]="f.currencyCode" [priceType]="'LIST'">
          <aliceut-price-display matListItemMeta [amount]="item.lineTotal" [currency]="f.currencyCode" [priceType]="'LIST'">
      mat-divider [margin: 12px 0]
      div [display: flex; justify-content: flex-end]
        span mat-h6 — Total:
        <aliceut-price-display [amount]="f.totalAmount" [currency]="f.currencyCode" [priceType]="'LIST'">

    mat-card [padding: 24px] *ngIf="f.trackingNumber"
      h2 mat-h6 — Tracking
      p mat-body-2 — Tracking number: <strong>{{ f.trackingNumber }}</strong>
      p mat-body-2 — Estimated delivery: {{ f.estimatedDeliveryAt | date:'mediumDate' }}
      p mat-caption color="secondary" — Assigned when the fulfillment was created, not at shipment — it does not change when you mark this shipped.

  <!-- Right: Buyer Info + Actions -->
  aside
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Shipping Address
      mat-icon [color=secondary; margin-bottom: 8px] — lock
      p mat-caption color="secondary" [margin-bottom: 8px] — Address visible for fulfillment purposes. Access is logged.
      address [font-style: normal; line-height: 1.8]
        strong — {{ f.shippingAddress.fullName }}
        br
        {{ f.shippingAddress.addressLine1 }}
        br
        {{ f.shippingAddress.addressLine2 }}
        br *ngIf="f.shippingAddress.addressLine2"
        {{ f.shippingAddress.city }}, {{ f.shippingAddress.stateProvince }} {{ f.shippingAddress.postalCode }}
        br
        {{ countryName(f.shippingAddress.countryCode) }}
      p mat-caption color="secondary" — This is the address as it was at checkout.

    mat-card [padding: 24px]
      h2 mat-h6 [margin-bottom: 16px] — Actions

      <!-- Mark Shipped -->
      div *ngIf="f.status === 'PENDING'" [margin-bottom: 12px]
        p mat-body-2 [margin-bottom: 8px] — Mark this fulfillment as shipped once dispatched.
        p mat-caption color="secondary" [margin-bottom: 8px] — Tracking number {{ f.trackingNumber }} will be sent to the buyer.
        button mat-flat-button color="primary" [fullWidth] (click)="markShipped()" [disabled]="isActing"
          mat-icon — local_shipping
          span — Mark as Shipped

      <!-- Issue Refund / Cancel -->
      div *ngIf="f.status === 'PENDING' || f.status === 'SHIPPED'" [margin-top: 12px]
        button mat-stroked-button color="warn" [fullWidth] (click)="openRefundDialog()" [disabled]="isActing || isSuspended"
          mat-icon — currency_exchange
          span — Issue Refund
        button mat-stroked-button color="warn" [fullWidth; margin-top: 8px] (click)="openCancelDialog()"
                *ngIf="f.status === 'PENDING'" [disabled]="isActing || isSuspended"
          mat-icon — cancel
          span — Cancel Fulfillment

      <!-- Terminal state messages -->
      div *ngIf="['DELIVERED','REFUNDED','CANCELLED'].includes(f.status)"
        mat-icon [color]="terminalIconColor" — {{ terminalIcon }}
        p mat-body-2 — {{ terminalMessage }}
```

### Actions and their endpoints

All three confirm through `ConfirmDialog` ([shared-components.md § 4.7](shared-components.md#47-confirmdialog)); the refund and cancel reasons come back on the dialog result and are sent to the API.

| Action | Call | Dialog |
|---|---|---|
| Mark as Shipped | `POST /seller/orders/:fulfillmentId/ship` — SELLER, **survives suspension** | "Confirm shipment. Tracking number {{ f.trackingNumber }} will be shared with the buyer." No reason required |
| Issue Refund | `POST /seller/orders/:fulfillmentId/refund` — `SELLER_ACTIVE` | `requireReason: true`, `danger: true`. "Refund this fulfillment? This cannot be undone." Valid from `PENDING` and `SHIPPED`; a `PENDING` refund restores stock and a `SHIPPED` one does not, so the message names which case applies (US-S-07) |
| Cancel Fulfillment | `POST /seller/orders/:fulfillmentId/cancel` — `SELLER_ACTIVE` | `requireReason: true`, `danger: true`. Valid from `PENDING` only; restores stock (US-S-11) |

Refund and cancel are `SELLER_ACTIVE`, so both buttons are disabled for a suspended seller while Mark as Shipped stays live — the obligation to dispatch a fulfillment placed before the suspension survives it ([navigation-routing.md § 5](navigation-routing.md#auth-guard-matrix)). Stock restoration is written by the inventory consumer from the event, never by this screen ([diagram 03](../diagrams/03-fulfillment-lifecycle.md)).

---

<a id="screen-9-inventory"></a>
## Screen 9 — Inventory

**Route:** `/seller/inventory`  
**Auth:** SELLER + APPROVED

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — Inventory
  button mat-stroked-button (click)="openCsvImport()" *ngIf="!isSuspended"
    mat-icon — upload_file
    span — Import CSV

<!-- Low stock banner -->
mat-card.warning-banner *ngIf="lowStockCount > 0" [margin-bottom: 16px]
  mat-icon color="warn" — warning_amber
  span — {{ lowStockCount }} SKU(s) are below their low-stock threshold.

<aliceut-data-table [dataSource]="inventory" [loading]="loading" emptyMessage="No inventory records found.">
  ng-container matColumnDef="sku"
    th mat-header-cell — SKU
    td mat-cell — {{ row.sku }}
  ng-container matColumnDef="variant"
    th mat-header-cell — Variant
    td mat-cell — {{ row.variantLabel }}
  ng-container matColumnDef="product"
    th mat-header-cell — Product
    td mat-cell — {{ row.productTitle | truncate:40 }}
  ng-container matColumnDef="onHand"
    th mat-header-cell — On Hand
    td mat-cell
      <!-- Inline edit is a FormControl held by the page component, keyed by offerId — never ngModel -->
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 80px] *ngIf="editingOnHand === row.offerId"
        mat-label — On hand
        input matInput type="number" min="0" [formControl]="onHandCtrl" (blur)="saveQty(row)"
      button mat-button *ngIf="editingOnHand !== row.offerId" (click)="startEditOnHand(row)"
             [attr.aria-label]="'Edit on-hand quantity for ' + row.sku"
        span — {{ row.onHand }}
        mat-icon [font-size: 14px; vertical-align: middle] — edit
  ng-container matColumnDef="reserved"
    th mat-header-cell [matTooltip]="'Units held by PENDING orders'"] — Reserved
    td mat-cell — {{ row.reserved }}
  ng-container matColumnDef="available"
    th mat-header-cell — Available
    td mat-cell
      span [color]="row.available <= row.lowStockThreshold ? 'warn' : 'default'" — {{ row.available }}
      mat-icon *ngIf="row.available <= row.lowStockThreshold && row.available > 0" color="warn" [font-size: 14px] [matTooltip]="'Low stock'" — warning_amber
      mat-chip *ngIf="row.available === 0" color="warn" [font-size: 10px] — Out of stock
  ng-container matColumnDef="threshold"
    th mat-header-cell — Alert Threshold
    td mat-cell
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 80px] *ngIf="editingThreshold === row.offerId"
        mat-label — Alert at
        input matInput type="number" min="0" [formControl]="thresholdCtrl" (blur)="saveThreshold(row)"
      button mat-button *ngIf="editingThreshold !== row.offerId" (click)="startEditThreshold(row)"
             [attr.aria-label]="'Edit low-stock threshold for ' + row.sku"
        span — {{ row.lowStockThreshold }}
        mat-icon [font-size: 14px] — edit
```

### Data source and writes

There is **no `GET /seller/inventory` endpoint.** The table reads `GET /seller/offers`, whose row carries the stock join — `onHand`, `reserved`, `available` and `lowStockThreshold` — alongside the offer. Each inline save is `PATCH /seller/inventory/:offerId { onHandQty?, lowStockThreshold? }`, and the CSV import is `POST /seller/inventory/bulk` ([seller.md § Endpoint Index](../technical-design/api-design/seller.md#endpoint-index)). Both writes are `SELLER_ACTIVE`, which is why the route carries `sellerApprovedGuard` and `sellerNotSuspendedGuard`.

`reserved` is units held by `PENDING` fulfillments and is never editable here: it is released by the refund, cancel and ship paths, each of which is written by the inventory consumer from the event rather than by this screen.

### CSV Import Dialog

`MatDialog` containing:

```
mat-dialog-title — Bulk Inventory Update
mat-dialog-content
  p mat-body-2 — Upload a CSV with columns: sku, on_hand, low_stock_threshold (optional)
  a mat-button href="/assets/inventory-template.csv" download — Download template
  <aliceut-file-upload [accept]="'.csv'" [maxSizeMb]="5" [multiple]="false" [maxFiles]="1" (filesChange)="csvFile = $event[0]">

  <!-- After file parse: preview diff table -->
  div *ngIf="previewRows.length > 0" [margin-top: 16px]
    p mat-body-2 — Preview: {{ previewRows.length }} rows
    mat-table [dataSource]="previewRows"
      [sku, variant, currentOnHand → newOnHand, status columns]
      [Rows with errors in red, warnings in orange, valid in green]

    mat-card.warning-banner *ngIf="warningRows.length > 0"
      mat-icon — warning_amber
      span — {{ warningRows.length }} row(s) would result in negative available stock. Confirm to proceed anyway — existing PENDING orders will not be cancelled.
    mat-card.error-banner *ngIf="errorRows.length > 0"
      mat-icon — error_outline
      span — {{ errorRows.length }} row(s) have errors (invalid SKU or not yours) and will be skipped.

mat-dialog-actions [align=end]
  button mat-button mat-dialog-close — Cancel
  button mat-flat-button color="primary" [disabled]="!csvFile || hasParseErrors || isConfirming" (click)="confirmImport()"
    mat-spinner *ngIf="isConfirming" [diameter]="20"
    span *ngIf="!isConfirming" — Confirm Update
```

---

<a id="screen-10-offer-pricing"></a>
## Screen 10 — Offer Pricing

**Route:** `/seller/listings/:offerId/pricing`  
**Auth:** SELLER + APPROVED + Not Suspended (`KycApprovedGuard + SellerActiveGuard`)

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/seller/listings" aria-label="Back to listings" — arrow_back
  h1 mat-h4 — Manage Pricing — {{ productTitle }}

<!-- Offer currency (read-only) -->
p mat-body-2 color="secondary" [margin-bottom: 16px] — Currency: <strong>{{ offer.nativeCurrencyCode }}</strong> (fixed at offer creation — to sell in a second currency, create a separate offer)

<!-- Current price rows table -->
<aliceut-data-table [dataSource]="prices" [loading]="loading" emptyMessage="No prices set yet. Add a LIST price to make this offer visible to buyers.">
  ng-container matColumnDef="priceType"
    th mat-header-cell — Price Type
    td mat-cell
      mat-chip [color]="row.priceType === 'LIST' ? 'primary' : 'default'" — {{ row.priceType }}
  ng-container matColumnDef="amount"
    th mat-header-cell — Amount
    td mat-cell
      <aliceut-price-display [amount]="row.amount" [currency]="offer.nativeCurrencyCode" [priceType]="row.priceType">
  ng-container matColumnDef="startsAt"
    th mat-header-cell — Valid From
    td mat-cell — {{ row.startsAt ? (row.startsAt | date:'mediumDate') : '—' }}
  ng-container matColumnDef="endsAt"
    th mat-header-cell — Valid Until
    td mat-cell — {{ row.endsAt ? (row.endsAt | date:'mediumDate') : '—' }}
  ng-container matColumnDef="actions"
    th mat-header-cell — —
    td mat-cell
      button mat-icon-button (click)="editPrice(row)" [matTooltip]="'Edit'"
        mat-icon — edit
      button mat-icon-button color="warn" (click)="deletePrice(row)" [matTooltip]="'Delete'"
        mat-icon — delete_outline
  [rowDef for all columns]
</aliceut-data-table>

<!-- Pending orders warning -->
mat-card.warning-banner *ngIf="offer.hasPendingOrders" [margin-bottom: 16px]
  mat-icon color="warn" — info_outline
  span — Price changes do not affect orders that have already been placed.

<!-- Add Price button -->
button mat-flat-button color="primary" (click)="openAddPriceForm()" [margin-top: 16px]
  mat-icon — add
  span — Add Price

<!-- Add / Edit Price inline form (shown when addingPrice or editingPrice) -->
mat-card *ngIf="showPriceForm" [padding: 24px; margin-top: 16px]
  h2 mat-h6 [margin-bottom: 16px] — {{ editingPrice ? 'Edit Price' : 'Add Price' }}
  form [formGroup]="priceForm" (ngSubmit)="savePrice()"
    div [display: flex; gap: 16px; flex-wrap: wrap; align-items: flex-start]
      mat-form-field [appearance=outline; min-width: 140px]
        mat-label — Price Type
        mat-select formControlName="priceType"
          mat-option value="LIST" — LIST
          mat-option value="SALE" — SALE
      <aliceut-currency-input [currencyCode]="offer.nativeCurrencyCode" formControlName="amount" [required]="true">
        mat-error *ngIf="priceForm.get('amount')?.hasError('pattern')" — Amount must be a valid number
      <!-- SALE fields (shown when priceType === 'SALE') -->
      ng-container *ngIf="priceForm.get('priceType')?.value === 'SALE'"
        mat-form-field [appearance=outline]
          mat-label — Valid From
          input matInput [matDatepicker]="startsAtPicker" formControlName="startsAt"
          mat-datepicker-toggle matSuffix [for]="startsAtPicker"
          mat-datepicker #startsAtPicker
        mat-form-field [appearance=outline]
          mat-label — Valid Until
          input matInput [matDatepicker]="endsAtPicker" formControlName="endsAt"
          mat-datepicker-toggle matSuffix [for]="endsAtPicker"
          mat-datepicker #endsAtPicker

    mat-error *ngIf="priceForm.errors?.['duplicate']" [margin-top: 8px] — A LIST price already exists for this offer. Edit or delete it before creating a new one.
    mat-error *ngIf="priceForm.errors?.['saleRange']" [margin-top: 8px] — Valid From must be before Valid Until.

    div [display: flex; gap: 8px; justify-content: flex-end; margin-top: 16px]
      button mat-button type="button" (click)="cancelPriceForm()" — Cancel
      button mat-flat-button color="primary" type="submit" [disabled]="priceForm.invalid || isSaving"
        mat-spinner *ngIf="isSaving" [diameter]="20"
        span *ngIf="!isSaving" — Save
```

---

<a id="screen-11-seller-forgot-password"></a>
## Screen 11 — Seller Forgot Password

**Route:** `/seller/forgot-password`  
**Auth:** Public (no authentication required)

### Layout

The card shell, the email field, the error banner and the submit button are [shared-components.md § 8.1–8.3](shared-components.md#8-auth-screen-pattern). Portal mark `mat-icon lock_reset`, title "Forgot your password?", subtitle "Enter your email and we'll send a reset link.", submit label "Send Reset Link". What this screen adds:

```
mat-card-content
  <!-- Default state: form -->
  ng-container *ngIf="!submitted"
    [shared form: email + error banner + "Send Reset Link" submit]
    p mat-body-2 [text-align: center; margin-top: 16px]
      a mat-button routerLink="/seller/login" — Back to Sign In

  <!-- Success state: terminal for the page -->
  ng-container *ngIf="submitted"
    div [text-align: center; padding: 16px 0]
      mat-icon [font-size: 48px; color: success] — mark_email_read
      h3 mat-h5 [margin-top: 16px] — Check your email
      p mat-body-2 [margin-top: 8px] — If an account with that email exists, we sent a reset link. Check your inbox.
      p mat-caption [margin-top: 8px] color="secondary" — Not in your inbox? Check your spam folder.
      p mat-body-2 [margin-top: 16px]
        a mat-button routerLink="/seller/login" — Back to Sign In
```

`POST /auth/forgot-password` with `{ email, portal: "SELLER" }`. The byte-identical `202`, the 3-per-hour-per-email rate limit and the **terminal** submitted state are the cross-portal rules in [shared-components.md § 8.5](shared-components.md#8-auth-screen-pattern): there is no resend control, because a second submission would answer identically and re-arming the form invites the reader to treat the first answer as a signal about whether the address exists.

---

<a id="screen-12-seller-reset-password"></a>
## Screen 12 — Seller Reset Password

**Route:** `/seller/reset-password?token=`  
**Auth:** Public; reads `?token=` query param on component init

### Layout

The card shell, the password and confirm-password fields with their `showPassword` / `showConfirmPassword` toggles, the hint and the submit button are [shared-components.md § 8.1–8.4](shared-components.md#8-auth-screen-pattern). Portal mark `mat-icon lock_reset`, title "Reset your password", submit label "Set New Password". Three states, switched on `tokenState`:

```
mat-card-content
  <!-- 'form' — shown optimistically on mount; there is no token pre-validation endpoint -->
  ng-container *ngIf="tokenState === 'form'"
    [shared form: password + confirm password + "Set New Password" submit]

  <!-- 'invalid' — after the submit returns 400 -->
  ng-container *ngIf="tokenState === 'invalid'"
    div [text-align: center; padding: 16px 0]
      mat-icon [font-size: 48px; color: warn] — link_off
      h3 mat-h5 [margin-top: 16px] — Reset link no longer valid
      p mat-body-2 [margin-top: 8px] — This link has expired, has already been used, or is not valid for this portal. Request a new one.
      button mat-flat-button color="primary" routerLink="/seller/forgot-password" [margin-top: 16px] — Request new link
      p mat-body-2 [margin-top: 16px]
        a mat-button routerLink="/seller/login" — Back to Sign In

  <!-- 'success' — redirect imminent -->
  ng-container *ngIf="tokenState === 'success'"
    div [text-align: center; padding: 16px 0]
      mat-icon [font-size: 48px; color: success] — check_circle_outline
      h3 mat-h5 [margin-top: 16px] — Password updated
      p mat-body-2 [margin-top: 8px] — Your password has been reset. Redirecting you to sign in…
```

`POST /auth/reset-password` with `{ token, newPassword, portal: "SELLER" }`. The optimistic form, the single `400` that covers expired, already-used **and wrong-portal** tokens without distinguishing them, the 5-attempts-per-token-per-hour limit and the revocation of every session on success are the cross-portal rules in [shared-components.md § 8.5](shared-components.md#8-auth-screen-pattern). There is no `mode` parameter on a seller link — that hint is buyer-only.

**On success:** redirect to `/seller/login?passwordReset=true`, where the login page shows a success banner: "Password reset successfully — please sign in with your new password."

---

<a id="screen-13-seller-notifications"></a>
## Screen 13 — Seller Notifications

**Route:** `/seller/notifications`  
**Guard:** *(shell only)* — `GET /notifications` is plain JWT, and an unapproved or suspended seller has notifications to read, the suspension notice among them ([navigation-routing.md § 5](navigation-routing.md#auth-guard-matrix))  
**Component:** `SellerNotificationsComponent`

### Layout, rendering and API calls

The layout, the client-side composition of each row's two lines, the cursor-paging rules, the API call table and the four states are the shared notifications pattern in [shared-components.md § 9](shared-components.md#9-notifications-page-pattern). This portal's specifics:

- Heading is `h1 mat-h4 — Notifications`; the header carries no filter control, only "Mark all as read".
- Paging is the **"Load more"** variant, ending in the "End of list" caption.
- `EmptyState` copy: `icon="notifications_none"`, `title="No notifications"`, `message="Order and listing alerts will appear here."`
- `titleFor(n)` / `bodyFor(n)` / `typeIcon(n.type)` resolve against the [appendix](#appendix-seller-notifications) table below.

---

<a id="appendix-seller-notifications"></a>
## Appendix — Seller Notification Types

The types a seller account receives, rendered by `<aliceut-notification-bell>` in the shell and by `/seller/notifications`. The API supplies `type` and an opaque `payload`; the icon and the message are composed client-side from this table, with each bracketed value taken from `payload` ([shared-components.md § 9.2](shared-components.md#9-notifications-page-pattern)).

| Type | Icon | Message pattern | Opens |
|---|---|---|---|
| `ORDER_PLACED` | `receipt_long` | "New order [FUL- display id] placed" | `/seller/orders/{fulfillmentId}` |
| `FULFILLMENT_CANCELLED` | `cancel` (warn) | "Fulfillment [FUL- display id] was cancelled" | `/seller/orders/{fulfillmentId}` |
| `LOW_STOCK` | `warning_amber` (warn) | "[SKU] is running low ([N] left)" | `/seller/inventory` |
| `LISTING_FLAGGED` | `flag` (warn) | "'[product title]' has been flagged for review" | `/seller/listings/{offerId}/edit` |
| `LISTING_REMOVED` | `block` (warn) | "'[product title]' was removed by an admin" | `/seller/listings` |
| `KYC_SUBMITTED` | `assignment` | "Your KYC application was received" | `/seller/kyc` |
| `KYC_DECIDED` | `check_circle_outline` (success) on `APPROVED`, `cancel` (warn) on `REJECTED` | "Your KYC application was [approved / rejected]" — the `payload` carries `decision: APPROVED \| REJECTED`, so one type drives both lines | `/seller/kyc` |
| `SELLER_SUSPENDED` | `block` (warn) | "Your account has been suspended" | `/seller/profile` |
| `SELLER_REINSTATED` | `lock_open` (success) | "Your account has been reinstated" | `/seller/profile` |
| `SUSPENSION_EXPIRED` | `lock_open` (success) | "Your suspension has ended and your listings are active again" | `/seller/profile` |

These are the seller-relevant canonical types in [notifications.md](../technical-design/api-design/notifications.md). `SUSPENSION_EXPIRED` exists as a notification **type** only; it is not a stored status and nothing passes it to a `StatusBadge` ([shared-components.md § 5](shared-components.md#5-status-vocabulary)).

---

*Last updated: 2026-09-24 (UI-design consolidation)*
