# Admin Portal — UI Design Specification
## admin-app (port 4202)

**Status:** Complete  
**Stack:** Angular 22+ + Angular Material + the `libs/ui` composites  
**Auth:** Email/password only. JWT with ADMIN role. No self-registration, no OAuth, no password-reset flow.  
**API:** [admin.md](../technical-design/api-design/admin.md), [notifications.md](../technical-design/api-design/notifications.md)

Component contracts are owned by [conventions/design-system.md § 8](../../conventions/design-system.md#8-shared-component-library-libsui); the cross-cutting rules every screen below follows — standalone + OnPush, `ViewState<T>`, reactive forms, cursor pagination, accessibility — are in [shared-components.md § 7](shared-components.md#7-rules-every-screen-follows) and are not repeated per screen.

---

## Summary

- [Shell Layout](#shell-layout)
- [Screen 1 — Admin Login](#screen-1-admin-login)
- [Screen 2 — Admin Dashboard](#screen-2-admin-dashboard)
- [Screen 3 — KYC Queue](#screen-3-kyc-queue)
- [Screen 4 — KYC Application Detail](#screen-4-kyc-application-detail)
- [Screen 5 — Catalog Moderation Queue](#screen-5-catalog-moderation-queue)
- [Screen 6 — Moderation Case Detail](#screen-6-moderation-case-detail)
- [Screen 7 — Seller Management](#screen-7-seller-management)
- [Screen 8 — Seller Detail](#screen-8-seller-detail)
- [Screen 9 — Keyword Blocklist](#screen-9-keyword-blocklist)
- [Screen 10 — Admin Notifications](#screen-10-admin-notifications)

---

## Scope boundary

The admin scope in V1 is **KYC decisions, catalogue moderation and the keyword blocklist** — nothing else. In particular:

- **No admin surface writes inventory.** There is no admin stock screen and no admin stock endpoint; correcting a quantity is the seller's action.
- **No admin catalogue browser.** An admin reaches a listing through a moderation case or through a seller's moderation history, not through a product search of their own.
- **No admin order surface.** Orders belong to the buyer and the seller; the auto-refund monitor handles the ship-by window without an admin screen.

Adding any of these is a scope decision, not a detail.

---

<a id="shell-layout"></a>
## Shell Layout

```
a.skip-link href="#main-content" — Skip to main content     ← first focusable element in the DOM

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
        span matListItemMeta [matBadge]="stats.pendingKyc" [matBadgeHidden]="stats.pendingKyc === 0" matBadgeColor="warn"
      a mat-list-item routerLink="/admin/moderation" routerLinkActive="active"
        mat-icon matListItemIcon — gavel
        span matListItemTitle — Moderation
        span matListItemMeta [matBadge]="stats.openModerationCases" [matBadgeHidden]="stats.openModerationCases === 0" matBadgeColor="warn"
      a mat-list-item routerLink="/admin/sellers" routerLinkActive="active"
        mat-icon matListItemIcon — store
        span matListItemTitle — Sellers
      a mat-list-item routerLink="/admin/keyword-blocklist" routerLinkActive="active"
        mat-icon matListItemIcon — block
        span matListItemTitle — Keyword Blocklist
      mat-divider
      a mat-list-item (click)="logout()"
        mat-icon matListItemIcon — logout
        span matListItemTitle — Sign Out

  mat-sidenav-content
    mat-toolbar [color=primary] [position: sticky; top: 0; z-index: 100]
      button mat-icon-button (click)="drawer.toggle()" *ngIf="!isDesktop" aria-label="Toggle navigation menu"
        mat-icon — menu
      span — Admin Portal
      span.spacer [flex: 1]
      <aliceut-notification-bell
        [notifications]="notifications"
        [unreadCount]="unreadCount"
        (markAsRead)="markRead($event)"
        (markAllRead)="markAllRead()">
      button mat-button [matMenuTriggerFor]="adminMenu"
        mat-icon — account_circle
        span — {{ adminName }}
      mat-menu #adminMenu
        button mat-menu-item (click)="logout()" — logout icon — Sign Out

    main#main-content.admin-content [padding: 24px]
      router-outlet
```

**Material primitives the shell imports directly:** `MatSidenavModule`, `MatToolbarModule`, `MatListModule`, `MatIconModule`, `MatButtonModule`, `MatMenuModule`, `MatBadgeModule`, `MatDividerModule`. `NotificationBellComponent` comes from `@aliceut/shared-ui`; nothing routes a Material module through the barrel.

**Shell data.** Three reads, all on shell init and refreshed on window focus:

| Data | Call |
|---|---|
| Nav badges (`pendingKyc`, `openModerationCases`) | `GET /admin/dashboard/stats` |
| Bell dropdown rows | `GET /notifications?limit=20` |
| Bell badge | `GET /notifications/unread-count` |

The bell also polls on a 60 s interval. There is no WebSocket in V1.

---

<a id="screen-1-admin-login"></a>
## Screen 1 — Admin Login

**Route:** `/admin/login`  
**Guard:** `guestGuard` — an authenticated admin is sent to `/admin/dashboard`

```
div.admin-login-page [display: flex; justify-content: center; align-items: flex-start; padding: 64px 16px; background: grey-50; min-height: 100vh]
  mat-card [width: 100%; max-width: 400px; padding: 40px]
    mat-card-header [text-align: center; margin-bottom: 32px]
      mat-icon [font-size: 56px; color: primary] — admin_panel_settings
      mat-card-title mat-h4 — AliceUT Admin
      mat-card-subtitle — Restricted access — authorised personnel only
    mat-card-content
      form [formGroup]="loginForm" (ngSubmit)="login()"
        mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth; margin-bottom: 16px]
          mat-label — Admin email
          input matInput type="email" formControlName="email" autocomplete="email"
          mat-icon matPrefix — mail_outline
          mat-error *ngIf="loginForm.controls.email.hasError('required')" — Email is required
          mat-error *ngIf="loginForm.controls.email.hasError('email')" — Enter a valid email address
        mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
          mat-label — Password
          input matInput [type]="showPw ? 'text' : 'password'" formControlName="password" autocomplete="current-password"
          button mat-icon-button matSuffix type="button" (click)="showPw = !showPw" aria-label="Toggle password visibility"
            mat-icon — {{ showPw ? 'visibility_off' : 'visibility' }}
          mat-error — Password is required

        mat-card.error-banner *ngIf="loginError" [margin-bottom: 16px]
          mat-icon — error_outline
          span — {{ loginError }}

        button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="loginForm.invalid || isSubmitting"
          mat-spinner *ngIf="isSubmitting" [diameter]="20"
          span *ngIf="!isSubmitting" — Sign In
```

**No register link, no OAuth buttons, no "Forgot password?" link.** Admin accounts are provisioned by the seed script (`admin@aliceut.dev`) and a password change is a direct database update by the developer in V1 — so a reset link would lead nowhere.

**Errors.** A wrong credential and a non-ADMIN account produce the same generic message — "Invalid credentials" — because distinguishing them tells an attacker which emails are admin accounts. A `429` renders as "Too many attempts. Try again in a few minutes."

The response's access token is held in memory by `AuthService`; the refresh token arrives as an HttpOnly cookie scoped to `/api/v1/auth`. Neither is written to `localStorage`, and neither appears in a URL.

### States

| State | Rendering |
|---|---|
| Loading | Submit disabled with an inline spinner; fields stay editable |
| Empty | n/a — a form with no data to fetch |
| Error | `mat-card.error-banner` above the submit button; fields retain their values so the password can be corrected without retyping the email |

---

<a id="screen-2-admin-dashboard"></a>
## Screen 2 — Admin Dashboard

**Route:** `/admin/dashboard`  
**API:** `GET /admin/dashboard/stats`, `GET /admin/kyc?status=PENDING&limit=5`

### Layout

```
h1 mat-h4 — Admin Dashboard
p mat-body-2 color="secondary" — {{ today | date:'fullDate' }}

<!-- Summary stat cards -->
div.stats-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; margin-bottom: 32px]

  mat-card.stat-card [cursor: pointer] (click)="navigate('/admin/kyc', { status: 'PENDING' })"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption — KYC Pending
          p mat-headline-4 — {{ stats.pendingKyc }}
        mat-icon [font-size: 40px; color: amber] — assignment_ind
    mat-card-footer [padding: 8px 16px; background: amber-50]
      span mat-caption — Review applications →

  mat-card.stat-card [cursor: pointer; outline: 2px solid var(--warn)] *ngIf="stats.slaBreach > 0"
                     (click)="navigate('/admin/kyc', { status: 'PENDING' })"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption color="warn" — SLA breaches (over 72 h)
          p mat-headline-4 color="warn" — {{ stats.slaBreach }}
        mat-icon [font-size: 40px] color="warn" — access_time
    mat-card-footer [padding: 8px 16px; background: red-50]
      span mat-caption color="warn" — Oldest applications first →

  mat-card.stat-card [cursor: pointer] (click)="navigate('/admin/moderation', { status: 'OPEN' })"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption — Open moderation cases
          p mat-headline-4 — {{ stats.openModerationCases }}
        mat-icon [font-size: 40px; color: orange] — gavel
    mat-card-footer [padding: 8px 16px; background: orange-50]
      span mat-caption — Moderate catalog →

  mat-card.stat-card
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption — Flagged listings
          p mat-headline-4 — {{ stats.flaggedListings }}
        mat-icon [font-size: 40px; color: orange] — flag
      p mat-caption color="secondary" — Offers currently held out of search

  mat-card.stat-card [cursor: pointer] (click)="navigate('/admin/sellers', { suspensionStatus: 'SUSPENDED' })"
    mat-card-content
      div [display: flex; justify-content: space-between; align-items: center]
        div
          p mat-caption — Suspended sellers
          p mat-headline-4 — {{ stats.activeSuspensions }}
        mat-icon [font-size: 40px; color: deep-orange] — block
    mat-card-footer [padding: 8px 16px]
      span mat-caption — Manage sellers →

<!-- Oldest pending applications -->
div.oldest-pending [margin-top: 8px]
  h2 mat-h5 [margin-bottom: 16px] — Longest-waiting applications
  mat-list
    a mat-list-item *ngFor="let app of oldestPending; trackBy: trackById" [routerLink]="['/admin/kyc', app.id]"
      mat-icon matListItemIcon [color]="app.slaBreached ? 'warn' : undefined" — assignment_ind
      span matListItemTitle — {{ app.businessName }}
      span matListItemLine — {{ app.country }} · submitted {{ app.submittedAt | timeAgo }}
      div matListItemMeta [display: flex; align-items: center; gap: 8px]
        mat-chip *ngIf="app.isResubmission" [color=accent; font-size: 10px] — Resubmit
        mat-chip *ngIf="app.slaBreached" color="warn" [font-size: 10px] — {{ app.daysPending }}d
  <aliceut-empty-state *ngIf="oldestPending.length === 0"
    icon="task_alt" title="No pending applications" message="Every KYC application has been decided.">
```

**Card values map one-to-one onto `GET /admin/dashboard/stats`:** `pendingKyc`, `slaBreach`, `flaggedListings`, `activeSuspensions`, `openModerationCases`. Nothing on this screen is derived, and nothing is counted client-side.

**Two counts that look alike and are not.** `flaggedListings` counts `catalog.offer` rows with `status = 'FLAGGED'`; `openModerationCases` counts `admin.moderation_case` rows with `status = 'OPEN'`. They usually agree but do not have to — a case dismissed while another rule still holds the offer flagged separates them — so the moderation queue is driven by the case count and the flagged count is reported on its own.

**The list under the cards is the queue's own first page.** `GET /admin/kyc` defaults to `submitted_at ASC`, oldest first, which is exactly the triage order US-A-01 asks for, so the five longest-waiting applications need no separate endpoint and no activity feed. There is no audit or activity read in the admin API, and this screen does not imply one.

**`slaBreach` is a count, not a filter.** `GET /admin/kyc` takes `status`, `country`, `sortDir`, `limit` and `cursor` — there is no SLA parameter — so the SLA card navigates to the pending queue, where the default oldest-first order puts breached applications at the top and each carries its own `slaBreached` badge.

### States

| State | Rendering |
|---|---|
| Loading | Five skeleton stat cards and three skeleton list rows |
| Empty | Counts of `0` render normally as `0`; the list renders `EmptyState` "No pending applications" |
| Error | `mat-card.error-banner` in place of the grid with a Retry action. The two reads are independent, so a failure in one leaves the other rendered |

---

<a id="screen-3-kyc-queue"></a>
## Screen 3 — KYC Queue

**Route:** `/admin/kyc`  
**API:** `GET /admin/kyc?status=&country=&sortDir=&limit=&cursor=`

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — KYC Applications

<aliceut-data-table
  [dataSource]="applications" [loading]="loading"
  [hasMore]="hasMore" [hasPrevious]="hasPrevious"
  emptyMessage="No applications match these filters."
  (nextPage)="next()" (previousPage)="previous()" (sortChange)="onSort($event)">

  <!-- Filter slot -->
  ng-template [table-actions]
    mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 180px]
      mat-label — Status
      mat-select [formControl]="statusFilter"
        mat-option value="" — All
        mat-option value="PENDING" — Pending
        mat-option value="UNDER_REVIEW" — Under review
        mat-option value="APPROVED" — Approved
        mat-option value="REJECTED" — Rejected
    mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 180px]
      mat-label — Country
      mat-select [formControl]="countryFilter"
        mat-option value="" — All countries
        mat-option *ngFor="let c of countries; trackBy: trackByCode" [value]="c.code" — {{ c.name }}

  ng-container matColumnDef="businessName"
    th mat-header-cell scope="col" — Business name
    td mat-cell
      div — {{ row.businessName }}
      mat-chip *ngIf="row.isResubmission" [color=accent; font-size: 10px]
        mat-icon [font-size: 12px] — refresh
        span — Resubmit

  ng-container matColumnDef="country"
    th mat-header-cell scope="col" — Country
    td mat-cell — {{ row.country }}

  ng-container matColumnDef="submittedAt"
    th mat-header-cell scope="col" mat-sort-header — Submitted
    td mat-cell — {{ row.submittedAt | date:'mediumDate' }}

  ng-container matColumnDef="daysPending"
    th mat-header-cell scope="col" — Waiting
    td mat-cell
      div [display: flex; align-items: center; gap: 4px]
        span [color]="row.slaBreached ? 'warn' : 'default'" — {{ row.daysPending !== null ? row.daysPending + 'd' : '—' }}
        mat-chip *ngIf="row.slaBreached" color="warn" [font-size: 10px]
          mat-icon [font-size: 12px] — schedule
          span — SLA

  ng-container matColumnDef="status"
    th mat-header-cell scope="col" — Status
    td mat-cell — <aliceut-status-badge [status]="row.status" [statusType]="'kyc'">

  ng-container matColumnDef="actions"
    th mat-header-cell scope="col" — Actions
    td mat-cell
      button mat-flat-button color="primary" [routerLink]="['/admin/kyc', row.id]" — Review

  [header row + row def over the six columns]
</aliceut-data-table>
```

**Every column is a field the list response returns:** `businessName`, `country`, `status`, `submittedAt`, `daysPending`, `slaBreached`, `isResubmission`, plus `id` for the row link. `daysPending` is `null` once an application is decided, which the cell renders as an em dash rather than "0d".

**`status` is the application's `kyc_status`** — `PENDING`, `UNDER_REVIEW`, `APPROVED`, `REJECTED`. It is not the seller profile's `PENDING_KYC | APPROVED | REJECTED`; those are two different enums on two different rows, and this queue lists applications. `UNDER_REVIEW` is offered because the enum defines it, though no V1 endpoint writes it, so the filter returns an empty page until one does.

**No multi-select and no bulk action.** Nothing in the admin API decides more than one KYC application per call, and a KYC decision is a judgement on one business's documents. Bulk removal exists for moderation, where the same violation genuinely spans listings; it has no analogue here.

**Sorting** is limited to the submitted date, which maps to `sortDir` (`asc` default, oldest first). Changing it discards the cursor stack and refetches from the first page, because a cursor is only valid for the sort it was issued under.

### States

| State | Rendering |
|---|---|
| Loading | Five skeleton rows; both paging buttons disabled |
| Empty | `EmptyState` icon `task_alt`, "No pending applications — all caught up." With a filter applied: "No applications match this filter" plus a Clear filters action |
| Error | `mat-card.error-banner` above the table with Retry; the filter controls stay usable |
| Last page | Next disabled with the caption "End of list" |

---

<a id="screen-4-kyc-application-detail"></a>
## Screen 4 — KYC Application Detail

**Route:** `/admin/kyc/:applicationId`  
**API:** `GET /admin/kyc/:applicationId`, `POST /admin/kyc/:applicationId/decide`

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/admin/kyc" aria-label="Back to KYC queue" — arrow_back
  h1 mat-h4 — KYC review: {{ application.seller.businessName }}
  <aliceut-status-badge [status]="application.status" [statusType]="'kyc'">

div.review-grid [display: grid; grid-template-columns: 1fr 380px; gap: 24px]
  <!-- Left: submitted information + documents -->
  div
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Seller account
      mat-list [dense]
        mat-list-item
          mat-icon matListItemIcon — business
          span matListItemTitle — Legal business name
          span matListItemMeta — {{ application.seller.businessName }}
        mat-list-item
          mat-icon matListItemIcon — receipt
          span matListItemTitle — Tax ID
          span matListItemMeta — {{ application.seller.taxId }}
        mat-list-item
          mat-icon matListItemIcon — mail_outline
          span matListItemTitle — Account email
          span matListItemMeta — {{ application.seller.email }}
        mat-list-item
          mat-icon matListItemIcon — schedule
          span matListItemTitle — Submitted
          span matListItemMeta — {{ application.submittedAt | date:'medium' }}

    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 8px] — Submitted business details
      p mat-caption color="secondary" [margin-bottom: 12px] — As entered by the seller.
      mat-list [dense]
        mat-list-item *ngFor="let entry of submittedDataEntries; trackBy: trackByKey"
          span matListItemTitle — {{ entry.label }}
          span matListItemMeta — {{ entry.value }}

    <!-- Documents -->
    mat-card [padding: 24px]
      h2 mat-h6 [margin-bottom: 8px] — Uploaded documents
      mat-card.info-banner [margin-bottom: 16px]
        mat-icon — lock
        span mat-caption — Opening this page is recorded against your account for compliance (NFR-09).
      mat-list
        mat-list-item *ngFor="let doc of application.documentUrls; let i = index; trackBy: trackByIndex"
          mat-icon matListItemIcon — description
          span matListItemTitle — Document {{ i + 1 }}
          a mat-stroked-button matListItemMeta [href]="doc | safe:'url'" download target="_blank" rel="noopener"
            mat-icon — download
            span — Download
      p mat-caption color="secondary" [margin-top: 12px]
        — Links expire five minutes after this page loaded. Reload the page to reissue them.
      <aliceut-empty-state *ngIf="application.documentUrls.length === 0"
        icon="folder_off" title="No documents" message="This application has no uploaded documents.">

  <!-- Right: decision panel -->
  aside
    mat-card [padding: 24px; position: sticky; top: 88px]
      h2 mat-h6 [margin-bottom: 16px] — Review decision

      <!-- Already decided -->
      div *ngIf="application.status !== 'PENDING'" [margin-bottom: 16px]
        <aliceut-status-badge [status]="application.status" [statusType]="'kyc'">
        p mat-body-2 *ngIf="application.decidedAt" — Decided {{ application.decidedAt | date:'medium' }}
        p mat-body-2 *ngIf="application.decisionReason" — Reason: {{ application.decisionReason }}
        p mat-caption color="secondary" — A decided application cannot be re-decided. A rejected seller resubmits, which creates a new application.

      <!-- Pending decision -->
      div *ngIf="application.status === 'PENDING'"
        button mat-flat-button color="primary" [fullWidth] (click)="approve()" [disabled]="isActing" [margin-bottom: 12px]
          mat-icon — check_circle_outline
          span — Approve application

        mat-divider [margin: 12px 0]
          span mat-caption color="secondary" — or

        form [formGroup]="rejectForm" [margin-top: 12px]
          mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
            mat-label — Rejection reason
            textarea matInput formControlName="reason" rows="4" maxlength="500"
            mat-hint align="end" — {{ rejectForm.controls.reason.value.length }}/500
            mat-error — A rejection reason is required and is sent to the seller
          button mat-stroked-button color="warn" [fullWidth] [disabled]="rejectForm.invalid || isActing" (click)="reject()" [margin-top: 8px]
            mat-icon — cancel
            span — Reject application

      mat-spinner *ngIf="isActing" [diameter]="32] [margin: 16px auto; display: block]
```

**The response is nested, and this screen renders it as it arrives.** `seller` is an object carrying `businessName`, `taxId` and `email`; `submittedData` is an **opaque object** the API does not schematise, so the component renders its keys as a label/value list rather than binding named fields that may not be there. `country` is one of those keys — it is what the queue's country filter reads (`submitted_data->>'country'`) and it is an ISO 3166-1 alpha-2 code.

**Documents download; they are never rendered inline.** `documentUrls[]` is an unlabelled array of presigned GETs with a five-minute TTL. There are no labelled "Business licence / Government ID / Bank statement" tabs, because the API does not say which URL is which, and there is no `<iframe>` or `<img>` viewer: an uploaded file is not scanned for malware in V1, so nothing renders or parses those bytes inside a session holding an admin token. Downloading keeps the file out of the browser's rendering path, which is the mitigation that makes the accepted risk acceptable.

The links expire five minutes after the page load that issued them. That is short enough that a copied URL is worthless by the time it could be shared, and the screen says so rather than letting an admin wonder why a link stopped working.

**`taxId` in full, and the read is logged.** The route is ADMIN-only and checking the tax ID against the documents is the purpose of the screen, so it is not redacted here. It is masked in logs and in the audit document, and the seller **list** does not return it at all — this detail read is the single disclosure point, which is what makes one access record per read correct.

**Approve and reject both confirm first.** Approve opens `ConfirmDialog` with title "Approve seller?" and message "They will be able to create listings immediately." Reject opens `ConfirmDialog` echoing the typed reason for a final look; the reason itself is typed in the form above, not in the dialog, because it needs a 500-character counter next to the guidance about what the seller will read.

`POST /admin/kyc/:applicationId/decide` takes `{ decision: 'APPROVED' | 'REJECTED', reason }`. `reason` is required on `REJECTED` and capped at 500 characters. A `409` means another admin decided it first: the screen shows "This application was already decided" and refetches, so the decision panel switches to its decided form rather than offering a button that cannot work.

**A resubmission's history is not on this response.** The queue row carries the `Resubmit` badge and the prior rejection reason; this screen shows the application in front of it.

### States

| State | Rendering |
|---|---|
| Loading | Skeleton list rows in both left cards; the decision panel renders disabled |
| Empty | n/a — a missing application is the error case below |
| Error | `404` renders `EmptyState` icon `search_off`, "Application not found", with a link back to the queue. Any other failure renders the error banner with Retry |
| Acting | Both buttons disabled with a centred spinner; a `409` refetches and re-renders as decided |

---

<a id="screen-5-catalog-moderation-queue"></a>
## Screen 5 — Catalog Moderation Queue

**Route:** `/admin/moderation`  
**API:** `GET /admin/moderation?status=&source=&limit=&cursor=`, `POST /admin/moderation`, `POST /admin/moderation/:caseId/decide`, `POST /admin/moderation/bulk-remove`

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — Catalog moderation
  button mat-stroked-button (click)="openManualFlagDialog()"
    mat-icon — flag
    span — Flag a listing

div [display: flex; gap: 12px; align-items: center; flex-wrap: wrap; margin-bottom: 16px]
  mat-chip-listbox [formControl]="statusFilter" aria-label="Case status filter"
    mat-chip-option value="OPEN" — Open
    mat-chip-option value="RESOLVED" — Resolved
    mat-chip-option value="DISMISSED" — Dismissed
  mat-chip-listbox [formControl]="sourceFilter" aria-label="Flag source filter"
    mat-chip-option value="KEYWORD_MATCH" — Keyword match
    mat-chip-option value="PROHIBITED_CATEGORY" — Prohibited category
    mat-chip-option value="ADMIN_MANUAL" — Flagged by an admin

<aliceut-data-table
  [dataSource]="cases" [loading]="loading"
  [hasMore]="hasMore" [hasPrevious]="hasPrevious"
  emptyMessage="No cases match these filters."
  (nextPage)="next()" (previousPage)="previous()"
  (sortChange)="onSort($event)" (selectionChange)="selected = $event">

  ng-container matColumnDef="select"
    th mat-header-cell scope="col"
      mat-checkbox [formControl]="selectAllControl" aria-label="Select all cases on this page"
    td mat-cell
      mat-checkbox [checked]="selection.isSelected(row)" (change)="selection.toggle(row)"
        [aria-label]="'Select case for ' + row.productTitle"

  ng-container matColumnDef="product"
    th mat-header-cell scope="col" — Listing
    td mat-cell
      p mat-body-2 — {{ row.productTitle }}
      p mat-caption color="secondary" — by {{ row.sellerName }}

  ng-container matColumnDef="reason"
    th mat-header-cell scope="col" — Why it was flagged
    td mat-cell
      mat-chip [color]="sourceChipColor(row.source)" [font-size: 10px] — {{ sourceLabel(row.source) }}
      p mat-caption color="warn" [margin-top: 4px] — {{ row.reason | truncate:80 }}
      p mat-caption color="secondary" [margin-top: 4px] — {{ row.descriptionSnippet | truncate:120 }}

  ng-container matColumnDef="caseStatus"
    th mat-header-cell scope="col" — Case
    td mat-cell
      mat-chip [class]="'case-' + row.status.toLowerCase()" [font-size: 10px] — {{ caseStatusLabel(row.status) }}

  ng-container matColumnDef="createdAt"
    th mat-header-cell scope="col" mat-sort-header — Flagged
    td mat-cell — {{ row.createdAt | date:'mediumDate' }}

  ng-container matColumnDef="actions"
    th mat-header-cell scope="col" — Actions
    td mat-cell
      button mat-stroked-button [routerLink]="['/admin/moderation', row.id]" [margin-right: 8px] — Review
      button mat-flat-button color="warn" (click)="removeOne(row)" [disabled]="row.status !== 'OPEN'" — Remove

  [header row + row def over the six columns]
</aliceut-data-table>

<!-- Bulk action bar — shown when the selection is non-empty -->
div.bulk-action-bar *ngIf="selected.length > 0"
  span — {{ selected.length }} case(s) selected
  button mat-stroked-button color="warn" (click)="openBulkRemoveDialog()" — Remove selected
  button mat-button (click)="selection.clear()" — Clear selection
```

**Every field is one the list response returns:** `id`, `offerId`, `productId`, `productTitle`, `descriptionSnippet`, `sellerProfileId`, `sellerName`, `reason`, `source`, `status`, `createdAt`. There is no thumbnail column — the moderation list carries no image field, and catalogue images are storage keys rather than URLs.

**`createdAt` is the flag time.** `admin.moderation_case` has no separate `flagged_at` column, so the queue sorts on `created_at DESC` (newest flag first) and the column is labelled "Flagged" while binding `createdAt`. The two names never both appear.

**Three flag sources, and one of them is an admin.** `source` is the `moderation_source` enum complete: `KEYWORD_MATCH` and `PROHIBITED_CATEGORY` are raised automatically at listing time, and `ADMIN_MANUAL` is raised by an admin through the "Flag a listing" action. Buyer reports are deferred to V2 — there is no fourth value and no "auto" umbrella value, because "auto" is two distinct rules an admin needs to tell apart.

**Case status is a labelled chip, not a `StatusBadge`.** `OPEN | RESOLVED | DISMISSED` is a moderation-case vocabulary, and `StatusBadge`'s `statusType` union covers order, fulfillment, KYC, listing and seller statuses only. Feeding case statuses to the `listing` type would colour a resolved case as if it described the offer, which it does not — a removed listing's case is `RESOLVED` with `decision = REMOVE`, and `REMOVED` is never a case status. The chip carries a text label so state does not rest on colour alone.

**`openManualFlagDialog()`** opens a small `MatDialog` taking an **offer id** and a required reason (≤ 500 chars), and calls `POST /admin/moderation { offerId, reason }`. `source` is not sent — the server stamps `ADMIN_MANUAL`, since a flag raised through an ADMIN route is by definition an admin flag. A `409` means the offer already has an open case, which the dialog reports with a link to it. The other entry point is the row action on a seller's moderation history (Screen 8), where an `offerId` is already in hand.

**`removeOne(row)`** opens `ConfirmDialog` with `requireReason: true` and `danger: true`, then calls `POST /admin/moderation/:caseId/decide { decision: 'REMOVE', reason }` with the reason from the dialog result. The reason is mandatory because the seller is told which rule was broken. Only an `OPEN` case can be decided, so the button is disabled otherwise.

**`openBulkRemoveDialog()`** opens `BulkRemoveDialogComponent` with two modes, chosen by a radio group at the top:

- **One reason for all** — a single reason textarea, sent as `sharedReason`.
- **A reason per case** — a row per selected case, each with its own reason textarea, sent as `cases[].reason`.

Submit calls `POST /admin/moderation/bulk-remove { cases: [{ caseId, reason }], sharedReason }`. At most 100 cases per request; the dialog blocks a larger selection with a message rather than sending it. A case with neither its own nor a shared reason is a `400`, so Submit stays disabled until every selected case resolves a reason.

There is no removal-category dropdown. The decide and bulk-remove bodies accept one `reason` string, and a category select would produce a value the API has nowhere to put.

**The response is per case, so a partial failure is legible.** `{ removed, failed, results[] }` — each result is either `REMOVED` with its `offerId` and `productRemoved` flag, or `SKIPPED` with code `CONFLICT` when another admin decided it between the render and the submit. The dialog reports both tallies and lists the skipped rows; the successful removals stand. The queue then refetches from the first page, because the removed rows invalidated the cursor.

### States

| State | Rendering |
|---|---|
| Loading | Five skeleton rows; the bulk bar is hidden and both paging buttons are disabled |
| Empty | `EmptyState` icon `verified`, "No flagged listings — catalog is clean." With filters applied: "No cases match these filters" plus Clear filters |
| Error | Error banner above the table with Retry; the chips stay usable |
| Acting | The acted-on row shows an inline spinner and its buttons disable; the rest of the table stays interactive |
| Last page | Next disabled with "End of list" |

---

<a id="screen-6-moderation-case-detail"></a>
## Screen 6 — Moderation Case Detail

**Route:** `/admin/moderation/:caseId`  
**API:** `GET /admin/moderation/:caseId`, `POST /admin/moderation/:caseId/decide`

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/admin/moderation" aria-label="Back to moderation queue" — arrow_back
  h1 mat-h4 — Moderation case
  mat-chip [class]="'case-' + case.status.toLowerCase()" — {{ caseStatusLabel(case.status) }}

div.case-grid [display: grid; grid-template-columns: 1fr 360px; gap: 24px]
  <!-- Left: what was flagged -->
  div
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — Listing
      mat-list [dense]
        mat-list-item
          mat-icon matListItemIcon — inventory_2
          span matListItemTitle — Product
          span matListItemMeta — {{ case.productTitle }}
        mat-list-item
          mat-icon matListItemIcon — storefront
          span matListItemTitle — Seller
          a matListItemMeta [routerLink]="['/admin/sellers', case.sellerProfileId]" — {{ case.sellerName }}
        mat-list-item
          mat-icon matListItemIcon — sell
          span matListItemTitle — Offer
          span matListItemMeta [font-family: monospace] — {{ case.offerId }}

    mat-card [padding: 24px]
      h2 mat-h6 [margin-bottom: 12px] — Flag details
      mat-list [dense]
        mat-list-item
          mat-icon matListItemIcon color="warn" — flag
          span matListItemTitle — Source
          span matListItemMeta — {{ sourceLabel(case.source) }}
        mat-list-item
          mat-icon matListItemIcon — schedule
          span matListItemTitle — Flagged at
          span matListItemMeta — {{ case.createdAt | date:'medium' }}
      div.reason-text [margin-top: 12px; padding: 12px; background: grey-50; border-radius: 4px]
        p mat-caption color="secondary" — Reason recorded on the case
        p mat-body-2 — {{ case.reason }}

  <!-- Right: action panel -->
  aside
    mat-card [padding: 24px; position: sticky; top: 88px]
      h2 mat-h6 [margin-bottom: 16px] — Take action

      <!-- Already decided -->
      div *ngIf="case.status !== 'OPEN'"
        mat-chip [class]="'case-' + case.status.toLowerCase()" — {{ caseStatusLabel(case.status) }}
        p mat-body-2 [margin-top: 8px] *ngIf="case.decision" — Decision: {{ case.decision === 'REMOVE' ? 'Listing removed' : 'Flag dismissed' }}
        p mat-body-2 *ngIf="case.decidedAt" — Decided {{ case.decidedAt | date:'medium' }}
        p mat-body-2 *ngIf="case.decidedByUserId" — By admin {{ case.decidedByUserId }}
        p mat-body-2 *ngIf="case.reason" — Reason: {{ case.reason }}
        p mat-caption color="secondary" [margin-top: 8px] *ngIf="case.decision === 'REMOVE'"
          — Removal is final. The seller cannot reactivate the listing and may create a new compliant one instead.

      <!-- Open case -->
      div *ngIf="case.status === 'OPEN'"
        h3 mat-body-1 [font-weight: 500; margin-bottom: 8px] — Remove the listing
        form [formGroup]="removeForm"
          mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
            mat-label — Removal reason
            textarea matInput formControlName="reason" rows="4" maxlength="500"
            mat-hint align="end" — {{ removeForm.controls.reason.value.length }}/500
            mat-error — A removal reason is required and is sent to the seller
          mat-card.info-banner [margin-top: 8px]
            mat-icon — mail_outline
            span mat-caption — The seller receives this reason in the daily removal digest (ET-09).
          button mat-flat-button color="warn" [fullWidth; margin-top: 12px]
                 [disabled]="removeForm.invalid || isActing" (click)="remove()"
            mat-icon — delete_outline
            span — Remove listing

        mat-divider [margin: 16px 0]
          span mat-caption color="secondary" — or

        form [formGroup]="dismissForm" [margin-top: 12px]
          mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
            mat-label — Note (optional)
            textarea matInput formControlName="reason" rows="2" maxlength="500"
            mat-hint align="end" — {{ dismissForm.controls.reason.value.length }}/500
          mat-card.info-banner [margin-top: 8px]
            mat-icon — info_outline
            span mat-caption — Dismissing returns the listing to Active and stops the same term flagging this offer again.
          button mat-stroked-button color="primary" [fullWidth; margin-top: 8px] [disabled]="isActing" (click)="dismiss()"
            mat-icon — check_circle_outline
            span — Dismiss flag (listing is compliant)
```

**Case status values are `OPEN | RESOLVED | DISMISSED`**, and `decision` is `REMOVE | DISMISS | null`. A case is decided exactly once: `REMOVE` sets the case `RESOLVED` and the offer `REMOVED`; `DISMISS` sets the case `DISMISSED` and returns the offer to `ACTIVE` with its `statusChangedReason` cleared. A second decision is `409`, which this screen reports as "This case was already decided" and then refetches.

**One `reason` field per decision, not a category plus a note.** `POST /admin/moderation/:caseId/decide` takes `{ decision, reason }`. `reason` is required for `REMOVE` — the seller is told which rule was broken — and optional for `DISMISS`, since nothing happened to their listing. Both are capped at 500 characters.

**Dismissal suppresses the terms it cleared.** The case keeps the terms that tripped the scan, and the listing-time keyword scan afterwards skips that `(offer, term)` pair, so the seller's next edit does not reopen the identical case. Suppression is per term: a term never dismissed still flags the offer normally. A `REMOVE` suppresses nothing, because the offer is terminal. The dismiss panel states this, because an admin needs to know that clearing a false positive is durable.

**Removal can cascade to the product.** When no non-`REMOVED` offer remains on the product, the product row is removed too and the response's `productRemoved` is `true` — the confirmation snackbar says so. A product another seller still lists is left alone: one seller's violation is not the other's.

**Removal does not touch orders.** Pending unshipped orders on a removed listing stay active and the seller remains responsible for fulfilling them. The panel says this so an admin does not expect a removal to cancel anything.

### States

| State | Rendering |
|---|---|
| Loading | Skeleton list rows on the left; the action panel renders disabled |
| Empty | n/a |
| Error | `404` renders `EmptyState` "Case not found" with a link back to the queue; other failures render the error banner with Retry |
| Acting | Both buttons disabled with a spinner; a `409` refetches and re-renders as decided |

---

<a id="screen-7-seller-management"></a>
## Screen 7 — Seller Management

**Route:** `/admin/sellers`  
**API:** `GET /admin/sellers?kycStatus=&suspensionStatus=&q=&limit=&cursor=`

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — Sellers

<aliceut-data-table
  [dataSource]="sellers" [loading]="loading"
  [hasMore]="hasMore" [hasPrevious]="hasPrevious"
  emptyMessage="No sellers match these filters."
  (nextPage)="next()" (previousPage)="previous()" (sortChange)="onSort($event)">

  <!-- Filter slot -->
  ng-template [table-actions]
    div.table-actions [display: flex; gap: 12px; flex-wrap: wrap; align-items: flex-end]
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 320px]
        mat-label — Search business name, email or tax ID
        input matInput [formControl]="searchControl"
        mat-icon matSuffix — search
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 180px]
        mat-label — KYC status
        mat-select [formControl]="kycStatusFilter"
          mat-option value="" — All
          mat-option value="PENDING_KYC" — Pending KYC
          mat-option value="APPROVED" — Approved
          mat-option value="REJECTED" — Rejected
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 180px]
        mat-label — Account
        mat-select [formControl]="suspensionStatusFilter"
          mat-option value="" — All
          mat-option value="ACTIVE" — Active
          mat-option value="SUSPENDED" — Suspended

  ng-container matColumnDef="businessName"
    th mat-header-cell scope="col" mat-sort-header — Business name
    td mat-cell — {{ row.businessName }}
  ng-container matColumnDef="email"
    th mat-header-cell scope="col" — Email
    td mat-cell — {{ row.email }}
  ng-container matColumnDef="country"
    th mat-header-cell scope="col" — Country
    td mat-cell — {{ row.country }}
  ng-container matColumnDef="createdAt"
    th mat-header-cell scope="col" mat-sort-header — Registered
    td mat-cell — {{ row.createdAt | date:'mediumDate' }}
  ng-container matColumnDef="kycStatus"
    th mat-header-cell scope="col" — KYC
    td mat-cell — <aliceut-status-badge [status]="row.kycStatus" [statusType]="'kyc'">
  ng-container matColumnDef="suspensionStatus"
    th mat-header-cell scope="col" — Account
    td mat-cell
      <aliceut-status-badge [status]="row.suspensionStatus" [statusType]="'seller'">
      p mat-caption color="secondary" *ngIf="row.suspendedUntil" — until {{ row.suspendedUntil | date:'mediumDate' }}
  ng-container matColumnDef="listings"
    th mat-header-cell scope="col" — Listings
    td mat-cell
      span — {{ row.activeListingsCount }} active
      span mat-caption color="secondary" *ngIf="row.removedListingsCount > 0" — · {{ row.removedListingsCount }} removed
  ng-container matColumnDef="actions"
    th mat-header-cell scope="col" — Actions
    td mat-cell
      button mat-icon-button [routerLink]="['/admin/sellers', row.id]" aria-label="View seller profile"
        mat-icon — visibility

  [header row + row def over the eight columns]
</aliceut-data-table>
```

**Two independent status filters, not one merged select.** `kycStatus` and `suspensionStatus` are separate query parameters because they are separate columns: a suspended seller can be KYC-approved, and an approved one can be suspended. A single select offering `ACTIVE | SUSPENDED | PENDING_KYC` cannot express "approved and suspended", which is exactly the combination an admin most often looks for.

**No tax ID column.** `q` still searches `tax_id` — it matches against a value the admin already holds — but the list response does not return one. A paginated queue returning full tax IDs would spread PII across every page load and would need an access record per returned row to stay honest; keeping the value on the detail screen makes that read the single disclosure point and one record per access correct. No record is written for a search, because a search discloses no tax ID back.

**`searchControl` is server-side.** It debounces 300 ms and refetches `GET /admin/sellers?q=…` from the first page, discarding the cursor stack. It is not a client-side filter over the loaded page — with cursor pagination that would search twenty rows and look like an empty result.

### States

| State | Rendering |
|---|---|
| Loading | Five skeleton rows; paging disabled |
| Empty | `EmptyState` icon `storefront`, "No sellers yet." With filters or a search term: "No sellers match these filters" plus Clear filters |
| Error | Error banner above the table with Retry; filters stay usable |
| Last page | Next disabled with "End of list" |

---

<a id="screen-8-seller-detail"></a>
## Screen 8 — Seller Detail

**Route:** `/admin/sellers/:sellerProfileId`  
**API:** `GET /admin/sellers/:sellerProfileId`, `POST /admin/sellers/:sellerProfileId/suspend`, `POST /admin/sellers/:sellerProfileId/reinstate`, `POST /admin/moderation`

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/admin/sellers" aria-label="Back to seller list" — arrow_back
  h1 mat-h4 — {{ seller.businessName }}
  <aliceut-status-badge [status]="seller.kycStatus" [statusType]="'kyc'">
  <aliceut-status-badge [status]="seller.suspensionStatus" [statusType]="'seller'">

div.detail-grid [display: grid; grid-template-columns: 1fr 360px; gap: 24px]
  <!-- Left: profile + history -->
  div
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 8px] — Seller profile
      mat-card.info-banner [margin-bottom: 16px]
        mat-icon — lock
        span mat-caption — This page shows the seller's tax ID. Opening it is recorded against your account (NFR-09).
      mat-list [dense]
        mat-list-item
          mat-icon matListItemIcon — business
          span matListItemTitle — Business name
          span matListItemMeta — {{ seller.businessName }}
        mat-list-item
          mat-icon matListItemIcon — receipt
          span matListItemTitle — Tax ID
          span matListItemMeta — {{ seller.taxId }}
        mat-list-item
          mat-icon matListItemIcon — mail_outline
          span matListItemTitle — Email
          span matListItemMeta — {{ seller.email }}
        mat-list-item
          mat-icon matListItemIcon — public
          span matListItemTitle — Country
          span matListItemMeta — {{ seller.country }}
        mat-list-item
          mat-icon matListItemIcon — calendar_today
          span matListItemTitle — Registered
          span matListItemMeta — {{ seller.createdAt | date:'mediumDate' }}
        mat-list-item
          mat-icon matListItemIcon — inventory_2
          span matListItemTitle — Active listings
          span matListItemMeta — {{ seller.activeListingsCount }}
        mat-list-item
          mat-icon matListItemIcon — delete_outline
          span matListItemTitle — Removed listings
          span matListItemMeta — {{ seller.removedListingsCount }}

    <!-- KYC standing -->
    mat-card [padding: 24px; margin-bottom: 16px]
      h2 mat-h6 [margin-bottom: 16px] — KYC standing
      div [display: flex; align-items: center; gap: 12px]
        <aliceut-status-badge [status]="seller.kycStatus" [statusType]="'kyc'">
        p mat-body-2 *ngIf="seller.kycStatus === 'REJECTED' && seller.rejectionReason" — Last rejection: {{ seller.rejectionReason }}
      p mat-caption color="secondary" [margin-top: 8px]
        — This is the seller profile's current standing. It moves back to Pending KYC whenever they resubmit, and it is independent of the account's suspension state.
      p mat-body-2 [margin-top: 8px] *ngIf="seller.kycStatus === 'PENDING_KYC'"
        — An application is awaiting review. Open the KYC queue to find it.
      a mat-stroked-button routerLink="/admin/kyc" [queryParams]="{ status: 'PENDING' }" *ngIf="seller.kycStatus === 'PENDING_KYC'"
        mat-icon — assignment_ind
        span — Go to KYC queue

    <!-- Moderation history -->
    mat-card [padding: 24px]
      h2 mat-h6 [margin-bottom: 16px] — Moderation history
      table mat-table [dataSource]="seller.moderationHistory"
        ng-container matColumnDef="type"
          th mat-header-cell scope="col" — Action
          td mat-cell — {{ moderationTypeLabel(row.type) }}
        ng-container matColumnDef="product"
          th mat-header-cell scope="col" — Listing
          td mat-cell — {{ row.productTitle }}
        ng-container matColumnDef="actor"
          th mat-header-cell scope="col" — By
          td mat-cell
            span — {{ row.actor.role === 'PLATFORM' ? 'Platform (automatic)' : 'Admin' }}
            span mat-caption color="secondary" *ngIf="row.actor.userId" — {{ row.actor.userId }}
        ng-container matColumnDef="occurredAt"
          th mat-header-cell scope="col" — When
          td mat-cell — {{ row.occurredAt | date:'mediumDate' }}
        ng-container matColumnDef="reason"
          th mat-header-cell scope="col" — Reason
          td mat-cell — {{ row.reason | truncate:60 }}
        ng-container matColumnDef="actions"
          th mat-header-cell scope="col" — Actions
          td mat-cell
            button mat-icon-button (click)="flagListing(row.offerId, row.productTitle)"
              [matTooltip]="'Flag this listing'" aria-label="Flag this listing"
              mat-icon — flag
        [header row + row def]
      <aliceut-empty-state *ngIf="seller.moderationHistory.length === 0"
        icon="gavel" title="No moderation actions" message="Nothing has been flagged or removed for this seller.">

  <!-- Right: account actions -->
  aside
    mat-card [padding: 24px; position: sticky; top: 88px]
      h2 mat-h6 [margin-bottom: 16px] — Account actions

      <!-- Currently suspended -->
      div *ngIf="seller.suspensionStatus === 'SUSPENDED'" [margin-bottom: 16px]
        mat-card.error-banner
          mat-icon color="warn" — block
          div
            p mat-body-2 — Currently suspended
            p mat-caption — Reason: {{ seller.suspensionReason }}
            p mat-caption *ngIf="seller.suspendedUntil" — Until {{ seller.suspendedUntil | date:'medium' }}
            p mat-caption *ngIf="!seller.suspendedUntil" — Permanent suspension
        button mat-flat-button color="primary" [fullWidth; margin-top: 8px] (click)="reinstate()" [disabled]="isActing"
          mat-icon — lock_open
          span — Lift suspension
        div *ngIf="seller.suspendedUntil" [margin-top: 16px]
          p mat-caption color="secondary" — Extending replaces the current end date rather than adding a second suspension.
          form [formGroup]="extendForm"
            mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
              mat-label — Extend to
              mat-select formControlName="durationDays"
                mat-option [value]="7" — 7 days from now
                mat-option [value]="30" — 30 days from now
                mat-option [value]="90" — 90 days from now
                mat-option [value]="null" — Permanent
            mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth; margin-top: 8px]
              mat-label — Reason
              textarea matInput formControlName="reason" rows="3" maxlength="500"
              mat-hint align="end" — {{ extendForm.controls.reason.value.length }}/500
              mat-error — A reason is required
            button mat-stroked-button color="warn" [fullWidth; margin-top: 8px]
                   [disabled]="extendForm.invalid || isActing" (click)="extendSuspension()"
              span — Extend suspension

      <!-- Not suspended -->
      div *ngIf="seller.suspensionStatus === 'ACTIVE'"
        form [formGroup]="suspendForm"
          mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
            mat-label — Suspension duration
            mat-select formControlName="durationDays"
              mat-option [value]="7" — 7 days
              mat-option [value]="30" — 30 days
              mat-option [value]="90" — 90 days
              mat-option [value]="null" — Permanent
          mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth; margin-top: 8px]
            mat-label — Reason for suspension
            textarea matInput formControlName="reason" rows="3" maxlength="500"
            mat-hint align="end" — {{ suspendForm.controls.reason.value.length }}/500
            mat-error — A reason is required and is sent to the seller
          button mat-flat-button color="warn" [fullWidth; margin-top: 12px]
                 [disabled]="suspendForm.invalid || isActing" (click)="suspendSeller()"
            mat-icon — block
            span — Suspend seller
```

**Field names come straight from the detail response:** `businessName`, `taxId`, `email`, `country`, `kycStatus`, `suspensionStatus`, `suspendedUntil`, `suspensionReason`, `rejectionReason`, `activeListingsCount`, `removedListingsCount`, `createdAt`, `moderationHistory[]`. There is no `accountStatus` field — account state is `suspensionStatus`, and KYC state is `kycStatus`; the two are rendered as two badges because they are two columns.

**`moderationHistory[]` is a plain array on the response, so it is a plain `mat-table`.** Each entry is `{ type, occurredAt, actor: { userId, role }, offerId, productTitle, reason }`, ordered newest first. `actor.role` is `PLATFORM` with a `null` `userId` for an automatic flag — no person raised it — and `ADMIN` with the acting admin's user id otherwise. It is not wrapped in `DataTable`: a fixed array has no cursor, so a paginated footer would render controls that can never do anything.

**Suspension history is not on this response.** The three suspension fields describe the *current* suspension only, and `suspension_reason` is overwritten on each new suspension. The full trail lives in the audit stream; V1 has no suspension-history table and this screen does not pretend to one.

**KYC history is not on this response either.** The screen shows the profile's current standing plus the last rejection reason, and links to the KYC queue rather than to a specific application, because the detail response carries no application id.

**Suspend is offered whenever the account is `ACTIVE`**, whatever the KYC status. US-A-05 does not restrict suspension to approved sellers, and a seller abusing the platform before approval is exactly a case an admin needs to act on.

**Durations are `7`, `30`, `90` or `null`.** `null` means permanent, and the API rejects any other value with `422`.

**Suspend confirmation.** `ConfirmDialog`, `danger: true`, title "Suspend {{ businessName }}?", message "Their active listings are deactivated and de-indexed. Pending orders stay active and remain their responsibility, and they keep access to the order list and the ship action so they can discharge them. They are notified by email." When the duration is Permanent the message additionally reads "This suspension has no end date and can only be lifted manually." The dialog's `requireReason` is not used here, because the reason is already typed in the form with its counter and its guidance.

**Extending is the same endpoint.** A timed suspension re-submitted updates `suspended_until` and the reason on the existing row rather than creating a second one, and a timed suspension may be extended to permanent. A **permanently** suspended seller cannot be re-suspended — the API answers `409` "Seller is already permanently suspended" — so no extend form is offered in that case.

**Lift suspension** opens `ConfirmDialog` with `requireReason: true`, title "Lift suspension?", message "The account is reactivated and listings deactivated by this suspension return. Enter a reason for reinstatement." The reason from the dialog result is sent to `POST /admin/sellers/:sellerProfileId/reinstate { reason }`, where it is mandatory — a reinstatement overrides a previous admin decision, so the justification is recorded with it. Listings an admin **removed** under moderation stay removed: lifting a suspension is not a review of an independent content decision, and the dialog says so.

**`flagListing(offerId, title)`** opens the same manual-flag dialog as the moderation queue, pre-filled with the offer id from the history row, and calls `POST /admin/moderation { offerId, reason }`. This is the second of the two entry points for an admin-raised flag.

Every action here changes a claim in the seller's live access token, so the seller's next request refreshes and receives the new status rather than continuing on the old one for up to fifteen minutes. The confirmation snackbar says the change is effective immediately.

### States

| State | Rendering |
|---|---|
| Loading | Skeleton list rows in each left card; the action panel renders disabled |
| Empty | The moderation history renders `EmptyState`; the profile itself is never empty |
| Error | `404` renders `EmptyState` "Seller not found" with a link back to the list; other failures render the error banner with Retry |
| Acting | The acting button disables with a spinner; on success the screen refetches so both badges and the action panel reflect the new state. A `409` — already permanently suspended, or not currently suspended — refetches and reports the current state |

---

<a id="screen-9-keyword-blocklist"></a>
## Screen 9 — Keyword Blocklist

**Route:** `/admin/keyword-blocklist`  
**API:** `GET /admin/keyword-blocklist`, `POST /admin/keyword-blocklist`, `PATCH /admin/keyword-blocklist/:termId`, `DELETE /admin/keyword-blocklist/:termId`

The listing-time blocklist is an admin-editable table, so adding a newly-abused term does not require a deployment.

### Layout

```
div.page-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px]
  h1 mat-h4 — Keyword blocklist
  button mat-flat-button color="primary" (click)="openAddDialog()"
    mat-icon — add
    span — Add term

mat-card.info-banner [margin-bottom: 16px]
  mat-icon — schedule
  span mat-body-2 — A change takes effect on the listing guard's next cache refresh, within about a minute — not instantly.

<aliceut-data-table
  [dataSource]="terms" [loading]="loading"
  [hasMore]="hasMore" [hasPrevious]="hasPrevious"
  emptyMessage="No terms match these filters."
  (nextPage)="next()" (previousPage)="previous()">

  ng-template [table-actions]
    div [display: flex; gap: 12px; flex-wrap: wrap; align-items: flex-end]
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 240px]
        mat-label — Search term
        input matInput [formControl]="searchControl"
        mat-icon matSuffix — search
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 180px]
        mat-label — Category
        mat-select [formControl]="categoryFilter"
          mat-option value="" — All
          mat-option value="WEAPONS" — Weapons
          mat-option value="DRUGS" — Drugs
          mat-option value="ADULT" — Adult
          mat-option value="OTHER" — Other
      mat-form-field [appearance=outline; subscriptSizing=dynamic; width: 160px]
        mat-label — Active
        mat-select [formControl]="isActiveFilter"
          mat-option value="" — All
          mat-option value="true" — Active only
          mat-option value="false" — Inactive only

  ng-container matColumnDef="term"
    th mat-header-cell scope="col" — Term
    td mat-cell [font-family: monospace] — {{ row.term }}
  ng-container matColumnDef="matchType"
    th mat-header-cell scope="col" — Match
    td mat-cell — {{ matchTypeLabel(row.matchType) }}
  ng-container matColumnDef="category"
    th mat-header-cell scope="col" — Category
    td mat-cell — <mat-chip [font-size: 10px] — {{ categoryLabel(row.category) }}
  ng-container matColumnDef="isActive"
    th mat-header-cell scope="col" — Status
    td mat-cell
      mat-chip [class]="row.isActive ? 'badge-success' : 'badge-inactive'" [font-size: 10px]
        — {{ row.isActive ? 'Active' : 'Inactive' }}
  ng-container matColumnDef="createdBy"
    th mat-header-cell scope="col" — Added by
    td mat-cell
      span — {{ row.createdByName }}
      p mat-caption color="secondary" — {{ row.createdAt | date:'mediumDate' }}
  ng-container matColumnDef="actions"
    th mat-header-cell scope="col" — Actions
    td mat-cell
      button mat-icon-button (click)="openEditDialog(row)" aria-label="Edit term" [matTooltip]="'Edit'"
        mat-icon — edit
      button mat-icon-button color="warn" (click)="deactivate(row)" *ngIf="row.isActive"
              aria-label="Deactivate term" [matTooltip]="'Deactivate'"
        mat-icon — block
      button mat-icon-button (click)="reactivate(row)" *ngIf="!row.isActive"
              aria-label="Reactivate term" [matTooltip]="'Reactivate'"
        mat-icon — undo

  [header row + row def over the six columns]
</aliceut-data-table>
```

### Add / edit dialog

```
mat-dialog-title — {{ isEdit ? 'Edit term' : 'Add blocklist term' }}
mat-dialog-content
  form [formGroup]="termForm"
    mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
      mat-label — Term
      input matInput formControlName="term" maxlength="100"
      mat-hint — 2–100 characters
      mat-error *ngIf="termForm.controls.term.hasError('required')" — A term is required
      mat-error *ngIf="termForm.controls.term.hasError('minlength')" — At least 2 characters
    mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
      mat-label — Match type
      mat-select formControlName="matchType"
        mat-option value="SUBSTRING" — Substring — matches anywhere in the text
        mat-option value="WORD" — Whole word
        mat-option value="REGEX" — Regular expression
    mat-form-field [appearance=outline; subscriptSizing=dynamic; fullWidth]
      mat-label — Category
      mat-select formControlName="category"
        mat-option value="WEAPONS" — Weapons
        mat-option value="DRUGS" — Drugs
        mat-option value="ADULT" — Adult
        mat-option value="OTHER" — Other
    mat-checkbox formControlName="isActive" *ngIf="isEdit" — Active
    mat-card.warning-banner *ngIf="termForm.value.matchType === 'REGEX'"
      mat-icon — warning_amber
      span mat-caption — A regular expression is compiled and checked before it is stored. A pattern that cannot compile, or that is not linear-time on its input, is rejected — the guard runs on every listing save.
mat-dialog-actions [align=end]
  button mat-button mat-dialog-close — Cancel
  button mat-flat-button color="primary" [disabled]="termForm.invalid || isSaving" (click)="save()"
    mat-spinner *ngIf="isSaving" [diameter]="20"
    span *ngIf="!isSaving" — {{ isEdit ? 'Save' : 'Add term' }}
```

**Deactivate, never delete.** `DELETE /admin/keyword-blocklist/:termId` sets `isActive = false` and keeps the row, so every past moderation case whose reason names the term still resolves and the audit trail behind a removal stays readable years later. Reactivating is `PATCH … { isActive: true }` on the same row — a term is never re-created, which is why the row action offers Reactivate rather than Add for an inactive term. Inactive terms are listed by default for the same reason.

**Errors surfaced in the dialog:** `409` on a duplicate `(term, matchType)` — "This term already exists with that match type" — and `422` on an uncompilable or unsafe regex, reported against the term field rather than as a page-level failure.

**Adding a term does not rescan the catalogue.** A new term applies at the next listing or edit save; live listings are not retroactively flagged, and there is no rescan job in V1. The add dialog's confirmation snackbar says so, because "the term is now blocked" invites the opposite inference.

`id` on a blocklist row is a numeric `BIGSERIAL` key, not a UUID — the only id in the admin portal that is.

### States

| State | Rendering |
|---|---|
| Loading | Five skeleton rows; paging disabled |
| Empty | `EmptyState` icon `block`, "No blocklist terms yet", with the Add term button projected as its CTA |
| Error | Error banner above the table with Retry |
| Saving | Dialog submit disabled with a spinner; on success the dialog closes and the table refetches from the first page |

---

<a id="screen-10-admin-notifications"></a>
## Screen 10 — Admin Notifications

**Route:** `/admin/notifications`  
**Guard:** none of its own — the parent `/admin` route applies `adminAuthGuard`  
**API:** `GET /notifications`, `GET /notifications/unread-count`, `PATCH /notifications/:notificationId/read`, `PATCH /notifications/read-all`

### Layout

```
div.notifications-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px]
  h1 mat-h4 — Notifications
  div [display: flex; gap: 12px; align-items: center]
    mat-slide-toggle [formControl]="unreadOnly" — Unread only
    button mat-stroked-button [disabled]="unreadCount === 0 || isActing" (click)="markAllRead()" — Mark all as read

div.notifications-list [max-width: 800px]
  mat-card.notification-card *ngFor="let n of notifications; trackBy: trackById"
    [class.unread]="!n.readAt"
    [display: flex; align-items: flex-start; gap: 16px; padding: 16px]
    mat-icon [color]="typeIconColor(n.type)" — {{ typeIcon(n.type) }}
    div [flex: 1]
      p mat-body-1 [font-weight]="!n.readAt ? '600' : '400'" — {{ titleFor(n) }}
      p mat-body-2 — {{ detailFor(n) }}
      p mat-caption color="secondary" — {{ n.createdAt | timeAgo }}
    button mat-icon-button *ngIf="!n.readAt" (click)="markRead(n.id)"
            aria-label="Mark notification as read" [matTooltip]="'Mark as read'"
      mat-icon — done

div.list-footer [display: flex; justify-content: center; gap: 12px; margin-top: 16px]
  button mat-stroked-button [disabled]="!hasPrevious || loading" (click)="previous()" — Previous
  button mat-stroked-button [disabled]="!hasMore || loading" (click)="next()" — Next
  span mat-caption color="secondary" *ngIf="!hasMore" — End of list

<aliceut-empty-state *ngIf="!loading && notifications.length === 0"
  icon="notifications_none"
  title="No notifications"
  message="Platform alerts appear here.">
</aliceut-empty-state>
```

**A notification row carries a `type` and an opaque `payload` — there is no `title` and no `body`.** Both lines of copy are composed in the client from the type plus the payload's fields; `titleFor(n)` and `detailFor(n)` are the mapping below.

**Cursor pagination, not pages.** `GET /notifications?limit=20&cursor=…` with `unreadOnly` as an optional filter. `meta.hasMore` drives Next, the component's cursor stack drives Previous, and there is no page number, no `page` parameter and no total. Toggling `unreadOnly` discards the stack and refetches from the first page.

### Notification types reaching an admin

| Type | Icon | Line composed from the payload |
|---|---|---|
| `KYC_SUBMITTED` | `assignment_ind` | "{{ businessName }} submitted a KYC application" — clicking opens the application |
| `LISTING_FLAGGED` | `flag` (warn) | "'{{ productTitle }}' was flagged for review" — clicking opens the moderation case |

Those are the two events the catalogue fans out to admins: `seller.kyc.submitted` reaches every admin, and `listing.flagged` copies the admin alongside the seller. Every other notification type is buyer- or seller-addressed and never lands in an admin's list.

Both types are actionable, so clicking a row navigates to the record it names. There is no admin notification that is informational only.

### States

| State | Rendering |
|---|---|
| Loading | Three skeleton notification cards; both paging buttons disabled |
| Empty | `EmptyState` "No notifications"; with the unread filter on: "Nothing unread" plus a Show all action |
| Error | Error banner in place of the list with Retry |
| Acting | The row's mark-read button disables; a failure reverts the row's read styling and shows an error snackbar |

### Mobile

Full-width cards, and the header's toggle and button wrap onto a second line below the heading.

---

*Last updated: 2026-09-14 (design alignment)*
