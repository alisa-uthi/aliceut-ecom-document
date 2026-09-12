# AliceUT Design System
## Angular Material UI Specification

**Status:** Complete  
**Stack:** Angular 22+ + Angular Material + Angular CDK

---

## Summary

| Section | Description |
|---------|-------------|
| [1. Design Principles](#1-design-principles) | Core UX philosophy: familiar, data-dense, error-first |
| [2. Color Palette](#2-color-palette) | Indigo primary, amber accent, red warn, semantic status colours |
| [3. Typography Scale](#3-typography-scale) | Roboto + Angular Material type levels |
| [4. Spacing System — 8px Grid](#4-spacing-system-8px-grid) | Token-based spacing from 4px to 64px |
| [5. Angular CDK Breakpoints](#5-angular-cdk-breakpoints) | Handset / Tablet / Desktop / Widescreen definitions |
| [6. Icon Library — Material Icons (Outlined)](#6-icon-library-material-icons-outlined) | Icon reference table for all use cases |
| [7. Elevation and Shadows](#7-elevation-and-shadows) | Material elevation levels and usage |
| [8. Shared Component Library — `libs/ui/`](#8-shared-component-library-libsui) | ProductCard, StatusBadge, PriceDisplay, DataTable, and more |
| [9. Form Patterns](#9-form-patterns) | `mat-form-field` conventions, validators, monetary inputs |
| [10. Notification Patterns](#10-notification-patterns) | Toast, confirm dialog, inline errors, in-app panel |
| [11. Page Layout Patterns](#11-page-layout-patterns) | Buyer shell vs seller/admin shell; responsive grid |
| [12. Accessibility Standards](#12-accessibility-standards) | Focus rings, alt text, ARIA, skip links |
| [13. Loading State Patterns](#13-loading-state-patterns) | Skeleton, spinner, progress bar by context |
| [14. Component Import Strategy](#14-component-import-strategy) | Import from `@aliceut/shared-ui` barrel, never AM modules directly |
| [15. Custom Pipes](#15-custom-pipes) | TimeAgo, Truncate, CurrencyDisplay, Safe pipes |

<a id="1-design-principles"></a>
## 1. Design Principles

- **Familiar over novel.** Use Angular Material components as-is; no custom components unless AM cannot fulfill the need.
- **Data density over whitespace.** Admin/seller portals prioritize scannable tables; buyer portal prioritizes product imagery.
- **Error states are first-class.** Every data-fetching view must define loading, empty, and error states.
- **Mobile-first, not mobile-only.** Buyer portal primary breakpoint is mobile; admin/seller portals primary breakpoint is desktop with graceful mobile degradation.

---

<a id="2-color-palette"></a>
## 2. Color Palette

### Primary — Indigo

A professional, trust-signaling blue-indigo. Maps to Angular Material's `$mat-indigo` palette.

| Role | Hex | Material Token |
|------|-----|----------------|
| Primary 500 (default) | `#3F51B5` | `$mat-indigo-500` |
| Primary 700 (hover / active) | `#303F9F` | `$mat-indigo-700` |
| Primary 100 (light chip / badge bg) | `#C5CAE9` | `$mat-indigo-100` |
| On-Primary (text on primary) | `#FFFFFF` | white |

### Accent — Amber

Warm amber for CTAs (Add to Cart, Checkout, Place Order), notifications, and highlights.

| Role | Hex | Material Token |
|------|-----|----------------|
| Accent 500 (default) | `#FFC107` | `$mat-amber-500` |
| Accent 700 (hover) | `#FFA000` | `$mat-amber-700` |
| Accent 100 | `#FFECB3` | `$mat-amber-100` |
| On-Accent (text on accent) | `#212121` | near-black |

### Warn — Red

Standard Material red for destructive actions, error states, and validation errors.

| Role | Hex | Material Token |
|------|-----|----------------|
| Warn 500 | `#F44336` | `$mat-red-500` |
| Warn 100 (light error bg) | `#FFCDD2` | `$mat-red-100` |
| On-Warn | `#FFFFFF` | white |

### Neutral Greys

| Role | Hex | Usage |
|------|-----|-------|
| Surface / Page background | `#FAFAFA` | `$mat-grey-50` — page bg |
| Card / Panel background | `#FFFFFF` | white — mat-card bg |
| Divider | `#E0E0E0` | `$mat-grey-300` |
| Disabled text | `#9E9E9E` | `$mat-grey-500` |
| Secondary text | `#616161` | `$mat-grey-700` |
| Primary text | `#212121` | `$mat-grey-900` |

### Semantic Colours (Status)

| Status | Chip colour | Hex |
|--------|-------------|-----|
| PENDING | Yellow | `#F9A825` |
| SHIPPED / IN_PROGRESS | Blue | `#1976D2` |
| DELIVERED / COMPLETED / ACTIVE | Green | `#388E3C` |
| REFUNDED | Teal | `#00796B` |
| CANCELLED / REMOVED / REJECTED | Red | `#D32F2F` |
| PARTIALLY_PLACED / FLAGGED | Orange | `#E64A19` |
| SUSPENDED | Deep-orange | `#BF360C` |
| DRAFT | Grey | `#757575` |
| APPROVED / KYC_APPROVED | Green | `#388E3C` |
| PENDING_KYC | Amber | `#F9A825` |

### Angular Material Theme Configuration (SCSS)

```scss
// styles/theme.scss
@use '@angular/material' as mat;

$aliceut-primary: mat.define-palette(mat.$indigo-palette, 500, 100, 700);
$aliceut-accent:  mat.define-palette(mat.$amber-palette, 500, 100, 700);
$aliceut-warn:    mat.define-palette(mat.$red-palette, 500);

$aliceut-theme: mat.define-light-theme((
  color: (
    primary: $aliceut-primary,
    accent:  $aliceut-accent,
    warn:    $aliceut-warn,
  ),
  typography: mat.define-typography-config(),
  density: 0,
));

@include mat.all-component-themes($aliceut-theme);
```

Dark theme is optional in V1. [DESIGN DECISION: Light theme only for V1 to reduce implementation surface. Dark theme can be added in Phase 2 by defining `$aliceut-dark-theme` with `define-dark-theme`.]

---

<a id="3-typography-scale"></a>
## 3. Typography Scale

Angular Material typography config — Roboto (CDN) with fallback `sans-serif`.

| Role | Material Level | Font Size | Weight | Line Height | Usage |
|------|----------------|-----------|--------|-------------|-------|
| `h1` | `headline-1` | 2.5rem / 40px | 300 | 1.2 | Page hero (rare) |
| `h2` | `headline-2` | 2rem / 32px | 300 | 1.25 | Section headings in buyer portal |
| `h3` | `headline-3` | 1.75rem / 28px | 400 | 1.3 | Product title on PDP |
| `h4` | `headline-4` | 1.5rem / 24px | 400 | 1.35 | Card headers, modal titles |
| `h5` | `headline-5` | 1.25rem / 20px | 400 | 1.4 | Sidebar section titles |
| `h6` | `headline-6` | 1rem / 16px | 500 | 1.5 | Table headers, label groups |
| Body 1 | `body-1` | 1rem / 16px | 400 | 1.5 | Primary body text |
| Body 2 | `body-2` | 0.875rem / 14px | 400 | 1.5 | Secondary text, descriptions |
| Caption | `caption` | 0.75rem / 12px | 400 | 1.4 | Timestamps, helper text, tooltips |
| Button | `button` | 0.875rem / 14px | 500 | auto | Button labels (Material default) |
| Overline | `overline` | 0.625rem / 10px | 400 | 2.0 | Badge labels, category chips |

```scss
$aliceut-typography: mat.define-typography-config(
  $font-family: 'Roboto, sans-serif',
  $headline-4: mat.define-typography-level(1.5rem, 1.35, 400),
  $headline-5: mat.define-typography-level(1.25rem, 1.4, 400),
  $body-1:     mat.define-typography-level(1rem, 1.5, 400),
  $body-2:     mat.define-typography-level(0.875rem, 1.5, 400),
  $caption:    mat.define-typography-level(0.75rem, 1.4, 400),
);
```

---

<a id="4-spacing-system-8px-grid"></a>
## 4. Spacing System — 8px Grid

All margin, padding, and gap values are multiples of 8px.

| Token | Size | CSS Custom Property |
|-------|------|---------------------|
| `xs` | 4px | `--space-xs` |
| `sm` | 8px | `--space-sm` |
| `md` | 16px | `--space-md` |
| `lg` | 24px | `--space-lg` |
| `xl` | 32px | `--space-xl` |
| `xxl` | 48px | `--space-xxl` |
| `xxxl` | 64px | `--space-xxxl` |

Standard page content padding: 24px (`lg`) on desktop, 16px (`md`) on mobile.  
Card internal padding: 16px (`md`) all sides.  
Form field gap: 16px (`md`) between fields.

---

<a id="5-angular-cdk-breakpoints"></a>
## 5. Angular CDK Breakpoints

```typescript
// libs/ui/src/lib/breakpoints.ts
export const BREAKPOINTS = {
  handset:   '(max-width: 599px)',
  tablet:    '(min-width: 600px) and (max-width: 959px)',
  desktop:   '(min-width: 960px)',
  widescreen:'(min-width: 1280px)',
};
```

| Name | Range | Angular CDK Alias | Notes |
|------|-------|-------------------|-------|
| Handset (XS–SM) | 0–599px | `Handset` | Mobile; single-column layout |
| Tablet | 600–959px | `Tablet` | 2-column grid; sidebar collapses to bottom sheet |
| Desktop | 960–1279px | `Web` | Full sidebar; 3-4 column grids |
| Widescreen | 1280px+ | `WebLandscape` | Max content width 1440px, centred |

Use `BreakpointObserver` from `@angular/cdk/layout` in components; never CSS-only media queries in `.ts` files.

---

<a id="6-icon-library-material-icons-outlined"></a>
## 6. Icon Library — Material Icons (Outlined)

Use `mat-icon` with the **Outlined** variant (`material-icons-outlined` class) for clarity at small sizes. Icons referenced below are `ligature` names.

| Use case | Icon name | Notes |
|----------|-----------|-------|
| Search | `search` | Toolbar, search bar |
| Cart | `shopping_cart` | Header cart badge |
| Account / Profile | `account_circle` | User menu |
| Notifications | `notifications_none` | Bell (outlined) |
| Home | `home` | Nav |
| Orders | `receipt_long` | Buyer orders |
| Settings | `settings` | Account settings |
| Edit | `edit` | Row actions |
| Delete | `delete_outline` | Destructive actions |
| Visibility | `visibility` | View / preview |
| Check / Approve | `check_circle_outline` | KYC approve |
| Reject / Block | `cancel` | KYC reject |
| Warning | `warning_amber` | Flags, low stock |
| Error | `error_outline` | Validation errors |
| Info | `info_outline` | Tooltips, hints |
| Upload | `upload_file` | File upload |
| Download / Export | `download` | CSV export |
| Add | `add` | FAB, add row |
| Close / Remove | `close` | Chips, dialogs |
| Expand | `expand_more` | Accordion, dropdown |
| Collapse | `expand_less` | — |
| Filter | `filter_list` | Filter panel toggle |
| Sort | `swap_vert` | Table sort |
| Ship | `local_shipping` | Fulfillment status |
| Delivered | `done_all` | — |
| Refund | `currency_exchange` | — |
| Inventory | `inventory_2` | Seller inventory |
| Store / Seller | `storefront` | Seller name |
| Category | `category` | Nav / filter |
| Image | `image` | Upload placeholder |
| Star | `star` | Rating (from seed data) |
| Star outline | `star_outline` | Empty rating star |
| Business | `business` | B2B badge |
| Lock | `lock` | Auth, KYC locked state |
| Refresh | `refresh` | Reload, retry |
| Arrow back | `arrow_back` | Breadcrumb navigation |
| More options | `more_vert` | Row overflow menu |
| Drag handle | `drag_handle` | Image reorder |

---

<a id="7-elevation-and-shadows"></a>
## 7. Elevation and Shadows

Follow Material Design elevation system.

| Level | `mat-elevation-z` | Usage |
|-------|-------------------|-------|
| 0 | None | Flat page bg sections |
| 1 | `z1` | Default mat-card |
| 2 | `z2` | Hovered mat-card |
| 4 | `z4` | mat-toolbar (sticky), dialogs header |
| 8 | `z8` | mat-dialog, mat-menu |
| 16 | `z16` | Bottom sheets |
| 24 | `z24` | mat-snack-bar |

---

<a id="8-shared-component-library-libsui"></a>
## 8. Shared Component Library — `libs/ui/`

All components live in `libs/ui/src/lib/` as standalone Angular components. They wrap Angular Material; callers never import AM modules directly in feature modules.

---

### 8.1 ProductCard

**Purpose:** Display a product in search results grid and featured sections.

**Template structure:**

```
mat-card [style: max-width 280px; height: 360px; flex-shrink: 0]
  ├── mat-card-header [padding: 0]
  │   └── <img mat-card-image> — product primary image (aspect ratio 1:1, object-fit: cover)
  ├── mat-card-content
  │   ├── category chip (mat-chip, outlined, caption text)
  │   ├── title — 2 lines max, truncated with ellipsis (body-1, 500 weight)
  │   ├── <aliceut-price-display> component
  │   ├── seller name line (body-2, secondary text, storefront icon)
  │   └── rating stars (mat-icon star × N, caption text — tooltip: "Based on third-party data")
  └── mat-card-actions [align: end]
      └── button [mat-flat-button, color accent] "Add to Cart"
          — disabled when out of stock; label changes to "Out of Stock"
```

**Inputs:**

| Input | Type | Description |
|-------|------|-------------|
| `product` | `ProductCardDto` | Product summary (id, title, category, imageUrl, rating, seller) |
| `effectivePrice` | `EffectivePriceDto` | Resolved price display data |
| `inStock` | `boolean` | Controls CTA state |
| `loading` | `boolean` | Shows skeleton when true |

**Outputs:** `addToCart: EventEmitter<{productId, offerId}>`, `cardClick: EventEmitter<string>` (navigates to PDP)

**Skeleton state:** When `loading=true`, replace card content with CSS shimmer skeleton:

```html
<!-- Loading skeleton state -->
<div [class.is-loading]="loading" class="product-card-skeleton">
  <div class="skeleton-rect" style="height: 200px;"></div>  <!-- image placeholder -->
  <div class="skeleton-text" style="width: 80%;"></div>      <!-- title placeholder -->
  <div class="skeleton-text" style="width: 50%;"></div>      <!-- price placeholder -->
</div>
```

Note: Angular Material does not include a skeleton loader component. Use CSS shimmer classes `.skeleton-rect` and `.skeleton-text` defined in `libs/ui/src/lib/styles/_skeleton.scss`. Apply `[class.is-loading]="loading"` on the card host to toggle skeleton visibility.

**Mobile:** Card width 100% of grid cell; grid is `repeat(auto-fill, minmax(160px, 1fr))` on handset, `minmax(220px, 1fr)` on tablet, `minmax(260px, 1fr)` on desktop.

---

### 8.2 StatusBadge

**Purpose:** Consistent colour-coded status chip across all portals.

**Template:** `<mat-chip [class]="statusClass">{{ label }}</mat-chip>`  
Non-interactive (no click handler); uses `mat-chip` in display-only mode.

**Inputs:**

| Input | Type | Values |
|-------|------|--------|
| `status` | `string` | Order, fulfillment, KYC, or listing status enum value |
| `statusType` | `'order' \| 'fulfillment' \| 'kyc' \| 'listing' \| 'seller'` | Drives colour mapping |

**Colour mapping** (CSS classes on host, maps to semantic colours in §2):

| Status value | Class | Colour |
|-------------|-------|--------|
| `PENDING`, `PENDING_KYC` | `.badge-pending` | Amber |
| `SHIPPED`, `IN_PROGRESS`, `PARTIALLY_SHIPPED` | `.badge-active` | Blue |
| `DELIVERED`, `COMPLETED`, `ACTIVE`, `APPROVED` | `.badge-success` | Green |
| `REFUNDED`, `PARTIALLY_REFUNDED` | `.badge-refunded` | Teal |
| `CANCELLED`, `REMOVED`, `REJECTED` | `.badge-danger` | Red |
| `CLEARED` | `.badge-success` | Green | Moderation case cleared (false positive) |
| `PARTIALLY_PLACED`, `FLAGGED` | `.badge-warning` | Orange |
| `SUSPENDED` | `.badge-suspended` | Deep-orange |
| `DRAFT` | `.badge-draft` | Grey |
| `PARTIALLY_DELIVERED` | `.badge-partial` | Blue-grey |

**Accessibility:** `role="status"` on the chip element; `aria-label` = full status description (e.g. "Order status: Shipped").

---

### 8.3 PriceDisplay

**Purpose:** Render a monetary amount correctly — formatted string, FX estimates with visual indicator, SALE strikethrough.

**Template structure:**

```
<span class="price-display">
  <!-- If SALE price active -->
  <span class="price-original line-through mat-caption">[list price]</span>
  <!-- Effective price -->
  <span class="price-effective mat-headline-6">[≈ prefix if FX estimate][amount] [currency]</span>
  <!-- If FX estimate: tooltip trigger -->
  <mat-icon matTooltip="Estimated in [buyer_currency], actual charge in [offer_currency]">info_outline</mat-icon>
  <!-- If SALE: countdown badge -->
  <mat-chip class="sale-chip">SALE ends [timer]</mat-chip>
  <!-- If B2B_TIER visible -->
  <span class="tier-hint mat-caption">Buy [min_qty]+ at [tier_price] each</span>
</span>
```

**Inputs:**

| Input | Type | Description |
|-------|------|-------------|
| `amount` | `string` | Amount as string (never number) |
| `currency` | `string` | ISO 4217 code |
| `listAmount` | `string \| null` | Original list price (shown struck-through when SALE active) |
| `isFxEstimate` | `boolean` | Adds `≈` prefix and info icon |
| `offerCurrency` | `string \| null` | Original currency when FX estimate |
| `saleEndsAt` | `Date \| null` | Drives countdown badge |
| `tierMinQty` | `number \| null` | B2B tier threshold |
| `tierAmount` | `string \| null` | B2B tier price |

**Formatting:** Use `Intl.NumberFormat` at render boundary. Currency scale: JPY → 0 decimals; BHD/KWD → 3; all others → 2. Amount value comes in as string; parse with `decimal.js` only if arithmetic needed.

---

### 8.4 CurrencyInput

**Purpose:** Monetary amount input field that enforces string-based entry and shows currency symbol.

**Template:** `mat-form-field` with `matInput` (type="text"), currency code suffix (`matSuffix`), and numeric-only input mask. Emits value as string to parent form.

**Inputs:** `currencyCode: string`, `placeholder: string`, `required: boolean`  
**Outputs:** `valueChange: EventEmitter<string>` — emits formatted decimal string  
**Validation:** Rejects non-numeric characters; validates decimal places against `Currency.minor_unit_scale`; shows `mat-error` inline.

---

### 8.5 ConfirmDialog

**Purpose:** Reusable confirmation dialog for destructive/irreversible actions.

**Template:**

```
mat-dialog-container
  mat-dialog-title — [title prop]
  mat-dialog-content
    mat-icon [color=warn] — warning_amber
    <p> — [message prop]
    <mat-form-field *ngIf="requireReason"> — optional reason textarea
  mat-dialog-actions [align=end]
    button [mat-button] — [cancelLabel || 'Cancel']
    button [mat-flat-button, color=warn] — [confirmLabel || 'Confirm']
      — disabled until reason filled if requireReason=true
```

**Config interface:**

```typescript
interface ConfirmDialogConfig {
  title: string;
  message: string;
  confirmLabel?: string;    // default 'Confirm'
  cancelLabel?: string;     // default 'Cancel'
  requireReason?: boolean;  // shows textarea, blocks confirm until filled
  reasonLabel?: string;     // default 'Reason'
  reasonMaxLength?: number; // default 500
  danger?: boolean;         // red confirm button when true
}
```

**Usage:** `MatDialog.open(ConfirmDialogComponent, { data: config })` → returns `Observable<{ confirmed: boolean, reason?: string } | undefined>`.

---

### 8.6 DataTable

**Purpose:** Sortable, filterable, paginated table wrapper over `mat-table`.

**Template structure:**

```
div.table-container
  mat-toolbar [dense, optional actions slot]
    ng-content select="[table-actions]"  — caller injects bulk-action buttons, export button
  mat-form-field [appearance=outline, subscriptSizing=dynamic]
    mat-icon matPrefix — search
    input matInput [placeholder="Search..."] (input)="applyFilter($event)"
  div.table-scroll-wrapper [overflow-x: auto]
    table mat-table [dataSource] matSort
      [ng-content for column defs]
    mat-paginator [pageSizeOptions="[10,25,50]" showFirstLastButtons]
  <aliceut-empty-state *ngIf="isEmpty">
```

**Inputs:** `columns: ColumnDef[]`, `dataSource: MatTableDataSource<T>`, `loading: boolean`, `emptyMessage: string`  
**Features:** sticky header (`position: sticky; top: 0`), loading overlay (`mat-progress-bar` above table), row selection (`SelectionModel<T>`), bulk-action slot.

---

### 8.7 NotificationBell

**Purpose:** Header bell icon with unread badge and dropdown panel.

**Template:**

```
button mat-icon-button [matBadge]="unreadCount" [matBadgeHidden]="unreadCount === 0"
  mat-icon — notifications_none
[mat-menu trigger]
  mat-menu
    div.notification-list [max-height: 360px; overflow-y: auto]
      mat-list
        mat-list-item *ngFor="let n of notifications"
          mat-icon [color based on type]
          span.notification-body — [n.message] [n.createdAt | timeAgo]
          button mat-icon-button (click)="markRead(n.id)" — close icon
      div.notification-footer *ngIf="hasMore"
        a routerLink="/notifications" — View all
    div.empty *ngIf="notifications.length === 0"
      mat-icon — notifications_none
      p — No new notifications
```

**Inputs:** `notifications: InAppNotificationDto[]`, `unreadCount: number`  
**Outputs:** `markAsRead: EventEmitter<string>`, `markAllRead: EventEmitter<void>`  
**Polling:** Parent component polls notification API on page focus / 60s interval (no WebSocket in V1).

---

### 8.8 FileUpload

**Purpose:** File drag-and-drop + click-to-browse upload area for KYC documents and product images.

**Template:**

```
div.upload-zone [class.drag-over]="isDragging" (dragover) (drop) (click)
  mat-icon — upload_file
  p — "Drag & drop or click to browse"
  p.hint — "Accepted: [accept prop] · Max [maxSizeMb]MB"
  input type="file" [hidden] [multiple] [accept]

div.file-list *ngIf="files.length"
  div.file-item *ngFor="let f of files"
    mat-icon — [file type icon]
    span.file-name — [f.name]
    mat-progress-bar *ngIf="f.uploading" [value]="f.progress"
    mat-icon.success *ngIf="f.done && !f.error" color="primary" — check_circle_outline
    div.file-error *ngIf="f.error"
      mat-icon color="warn" — error_outline
      span — [f.errorMessage]
      button mat-button color="primary" — Retry
    button mat-icon-button (click)="remove(f)" — close
```

**Inputs:** `accept: string` (e.g. `"image/*,.pdf"`), `maxSizeMb: number`, `multiple: boolean`, `maxFiles: number`  
**Outputs:** `filesChange: EventEmitter<UploadedFile[]>`  
**Validation errors:** displayed inline per file; summarized below the list when all fail.

---

### 8.9 EmptyState

**Purpose:** Consistent empty / zero-data state illustration across all tables and list views.

**Template:**

```
div.empty-state [text-align: center; padding: 48px 24px]
  mat-icon [font-size: 64px; color: disabled] — [icon prop]
  h4 mat-h4 — [title prop]
  p mat-body-2 — [message prop]
  ng-content — optional CTA button slot
```

**Inputs:** `icon: string` (Material icon name), `title: string`, `message: string`  
**Example usage:** Order history empty → `icon="receipt_long"`, `title="No orders yet"`, `message="Browse the catalog to get started"` + `<button mat-flat-button color="primary">Browse</button>` in content slot.

---

<a id="9-form-patterns"></a>
## 9. Form Patterns

- Use `mat-form-field` with `appearance="outline"` throughout; `subscriptSizing="dynamic"` to avoid layout shift from validation messages.
- `mat-error` shown only after field is touched or form is submitted.
- Required fields: `*` asterisk in label suffix (Angular Material default behaviour); no "Required" text in placeholder.
- Async validators (e.g. email uniqueness check): show `mat-spinner` in suffix slot during pending state.
- Multi-step forms: use `mat-stepper` (linear mode) with validation guards between steps.
- Monetary inputs: always use `CurrencyInput` component, never a plain `number` input.
- Markdown description inputs: `mat-form-field` with `textarea`, autosize, character counter (`matTextareaAutosize`, `matCounterMax`).

---

<a id="10-notification-patterns"></a>
## 10. Notification Patterns

| Channel | Component | Trigger |
|---------|-----------|---------|
| Inline validation errors | `mat-error` inside form fields | Field blur / submit |
| Brief success/info toasts | `MatSnackBar` (3s, bottom-center) | Add to cart, save, mark shipped |
| Persistent page-level warnings | `<mat-card class="warning-banner">` with warning icon | Stale cart items, KYC pending |
| Destructive confirmations | `ConfirmDialog` component | Delete, refund, suspend, cancel |
| In-app notification panel | `NotificationBell` component | Bell icon in toolbar |

---

<a id="11-page-layout-patterns"></a>
## 11. Page Layout Patterns

### Buyer Portal — Shell

```
mat-toolbar [color=primary] [position: sticky; top: 0; z-index: 100]
  [logo] | [search bar — flex 1] | [cart icon+badge] | [notification bell] | [user menu]
main.page-content [max-width: 1440px; margin: 0 auto; padding: 24px]
  [router-outlet]
```

### Seller / Admin Portal — Shell

```
mat-sidenav-container [fullscreen]
  mat-sidenav [mode=side on desktop, over on mobile] [opened on desktop]
    mat-nav-list — sidebar navigation
  mat-sidenav-content
    mat-toolbar [position: sticky; top: 0]
      button mat-icon-button (click)="drawer.toggle()" — menu icon (mobile only)
      [portal name] — spacer — [notification bell] | [user menu]
    main.content [padding: 24px]
      [router-outlet]
```

### Responsive Grid

- Buyer product grids: CSS Grid `repeat(auto-fill, minmax(260px, 1fr))`, gap `16px`.
- Admin/Seller data tables: full width within content area; `overflow-x: auto` wrapper.
- Form layouts: single column on mobile; 2-column on tablet+; max form width `600px`.

---

<a id="12-accessibility-standards"></a>
## 12. Accessibility Standards

- All interactive elements must have visible focus ring (Angular Material default; do not override `outline: 0` globally).
- Images: `alt` attribute always present; product images use descriptive alt text from product title.
- Color alone never conveys meaning — always pair colour with icon or text label in status badges.
- Form fields: every `mat-form-field` must have a visible `mat-label`; never rely on placeholder alone.
- Dialog: `mat-dialog-title` aria-labelled-by, initial focus on first interactive element or cancel button.
- Tables: `<th>` with `scope="col"`, sort column announces current direction via `mat-sort-header`.
- Screen reader text: use `.cdk-visually-hidden` for supplemental content (e.g. "items in cart" after badge number).
- Skip to main content link at top of each portal shell.

---

<a id="13-loading-state-patterns"></a>
## 13. Loading State Patterns

| Context | Loading treatment |
|---------|-------------------|
| Page / route transition | `mat-progress-bar` (indeterminate) at top of `<main>`, shown via `router.events` |
| In-place data refresh | `mat-progress-spinner` (diameter 32) centred over content area with `opacity: 0.5` overlay |
| DataTable initial load | Skeleton rows (5 rows of grey rectangles) via `loading` input on DataTable component |
| ProductCard grid | `loading=true` cards render as skeleton cards |
| Button action in progress | Button `[disabled]` + `mat-spinner` (diameter 20) inside button replacing label |
| File upload | `mat-progress-bar` per file in FileUpload component |

---

<a id="14-component-import-strategy"></a>
## 14. Component Import Strategy

All feature modules import from `libs/ui/` barrel:

```typescript
import {
  ProductCardComponent,
  StatusBadgeComponent,
  PriceDisplayComponent,
  CurrencyInputComponent,
  ConfirmDialogComponent,
  DataTableComponent,
  NotificationBellComponent,
  FileUploadComponent,
  EmptyStateComponent,
} from '@aliceut/shared-ui';
```

Feature modules never import `MatCardModule`, `MatTableModule`, etc. directly — they rely on the `libs/ui/` wrappers which re-export the necessary AM modules.

---

<a id="15-custom-pipes"></a>
## 15. Custom Pipes

All pipes live in `libs/ui/src/lib/pipes/` and are exported from the `@aliceut/shared-ui` barrel (`libs/ui/src/index.ts`).

**TimeAgoPipe** (`time-ago.pipe.ts`)
- Selector: `| timeAgo`
- Input: `Date | string | number`
- Output: Human-readable relative time string (e.g., "3 minutes ago", "2 hours ago", "yesterday")
- Usage: `{{ event.occurredAt | timeAgo }}`, `{{ order.placedAt | timeAgo }}`
- Updates: Does NOT auto-update; host component must trigger change detection if live updating is needed
- Note: Uses Angular's LOCALE_ID for locale-aware formatting

**TruncatePipe** (`truncate.pipe.ts`)
- Selector: `| truncate:N`
- Parameters: `limit: number` (max chars), `suffix?: string` (default: `'…'`)
- Input: `string`
- Output: String truncated to limit chars + suffix if truncated
- Usage: `{{ row.reason | truncate:60 }}`, `{{ row.productTitle | truncate:40 }}`

**CurrencyDisplayPipe** (`currency-display.pipe.ts`)
- Selector: `| currencyDisplay:currencyCode`
- Parameters: `currencyCode: string` (ISO 4217)
- Input: `string` (monetary amount as string per FR-P-04b, e.g. `"99.9900"`)
- Output: Formatted string using `Intl.NumberFormat` for the given currency locale (e.g., `"$99.99"`, `"¥100"`, `"฿99.99"`)
- NOTE: Input MUST be a string amount. Never pass a JS `number` — this would violate FR-P-04b.
- Usage: `{{ item.unitPrice | currencyDisplay:item.currency }}`

**SafePipe** (`safe.pipe.ts`)
- Selector: `| safe:'resourceUrl'` or `| safe:'url'` or `| safe:'html'`
- Parameters: `type: 'html' | 'url' | 'resourceUrl' | 'style' | 'script'`
- Input: `string`
- Output: `SafeHtml | SafeUrl | SafeResourceUrl` etc. via Angular `DomSanitizer.bypassSecurityTrustX()`
- Usage: `[src]="kycDocUrl | safe:'resourceUrl'"`, `[href]="deepLink | safe:'url'"`
- **Security note:** Only use for content from trusted internal sources (e.g., KYC document viewer loading from verified storage). Never pass user-provided URLs through `safe:'resourceUrl'`.
