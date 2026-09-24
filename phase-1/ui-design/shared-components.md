# Shared UI Components — AliceUT Phase 1
## Phase 1 usage registry for `libs/ui/`

**Status:** Complete  
**Stack:** Angular 22+ + Angular Material  
**Contract owner:** [conventions/design-system.md § 8](../../conventions/design-system.md#8-shared-component-library-libsui) and [§ 15](../../conventions/design-system.md#15-custom-pipes)  
**Scope:** Which shared components the Phase 1 screens use, and what each one is fed on those screens. buyer-app (4200), seller-app (4201), admin-app (4202).

---

## Summary

1. [How to read this document](#1-how-to-read)
2. [Where a component comes from](#2-where-a-component-comes-from)
3. [Component registry](#3-component-registry)
4. [Per-component phase-1 usage](#4-per-component-phase-1-usage)
5. [Status vocabulary by `statusType`](#5-status-vocabulary)
6. [Pipes](#6-pipes)
7. [Rules every screen follows](#7-rules-every-screen-follows)

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
| Seller KYC documents | `application/pdf,image/jpeg,image/png` | 10 | yes / 5 | Sent as `documents[]` in the `POST /seller/kyc` (or `/seller/kyc/resubmit`) multipart body |
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

*Last updated: 2026-09-14 (design alignment)*
