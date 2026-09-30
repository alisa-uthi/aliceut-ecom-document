# Shared UI Components — AliceUT Phase 1
## Phase 1 usage registry for `libs/ui/`

**Status:** Complete  
**Stack:** Angular 22+ + Angular Material  
**Contract owner:** [conventions/design-system.md § 8](../../conventions/design-system.md#8-shared-component-library-libsui) and [§ 15](../../conventions/design-system.md#15-custom-pipes)  
**Scope:** Which shared components the Phase 1 screens use and what each one is fed on those screens ([§ 3](#3-component-registry)–[§ 6](#6-pipes)), the rules every screen follows ([§ 7](#7-rules-every-screen-follows)), and the two screen patterns each portal repeats — the auth card ([§ 8](#8-auth-screen-pattern)) and the notifications page ([§ 9](#9-notifications-page-pattern)). buyer-app (4200), seller-app (4201), admin-app (4202).

---

## Summary

1. [How to read this document](#1-how-to-read)
2. [Where a component comes from](#2-where-a-component-comes-from)
3. [Component registry](#3-component-registry)
4. [Per-component phase-1 usage](#4-per-component-phase-1-usage)
5. [Status vocabulary by `statusType`](#5-status-vocabulary)
6. [Pipes](#6-pipes)
7. [Rules every screen follows](#7-rules-every-screen-follows)
8. [Auth screen pattern](#8-auth-screen-pattern)
9. [Notifications page pattern](#9-notifications-page-pattern)

---

<a id="1-how-to-read"></a>
## 1. How to read this document

`conventions/design-system.md § 8` is the single owner of every shared component's contract — inputs, outputs, template structure, states and colour. This document does not restate those contracts. It records the *phase-1 facts* the convention deliberately leaves out: which screens use each component, which API response fields are bound to which input, and which enum values each screen actually passes.

Two earlier copies of these contracts lived here and drifted from the convention — a second `StatusBadge` colour map, a `columns`/`data` `DataTable` API that no screen used, and a `ConfirmDialog` that discarded the reason three flows need. `conventions/` outranks `phase-1/ui-design/`, so the convention's version is the one that survives and this document points at it rather than paraphrasing it. If a screen needs behaviour the convention does not describe, the fix is a change to `design-system.md § 8`, not a local contract here.

---

<a id="2-where-a-component-comes-from"></a>
## 2. Where a component comes from

Two import paths, and they are not interchangeable ([frontend-coding-standards.md § 8](../../conventions/frontend-coding-standards.md#8-angular-material-usage-rules), [design-system.md § 14](../../conventions/design-system.md#14-component-import-strategy)):

| Kind | Where from | How it is imported |
|---|---|---|
| **Composite** — own template and logic (`<aliceut-*>`) | `libs/ui`, exported from `@aliceut/shared-ui` | Named import from the barrel, listed in the feature component's `imports: []` |
| **Angular Material primitive** — `MatButtonModule`, `MatTableModule`, `MatStepperModule`, `MatSidenavModule`, `MatChipsModule`, `MatDatepickerModule`, `MatSnackBar`, … | `@angular/material/*` | Named import **directly in the feature component** that uses it |

`libs/ui` re-exports no Angular Material module. There is no `MatModule` catch-all and no wrapper whose only job is to pass a primitive through. A composite imports whatever Material modules it needs internally; that is an implementation detail its consumers never see. A screen that needs a primitive with no composite equivalent imports the primitive — the wireframes below name Material primitives directly wherever that is the case, and doing so is correct rather than a shortcut.

There is no `LibsUiModule`. Every shared component is a **standalone** component; `NgModule` packaging appears nowhere in the frontend.

---

<a id="3-component-registry"></a>
## 3. Component registry

The nine composites `libs/ui` exports, and where Phase 1 uses them.

| Composite | Selector | Used by |
|---|---|---|
| `ProductCardComponent` | `<aliceut-product-card>` | buyer: home featured grid, search results grid |
| `StatusBadgeComponent` | `<aliceut-status-badge>` | buyer: order history, order detail · seller: listings, order queue, order detail, listing editor · admin: KYC queue, KYC detail, seller list, seller detail |
| `PriceDisplayComponent` | `<aliceut-price-display>` | buyer: product card, PDP, cart, checkout, order detail · seller: listings, order queue, order detail, offer pricing |
| `CurrencyInputComponent` | `<aliceut-currency-input>` | buyer: search price-range filter · seller: listing editor pricing rows, offer pricing form |
| `ConfirmDialogComponent` | opened via `MatDialog` | buyer: cancel order, remove address · seller: mark shipped, refund, cancel, delete listing, delete price row · admin: KYC approve/reject, listing remove, bulk remove, suspend, reinstate |
| `DataTableComponent` | `<aliceut-data-table>` | seller: listings, order queue, inventory, offer pricing · admin: KYC queue, moderation queue, seller list · buyer: order history |
| `NotificationBellComponent` | `<aliceut-notification-bell>` | all three portal shells |
| `FileUploadComponent` | `<aliceut-file-upload>` | seller: KYC documents, product images, inventory CSV · buyer: business logo |
| `EmptyStateComponent` | `<aliceut-empty-state>` | every list, table and notification surface |

A tenth entry is earned by a component with its own template and logic that at least two screens use ([design-system.md § 14](../../conventions/design-system.md#14-component-import-strategy)). Nothing in Phase 1 clears that bar beyond the nine above.

---

<a id="4-per-component-phase-1-usage"></a>
## 4. Per-component phase-1 usage

### 4.1 NotificationBell

Contract: [design-system.md § 8.7](../../conventions/design-system.md#8-shared-component-library-libsui). Inputs `notifications`, `unreadCount`; outputs `markAsRead`, `markAllRead`.

Every portal shell binds the same two reads:

| Input | Source |
|---|---|
| `notifications` | `GET /notifications?limit=20` — the `data[]` rows, each `{ id, type, payload, readAt, createdAt }` |
| `unreadCount` | `GET /notifications/unread-count` — `data.unreadCount` |

`unreadCount` is its own endpoint because `GET /notifications` carries no total and `meta` permits no extra key ([api-conventions.md § Pagination](../../conventions/api-conventions.md#pagination), [notifications.md § Get unread count](../technical-design/api-design/notifications.md#get-unread-count)). The badge caps the *displayed* figure at `99+`; the returned number is not clamped. The dropdown's "View all" link targets the portal's notifications page.

`markAsRead` calls `PATCH /notifications/:notificationId/read`; `markAllRead` calls `PATCH /notifications/read-all`. Parent components poll on page focus and on a 60 s interval — there is no WebSocket in V1.

**A notification row has no `title` and no `body`.** The API returns a `type` and an opaque `payload` object; the human-readable line is composed in the client from the two. Each portal's notifications screen carries the type-to-copy table for the types it renders.

---

### 4.2 StatusBadge

Contract: [design-system.md § 8.2](../../conventions/design-system.md#8-shared-component-library-libsui). Inputs `status`, `statusType`. Colour is owned by the map in that section and defined nowhere else; a status a screen renders but the map omits is a gap in the map, closed there.

`role="status"` and an `aria-label` carrying the full description ("Order status: Shipped") are part of the component, so no call site adds them.

The `statusType` union is `'order' | 'fulfillment' | 'kyc' | 'listing' | 'seller'`. See [§ 5](#5-status-vocabulary) for the values each one receives in V1.

---

### 4.3 PriceDisplay

Contract: [design-system.md § 8.3](../../conventions/design-system.md#8-shared-component-library-libsui) — the canonical prop surface. This section documents the Phase-1 binding source for each input.

Every amount reaching this component is a **string** already denominated in the currency it will be shown in, with its currency code beside it. The component formats with `Intl.NumberFormat` at the render boundary and performs no arithmetic. Decimal places follow `Currency.minor_unit_scale` — JPY 0, BHD/KWD 3, USD/THB/SGD 2.

Phase-1 binding sources per input:

| Input | Where the value comes from |
|---|---|
| `amount`, `currency` | Browse surfaces: `lowestOffer.displayAmount` / `displayCurrency` from `GET /search/products`, or `effectivePrice.displayAmount` / `displayCurrency` from `GET /catalog/products/:id/offers`. Native-currency fallback: when `displayAmount` is `null`, bind `amount` / `currency` instead. Seller surfaces: the offer's `prices[].amount` with the offer's `nativeCurrencyCode`. Order surfaces: the snapshotted `unitPrice` / `lineTotal` / `totalAmount` with the fulfillment's `currencyCode` |
| `priceType` | `lowestOffer.priceType` on browse, `effectivePrice.priceType` on the PDP and the offers list — `'LIST'` or `'SALE'`. **Where the amount has no price type at all, bind the `'LIST'` literal.** That covers order surfaces (snapshotted amounts have no active price type) and every cart and checkout *total* — a line total, a group subtotal, a shipping or tax zero, the item subtotal and the grand total are sums, not price rows, and none of them is a SALE. The literal is deliberate at those sites and is not a placeholder for a real price type: `priceType` is a required input, `'SALE'` is the only value that changes rendering, and `'LIST'` is what "this is not a sale price" is spelled as. Never omit — it drives the SALE chip, the countdown and `compareAtAmount` visibility |
| `compareAtAmount` | `lowestOffer.compareAtAmount` on browse, `effectivePrice.compareAtAmount` on the PDP and the offers list — the live `LIST` amount when `priceType = 'SALE'`, enabling the struck-through original price (US-B-05). `null` when `priceType = 'LIST'` |
| `converted` | **Derived in the template, never read from a response — no API response carries a `converted` flag.** It is `true` when the display amount is non-null *and* its `displayCurrency` differs from the native `currency` on the same object: `lowestOffer` on browse, `effectivePrice` on the PDP and the offers list, `lineTotal` on a cart or checkout line, `group` on a per-seller subtotal. `false` on seller surfaces (native amounts, never converted) and on order surfaces (captured amounts, read as-is). Drives the `≈` prefix and the info tooltip. Default `false`. **Do not test `fxRate`** — it exists only on `lowestOffer` and `effectivePrice`; `lineTotal` and `groups[]` carry no such key ([cart.md § Get cart](../technical-design/api-design/cart.md#get-cart)) |
| `estimatedFrom` | The **native** currency code on the same object as the amount, when it differs from the displayed one (required when `converted = true`): `lowestOffer.currency` on browse, `effectivePrice.currency` on the PDP and the offers list, `lineTotal.currency` on a cart or checkout line, `group.currency` on a per-seller subtotal. Seller surfaces bind the offer's `nativeCurrencyCode` for `currency`, but they never convert, so this stays unbound there |
| `fxAsOf` | ISO 8601 rate timestamp from the same object as the amount — `lowestOffer.fxAsOf` on browse, `effectivePrice.fxAsOf` on the PDP and the offers list, `lineTotal.fxAsOf` on a cart or checkout line, `group.fxAsOf` on a per-seller subtotal. A `lineTotal`'s pair mirrors its `effectivePrice` (the same rate converted both), and a group's follows the same three-case rule ([cart.md § Get cart](../technical-design/api-design/cart.md#get-cart)). Required when `converted = true`; `null` in the no-rate case, where `converted` is `false` anyway |
| `fxStale` | From the same object as `fxAsOf`, per surface family — `true` when that rate is older than `FX_STALE_AFTER_HOURS` (env, default 24). The component shows a visible "indicative" label when stale; that warning is separate from the estimated label and does not gate it (FR-P-02). Required when `converted = true`. `false` is the same-currency case, `null` the no-rate case |
| `saleEndsAt` | `effectivePrice.saleEndsAt` — the `SALE` price row's `endsAt`. Drives the countdown badge |

The cart's **cross-group** totals — `itemSubtotal` and `grandTotal` — are deliberately absent from the FX rows above. They are sums across groups with no single native currency, so `estimatedFrom` has no referent and `[converted]` stays unbound on them; FR-P-02's disclosure is a caption on the summary block instead. [buyer-portal.md § Totals](buyer-portal.md#totals) owns that rule.

**No screen computes a monetary value.** Line totals, subtotals and converted amounts arrive from the server as strings. There is no multiplication, addition or rounding of money in any template or component, and there is no FX service in a portal app ([frontend-coding-standards.md § 5](../../conventions/frontend-coding-standards.md#5-money-display-patterns)).

---

### 4.4 CurrencyInput

Contract: [design-system.md § 8.4](../../conventions/design-system.md#8-shared-component-library-libsui). A `ControlValueAccessor` emitting a decimal **string**, with a `mat-label` (never placeholder-only) and the currency code as `matSuffix`.

Used for every monetary input in Phase 1: the seller's price amount on the listing editor and the offer-pricing form, and both ends of the buyer's price-range filter. `<input type="number">` is never used for money, and a `mat-slider` is not permitted for a monetary range — a slider is bound to a JS `number`, which is the one thing money may not be.

`currencyCode` on the seller's price inputs is the parent **offer's** `nativeCurrencyCode`, not a per-row choice: an offer has exactly one pricing currency and every price row inherits it ([seller.md § Add/update offer price](../technical-design/api-design/seller.md#addupdate-offer-price)).

---

### 4.5 EmptyState

Contract: [design-system.md § 8.9](../../conventions/design-system.md#8-shared-component-library-libsui). Inputs `icon`, `title`, `message`; the CTA is **projected content**, not an input.

```html
<aliceut-empty-state icon="receipt_long" title="No orders yet"
                     message="Browse the catalog to get started">
  <button mat-flat-button color="primary" routerLink="/">Browse products</button>
</aliceut-empty-state>
```

There is no `actionLabel` and no `actionRoute`. A CTA that needs a `routerLink`, a click handler or a disabled state cannot be expressed as two string inputs, and every Phase 1 call site projects a button.

---

### 4.6 DataTable

Contract: [design-system.md § 8.6](../../conventions/design-system.md#8-shared-component-library-libsui). Inputs `dataSource`, `loading`, `emptyMessage`, `hasMore`, `hasPrevious`; outputs `nextPage`, `previousPage`, `filterChange`, `sortChange`, `selectionChange`.

**Columns are projected by the caller**, not declared through a `columns` array. Every table in Phase 1 needs custom cells — status badges, price strings, row action menus, selection checkboxes — so the caller projects `<ng-container matColumnDef="…">` blocks and the wrapper owns the shell: toolbar with the `[table-actions]` slot, search field, scroll wrapper, sticky header, loading overlay, empty state and the pagination footer.

**Pagination is Previous/Next, and there is no `MatPaginator`.** Every list endpoint is cursor-paginated and returns no total, so there is no `length` from which page numbers, a page count or "N of M" could be rendered ([api-conventions.md § Pagination](../../conventions/api-conventions.md#pagination), [frontend-coding-standards.md § 8](../../conventions/frontend-coding-standards.md#8-angular-material-usage-rules)). There is no `page`, `pageSize`, `total` or `pageChange` anywhere in the contract or at any call site.

The **smart component owns the cursor stack**: it pushes `meta.nextCursor` on `nextPage` and pops on `previousPage`, and passes `hasMore` straight from `meta.hasMore` and `hasPrevious` as "the stack is non-empty". The table never constructs or inspects a cursor — the token is opaque and its shape may change without an API version bump.

Because the user has no page count to infer position from, both boundaries are stated rather than implied: an empty page renders `EmptyState`, and the last page disables Next with the caption "End of list". A row count is never presented as a total.

Sorting emits `sortChange`; the smart component maps it to the endpoint's own sort parameter and **discards the cursor stack**, because a cursor is only valid for the sort and filter set it was issued under and presenting it against a different one is a plain `400`.

A short, non-paginated array — the `moderationHistory[]` on the admin seller-detail response, for instance — is rendered with a plain `mat-table` rather than this composite. Wrapping a fixed array in a paginated shell produces a footer whose controls can never do anything.

---

### 4.7 ConfirmDialog

Contract: [design-system.md § 8.5](../../conventions/design-system.md#8-shared-component-library-libsui).

```typescript
MatDialog.open(ConfirmDialogComponent, { data: config })
// → Observable<{ confirmed: boolean; reason?: string } | undefined>
```

`undefined` means dismissed by backdrop or Escape. Config: `title`, `message`, `confirmLabel`, `cancelLabel`, `requireReason`, `reasonLabel`, `reasonMaxLength` (default **500**), `danger`.

**The reason comes back on the result object.** Four flows send a reason to the API and this dialog is where it is typed — seller refund (US-S-07), seller cancel (US-S-11), admin listing removal (US-A-04) and admin reinstate (US-A-05b). Each passes `requireReason: true`; Confirm stays disabled until a non-whitespace reason is entered, the textarea shows a character counter, and `reasonMaxLength` defaults to 500 to match the API field limit on every one of those endpoints. When `requireReason` is false the field is absent and `reason` is `undefined`.

No flow gets a bespoke dialog, and there is no type-a-value-to-confirm input in the config. A confirmation that needs extra emphasis says so in `message` and sets `danger: true`.

---

### 4.8 FileUpload

Contract: [design-system.md § 8.8](../../conventions/design-system.md#8-shared-component-library-libsui). Inputs `accept`, `maxSizeMb`, `multiple`, `maxFiles`; output `filesChange`.

The component does not hold an upload URL. It is a picker with validation and per-file progress; the owning screen decides where the bytes go and names the endpoint. Per-file state is part of the contract: progress bar while uploading, success tick, and an inline error with a **Retry** action per file, plus a summary line when every file fails.

Phase-1 call sites:

| Screen | `accept` | `maxSizeMb` | `multiple` / `maxFiles` | Destination |
|---|---|---|---|---|
| Seller KYC documents — **three** instances, one per required document (business licence, government ID, bank statement / proof of address) | `application/pdf,image/jpeg,image/png` | 10 | no / 1 each | The three picked files are concatenated into `documents[]` in the `POST /seller/kyc` (or `/seller/kyc/resubmit`) multipart body. Three single-file pickers rather than one multi-file picker, because each slot names which document it wants and can show its own required-field error ([seller-portal.md § Screen 3](seller-portal.md#screen-3-kyc-application)) |
| Seller product images | `image/jpeg,image/png,image/webp` | 5 | yes / 10 | Uploaded ahead of `POST /seller/products`, which references the resulting storage keys |
| Seller inventory CSV | `.csv` | 5 | no / 1 | Sent as `file` in the `POST /seller/inventory/bulk` multipart body |
| Buyer business logo | `image/jpeg,image/png` | 5 | no / 1 | The profile logo endpoint in `api-design/profile.md` |

KYC uploads are additionally validated server-side on extension, **sniffed** MIME type and size; a type failure is `415` and an oversize file is `413`, and a rejected file fails the whole request rather than being dropped silently. Client-side `accept` and `maxSizeMb` are a courtesy, never the check that matters.

---

<a id="5-status-vocabulary"></a>
## 5. Status vocabulary by `statusType`

Which values each `statusType` receives in V1. Colour for every value below is resolved by the one map in [design-system.md § 8.2](../../conventions/design-system.md#8-shared-component-library-libsui).

| `statusType` | Values passed | Source |
|---|---|---|
| `order` | The derived order status — never stored, computed from the order's fulfillment statuses on read | `user-stories/buyer.md` derived-status table, surfaced as `orderStatus` |
| `fulfillment` | `PENDING`, `SHIPPED`, `DELIVERED`, `REFUNDED`, `CANCELLED` | `fulfillment_status` enum, complete |
| `listing` | `ACTIVE`, `INACTIVE`, `REMOVED`, `FLAGGED` | `offer_status` enum, complete |
| `kyc` | `PENDING`, `UNDER_REVIEW`, `APPROVED`, `REJECTED` — one KYC **application**'s outcome | `kyc_status` enum, `seller.kyc_application.status` |
| `kyc` | `PENDING_KYC`, `APPROVED`, `REJECTED` — the seller **profile**'s current standing | `seller_kyc_status` enum, `seller.seller_profile.kyc_status` |
| `seller` | `ACTIVE`, `SUSPENDED` | `seller.seller_profile.suspension_status` |

Four things this table is deliberate about:

- **There is no `DRAFT` listing status.** A listing goes live on submit; `offer_status` has four values and `DRAFT` is not one of them.
- **The two KYC vocabularies are different enums and both are real.** The application's `status` records one submission's outcome and is immutable once decided; the profile's `kyc_status` is the seller's current standing and moves back to `PENDING_KYC` on a resubmission. A KYC screen may legitimately show both, and neither is derivable from the other.
- **Seller standing is two independent columns, not one chain.** `kyc_status` and `suspension_status` are separate: a suspended seller can be KYC-approved, and an unsuspended one can be KYC-rejected. No screen renders them as a single status field or a single wizard track.
- **`SUSPENSION_EXPIRED` is not a stored value.** It is the derived condition `suspended_until < now()`, and no column, claim or response field holds it. Nothing passes it to a badge. (`SUSPENSION_EXPIRED` does exist as an in-app *notification type*, which is a different vocabulary — see [notifications.md](../technical-design/api-design/notifications.md).)

Moderation case status (`OPEN`, `RESOLVED`, `DISMISSED`) is **not** in the `statusType` union and is not rendered through `StatusBadge`. The admin moderation screens render it as a labelled `mat-chip` — see [admin-portal.md](admin-portal.md).

---

<a id="6-pipes"></a>
## 6. Pipes

Four pipes, all defined in [design-system.md § 15](../../conventions/design-system.md#15-custom-pipes) and exported from `@aliceut/shared-ui`. Each is standalone and listed individually in the importing component's `imports: []`.

| Pipe | Usage | Phase-1 notes |
|---|---|---|
| `timeAgo` | `{{ n.createdAt \| timeAgo }}` | Pure, and it does **not** auto-update. A relative label refreshes only when its host component re-runs change detection; nothing in Phase 1 needs a ticking clock, so no host schedules one |
| `truncate` | `{{ row.reason \| truncate:60 }}` | Used on moderation reasons and product titles inside table cells |
| `currencyDisplay` | `{{ item.unitPrice \| currencyDisplay:item.currencyCode }}` | Input is always a string amount. `Number()` is applied once, inside the pipe, at the `Intl.NumberFormat` boundary and never for arithmetic. Scale from `Currency.minor_unit_scale` |
| `safe` | `[href]="url \| safe:'url'"` | Only for URLs the platform itself issued. No user-supplied value is ever passed through it, and no Phase 1 screen passes a document or description through `safe:'html'` or `safe:'resourceUrl'` |

`PriceDisplay` uses `currencyDisplay` internally, so a screen rendering money through the composite does not import the pipe as well.

---

<a id="7-rules-every-screen-follows"></a>
## 7. Rules every screen follows

These hold on every wireframe in `buyer-portal.md`, `seller-portal.md` and `admin-portal.md`, so the individual screens do not repeat them.

**Standalone and OnPush.** Every component is standalone with `ChangeDetectionStrategy.OnPush`; an exception carries a comment saying why. Every feature route is lazily loaded with `loadComponent` or `loadChildren`.

**Three states, always.** Every data-fetching component defines loading, empty and error, using the discriminated union from [frontend-coding-standards.md § 2](../../conventions/frontend-coding-standards.md#2-component-architecture):

```typescript
type ViewState<T> =
  | { status: 'loading' }
  | { status: 'empty' }
  | { status: 'error'; message: string }
  | { status: 'loaded'; data: T };
```

Rendered with `@switch` on `viewState.status` — never an `*ngIf="data && !loading && !error"` chain, which makes the error state invisible. Each screen's **States** section names what the three look like there; the loading treatments themselves are in [design-system.md § 13](../../conventions/design-system.md#13-loading-state-patterns).

**Reactive forms only.** No `[(ngModel)]` anywhere, including inline table edits and search boxes — those are `FormControl`s. `mat-form-field` always carries a `mat-label`, `appearance="outline"` and `subscriptSizing="dynamic"`, and `mat-error` shows only after touch or submit.

**Money.** Amounts arrive as strings and are rendered through `PriceDisplay` or `currencyDisplay`; monetary input goes through `CurrencyInput`. No template performs arithmetic on an amount, and no monetary field is ever typed `number`.

**Pagination.** Cursor only: `limit` (20 by default) plus an opaque `cursor`, Previous/Next from the cursor stack, no total and no page numbers. A bad cursor is a `400`, so the stack is discarded whenever the sort or filter set changes.

**Accessibility.** Every portal shell opens with `<a class="skip-link" href="#main-content">Skip to main content</a>` as its first focusable element, and the shell's `<main>` carries `id="main-content"`. Every `mat-icon-button` without visible text has an `aria-label`. Every `<img>` has `alt` — product images use the product title, decorative images use `alt=""`. Colour is never the only carrier of state.

**Lists.** Every `*ngFor` over data that can change supplies `trackBy` returning the row's `id`; static lists such as enum option sets may omit it. Observables are consumed with the `async` pipe, or with `takeUntilDestroyed(this.destroyRef)` where an imperative subscription is unavoidable.

**Auth.** The access token lives in an in-memory field on `AuthService` — never `localStorage`, never `sessionStorage`. The refresh token is an HttpOnly cookie the frontend never reads. No token appears in a URL, a query string, or a rendered response.

---

<a id="8-auth-screen-pattern"></a>
## 8. Auth screen pattern

Nine screens across the three portals are the same card — buyer login, register, forgot-password and reset-password; seller login, register, forgot-password and reset-password; admin login. The shell, the two fields, the error surface and the submit button are specified once here; each portal's screen states only its route, its copy and its own outcomes.

### 8.1 Card shell

```
div.auth-page [display: flex; justify-content: center; align-items: flex-start; padding: 48px 16px]
  mat-card [width: 100%; max-width: 440px; padding: 32px]
    mat-card-header [text-align: center; margin-bottom: 24px]
      [portal mark — buyer: img aliceut-logo.svg alt="AliceUT" height=48; seller: mat-icon storefront;
       admin: mat-icon admin_panel_settings — both at font-size 48px, color primary]
      mat-card-title — [screen title]
      mat-card-subtitle — [optional one-line subtitle]
    mat-card-content
      [form]
    mat-card-footer [text-align: center; padding: 16px]
      [cross-link to the sibling screen]
```

Width deltas, and they are the only ones: buyer register and both reset screens use the same 440px; seller register uses **480px** because its form is longer; admin login uses **400px** and `padding: 40px` on a `background: grey-50` full-height page.

### 8.2 Email and password fields

Both fields are `mat-form-field [appearance=outline; fullWidth; subscriptSizing=dynamic]` with a `mat-label` — never a placeholder-only label ([§ 7](#7-rules-every-screen-follows)).

```
mat-form-field
  mat-label — Email address
  input matInput type="email" formControlName="email" autocomplete="email"
  mat-error *ngIf="email.touched && email.hasError('required')" — Email is required
  mat-error *ngIf="email.touched && email.hasError('email')" — Enter a valid email

mat-form-field
  mat-label — Password
  input matInput [type]="showPassword ? 'text' : 'password'" formControlName="password"
        [autocomplete]="current-password on a login, new-password everywhere else"
  button mat-icon-button matSuffix type="button" (click)="showPassword = !showPassword"
    [attr.aria-label]="showPassword ? 'Hide password' : 'Show password'"
    mat-icon — {{ showPassword ? 'visibility_off' : 'visibility' }}
```

The flag is named **`showPassword`** on every screen; a screen with a second password field names the second flag `showConfirmPassword`. The toggle button is always `type="button"` so it cannot submit the form, and it always carries an `aria-label`, since it has no visible text.

A confirm-password field is a plain second field of the same shape, with the mismatch reported at form level: `mat-error *ngIf="form.hasError('passwordMismatch')" — Passwords do not match`.

### 8.3 Error surface and submit

```
mat-card.error-banner *ngIf="error" [margin-bottom: 16px]
  mat-icon — error_outline
  span — {{ error }}

button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="form.invalid || isLoading"
  mat-spinner *ngIf="isLoading" [diameter]="20"
  span *ngIf="!isLoading" — [submit label]
```

The spinner **replaces** the label rather than sitting beside it, and every field is disabled while a submission is in flight. A field-level failure (`emailTaken`, a wrong current password) renders as `mat-error` on the offending field instead of in the banner.

### 8.4 Password policy

One rule, enforced identically on registration, change-password and reset-password on every portal, and re-enforced server-side ([backend-coding-standards.md](../../conventions/backend-coding-standards.md) holds the validator definition):

```
Pattern: /^(?=.*[a-zA-Z])(?=.*\d).{8,128}$/
- Minimum 8 characters, maximum 128
- At least one letter (either case) and at least one digit
- Validator messages:
  - Too short:               "Password must be at least 8 characters."
  - Too long:                "Password must not exceed 128 characters."
  - Missing letter or digit: "Password must contain at least one letter and one digit."
```

Every password field's hint is the same sentence: **"At least 8 characters, 1 letter, 1 number"**.

### 8.5 Rules the auth endpoints impose on all three portals

- **`portal` is a required field** on `POST /auth/login`, `POST /auth/forgot-password` and `POST /auth/reset-password` — `"BUYER" | "SELLER" | "ADMIN"` on login, `"BUYER" | "SELLER"` on the two password-reset calls, which have no admin form. Portal separation is enforced server-side, not by hiding a button ([auth.md § Portal scoping](../technical-design/api-design/auth.md#portal-scoping)).
- **Login outcomes** are the same everywhere: `401` is the generic "Incorrect email or password." with no field-level enumeration; a correct password at the wrong portal is `403` "This account cannot sign in from this portal." rather than `401`, because retrying the password cannot help; a suspended account is `403`; `429` names the `Retry-After` interval. There is no account lockout in V1.
- **Forgot-password answers `202` byte-identically** whether the address is unregistered, registered without the portal's role, or registered with it — the three cases must not be distinguishable, so the success banner is shown after every submission and the form is never re-armed with a different message. Rate limit 3 per hour per email. The submitted state is terminal for the page.
- **Reset-password renders its form optimistically.** There is no token pre-validation endpoint, so validity is decided by the `POST /auth/reset-password` response. A `400` covers expired, already used and wrong-portal tokens under **one** message — telling them apart would confirm that an account exists at another portal. Rate limit 5 attempts per token per hour. On success every session for the account is revoked and the page navigates to that portal's login with `?passwordReset=true`, where a success banner is shown.
- **Reset links are portal-scoped.** A seller link opens the seller form only and is rejected at the buyer one, and the rejection is the same generic `400`.
- **Tokens in a URL.** The only token that ever appears in a URL is the one-time link token on `/verify-email?token=` and `/reset-password?token=`, plus the 60-second OAuth authorization code on the buyer portal's `/auth/callback`. An access or refresh token never does ([§ 7 Auth](#7-rules-every-screen-follows)).
- **Admin has no register, forgot-password or reset screen.** Admin accounts are seeded (`admin@aliceut.dev`) and a password change is a direct database update in V1, so a reset link would lead nowhere.

---

<a id="9-notifications-page-pattern"></a>
## 9. Notifications page pattern

Each portal has one notifications page — `/notifications`, `/seller/notifications`, `/admin/notifications` — and all three are this layout over the same endpoints. Each portal's screen states only its route, its guard, its paging control and its own type table.

### 9.1 Layout

```
div.notifications-header [display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px]
  h1 — Notifications
  [optional filter control]
  button mat-stroked-button [disabled]="unreadCount === 0 || markingAll" (click)="markAllRead()" — Mark all as read

div.notifications-list [max-width: 800px]
  mat-card.notification-card *ngFor="let n of notifications; trackBy: trackByNotificationId"
    [class.unread]="!n.readAt"
    [display: flex; align-items: flex-start; gap: 16px; padding: 16px]
    mat-icon [color]="typeIconColor(n.type)" [font-size: 24px] — {{ typeIcon(n.type) }}
    div [flex: 1]
      p mat-body-1 [font-weight]="!n.readAt ? '600' : '400'" — {{ titleFor(n) }}
      p mat-body-2 color="secondary" — {{ bodyFor(n) }}
      p mat-caption color="secondary" — {{ n.createdAt | timeAgo }}
    div.unread-dot *ngIf="!n.readAt" [width: 8px; height: 8px; border-radius: 50%; background: var(--mat-primary); flex-shrink: 0; margin-top: 6px]
      span.cdk-visually-hidden — Unread

  [paging control — see 9.3]

<aliceut-empty-state *ngIf="!loading && notifications.length === 0"
  icon="notifications_none" title="[portal copy]" message="[portal copy]">
```

A whole card is the click target, so it carries `role="button"`, `tabindex="0"` and a `keydown.enter` handler alongside the click. The unread dot is paired with visually-hidden text, because colour alone never carries state ([§ 7](#7-rules-every-screen-follows)).

### 9.2 A row has no title and no body

`GET /notifications` returns `{ id, type, payload, readAt, createdAt }` and **no `title`, `body` or `link`** ([§ 4.1](#41-notificationbell)). `payload` is an opaque JSON object whose keys follow the source event's payload, so:

- `titleFor(n)` and `bodyFor(n)` compose both lines **client-side** from `type` plus substitutions taken from `payload`, using the portal's own type table. `typeIcon(n.type)` comes from the same table.
- A `type` the client does not recognise renders a generic title and no body rather than an empty card, so a newly added notification type degrades instead of disappearing.
- The navigation target is derived the same way — from `type` plus the ids in `payload`. A type with no destination marks the row read and navigates nowhere.
- Any monetary value substituted into a message is a **string** from `payload`, rendered with the `currencyDisplay` pipe against its own currency code. No amount is parsed to a number or arithmetically combined.

### 9.3 Paging and API calls

Cursor pagination, never pages ([§ 7](#7-rules-every-screen-follows)). Either control is acceptable and each portal names the one it uses: a **"Load more"** button that appends the next page, or a **Previous / Next** pair driven by the component's cursor stack. Both end with the `End of list` caption once `meta.hasMore` is false. Toggling a filter discards the stack and refetches from the first page.

| Action | Call |
|---|---|
| Initial load | `GET /notifications?limit=20` |
| Next page | `GET /notifications?limit=20&cursor={meta.nextCursor}` — no `page` parameter and no total |
| Unread filter | `GET /notifications?unreadOnly=true&limit=20` |
| Badge count | `GET /notifications/unread-count` → `{ data: { unreadCount } }` |
| Mark one read | `PATCH /notifications/:notificationId/read` → `{ data: { id, readAt } }`; the echoed `id` is the key the rendered row is matched against. A repeat call is a no-op returning the original `readAt` |
| Mark all read | `PATCH /notifications/read-all` → `{ data: { markedCount } }` |

A `404` on mark-read means the notification does not exist **or** belongs to another user; the two are indistinguishable by design, and the client removes the row and refreshes the page.

### 9.4 States

- **Loading:** three skeleton cards.
- **Empty:** `EmptyState` as above; with a filter applied, the portal's filtered-empty copy plus a clear-filter action.
- **End of list:** the paging control is replaced by the "End of list" caption.
- **Error:** error banner with a Retry action; already-loaded pages stay visible.
- **All read:** "Mark all as read" is disabled when `unreadCount` is `0`.
- **Mobile:** full-width cards; the header's controls wrap below the heading.

---

*Last updated: 2026-09-24 (UI-design consolidation)*
