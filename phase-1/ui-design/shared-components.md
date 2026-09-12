# Shared UI Components — AliceUT Phase 1
## `libs/ui/` component library

**Status:** Draft  
**Stack:** Angular 22+ + Angular Material  
**Scope:** Components, directives, and pipes shared across buyer-app (4200), seller-app (4201), and admin-app (4202).

---

## Table of Contents

1. [NotificationBellComponent](#1-notificationbellcomponent)
2. [StatusBadgeComponent](#2-statusbadgecomponent)
3. [PriceDisplayComponent](#3-pricedisplaycomponent)
4. [EmptyStateComponent](#4-emptystatecomponent)
5. [DataTableComponent](#5-datatablecomponent)
6. [FileUploadComponent](#6-fileuploadcomponent)
7. [ConfirmDialogComponent](#7-confirmdialogcomponent)
8. [Pipes: timeAgo | truncate | currencyDisplay](#8-pipes)

---

<a id="1-notificationbellcomponent"></a>
## 1. NotificationBellComponent

**Selector:** `<aliceut-notification-bell>`  
**Module:** `LibsUiModule`

### Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `unreadCount` | `number` | `0` | Count of unread notifications |
| `maxDisplay` | `number` | `99` | Cap for badge display (shows "99+" above this) |

### Outputs

| Output | Type | Description |
|---|---|---|
| `(bellClick)` | `EventEmitter<void>` | Emitted when bell button is clicked; host navigates to /notifications |

### Behavior

- Renders a `mat-icon-button` with `notifications` icon.
- `matBadge` shown when `unreadCount > 0`; `matBadgeHidden` when `unreadCount === 0`.
- Badge label: `unreadCount <= maxDisplay ? unreadCount : maxDisplay + '+'`.
- Badge color: `mat-badge-warn`.
- Bell icon always visible when rendered — host is responsible for `*ngIf="isLoggedIn"`.

### Example

```html
<aliceut-notification-bell
  [unreadCount]="unreadCount"
  (bellClick)="router.navigate(['/notifications'])">
</aliceut-notification-bell>
```

---

<a id="2-statusbadgecomponent"></a>
## 2. StatusBadgeComponent

**Selector:** `<aliceut-status-badge>`  
**Module:** `LibsUiModule`

### Inputs

| Input | Type | Required | Description |
|---|---|---|---|
| `status` | `string` | Yes | Status value to display |
| `statusType` | `'order' \| 'fulfillment' \| 'kyc' \| 'listing' \| 'seller'` | Yes | Context for color/label mapping |

### Status → color mapping

**listing** (`statusType='listing'`)

| Status | Color | Label |
|---|---|---|
| `ACTIVE` | green (primary) | Active |
| `DRAFT` | grey | Draft |
| `FLAGGED` | orange (warn) | Flagged |
| `REMOVED` | red (error) | Removed |
| `UNDER_REVIEW` | yellow (accent) | Under Review |

**order** (`statusType='order'`)

| Status | Color | Label |
|---|---|---|
| `PENDING` | grey | Pending |
| `PROCESSING` | blue | Processing |
| `COMPLETED` | green | Completed |
| `CANCELLED` | red | Cancelled |

**fulfillment** (`statusType='fulfillment'`)

| Status | Color | Label |
|---|---|---|
| `PENDING` | grey | Pending |
| `SHIPPED` | cyan | Shipped |
| `DELIVERED` | green | Delivered |
| `REFUNDED` | orange | Refunded |
| `CANCELLED` | red | Cancelled |

**kyc** (`statusType='kyc'`)

| Status | Color | Label |
|---|---|---|
| `PENDING_KYC` | grey | Pending |
| `UNDER_REVIEW` | yellow | Under Review |
| `APPROVED` | green | Approved |
| `REJECTED` | red | Rejected |
| `RESUBMITTED` | blue | Resubmitted |

**seller account** (`statusType='seller'`)

| Status | Color | Label |
|---|---|---|
| `ACTIVE` | green | Active |
| `PENDING_KYC` | yellow | KYC Pending |
| `SUSPENDED` | red | Suspended |
| `SUSP_EXP` | orange | Suspension Expiring |

### Implementation

Renders a styled `<span>` or `<mat-chip>`. Unknown status values fall back to grey with the raw status string.

---

<a id="3-pricedisplaycomponent"></a>
## 3. PriceDisplayComponent

**Selector:** `<aliceut-price-display>`  
**Module:** `LibsUiModule`

All amounts arrive as strings from the API and are never parsed into floats by this component.

### Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `amount` | `string` | required | Offer-native (or display-currency) price amount string (e.g. `"99.99"`) |
| `currency` | `string` | required | ISO 4217 display currency code |
| `listAmount` | `string \| null` | `null` | Pre-sale LIST price; shows strikethrough when set |
| `isFxEstimate` | `boolean` | `false` | `true` = display price is an FX estimate (may be stale); shows stale indicator |
| `offerCurrency` | `string \| null` | `null` | Offer-native currency when it differs from `currency`; shown as secondary line |
| `saleEndsAt` | `Date \| null` | `null` | Shows countdown badge when within 24h of now |
| `tierMinQty` | `number \| null` | `null` | B2B tier minimum quantity; when set, shows "Business price" label |
| `tierAmount` | `string \| null` | `null` | B2B tier price amount string; displayed instead of `amount` when set |

### Display rules

- **SALE:** show `listAmount` struck through, `amount` in accent color, optional sale countdown badge if `saleEndsAt` within 24h.
- **B2B_TIER:** show `tierAmount` (or `amount` if null) with "Business price" label and minimum quantity (`tierMinQty`) requirement.
- **FX conversion:** if `offerCurrency` is set and differs from `currency`: show `amount currency` as primary, `offerCurrency` native amount as smaller secondary. If `isFxEstimate` is `true`, show stale indicator.
- **No conversion:** show `amount currency` only.
- All display formatting uses `currencyDisplay` pipe internally (see §8).

---

<a id="4-emptystatecomponent"></a>
## 4. EmptyStateComponent

**Selector:** `<aliceut-empty-state>`  
**Module:** `LibsUiModule`

### Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `icon` | `string` | `'inbox'` | `mat-icon` ligature name |
| `title` | `string` | `'Nothing here'` | Heading text |
| `message` | `string` | `''` | Body text |
| `actionLabel` | `string \| null` | `null` | CTA button label; button hidden when null |
| `actionRoute` | `string \| null` | `null` | `routerLink` path for CTA |

Centered layout — `text-align: center; padding: 48px 24px`. Suitable for list pages, search results, and notification pages.

---

<a id="5-datatablecomponent"></a>
## 5. DataTableComponent

**Selector:** `<aliceut-data-table>`  
**Module:** `LibsUiModule`  
Wraps `MatTable` + `MatPaginator` + `MatSort`.

### Inputs

| Input | Type | Description |
|---|---|---|
| `columns` | `ColumnDef[]` | Column definitions |
| `data` | `any[]` | Row data |
| `total` | `number` | Total item count for server-side pagination |
| `page` | `number` | Current page (1-based) |
| `limit` | `number` | Page size (default 20) |
| `loading` | `boolean` | Shows skeleton rows when `true` |
| `emptyMessage` | `string` | Text shown when `data` is empty and `loading` is false |
| `sortActive` | `string` | Active sort column `key` |
| `sortDirection` | `'asc' \| 'desc'` | Sort direction |

### ColumnDef interface

```typescript
interface ColumnDef {
  key: string;       // row property name
  header: string;    // column header label
  sortable?: boolean;
  pipe?: 'timeAgo' | 'truncate' | 'currencyDisplay' | 'statusBadge';
  width?: string;    // CSS e.g. '120px'
}
```

### Outputs

| Output | Type | Description |
|---|---|---|
| `(pageChange)` | `EventEmitter<{ page: number; limit: number }>` | Emitted on paginator page change |
| `(sortChange)` | `EventEmitter<{ column: string; direction: 'asc' \| 'desc' }>` | Emitted on sort header click |

---

<a id="6-fileuploadcomponent"></a>
## 6. FileUploadComponent

**Selector:** `<aliceut-file-upload>`  
**Module:** `LibsUiModule`

### Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `accept` | `string` | `'image/*'` | MIME types or file extensions |
| `maxSizeMb` | `number` | `5` | Maximum file size in MB |
| `multiple` | `boolean` | `false` | Allow multiple file selection |
| `maxFiles` | `number` | `1` | Maximum file count when `multiple=true` |
| `uploadUrl` | `string` | required | Backend API endpoint to obtain presigned URL |
| `uploadHeaders` | `Record<string, string>` | `{}` | Additional request headers (e.g. `Authorization`) |

### Outputs

| Output | Type | Description |
|---|---|---|
| `(filesChange)` | `EventEmitter<UploadedFile[]>` | Emitted on successful upload(s); `UploadedFile = { url: string; key: string }` |
| `(uploadError)` | `EventEmitter<string>` | Emitted on upload failure with error message |

### Behavior

- Drag-and-drop zone + "Browse files" button.
- Shows progress bar per file during upload.
- Error messages: `"File too large (max {N}MB)"` or `"Invalid file type"`.
- **Upload pattern:** calls backend for presigned URL → PUT direct to MinIO.

---

<a id="7-confirmdialogcomponent"></a>
## 7. ConfirmDialogComponent

Opened via: `MatDialog.open(ConfirmDialogComponent, { data: ConfirmDialogData })`  
**Module:** `LibsUiModule`

### ConfirmDialogData

```typescript
interface ConfirmDialogData {
  title: string;
  message: string;
  confirmLabel?: string;      // default: "Confirm"
  cancelLabel?: string;       // default: "Cancel"
  danger?: boolean;           // true: confirm button uses mat-warn color
  requireReason?: boolean;    // true: shows free-text reason textarea; confirm disabled until filled
  requireNameMatch?: string;  // if set, shows text input with this label as prompt;
                              // confirm button disabled until user types the exact string value
                              // used for permanent seller suspension confirmation
}
```

**Return type:** `MatDialogRef<ConfirmDialogComponent, boolean | undefined>`
- `true`: user confirmed
- `false` / `undefined`: user cancelled

### Notes

- `requireReason` and `requireNameMatch` are mutually exclusive; if both set, `requireNameMatch` takes precedence.
- `requireReason` result is not returned — caller re-reads form state after dialog closes. If the reason value is needed, pass a reference object via `data` or use a custom dialog.

---

<a id="8-pipes"></a>
## 8. Pipes

### timeAgo

Transforms an ISO8601 timestamp to a human-readable relative string.

| Age | Output |
|---|---|
| < 1 min | "just now" |
| < 60 min | "X minutes ago" |
| < 24 h | "X hours ago" |
| < 7 days | "X days ago" |
| ≥ 7 days | formatted date, e.g. "Sep 3, 2026" |

**Usage:** `{{ notification.createdAt | timeAgo }}`

Pure pipe. Transforms on every change detection cycle — use `async` pipe + `OnPush` on the host to avoid performance issues in large lists.

---

### truncate

Truncates a string to a maximum character length, appending ellipsis.

**Usage:** `{{ product.description | truncate:120 }}`  
**Default max:** 100 characters.  
Truncates at the last word boundary within max to avoid mid-word cuts.

---

### currencyDisplay

Formats a price amount string with currency symbol or code for display.

**Usage:** `{{ "99.99" | currencyDisplay:"THB" }}` → `"฿99.99"` or `"THB 99.99"`  
Uses `Intl.NumberFormat` with `style: 'currency'`.

Decimal places follow `Currency.minor_unit_scale`:
- JPY: 0 decimal places
- BHD: 3 decimal places
- All others (USD, THB, SGD): 2 decimal places

Input `amount` is always a string from the API — the pipe converts to `Number` for formatting only. Never used for arithmetic.

---

*Last updated: phase-1 design*
