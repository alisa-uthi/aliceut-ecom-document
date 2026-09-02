# Admin Portal — UI Design Specification
## admin-app (port 4202)

**Status:** Draft  
**Stack:** Angular 17+ + Angular Material + `libs/ui/` shared components  
**Auth:** Email/password only. JWT with ADMIN role. No self-registration. No OAuth.

---

## Shell Layout

```
mat-sidenav-container [fullscreen]
  mat-sidenav #drawer [mode]="isDesktop ? 'side' : 'over'" [opened]="isDesktop" [fixedInViewport]
    div.brand [padding: 16px 24px]
      mat-icon [color=primary; font-size: 28px] — admin_panel_settings
      span mat-h6 — AliceUT Admin

    mat-nav-list
      a mat-list-item routerLink="/admin/dashboard" routerLinkActive="active"
        mat-icon matListItemIcon — dashboard
        span matListItemTitle — Dashboard
      a mat-list-item routerLink="/admin/kyc" routerLinkActive="active"
        mat-icon matListItemIcon — assignment_ind
        span matListItemTitle — KYC Queue
        span.nav-badge [matBadge]="kycPendingCount" *ngIf="kycPendingCount > 0" — (shows red badge)
      a mat-list-item routerLink="/admin/moderation" routerLinkActive="active"
        mat-icon matListItemIcon — gavel
        span matListItemTitle — Moderation
        span.nav-badge [matBadge]="flaggedCount" *ngIf="flaggedCount > 0"
      a mat-list-item routerLink="/admin/sellers" routerLinkActive="active"
        mat-icon matListItemIcon — store
        span matListItemTitle — Sellers
      mat-divider
      a mat-list-item (click)="logout()"
        mat-icon matListItemIcon — logout
        span matListItemTitle — Sign Out

  mat-sidenav-content
    mat-toolbar [color=primary] [position: sticky; top: 0; z-index: 100]
      button mat-icon-button (click)="drawer.toggle()" *ngIf="!isDesktop"
        mat-icon — menu
      span — Admin Portal
      span.spacer [flex: 1]
      <aliceut-notification-bell [notifications]="notifications" [unreadCount]="unreadCount">
      button mat-button [matMenuTriggerFor]="adminMenu"
        mat-icon — account_circle
        span — {{ adminName }}
      mat-menu #adminMenu
        button mat-menu-item (click)="logout()" — logout icon — Sign Out

    main.admin-content [padding: 24px]
      router-outlet
```

---

## Screen 1 — Admin Login

**Route:** `/admin/login`  
**Auth:** None (redirect to dashboard if authenticated as ADMIN)

```
div.admin-login-page [display: flex; justify-content: center; align-items: flex-start; padding: 64px 16px; background: grey-50; min-height: 100vh]
  mat-card [width: 100%; max-width: 400px; padding: 40px]
    mat-card-header [text-align: center; margin-bottom: 32px]
      mat-icon [font-size: 56px; color: primary] — admin_panel_settings
      mat-card-title mat-h4 — AliceUT Admin
      mat-card-subtitle — Restricted access — authorised personnel only
    mat-card-content
      form [formGroup]="loginForm" (ngSubmit)="login()"
        mat-form-field [appearance=outline; fullWidth; margin-bottom: 16px]
          mat-label — Admin email
          input matInput type="email" formControlName="email" autocomplete="email"
          mat-icon matPrefix — mail_outline
        mat-form-field [appearance=outline; fullWidth]
          mat-label — Password
          input matInput [type]="showPw ? 'text' : 'password'" formControlName="password" autocomplete="current-password"
          button mat-icon-button matSuffix type="button" (click)="showPw = !showPw" aria-label="Toggle password visibility"
            mat-icon — {{ showPw ? 'visibility_off' : 'visibility' }}

        mat-card.error-banner *ngIf="loginError" [margin-bottom: 16px]
          mat-icon — error_outline
          span — {{ loginError }}

        button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="loginForm.invalid || isLoading"
          mat-spinner *ngIf="isLoading" [diameter]="20"
          span *ngIf="!isLoading" — Sign In
```

**No register link. No OAuth buttons.** Per US-A-00b, admin accounts are provisioned via seed script only. The page has no "Create account" or "Forgot password?" link — [RESOLVED] Admin password reset is out of scope in V1. Admin accounts are seeded in DB; password changes require direct DB update by the developer.

---

## Screen 2 — Admin Dashboard

**Route:** `/admin/dashboard`  
**Auth:** ADMIN role

### Layout

```
h1 mat-h4 — Admin Dashboard
p mat-body-2 color="secondary" — {{ today | date:'fullDate' }}

<!-- Summary stat cards -->
div.stats-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; margin-bottom: 32px]

  mat-card.stat-card [cursor: pointer] (click)="navigate('/admin/kyc?status=PENDING')"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption — KYC Pending
          p mat-headline-4 — {{ stats.kycPending }}
        mat-icon [font-size: 40px; color: amber] — assignment_ind
    mat-card-footer [padding: 8px 16px; background: amber-50]
      span mat-caption — Review applications →

  mat-card.stat-card [cursor: pointer; outline: 2px solid var(--warn)] *ngIf="stats.slaBreach > 0" (click)="navigate('/admin/kyc?sla=breached')"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption color="warn" — SLA Breaches (> 3 days)
          p mat-headline-4 color="warn" — {{ stats.slaBreach }}
        mat-icon [font-size: 40px] color="warn" — access_time
    mat-card-footer [padding: 8px 16px; background: red-50]
      span mat-caption color="warn" — Requires immediate attention →

  mat-card.stat-card (click)="navigate('/admin/moderation?status=PENDING')"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption — Flagged Listings Pending
          p mat-headline-4 — {{ stats.flaggedListings }}
        mat-icon [font-size: 40px; color: orange] — gavel
    mat-card-footer [padding: 8px 16px; background: orange-50]
      span mat-caption — Moderate catalog →

  mat-card.stat-card (click)="navigate('/admin/sellers?status=SUSPENDED')"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption — Suspended Sellers
          p mat-headline-4 — {{ stats.suspendedSellers }}
        mat-icon [font-size: 40px; color: deep-orange] — block

<!-- Recent activity feed -->
div.activity-feed [margin-top: 8px]
  h2 mat-h5 [margin-bottom: 16px] — Recent Activity
  mat-list
    mat-list-item *ngFor="let event of recentActivity"
      mat-icon matListItemIcon [color]="event.iconColor" — {{ event.icon }}
      span mat-list-item-title — {{ event.title }}
      span mat-list-item-line — {{ event.detail }}
      span matListItemMeta mat-caption color="secondary" — {{ event.occurredAt | timeAgo }}
  <aliceut-empty-state *ngIf="recentActivity.length === 0"
    icon="history" title="No recent activity" message="Actions you take will appear here.">
```

---

## Screen 3 — KYC Queue

**Route:** `/admin/kyc`  
**Auth:** ADMIN role

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — KYC Applications
  div [display: flex; gap: 12px]
    mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 160px]
      mat-label — Status
      mat-select [formControl]="statusFilter"
        mat-option value="" — All
        mat-option value="PENDING_KYC" — Pending
        mat-option value="APPROVED" — Approved
        mat-option value="REJECTED" — Rejected
    mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 160px]
      mat-label — Country
      mat-select [formControl]="countryFilter"
        mat-option value="" — All Countries
        mat-option *ngFor="let c of countries" [value]="c.code" — {{ c.name }}
    mat-slide-toggle [formControl]="slaBreachOnly" — SLA Breaches Only

<aliceut-data-table [dataSource]="applications" [loading]="loading" emptyMessage="No pending applications — all caught up.">
  ng-container matColumnDef="select"
    th mat-header-cell — <mat-checkbox (change)="toggleAll($event)">
    td mat-cell — <mat-checkbox [(ngModel)]="selection.isSelected(row)">

  ng-container matColumnDef="businessName"
    th mat-header-cell mat-sort-header — Business Name
    td mat-cell
      div — {{ row.businessName }}
      mat-chip *ngIf="row.isResubmission" [color=accent; font-size: 10px]
        mat-icon [font-size: 12px] — refresh
        span — Resubmit

  ng-container matColumnDef="country"
    th mat-header-cell — Country
    td mat-cell — {{ row.country }}

  ng-container matColumnDef="submittedAt"
    th mat-header-cell mat-sort-header — Submitted
    td mat-cell — {{ row.submittedAt | date:'mediumDate' }}

  ng-container matColumnDef="daysPending"
    th mat-header-cell — Days Pending
    td mat-cell
      div [display: flex; align-items: center; gap: 4px]
        span [color]="row.daysPending > 3 ? 'warn' : 'default'" — {{ row.daysPending }}d
        mat-chip *ngIf="row.daysPending > 3" color="warn" [font-size: 10px]
          mat-icon [font-size: 12px] — schedule
          span — SLA

  ng-container matColumnDef="status"
    th mat-header-cell — Status
    td mat-cell — <aliceut-status-badge [status]="row.kycStatus" [statusType]="'kyc'">

  ng-container matColumnDef="actions"
    th mat-header-cell — —
    td mat-cell
      button mat-flat-button color="primary" [routerLink]="['/admin/kyc', row.id]" — Review
```

---

## Screen 4 — KYC Application Detail

**Route:** `/admin/kyc/:id`  
**Auth:** ADMIN role

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/admin/kyc" — arrow_back
  h1 mat-h4 — KYC Review: {{ application.businessName }}
  <aliceut-status-badge [status]="application.kycStatus" [statusType]="'kyc'">

div.review-grid [display: grid; grid-template-columns: 1fr 380px; gap: 24px]
  <!-- Left: Submitted Information + Documents -->
  div
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Submitted Business Information
      mat-list [dense]
        mat-list-item
          mat-icon matListItemIcon — business
          span mat-list-item-title — Legal Name
          span matListItemMeta — {{ application.businessName }}
        mat-list-item
          mat-icon matListItemIcon — category
          span mat-list-item-title — Business Type
          span matListItemMeta — {{ application.businessType }}
        mat-list-item
          mat-icon matListItemIcon — receipt
          span mat-list-item-title — Tax ID
          span matListItemMeta — {{ application.taxId }}
        mat-list-item
          mat-icon matListItemIcon — public
          span mat-list-item-title — Country
          span matListItemMeta — {{ application.country }}
        mat-list-item
          mat-icon matListItemIcon — location_on
          span mat-list-item-title — Address
          span matListItemMeta — {{ application.address }}
        mat-list-item
          mat-icon matListItemIcon — phone
          span mat-list-item-title — Phone
          span matListItemMeta — {{ application.phone }}
        mat-list-item
          mat-icon matListItemIcon — person
          span mat-list-item-title — Account Email
          span matListItemMeta — {{ application.sellerEmail }}
        mat-list-item
          mat-icon matListItemIcon — schedule
          span mat-list-item-title — Submitted
          span matListItemMeta — {{ application.submittedAt | date:'medium' }}

    <!-- Resubmission context -->
    mat-card.info-banner *ngIf="application.isResubmission" [margin-bottom: 16px]
      mat-icon — info_outline
      div
        p mat-body-2 — This is a resubmission.
        p mat-caption — Previous rejection reason: "{{ application.previousRejectionReason }}"
        p mat-caption — Rejected on: {{ application.previousRejectionDate | date:'mediumDate' }}

    <!-- Document viewer -->
    mat-card [padding: 24px]
      h2 mat-h6 [margin-bottom: 8px] — Uploaded Documents
      mat-card.info-banner [margin-bottom: 16px]
        mat-icon — lock
        span mat-caption — Document access is logged for compliance (NFR-09).

      mat-tab-group
        mat-tab label="Business License"
          div.doc-viewer [margin-top: 16px; height: 500px; border: 1px solid divider; border-radius: 4px; overflow: hidden]
            <!-- PDF: embedded via <iframe> or PDF.js viewer. Image: <img> with zoom controls -->
            iframe *ngIf="businessLicenseDoc.isPdf" [src]="businessLicenseDoc.secureUrl | safe:'resourceUrl'" [width="100%" height="100%"]
            img *ngIf="!businessLicenseDoc.isPdf" [src]="businessLicenseDoc.secureUrl | safe:'url'" [max-width: 100%; max-height: 100%; object-fit: contain]
            mat-spinner *ngIf="businessLicenseDoc.loading" [diameter]="40] [centered]
        mat-tab label="Government ID"
          div.doc-viewer [same structure]
        mat-tab label="Bank Statement"
          div.doc-viewer [same structure]

  <!-- Right: Decision Panel -->
  aside
    mat-card [padding: 24px; position: sticky; top: 88px]
      h2 mat-h6 [margin-bottom: 16px] — Review Decision

      <!-- Already decided -->
      div *ngIf="application.kycStatus !== 'PENDING_KYC'" [margin-bottom: 16px]
        <aliceut-status-badge [status]="application.kycStatus" [statusType]="'kyc'">
        p mat-body-2 *ngIf="application.kycStatus === 'APPROVED'" — Approved on {{ application.decidedAt | date:'mediumDate' }} by {{ application.decidedByAdmin }}
        p mat-body-2 *ngIf="application.kycStatus === 'REJECTED'" — Rejected on {{ application.decidedAt | date:'mediumDate' }}
        p mat-body-2 *ngIf="application.kycStatus === 'REJECTED'" — Reason: {{ application.rejectionReason }}
        mat-divider [margin: 16px 0]

      <!-- Pending decision form -->
      div *ngIf="application.kycStatus === 'PENDING_KYC'"
        button mat-flat-button color="primary" [fullWidth] (click)="approve()" [disabled]="isActing" [margin-bottom: 12px]
          mat-icon — check_circle_outline
          span — Approve Application

        mat-divider [margin: 12px 0]
          span mat-caption color="secondary" — or

        form [formGroup]="rejectForm" [margin-top: 12px]
          mat-form-field [appearance=outline; fullWidth]
            mat-label — Rejection Reason *
            textarea matInput formControlName="rejectionReason" rows="4" maxlength="500"
            mat-hint align="end" — {{ rejectForm.value.rejectionReason?.length || 0 }}/500
            mat-error — Rejection reason is required
          button mat-stroked-button color="warn" [fullWidth] [disabled]="rejectForm.invalid || isActing" (click)="reject()" [margin-top: 8px]
            mat-icon — cancel
            span — Reject Application

      mat-spinner *ngIf="isActing" [diameter]="32] [margin: 16px auto; display: block]
```

### Approve/Reject actions

Both show `ConfirmDialog` before execution. Approve → dialog with title "Approve Seller?", message "This will allow them to create listings immediately." Reject → `ConfirmDialog` showing the rejection reason for confirmation.

---

## Screen 5 — Catalog Moderation Queue

**Route:** `/admin/moderation`  
**Auth:** ADMIN role

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — Catalog Moderation
  div [display: flex; gap: 12px; align-items: center]
    mat-chip-listbox [formControl]="sourceFilter" aria-label="Flag source filter"
      mat-chip-option value="auto" — Auto-flagged
      mat-chip-option value="keyword" — Keyword hit
      mat-chip-option value="category" — Prohibited category
    span mat-caption color="secondary" [margin-left: 8px] — V1: all flags are auto-flagged; buyer reports deferred to V2.

<aliceut-data-table [dataSource]="cases" [loading]="loading" emptyMessage="No flagged listings — catalog is clean.">
  ng-container matColumnDef="select"
    th mat-header-cell — <mat-checkbox (change)="toggleAll($event)">
    td mat-cell — <mat-checkbox [(ngModel)]="selection.isSelected(row)">

  ng-container matColumnDef="thumbnail"
    th mat-header-cell — —
    td mat-cell
      img [src]="row.primaryImageUrl" [alt]="" [width="48px" height="48px" border-radius="4px"]

  ng-container matColumnDef="product"
    th mat-header-cell — Product / Offer
    td mat-cell
      p mat-body-2 — {{ row.productTitle }}
      p mat-caption color="secondary" — by {{ row.sellerName }}

  ng-container matColumnDef="flagReason"
    th mat-header-cell — Flag Reason
    td mat-cell
      mat-chip color="warn" — {{ row.flagSource | titlecase }}
      p mat-caption color="warn" [margin-top: 4px] — {{ row.flagSnippet }}
        ← e.g. 'Keyword "knife" in title'

  ng-container matColumnDef="flaggedAt"
    th mat-header-cell mat-sort-header — Flagged
    td mat-cell — {{ row.flaggedAt | date:'mediumDate' }}

  ng-container matColumnDef="actions"
    th mat-header-cell — —
    td mat-cell
      button mat-stroked-button [routerLink]="['/admin/moderation', row.id]" [margin-right: 8px] — Review
      button mat-flat-button color="warn" (click)="removeListing(row)" *ngIf="selection.isEmpty()" — Remove

<!-- Bulk action bar (shown when selection is non-empty) -->
<div class="bulk-action-bar">
  <span>{{ selection.selected.length }} listing(s) selected</span>
  <button mat-stroked-button (click)="openBulkRemoveDialog()">Remove Selected</button>
</div>
```

**`openBulkRemoveDialog()` behavior:** Opens a `MatDialog` (`BulkRemoveDialogComponent`) with two modes:
- **Same reason for all:** Single `mat-select` (removal_category) + free-text `mat-textarea` (reason). Applied to all selected listings.
- **Per-listing reasons:** Table of selected listings, each with its own category dropdown + reason textarea. Toggle between modes via a radio button at top.

Submit calls `POST /admin/moderation/bulk-remove` with array of `{listingId, removalCategory, removalReasonText}`. Restriction: minimum 1 char reason required per listing (mandatory per US-A-04).

---

## Screen 6 — Moderation Case Detail

**Route:** `/admin/moderation/:id`  
**Auth:** ADMIN role

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/admin/moderation" — arrow_back
  h1 mat-h4 — Moderation Case #{{ case.id }}
  <aliceut-status-badge [status]="case.status" [statusType]="'listing'">

div.case-grid [display: grid; grid-template-columns: 1fr 360px; gap: 24px]
  <!-- Left: Listing Preview -->
  div
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Listing Details
      div [display: flex; gap: 16px; align-items: flex-start]
        img [src]="case.primaryImageUrl" [alt]="" [width: 120px; height: 120px; border-radius: 8px; object-fit: cover]
        div
          h3 mat-h5 — {{ case.productTitle }}
          p mat-body-2 — {{ case.category }}
          p mat-body-2 — Seller: {{ case.sellerName }}
          p mat-body-2 — Listed: {{ case.listedAt | date:'mediumDate' }}

      mat-divider [margin: 16px 0]
      h4 mat-h6 — Description
      div.description-text [padding: 12px; background: grey-50; border-radius: 4px; max-height: 300px; overflow-y: auto]
        <!-- Description rendered with keyword highlights -->
        p mat-body-2 [innerHTML]="highlightedDescription">   ← keyword hits wrapped in <mark> tags

    mat-card [padding: 24px]
      h2 mat-h6 [margin-bottom: 12px] — Flag Details
      mat-list [dense]
        mat-list-item
          mat-icon matListItemIcon color="warn" — flag
          span mat-list-item-title — Flag Source
          span matListItemMeta — {{ case.flagSource | titlecase }}
        mat-list-item
          mat-icon matListItemIcon color="warn" — schedule
          span mat-list-item-title — Flagged At
          span matListItemMeta — {{ case.flaggedAt | date:'medium' }}
      div.keyword-hits *ngIf="case.keywordHits.length > 0" [margin-top: 12px]
        p mat-body-2 — Matching keywords:
        div [display: flex; flex-wrap: wrap; gap: 8px; margin-top: 4px]
          mat-chip *ngFor="let kw of case.keywordHits" color="warn" — "{{ kw }}"
      p mat-body-2 *ngIf="case.flagSource === 'prohibited_category'" — Prohibited category: <strong>{{ case.prohibitedCategory }}</strong>

  <!-- Right: Action Panel -->
  aside
    mat-card [padding: 24px; position: sticky; top: 88px]
      h2 mat-h6 [margin-bottom: 16px] — Take Action

      <!-- Case already resolved -->
      div *ngIf="case.status !== 'FLAGGED'"
        <aliceut-status-badge [status]="case.status" [statusType]="'listing'">
        p mat-body-2 *ngIf="case.resolvedAt" — Resolved {{ case.resolvedAt | date:'mediumDate' }} by {{ case.resolvedBy }}
        p mat-body-2 *ngIf="case.resolution === 'REMOVED'" — Removal reason: {{ case.removalReason }}
        p mat-body-2 *ngIf="case.resolution === 'CLEARED'" — Cleared as compliant. Note: {{ case.clearanceNote || 'None' }}

      <!-- Pending case actions -->
      div *ngIf="case.status === 'FLAGGED'"
        <!-- Remove -->
        h3 mat-body-1 [font-weight: 500; margin-bottom: 8px] — Remove Listing
        form [formGroup]="removeForm"
          mat-form-field [appearance=outline; fullWidth]
            mat-label — Removal Reason *
            mat-select formControlName="removalReasonType"
              mat-option value="prohibited_category" — Prohibited category
              mat-option value="ip_violation" — IP / copyright violation
              mat-option value="misleading" — Misleading / fraudulent
              mat-option value="other" — Other
          mat-form-field [appearance=outline; fullWidth; margin-top: 8px]
            mat-label — Additional details (shown to seller)
            textarea matInput formControlName="removalNote" rows="3" maxlength="500"
            mat-hint align="end" — {{ removeForm.value.removalNote?.length || 0 }}/500
          mat-card.info-banner [margin-top: 8px]
            mat-icon — mail_outline
            span mat-caption — Seller will receive removal reason in daily digest (ET-09).
          button mat-flat-button color="warn" [fullWidth; margin-top: 12px] [disabled]="removeForm.invalid || isActing" (click)="removeAndNotify()"
            mat-icon — delete_outline
            span — Remove Listing

        mat-divider [margin: 16px 0]
          span mat-caption color="secondary" — or

        <!-- Dismiss / Clear -->
        form [formGroup]="clearForm" [margin-top: 12px]
          mat-form-field [appearance=outline; fullWidth]
            mat-label — Note (optional)
            textarea matInput formControlName="clearanceNote" rows="2" maxlength="500"
          button mat-stroked-button color="primary" [fullWidth; margin-top: 8px] [disabled]="isActing" (click)="clearFlag()"
            mat-icon — check_circle_outline
            span — Clear Flag (Listing is Compliant)
```

---

## Screen 7 — Seller Management

**Route:** `/admin/sellers`  
**Auth:** ADMIN role

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — Seller Management

<aliceut-data-table [dataSource]="sellers" [loading]="loading" emptyMessage="No sellers found matching your criteria.">
  <!-- Table actions slot -->
  ng-template [table-actions]
    <div class="table-actions">
      <!-- Server-side search (replaces generic DataTable client-side filter) -->
      <mat-form-field appearance="outline" class="search-field">
        <mat-label>Search by business name, email, or tax ID</mat-label>
        <input matInput [formControl]="searchControl" (keyup.enter)="applySearch()">
        <mat-icon matSuffix>search</mat-icon>
      </mat-form-field>
      <mat-form-field appearance="outline">
        <mat-label>Status</mat-label>
        <mat-select [formControl]="statusFilter" (selectionChange)="applyFilters()">
          <mat-option value="">All</mat-option>
          <mat-option value="ACTIVE">Active</mat-option>
          <mat-option value="SUSPENDED">Suspended</mat-option>
          <mat-option value="PENDING_KYC">KYC Pending</mat-option>
        </mat-select>
      </mat-form-field>
    </div>

  ng-container matColumnDef="businessName"
    th mat-header-cell mat-sort-header — Business Name
    td mat-cell — {{ row.businessName }}
  ng-container matColumnDef="email"
    th mat-header-cell — Email
    td mat-cell — {{ row.email }}
  ng-container matColumnDef="country"
    th mat-header-cell — Country
    td mat-cell — {{ row.country }}
  ng-container matColumnDef="createdAt"
    th mat-header-cell mat-sort-header — Registered
    td mat-cell — {{ row.createdAt | date:'mediumDate' }}
  ng-container matColumnDef="kycStatus"
    th mat-header-cell — KYC
    td mat-cell — <aliceut-status-badge [status]="row.kycStatus" [statusType]="'kyc'">
  ng-container matColumnDef="accountStatus"
    th mat-header-cell — Account
    td mat-cell — <aliceut-status-badge [status]="row.accountStatus" [statusType]="'seller'">
  ng-container matColumnDef="activeListings"
    th mat-header-cell — Listings
    td mat-cell — {{ row.activeListings }}
  ng-container matColumnDef="actions"
    th mat-header-cell — —
    td mat-cell
      button mat-icon-button [routerLink]="['/admin/sellers', row.id]" aria-label="View seller profile"
        mat-icon — visibility
```

> **Note:** `searchControl` debounces 300ms then triggers `GET /admin/sellers?q=[value]&status=[status]` — server-side paginated search, not a client-side filter. Returns paginated results.

---

## Screen 8 — Seller Detail

**Route:** `/admin/sellers/:id`  
**Auth:** ADMIN role

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/admin/sellers" — arrow_back
  h1 mat-h4 — {{ seller.businessName }}
  <aliceut-status-badge [status]="seller.kycStatus" [statusType]="'kyc'">
  <aliceut-status-badge [status]="seller.accountStatus" [statusType]="'seller'">

div.detail-grid [display: grid; grid-template-columns: 1fr 360px; gap: 24px]
  <!-- Left: Profile Info + History -->
  div
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Seller Profile
      mat-list [dense]
        mat-list-item
          mat-icon matListItemIcon — business
          span mat-list-item-title — Business Name
          span matListItemMeta — {{ seller.businessName }}
        mat-list-item
          mat-icon matListItemIcon — mail_outline
          span mat-list-item-title — Email
          span matListItemMeta — {{ seller.email }}
        mat-list-item
          mat-icon matListItemIcon — public
          span mat-list-item-title — Country
          span matListItemMeta — {{ seller.country }}
        mat-list-item
          mat-icon matListItemIcon — calendar_today
          span mat-list-item-title — Registered
          span matListItemMeta — {{ seller.createdAt | date:'mediumDate' }}
        mat-list-item
          mat-icon matListItemIcon — inventory_2
          span mat-list-item-title — Active Listings
          span matListItemMeta — {{ seller.activeListings }}
        mat-list-item
          mat-icon matListItemIcon — delete_outline
          span mat-list-item-title — Removed Listings
          span matListItemMeta — {{ seller.removedListings }}

    <!-- KYC History -->
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — KYC History
      mat-list [dense]
        mat-list-item *ngFor="let kyc of seller.kycHistory"
          mat-icon matListItemIcon [color]="kyc.status === 'APPROVED' ? 'primary' : 'warn'" — {{ kyc.status === 'APPROVED' ? 'check_circle_outline' : 'cancel' }}
          span mat-list-item-title — {{ kyc.status | titlecase }} — {{ kyc.decidedAt | date:'mediumDate' }}
          span mat-list-item-line *ngIf="kyc.reason" — {{ kyc.reason }}
          button mat-button matListItemMeta [routerLink]="['/admin/kyc', kyc.id]" *ngIf="kyc.id" — View
      button mat-stroked-button color="primary" [routerLink]="['/admin/kyc', seller.currentKycId]" *ngIf="seller.kycStatus === 'PENDING_KYC'"
        mat-icon — assignment_ind
        span — Review Current Application

    <!-- Moderation Action History -->
    mat-card [padding: 24px]
      h2 mat-h6 [margin-bottom: 16px] — Moderation History
      <aliceut-data-table [dataSource]="seller.moderationHistory" [loading]="false" emptyMessage="No moderation actions yet.">
        ng-container matColumnDef="action"
          th mat-header-cell — Action
          td mat-cell — <aliceut-status-badge [status]="row.actionType" [statusType]="'listing'">
        ng-container matColumnDef="target"
          th mat-header-cell — Target
          td mat-cell — {{ row.targetTitle || 'Seller account' }}
        ng-container matColumnDef="adminActor"
          th mat-header-cell — Admin
          td mat-cell — {{ row.adminName }}
        ng-container matColumnDef="date"
          th mat-header-cell — Date
          td mat-cell — {{ row.occurredAt | date:'mediumDate' }}
        ng-container matColumnDef="reason"
          th mat-header-cell — Reason
          td mat-cell — {{ row.reason | truncate:60 }}

  <!-- Right: Account Actions -->
  aside
    mat-card [padding: 24px; position: sticky; top: 88px]
      h2 mat-h6 [margin-bottom: 16px] — Account Actions

      <!-- Suspension status display -->
      div *ngIf="seller.accountStatus === 'SUSPENDED'" [margin-bottom: 16px]
        mat-card.error-banner
          mat-icon color="warn" — block
          div
            p mat-body-2 — Currently suspended
            p mat-caption — Reason: {{ seller.suspensionReason }}
            p mat-caption *ngIf="seller.suspendedUntil" — Until: {{ seller.suspendedUntil | date:'mediumDate' }}
            p mat-caption *ngIf="!seller.suspendedUntil" — Permanent suspension
        button mat-flat-button color="primary" [fullWidth] (click)="liftSuspension()" [margin-top: 8px]
          mat-icon — lock_open
          span — Lift Suspension

      <!-- Suspend (only when ACTIVE + KYC_APPROVED) -->
      div *ngIf="seller.accountStatus === 'ACTIVE' && seller.kycStatus === 'APPROVED'"
        form [formGroup]="suspendForm"
          mat-form-field [appearance=outline; fullWidth]
            mat-label — Suspension Duration
            mat-select formControlName="duration"
              mat-option value="7" — 7 days
              mat-option value="30" — 30 days
              mat-option value="90" — 90 days
              mat-option value="permanent" — Permanent
          mat-form-field [appearance=outline; fullWidth; margin-top: 8px]
            mat-label — Reason for suspension *
            textarea matInput formControlName="reason" rows="3" maxlength="500"
            mat-hint align="end" — {{ suspendForm.value.reason?.length || 0 }}/500
          button mat-flat-button color="warn" [fullWidth; margin-top: 12px] [disabled]="suspendForm.invalid || isActing" (click)="suspendSeller()"
            mat-icon — block
            span — Suspend Seller
```

### Suspend Confirmation

`ConfirmDialog` with:
- `danger=true`
- Title: "Suspend {{ seller.businessName }}?"
- Message: "All listings will be deactivated. Pending orders remain active. The seller will be notified by email."
- Extra warning when `duration === 'permanent'`: "This is a permanent suspension. Type the business name to confirm."
- [DESIGN DECISION: For permanent suspension, require the admin to type the seller's business name as a confirmation step to prevent accidental permanent bans.]

### Lift Suspension

`ConfirmDialog` with `requireReason=true`:
- Title: "Lift Suspension?"
- Message: "The seller's account and eligible listings will be reactivated. Enter a reason for reinstatement."
