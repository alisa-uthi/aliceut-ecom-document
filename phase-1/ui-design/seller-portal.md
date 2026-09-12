# Seller Portal — UI Design Specification
## seller-app (port 4201)

**Status:** Draft  
**Stack:** Angular 22+ + Angular Material + `libs/ui/` shared components  
**Auth:** Email/password only (no OAuth). JWT with SELLER role.

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
- [Screen 8 — Order Detail](#screen-8-order-detail)
- [Screen 9 — Inventory](#screen-9-inventory)
- [Screen 10 — Notification Panel](#screen-10-notification-panel)
- [Screen 11 — Offer Pricing](#screen-11-offer-pricing)
- [Screen 12 — Seller Forgot Password](#screen-12-seller-forgot-password)
- [Screen 13 — Seller Reset Password](#screen-13-seller-reset-password)
- [Screen 14 — Seller Notifications](#screen-14-seller-notifications)

<a id="shell-layout"></a>
## Shell Layout

```
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
      <aliceut-notification-bell [notifications]="notifications" [unreadCount]="unreadCount">
      button mat-button [matMenuTriggerFor]="profileMenu"
        mat-icon — account_circle
        span — {{ sellerProfile.businessName || sellerName }}
      mat-menu #profileMenu
        button mat-menu-item routerLink="/seller/kyc" *ngIf="!isApproved" — assignment icon — KYC Application
        mat-divider
        button mat-menu-item (click)="logout()" — logout icon — Sign Out

    main.seller-content [padding: 24px]
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

**Sidebar navigation note:** During suspension, all nav items except "Orders" are visible but clicking them shows "Your account is suspended" instead of the normal view. [DESIGN DECISION: Show nav items greyed out rather than hidden to maintain orientation and avoid confusion.]

---

<a id="screen-1-seller-login"></a>
## Screen 1 — Seller Login

**Route:** `/seller/login`  
**Auth:** None (redirect to dashboard if authenticated)

```
div.auth-page [display: flex; justify-content: center; padding: 48px 16px]
  mat-card [width: 100%; max-width: 440px; padding: 32px]
    mat-card-header [text-align: center; margin-bottom: 24px]
      mat-icon [font-size: 48px; color: primary] — storefront
      mat-card-title — Seller Portal Sign In
      mat-card-subtitle — Manage your listings and orders
    mat-card-content
      form [formGroup]="loginForm" (ngSubmit)="login()"
        mat-form-field [appearance=outline; fullWidth; margin-bottom: 16px]
          mat-label — Email address
          input matInput type="email" formControlName="email" autocomplete="email"
          mat-error — {{ emailError }}
        mat-form-field [appearance=outline; fullWidth]
          mat-label — Password
          input matInput [type]="showPw ? 'text' : 'password'" formControlName="password"
          button mat-icon-button matSuffix type="button" (click)="showPw = !showPw"
            mat-icon — {{ showPw ? 'visibility_off' : 'visibility' }}
        div [text-align: right; margin: 4px 0 16px]
          a mat-button routerLink="/seller/forgot-password" — Forgot password?

        mat-card.error-banner *ngIf="loginError" [margin-bottom: 16px]
          mat-icon — error_outline
          span — {{ loginError }}

        button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="loginForm.invalid || isLoading"
          mat-spinner *ngIf="isLoading" [diameter]="20"
          span *ngIf="!isLoading" — Sign In

      p mat-body-2 [text-align: center; margin-top: 24px]
        span — New seller?
        a mat-button color="primary" routerLink="/seller/register" — Create seller account

      p mat-caption [text-align: center; margin-top: 8px]
        span — Looking for the buyer store?
        a mat-button routerLink="http://localhost:4200" — Visit AliceUT
```

**Note:** No Google/Facebook OAuth buttons on seller login per US-B-00.

---

<a id="screen-2-seller-register"></a>
## Screen 2 — Seller Register

**Route:** `/seller/register`

```
div.auth-page [display: flex; justify-content: center; padding: 48px 16px]
  mat-card [width: 100%; max-width: 480px; padding: 32px]
    mat-card-title — Create a Seller Account
    mat-card-subtitle — Sell on AliceUT. Reach global buyers.
    mat-card-content
      form [formGroup]="registerForm" (ngSubmit)="register()"
        h4 mat-h6 [margin-bottom: 16px] — Step 1: Account Details
        mat-form-field [appearance=outline; fullWidth] — mat-label "Full Name" — formControlName="fullName"
        mat-form-field [appearance=outline; fullWidth] — mat-label "Email address" — input type="email" formControlName="email"
          mat-hint — If this email already has a buyer account, you'll be asked to sign in to link roles.
        mat-form-field [appearance=outline; fullWidth] — mat-label "Password"
          input [type]="showPw ? 'text' : 'password'" formControlName="password"
          mat-hint — At least 8 characters, 1 letter, 1 number
        mat-form-field [appearance=outline; fullWidth] — mat-label "Confirm Password" — formControlName="confirmPassword"

        <!-- Existing account detected state -->
        mat-card.info-banner *ngIf="existingAccountDetected" [margin-bottom: 16px]
          mat-icon — info_outline
          span — This email already has an account. Sign in with your password to add the Seller role.
          mat-form-field [appearance=outline; fullWidth; margin-top: 12px] — mat-label "Your Password" — input type="password" formControlName="existingPassword"

        button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="registerForm.invalid || isLoading"
          mat-spinner *ngIf="isLoading" [diameter]="20"
          span *ngIf="!isLoading" — Create Account & Continue to KYC

      p mat-body-2 [text-align: center; margin-top: 16px]
        span — Already a seller?
        a mat-button routerLink="/seller/login" — Sign in
```

After successful registration, redirect to `/seller/kyc` to complete Step 2 (KYC application form).

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
    message="Your KYC application has been approved. You can create listings from your dashboard."
    [actionLabel]="'Go to Dashboard'"
    actionRoute="/seller/dashboard">
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
      <aliceut-file-upload [accept]="'application/pdf,image/*'" [maxSizeMb]="10" [multiple]="false"
        (filesChange)="businessLicenseFile = $event[0]">
      mat-error *ngIf="docsSubmitted && !businessLicenseFile" — Business license document is required.

    div.doc-section [margin-bottom: 24px]
      h4 mat-h6 — Government-Issued ID (Passport / National ID) *
      <aliceut-file-upload [accept]="'application/pdf,image/*'" [maxSizeMb]="10" [multiple]="false"
        (filesChange)="idDocFile = $event[0]">
      mat-error *ngIf="docsSubmitted && !idDocFile" — Identity document is required.

    div.doc-section [margin-bottom: 24px]
      h4 mat-h6 — Bank Statement or Proof of Address *
      <aliceut-file-upload [accept]="'application/pdf,image/*'" [maxSizeMb]="10" [multiple]="false"
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

  mat-card.stat-card [cursor: pointer] (click)="navigate('/seller/orders?tab=pending')"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: flex-start]
        div
          p mat-caption [margin-bottom: 4px] — Pending Orders
          p mat-headline-5 — {{ stats.pendingOrders }}
        mat-icon [font-size: 32px; color: amber] — receipt_long
    mat-card-footer [padding: 8px 16px; background: primary-50]
      span mat-caption — View all pending →

  mat-card.stat-card (click)="navigate('/seller/inventory?filter=lowstock')"
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

  mat-card.stat-card (click)="navigate('/seller/listings?status=FLAGGED')"
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
    mat-chip *ngFor="let sku of lowStockAlerts" [removable]="false" color="warn"
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
    mat-list-item *ngFor="let order of recentPendingOrders"
      mat-icon matListItemIcon — receipt_long
      span mat-list-item-title — {{ order.displayId }}
      span mat-list-item-line — {{ order.itemSummary }} · {{ order.placedAt | timeAgo }}
      <aliceut-status-badge matListItemMeta [status]="order.status" [statusType]="'fulfillment'">
      button mat-icon-button matListItemMeta [routerLink]="['/seller/orders', order.id]" — chevron_right
```

**First-approval banner note:** `showFirstApprovalBanner` is true when `kycStatus === 'APPROVED'` AND `localStorage.getItem('firstApprovalBannerDismissed') !== 'true'`. Dismissed state persisted in `localStorage`. Banner is not shown once dismissed — `dismissFirstApprovalBanner()` sets `localStorage.setItem('firstApprovalBannerDismissed', 'true')`.

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
    th mat-header-cell — <mat-checkbox (change)="toggleAllRows($event)">
    td mat-cell — <mat-checkbox [(ngModel)]="selection.isSelected(row)" (change)="toggleRow(row)">

  ng-container matColumnDef="image"
    th mat-header-cell — Image
    td mat-cell
      img [src]="row.primaryImageUrl" [alt]="" [width="48px" height="48px" border-radius="4px" object-fit="cover"]

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
      div *ngFor="let price of row.listPrices"
        <aliceut-price-display [amount]="price.amount" [currency]="price.currency">

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
      button mat-menu-item [routerLink]="['/seller/listings', row.id, 'edit']" [disabled]="row.status === 'REMOVED'"
        mat-icon — edit
        span — Edit Listing
      button mat-menu-item [routerLink]="['/seller/listings', row.id, 'pricing']"
        mat-icon — currency_exchange
        span — Manage Pricing
      mat-divider
      button mat-menu-item (click)="deleteListing(row)" color="warn" [disabled]="row.hasPendingOrders"
        mat-icon color="warn" — delete_outline
        span — Delete Listing

  [rowDef for all columns]
</aliceut-data-table>
```

---

<a id="screen-6-create-edit-product"></a>
## Screen 6 — Create / Edit Product

**Route:** `/seller/listings/new` and `/seller/listings/:id/edit`  
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
    div.image-thumb *ngFor="let img of uploadedImages; let i = index"
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
    mat-expansion-panel *ngFor="let group of variantGroups; let gi = index" [formArrayName]="'variantGroups'"
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
  p mat-body-2 color="secondary" [margin-bottom: 16px] — Set prices in one or more currencies. At least one LIST price is required.
  mat-card.info-banner *ngIf="listing?.hasPendingOrders && priceForm.dirty" [margin-bottom: 12px]
    mat-icon — info_outline
    span — Price changes do not affect orders that have already been placed.

  div [formArrayName]="'prices'"]
    div.price-row *ngFor="let priceGroup of pricesArray.controls; let pi = index" [formGroupName]="pi"
      mat-card [padding: 16px; margin-bottom: 12px; background: surface]
        div [display: flex; gap: 16px; align-items: flex-start; flex-wrap: wrap]
          mat-form-field [appearance=outline; min-width: 120px]
            mat-label — Type
            mat-select formControlName="priceType"
              mat-option value="LIST" — LIST (Regular)
              mat-option value="SALE" — SALE (Discount)
              mat-option value="B2B_TIER" — B2B Tier (Bulk)
          mat-form-field [appearance=outline; min-width: 100px]
            mat-label — Currency
            mat-select formControlName="currency"
              mat-option value="USD" — USD
              mat-option value="THB" — THB
              mat-option value="JPY" — JPY
              mat-option value="SGD" — SGD
          <aliceut-currency-input [currencyCode]="priceGroup.value.currency" formControlName="amount" [required]="true">
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
          <!-- B2B Tier field -->
          mat-form-field [appearance=outline; max-width: 140px] *ngIf="priceGroup.value.priceType === 'B2B_TIER'"
            mat-label — Min Quantity
            input matInput type="number" formControlName="minQty" min="2"
          button mat-icon-button color="warn" (click)="removePrice(pi)" *ngIf="priceGroup.value.priceType !== 'LIST'"
            mat-icon — delete_outline
        mat-error *ngIf="priceGroup.errors?.['duplicate']" — A LIST price in this currency already exists.
        mat-error *ngIf="priceGroup.errors?.['saleRange']" — Sale start must be before sale end.
        mat-error *ngIf="priceGroup.errors?.['minQty']" — Minimum quantity must be at least 2.

  button mat-stroked-button (click)="addPrice()" [margin-top: 8px]
    mat-icon — add
    span — Add Price Row

<!-- Section 5: Inventory (per SKU) -->
mat-card [margin-bottom: 24px; padding: 24px]
  h2 mat-h5 [margin-bottom: 16px] — Inventory
  p mat-body-2 color="secondary" [margin-bottom: 16px] — Set initial stock per SKU. SKUs are auto-generated from variant combinations.
  mat-table [dataSource]="skuRows"
    ng-container matColumnDef="sku"
      th mat-header-cell — SKU
      td mat-cell — {{ row.sku }}
    ng-container matColumnDef="variantLabel"
      th mat-header-cell — Variant
      td mat-cell — {{ row.label }}
    ng-container matColumnDef="onHand"
      th mat-header-cell — On Hand
      td mat-cell
        mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 100px]
          input matInput type="number" min="0" [(ngModel)]="row.onHand"
    ng-container matColumnDef="threshold"
      th mat-header-cell — Low-Stock Alert At
      td mat-cell
        mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 100px]
          input matInput type="number" min="0" [(ngModel)]="row.lowStockThreshold"
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

### Keyword / Category Guard

If title/description/category triggers the prohibited content check on save, the submit is blocked and a `mat-snack-bar` error appears: "Your listing was flagged for review — it will not be visible until an admin clears it." The listing is saved as FLAGGED status.

### API Flow (Create New Listing)

**API flow for create (new listing):** (1) `POST /seller/products` with product fields (title, description, category, images, variants) → receives `productId`. (2) `POST /seller/offers` with `productId` + pricing. If step 2 fails, show an error: "Your product was saved but pricing could not be set — please try again from the Listings page." The `productId` from step 1 is retained so the user can retry offer creation without duplicating the product.

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

<aliceut-data-table [dataSource]="orders" [loading]="loading" [emptyMessage]="tabEmptyMessage">
  ng-container matColumnDef="orderId"
    th mat-header-cell — Order ID
    td mat-cell — {{ row.displayId }}
  ng-container matColumnDef="placedAt"
    th mat-header-cell mat-sort-header — Date
    td mat-cell — {{ row.placedAt | date:'mediumDate' }}
  ng-container matColumnDef="buyer"
    th mat-header-cell — Buyer
    td mat-cell — {{ row.maskedBuyerName }}   ← e.g. "J. Doe"
  ng-container matColumnDef="items"
    th mat-header-cell — Items
    td mat-cell — {{ row.itemSummary }}   ← "2 items"
  ng-container matColumnDef="total"
    th mat-header-cell — Total
    td mat-cell
      <aliceut-price-display [amount]="row.total" [currency]="row.currency">
  ng-container matColumnDef="status"
    th mat-header-cell — Status
    td mat-cell
      <aliceut-status-badge [status]="row.status" [statusType]="'fulfillment'">
      mat-chip *ngIf="row.listingRemoved" [color=warn; font-size: 10px] — Listing removed
  ng-container matColumnDef="actions"
    th mat-header-cell — —
    td mat-cell
      button mat-flat-button color="primary" [routerLink]="['/seller/orders', row.id]" — View
      button mat-flat-button color="accent" (click)="markShipped(row)" *ngIf="row.status === 'PENDING'" — Mark Shipped
```

**Empty states per tab (from US-S-05):**
- Pending → "No pending orders — new orders appear here."
- Shipped/Delivered/Refunded/Cancelled → "No orders in this status."

---

<a id="screen-8-order-detail"></a>
## Screen 8 — Order Detail

**Route:** `/seller/orders/:id`  
**Auth:** SELLER (owns this fulfillment)

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/seller/orders" — arrow_back
  h1 mat-h4 — Order {{ order.displayId }}
  <aliceut-status-badge [status]="order.status" [statusType]="'fulfillment'">

div.detail-grid [display: grid; grid-template-columns: 1fr 340px; gap: 24px]
  <!-- Left: Items -->
  div
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Order Items
      mat-list
        mat-list-item *ngFor="let item of order.items"
          img matListItemAvatar [src]="item.imageUrl" [alt]=""
          span mat-list-item-title — {{ item.productTitle }}
          span mat-list-item-line — {{ item.variantLabel }} · Qty: {{ item.qty }}
          span mat-list-item-line — Unit price: {{ item.unitPrice }} {{ item.currency }} (snapshotted)
          <aliceut-price-display matListItemMeta [amount]="item.lineTotal" [currency]="order.currency">
      mat-divider [margin: 12px 0]
      div [display: flex; justify-content: flex-end]
        span mat-h6 — Total:
        <aliceut-price-display [amount]="order.total" [currency]="order.currency">

    mat-card [padding: 24px] *ngIf="order.trackingNumber"
      h2 mat-h6 — Tracking
      p mat-body-2 — Tracking number: <strong>{{ order.trackingNumber }}</strong>
      p mat-body-2 — Estimated delivery: {{ order.eta | date:'mediumDate' }}

  <!-- Right: Buyer Info + Actions -->
  aside
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Shipping Address
      mat-icon [color=secondary; margin-bottom: 8px] — lock
      p mat-caption color="secondary" [margin-bottom: 8px] — Address visible for fulfillment purposes. Access is logged.
      address [font-style: normal; line-height: 1.8]
        strong — {{ order.shippingAddress.fullName }}
        br
        {{ order.shippingAddress.line1 }}
        br
        {{ order.shippingAddress.line2 }}
        br *ngIf="order.shippingAddress.line2"
        {{ order.shippingAddress.city }}, {{ order.shippingAddress.state }} {{ order.shippingAddress.postalCode }}
        br
        {{ order.shippingAddress.country }}

    mat-card [padding: 24px]
      h2 mat-h6 [margin-bottom: 16px] — Actions

      <!-- Mark Shipped -->
      div *ngIf="order.status === 'PENDING'" [margin-bottom: 12px]
        p mat-body-2 [margin-bottom: 8px] — Mark this order as shipped once dispatched.
        p mat-caption color="secondary" [margin-bottom: 8px] — Tracking number {{ order.trackingNumber }} will be sent to the buyer.
        button mat-flat-button color="primary" [fullWidth] (click)="markShipped()"
          mat-icon — local_shipping
          span — Mark as Shipped

      <!-- Issue Refund / Cancel -->
      div *ngIf="order.status === 'PENDING' || order.status === 'SHIPPED'" [margin-top: 12px]
        button mat-stroked-button color="warn" [fullWidth] (click)="openRefundDialog()" *ngIf="order.status === 'PENDING' || order.status === 'SHIPPED'"
          mat-icon — currency_exchange
          span — Issue Refund
        button mat-stroked-button color="warn" [fullWidth; margin-top: 8px] (click)="openCancelDialog()" *ngIf="order.status === 'PENDING'"
          mat-icon — cancel
          span — Cancel Order

      <!-- Terminal state messages -->
      div *ngIf="['DELIVERED','REFUNDED','CANCELLED'].includes(order.status)"
        mat-icon [color]="terminalIconColor" — {{ terminalIcon }}
        p mat-body-2 — {{ terminalMessage }}
```

**Mark Shipped** triggers `ConfirmDialog` with message: "Confirm shipment. Tracking number {{ order.trackingNumber }} will be shared with the buyer."

**Issue Refund** triggers `ConfirmDialog` with `requireReason=true`: "Are you sure you want to refund this order? This cannot be undone."

**Cancel Order** triggers `ConfirmDialog` with `requireReason=true` and `danger=true`.

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
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 80px] *ngIf="row.editing"
        input matInput type="number" min="0" [(ngModel)]="row.editValue" (blur)="saveQty(row)"
      span *ngIf="!row.editing" (click)="row.editing=true" [cursor: pointer] — {{ row.onHand }}
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
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 80px] *ngIf="row.editingThreshold"
        input matInput type="number" min="0" [(ngModel)]="row.thresholdValue" (blur)="saveThreshold(row)"
      span *ngIf="!row.editingThreshold" (click)="row.editingThreshold=true" — {{ row.lowStockThreshold }}
        mat-icon [font-size: 14px] — edit
```

### CSV Import Dialog

`MatDialog` containing:

```
mat-dialog-title — Bulk Inventory Update
mat-dialog-content
  p mat-body-2 — Upload a CSV with columns: sku, on_hand, low_stock_threshold (optional)
  a mat-button href="/assets/inventory-template.csv" download — Download template
  <aliceut-file-upload [accept]="'.csv'" [maxSizeMb]="5" [multiple]="false" (filesChange)="csvFile = $event[0]">

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

<a id="screen-10-notification-panel"></a>
## Screen 10 — Notification Panel

Rendered as `NotificationBell` component in toolbar. Notification types relevant to seller:

| Event | Icon | Message pattern |
|-------|------|-----------------|
| New order | `receipt_long` | "New order [FUL-xxx] placed" |
| Low stock | `warning_amber` (warn) | "[SKU name] is running low (N left)" |
| Listing flagged | `flag` (warn) | "'[Product title]' has been flagged for review" |
| Listing removed | `block` (warn) | "'[Product title]' was removed by admin" |
| KYC approved | `check_circle_outline` (success) | "Your KYC application was approved" |
| KYC rejected | `cancel` (warn) | "Your KYC application was rejected" |
| Suspension | `block` (error) | "Your account has been suspended" |

---

<a id="screen-11-offer-pricing"></a>
## Screen 11 — Offer Pricing

**Route:** `/seller/listings/:id/pricing`  
**Auth:** SELLER + APPROVED + Not Suspended (`KycApprovedGuard + SellerActiveGuard`)

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button [routerLink]="['/seller/listings', offerId]" — arrow_back
  h1 mat-h4 — Manage Pricing — {{ productTitle }}

<!-- Current price rows table -->
<aliceut-data-table [dataSource]="prices" [loading]="loading" emptyMessage="No prices set yet. Add a LIST price to make this offer visible to buyers.">
  ng-container matColumnDef="priceType"
    th mat-header-cell — Price Type
    td mat-cell
      mat-chip [color]="row.priceType === 'LIST' ? 'primary' : 'default'" — {{ row.priceType }}
  ng-container matColumnDef="amount"
    th mat-header-cell — Amount
    td mat-cell
      <aliceut-price-display [amount]="row.amount" [currency]="row.currency">
  ng-container matColumnDef="startsAt"
    th mat-header-cell — Valid From
    td mat-cell — {{ row.startsAt ? (row.startsAt | date:'mediumDate') : '—' }}
  ng-container matColumnDef="endsAt"
    th mat-header-cell — Valid Until
    td mat-cell — {{ row.endsAt ? (row.endsAt | date:'mediumDate') : '—' }}
  ng-container matColumnDef="minQty"
    th mat-header-cell — Min Qty
    td mat-cell — {{ row.minQty ?? '—' }}
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
          mat-option value="B2B_TIER" — B2B_TIER
      mat-form-field [appearance=outline; min-width: 160px]
        mat-label — Amount
        input matInput formControlName="amount" placeholder="e.g. 99.99"
        mat-hint — Enter as a number string
        mat-error *ngIf="priceForm.get('amount')?.hasError('pattern')" — Amount must be a valid number
      mat-form-field [appearance=outline; min-width: 100px]
        mat-label — Currency
        mat-select formControlName="currency"
          mat-option value="USD" — USD
          mat-option value="THB" — THB
          mat-option value="JPY" — JPY
          mat-option value="SGD" — SGD
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
      <!-- B2B_TIER field (shown when priceType === 'B2B_TIER') -->
      mat-form-field [appearance=outline; max-width: 140px] *ngIf="priceForm.get('priceType')?.value === 'B2B_TIER'"
        mat-label — Min Quantity
        input matInput type="number" formControlName="minQty" min="2"
        mat-error — Min quantity must be ≥ 2

    mat-error *ngIf="priceForm.errors?.['duplicate']" [margin-top: 8px] — A price with this type and currency already exists.
    mat-error *ngIf="priceForm.errors?.['saleRange']" [margin-top: 8px] — Valid From must be before Valid Until.

    div [display: flex; gap: 8px; justify-content: flex-end; margin-top: 16px]
      button mat-button type="button" (click)="cancelPriceForm()" — Cancel
      button mat-flat-button color="primary" type="submit" [disabled]="priceForm.invalid || isSaving"
        mat-spinner *ngIf="isSaving" [diameter]="20"
        span *ngIf="!isSaving" — Save
```

---

<a id="screen-12-seller-forgot-password"></a>
## Screen 12 — Seller Forgot Password

**Route:** `/seller/forgot-password`  
**Auth:** Public (no authentication required)

### Layout

```
div.auth-page [display: flex; justify-content: center; padding: 48px 16px]
  mat-card [width: 100%; max-width: 440px; padding: 32px]
    mat-card-header [text-align: center; margin-bottom: 24px]
      mat-icon [font-size: 48px; color: primary] — lock_reset
      mat-card-title — Forgot your password?
      mat-card-subtitle — Enter your email and we'll send a reset link.
    mat-card-content

      <!-- Default state: form -->
      ng-container *ngIf="!submitted"
        form [formGroup]="forgotForm" (ngSubmit)="sendResetLink()"
          mat-form-field [appearance=outline; fullWidth; margin-bottom: 16px]
            mat-label — Email address
            input matInput type="email" formControlName="email" autocomplete="email"
            mat-error — Enter a valid email address

          button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="forgotForm.invalid || isLoading"
            mat-spinner *ngIf="isLoading" [diameter]="20"
            span *ngIf="!isLoading" — Send Reset Link

        p mat-body-2 [text-align: center; margin-top: 16px]
          a mat-button routerLink="/seller/login" — Back to Sign In

      <!-- Success state: email sent -->
      ng-container *ngIf="submitted"
        div [text-align: center; padding: 16px 0]
          mat-icon [font-size: 48px; color: success] — mark_email_read
          h3 mat-h5 [margin-top: 16px] — Check your email
          p mat-body-2 [margin-top: 8px] — If an account with that email exists, we sent a reset link. Check your inbox.
          p mat-caption [margin-top: 8px] color="secondary" — Didn't receive it? Check your spam folder or
          button mat-button color="primary" (click)="resend()" — resend the email.
          p mat-body-2 [margin-top: 16px]
            a mat-button routerLink="/seller/login" — Back to Sign In
```

---

<a id="screen-13-seller-reset-password"></a>
## Screen 13 — Seller Reset Password

**Route:** `/seller/reset-password?token=`  
**Auth:** Public; reads `?token=` query param on component init

### Layout

```
div.auth-page [display: flex; justify-content: center; padding: 48px 16px]
  mat-card [width: 100%; max-width: 440px; padding: 32px]
    mat-card-header [text-align: center; margin-bottom: 24px]
      mat-icon [font-size: 48px; color: primary] — lock_reset
      mat-card-title — Reset your password
    mat-card-content

      <!-- Form shown optimistically on mount; token validity determined by POST /auth/reset-password response on submit (400 = expired/used). No pre-validation endpoint exists. -->
      ng-container *ngIf="tokenState !== 'expired' && tokenState !== 'invalid' && tokenState !== 'success'"
        form [formGroup]="resetForm" (ngSubmit)="resetPassword()"
          mat-form-field [appearance=outline; fullWidth; margin-bottom: 16px]
            mat-label — New password
            input matInput [type]="showPw ? 'text' : 'password'" formControlName="password" autocomplete="new-password"
            button mat-icon-button matSuffix type="button" (click)="showPw = !showPw"
              mat-icon — {{ showPw ? 'visibility_off' : 'visibility' }}
            mat-hint — At least 8 characters, 1 letter, 1 number
            mat-error — {{ passwordError }}
          mat-form-field [appearance=outline; fullWidth; margin-bottom: 16px]
            mat-label — Confirm password
            input matInput [type]="showPwConfirm ? 'text' : 'password'" formControlName="confirmPassword" autocomplete="new-password"
            button mat-icon-button matSuffix type="button" (click)="showPwConfirm = !showPwConfirm"
              mat-icon — {{ showPwConfirm ? 'visibility_off' : 'visibility' }}
            mat-error *ngIf="resetForm.errors?.['mismatch']" — Passwords do not match

          button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="resetForm.invalid || isSaving"
            mat-spinner *ngIf="isSaving" [diameter]="20"
            span *ngIf="!isSaving" — Set New Password

      <!-- Expired / used token (shown after submit returns 400) -->
      ng-container *ngIf="tokenState === 'expired' || tokenState === 'invalid'"
        div [text-align: center; padding: 16px 0]
          mat-icon [font-size: 48px; color: warn] — link_off
          h3 mat-h5 [margin-top: 16px] — Reset link expired
          p mat-body-2 [margin-top: 8px] — This link has expired or has already been used. Request a new one.
          button mat-flat-button color="primary" routerLink="/seller/forgot-password" [margin-top: 16px] — Request new link
          p mat-body-2 [margin-top: 16px]
            a mat-button routerLink="/seller/login" — Back to Sign In

      <!-- Success state: redirect imminent -->
      ng-container *ngIf="tokenState === 'success'"
        div [text-align: center; padding: 16px 0]
          mat-icon [font-size: 48px; color: success] — check_circle_outline
          h3 mat-h5 [margin-top: 16px] — Password updated
          p mat-body-2 [margin-top: 8px] — Your password has been reset. Redirecting you to sign in…
```

**On success:** Redirect to `/seller/login?passwordReset=true`. The login page shows a success banner: "Password reset successfully — please sign in with your new password."

---

<a id="screen-14-seller-notifications"></a>
## Screen 14 — Seller Notifications

**Route:** `/seller/notifications`
**Guard:** `SellerApprovedGuard` (seller must be KYC-approved; listing/order notifications only relevant post-approval)
**Component:** `SellerNotificationsComponent`

### Layout

Identical structure to buyer notifications page (see buyer-portal.md Screen 16). Seller-specific notification types only.

```
h1 mat-h4 — "Notifications"
div.notifications-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px]
  button mat-stroked-button [disabled]="allRead" (click)="markAllRead()" — Mark all as read

div.notifications-list [max-width: 800px]
  mat-card.notification-card *ngFor="let n of notifications"
    [class.unread]="!n.readAt"
    [cursor: pointer] (click)="handleClick(n)"
    [display: flex; align-items: flex-start; gap: 16px; padding: 16px]
    mat-icon [color]="typeIconColor(n.type)" — {{ typeIcon(n.type) }}
    div [flex: 1]
      p mat-body-1 [font-weight]="!n.readAt ? '600' : '400'" — {{ n.title }}
      p mat-body-2 *ngIf="n.body" — {{ n.body }}
      p mat-caption color="secondary" — {{ n.createdAt | timeAgo }}
    div.unread-dot *ngIf="!n.readAt"

  div.load-more *ngIf="hasMore"
    button mat-stroked-button (click)="loadMore()" — Load more

<aliceut-empty-state *ngIf="!loading && notifications.length === 0"
  icon="notifications_none"
  title="No notifications"
  message="Order and listing alerts will appear here.">
</aliceut-empty-state>
```

### Notification types displayed

`ORDER_PLACED`, `LISTING_FLAGGED`, `FULFILLMENT_CANCELLED`, `KYC_DECIDED`, `KYC_SUBMITTED`,
`LOW_STOCK`, `LISTING_REMOVED`, `SELLER_SUSPENDED`, `SELLER_REINSTATED`, `SUSPENSION_EXPIRED`
(seller-relevant canonical types from `notifications.md`; `KYC_DECIDED` payload carries `decision: APPROVED | REJECTED`)

### API calls

- `GET /notifications?page=1&limit=20`
- `GET /notifications?page=N&limit=20` — load more
- `PATCH /notifications/read-all`
- `PATCH /notifications/:id/read`

### Mobile

Full-width cards, same as buyer notifications.

---

*Last updated: phase-1 design*
