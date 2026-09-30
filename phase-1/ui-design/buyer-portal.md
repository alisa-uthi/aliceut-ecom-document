# Buyer Portal — UI Design Specification
## buyer-app (port 4200)

**Status:** Complete  
**Stack:** Angular 22+ + Angular Material + `libs/ui/` (`@aliceut/shared-ui`) composite components  
**Auth:** JWT; guest browsing and a guest cart are allowed, checkout requires an authenticated and email-verified account  
**Conventions:** [frontend-coding-standards.md](../../conventions/frontend-coding-standards.md), [design-system.md](../../conventions/design-system.md), [api-conventions.md](../../conventions/api-conventions.md)  
**API contracts:** [catalog.md](../technical-design/api-design/catalog.md), [search.md](../technical-design/api-design/search.md), [pricing.md](../technical-design/api-design/pricing.md), [cart.md](../technical-design/api-design/cart.md), [orders.md](../technical-design/api-design/orders.md), [profile.md](../technical-design/api-design/profile.md), [notifications.md](../technical-design/api-design/notifications.md), [auth.md](../technical-design/api-design/auth.md)

---

## Summary

- [Cross-cutting rules](#cross-cutting-rules)
- [Open contract dependencies](#open-contract-dependencies)
- [Shell Layout](#shell-layout)
- [Screen 1 — Home Page](#screen-1-home-page)
- [Screen 2 — Search Results](#screen-2-search-results)
- [Screen 3 — Product Detail Page (PDP)](#screen-3-pdp)
- [Screen 4 — Cart](#screen-4-cart)
- [Screen 5 — Checkout](#screen-5-checkout)
- [Screen 6 — Order Confirmation](#screen-6-order-confirmation)
- [Screen 7 — Order History](#screen-7-order-history)
- [Screen 8 — Order Detail](#screen-8-order-detail)
- [Screen 9 — Login](#screen-9-login)
- [Screen 10 — Register](#screen-10-register)
- [Screen 11 — Account Settings](#screen-11-account-settings)
- [Screen 12 — Email Verification Pending](#screen-12-email-verification-pending)
- [Screen 13 — Forgot Password](#screen-13-forgot-password)
- [Screen 14 — Reset Password](#screen-14-reset-password)
- [Screen 15 — Email Verification Callback](#screen-15-email-verification-callback)
- [Screen 16 — Notifications](#screen-16-notifications)
- [Appendix — Buyer Notification Types](#appendix-buyer-notifications)

<a id="cross-cutting-rules"></a>
## Cross-cutting rules

These apply to every screen below and are not repeated per screen.

### Components and imports

Where each component comes from and how it is imported is [shared-components.md § 2](shared-components.md#2-where-a-component-comes-from); standalone + OnPush, lazy feature routes, `trackBy` on every changeable list, reactive forms and cursor pagination are [§ 7](shared-components.md#7-rules-every-screen-follows). Neither is restated per screen below, and it is why the wireframes name `mat-*` primitives directly.

Smart (page) components inject services and fetch data; the `libs/ui` composites are presentational and inject no domain service.

### Money

Every monetary amount arrives from the API as a **string** and is rendered by `PriceDisplay` or the `currencyDisplay` pipe, which format with `Intl.NumberFormat` at the render boundary only. **No component multiplies, adds, or rounds a monetary value** — line totals, group subtotals, the item subtotal and the grand total are all server-computed fields, and there is no FX conversion anywhere in the client ([frontend-coding-standards.md § 5](../../conventions/frontend-coding-standards.md#5-money-display-patterns), FR-P-04a). Currency scale comes from `Currency.minor_unit_scale` (JPY 0, BHD 3, others 2), so no template hardcodes two decimal places. Monetary input uses `CurrencyInput`, never `<input type="number">` and never a numeric `mat-slider`. Seller pricing currencies in V1 are `USD`, `THB`, `JPY`, `SGD`.

`PriceDisplay`'s prop surface is owned by [design-system.md § PriceDisplay](../../conventions/design-system.md#83-pricedisplay) and the Phase-1 binding source for each input by [shared-components.md § 4.3](shared-components.md#43-pricedisplay). Neither is restated here. Two things are specific to this portal and stated only here:

- **Every buyer surface prefers the display-currency figure** — `displayAmount` / `displayCurrency` — and falls back to the native `amount` / `currency` when `displayAmount` is `null`, which is the no-rate case. The fallback follows the three-case FX nullability contract in [catalog.md § Get product offers](../technical-design/api-design/catalog.md#get-product-offers).
- **`converted` is derived in the template, never read from the response.** It is `true` when a non-null display amount is denominated in a currency other than the native one. No API response carries a `converted` flag, so the expression is the contract.

<a id="pagination"></a>
### Pagination

Every list is **cursor-paginated**: the request carries `limit` (default 20, max 100) and an opaque `cursor`, and the response carries `{ data, meta: { nextCursor, hasMore } }` with **no total** ([api-conventions.md § Pagination](../../conventions/api-conventions.md#pagination)). Consequences for this portal:

- There is **no `MatPaginator` and no page-number control on any screen.** Tables use the `DataTable` Previous/Next footer; grids and feeds use either a Previous/Next pair or a "Load more" button. The smart component owns the cursor stack — push `meta.nextCursor` on Next, pop on Previous — because the cursor is opaque and no component may construct one.
- No count of results is ever displayed, and no page count or "N of M". Because the buyer cannot infer position from a page number, every list states its boundaries: an empty result renders `EmptyState`, and the last page disables Next with an "End of list" caption.
- **Query parameters carry what defines the list, never a position in it**, and **no cursor ever appears in a URL, a bookmark or a shared link** — so a shared link always opens at the first page of the named list. The full rule, and why `page` is not coming back, is in [navigation-routing.md § 8](navigation-routing.md#deep-link-behavior).

### Display ids

An order is `ORD-` plus nine zero-padded digits (`ORD-000001042`); a fulfillment is `FUL-000003871`; a tracking number is `TRK-000003871` ([orders.md § The Order Aggregate](../technical-design/api-design/orders.md#the-order-aggregate)). Buyer screens address and label orders with `ORD-`. A fulfillment is always shown as a child of its order and is never called an order.

### Order status

An order's status is **derived on read** from its fulfillments and arrives as `orderStatus`; no row stores it. It may hold values a fulfillment never holds — `COMPLETED`, `IN_PROGRESS`, `PARTIALLY_SHIPPED`, `PARTIALLY_DELIVERED`, `PARTIALLY_REFUNDED` — while `fulfillment.status` is the stored enum `PENDING | SHIPPED | DELIVERED | REFUNDED | CANCELLED`. The two are rendered by the same `StatusBadge` with different `statusType` values (`'order'` / `'fulfillment'`) and are never mixed in one filter ([orders.md § Derived Order Status](../technical-design/api-design/orders.md#derived-order-status)).

### States

Every data-fetching screen defines loading, empty and error through the `ViewState<T>` union in [shared-components.md § 7](shared-components.md#7-rules-every-screen-follows). On this portal loading is skeletons for grids and tables, and a spinner inside the button for an in-flight action.

### Images

Catalog and search responses carry product images as `images[].storageKey`, not as URLs. The client resolves a key to its object-storage URL through one shared helper (`imageUrl(image)`); no template concatenates a bucket path, and a missing or unresolvable key renders the `image` placeholder icon on a grey field with the product title as `alt` — the `ProductCard` missing-image state.

### Accessibility

The skip link, the `mat-label` rule, `aria-label` on icon-only buttons, `alt` on every image and never-colour-alone are [shared-components.md § 7](shared-components.md#7-rules-every-screen-follows). One rule is specific to this portal: product images below the fold use `loading="lazy"`, and the PDP's primary image uses `loading="eager"`.

### Out of scope in V1

No screen, control or empty state in this portal designs for reviews or ratings, a wishlist, recommendations or "related products", dispute mediation, a real payment gateway, real carrier shipping, or internationalisation (BRD § 3.2; the rating filter and rating display were removed from FR-B-03 by the 2026-09-14 amendment recorded in BRD § 12). Shipping and tax are **structural zeroes**: both are always the string `"0.00"`, carried by the cart and order contracts so a later phase changes the value rather than the shape.

<a id="open-contract-dependencies"></a>
## Open contract dependencies

One binding this portal needs is required by a user story but has no field in the API contract that would supply it. It is recorded here rather than bound to an invented field name.

| Need | Required by | Gap |
|---|---|---|
| Cart line thumbnail and a link to the product | US-B-06 — "Cart page shows each line item's image, product and seller" | [cart.md § Get cart](../technical-design/api-design/cart.md#get-cart) items carry `offerId`, `productTitle`, `variantLabel`, `sellerId`, `sellerName`, `quantity`, `effectivePrice`, `lineTotal`, `availableQty`, `offerStatus` — no image reference and no product id. Product images cross catalog responses as `images[].storageKey`, which the client resolves; the cart item shape needs the same. Until it has one, the cart line renders the image slot as a placeholder and the product title is plain text rather than a link to the PDP. |

---

<a id="shell-layout"></a>
## Shell Layout

```
a.skip-link href="#main-content" — "Skip to main content"   ← first focusable element in the DOM

mat-toolbar [color=primary] [sticky top-0 z-100]
  a routerLink="/"
    img.logo [src=aliceut-logo.svg, alt="AliceUT", height=36]
  div.search-bar [flex: 1; max-width: 640px; margin: 0 24px]
    mat-form-field [appearance=outline; subscriptSizing=dynamic; width=100%]
      mat-label — Search products
      mat-icon matPrefix — search
      input matInput [formControl]="searchCtrl" (keyup.enter)="onSearch()"
  div.toolbar-actions
    button mat-icon-button routerLink="/cart" [matBadge]="cartCount()" [matBadgeHidden]="cartCount() === 0" aria-label="Cart"
      mat-icon — shopping_cart
      span.cdk-visually-hidden — {{ cartCount() }} items in cart
    <aliceut-notification-bell *ngIf="isLoggedIn"
      [notifications]="recentNotifications" [unreadCount]="unreadCount"
      (markAsRead)="markRead($event)" (markAllRead)="markAllRead()">
    button mat-button [matMenuTriggerFor]="userMenu" *ngIf="isLoggedIn"
      mat-icon — account_circle
      span.user-name — {{ displayName }}
      mat-chip.business-badge *ngIf="accountType === 'B2B'" color="accent" — Business
    button mat-flat-button color="primary" routerLink="/login" *ngIf="!isLoggedIn" — Sign In
    button mat-button routerLink="/register" *ngIf="!isLoggedIn" — Register
  mat-menu #userMenu
    button mat-menu-item routerLink="/orders" — receipt_long icon — My Orders
    button mat-menu-item routerLink="/account" — settings icon — Account Settings
    mat-divider
    button mat-menu-item (click)="logout()" — logout icon — Sign Out

main#main-content.page-content [max-width: 1440px; margin: 0 auto; padding: 24px 16px]
  router-outlet
```

**Cart badge.** `cartCount` is a `computed()` over `CartService`'s items — the sum of `quantity` across lines, a count and not a monetary value. For a signed-in buyer the lines come from `GET /cart`; for a guest they come from the `localStorage` guest cart (US-B-08).

**Notification bell.** `unreadCount` is bound from `GET /notifications/unread-count`, which returns `{ data: { unreadCount } }` computed per call over the caller's unread rows — there is no counter column and no cached count ([notifications.md § Get unread count](../technical-design/api-design/notifications.md#get-unread-count)). The badge is hidden at zero and displays `99+` above 99 without changing the returned number. `notifications` is the first page of `GET /notifications?limit=…` for the dropdown. The parent polls on page focus and on a 60s interval; there is no WebSocket in V1. The bell renders only when authenticated.

**Business badge.** `accountType` comes from the `accountType` field of `GET /profile/me` (mirroring the `account_type` JWT claim). B2B differentiation in V1 is branding only — the badge, the business name and the logo on invoices. There is no separate B2B navigation, no bulk pricing surface and no invoicing screen.

**Mobile (< 600px):** search bar collapses to a search icon button that expands inline. Logo + search icon + cart icon + hamburger. The user menu becomes a drawer slide-in. The skip link stays first in the DOM at every breakpoint.

---

<a id="screen-1-home-page"></a>
## Screen 1 — Home Page

**Route:** `/`  
**Auth:** None required

### Layout

```
section.hero-search [text-align: center; padding: 48px 24px; bg: primary light]
  h1 mat-headline-2 — "Find your next great deal"
  mat-form-field [width: 100%; max-width: 640px; appearance=outline]
    mat-label — What are you looking for?
    mat-icon matPrefix — search
    input matInput [formControl]="heroQueryCtrl" (keyup.enter)="search()"
    button mat-icon-button matSuffix (click)="search()" aria-label="Search"
      mat-icon — arrow_forward

section.categories [padding: 24px 0]
  h2 mat-headline-5 — "Shop by Category"
  div.category-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 16px]
    mat-card.category-tile *ngFor="let cat of categories; trackBy: trackByCategoryId"
      [routerLink]="['/search']" [queryParams]="{ categoryId: cat.id }"
      mat-icon [font-size: 40px] — [cat.icon]
      span mat-body-2 — {{ cat.name }}

section.latest-products [padding: 24px 0]
  h2 mat-headline-5 — "Latest Products"
  mat-divider
  div.product-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; margin-top: 16px]
    <aliceut-product-card *ngFor="let p of products; trackBy: trackByProductId"
      [product]="p.product" [effectivePrice]="p.effectivePrice" [inStock]="p.inStock"
      (addToCart)="addToCart($event)" (cardClick)="openPdp($event)">
    <aliceut-product-card *ngFor="let s of skeletonSlots" [loading]="true" *ngIf="loading">
  div.load-more *ngIf="!loading && hasMore" [text-align: center; margin-top: 24px]
    button mat-stroked-button color="primary" (click)="loadMore()" — Load more
  p.end-of-list mat-caption *ngIf="!loading && !hasMore && products.length > 0" [text-align: center]
    — End of list
```

### Data sources

- **Categories** — `GET /catalog/categories`, the full tree. Not paginated: the taxonomy is bounded. The tile grid renders root categories; the tree itself is used by the search sidebar.
- **Products** — `GET /search/products?sortBy=newest&limit=20`, with no `q`. This endpoint is used rather than `GET /catalog/products` because the catalog list response carries no price, and a `ProductCard` renders one. `lowestOffer` maps to the card's `effectivePrice`, `inStock` to its `inStock` input, and `images[].storageKey` to the card image. Paging appends the next page using `meta.nextCursor` / `meta.hasMore`.

**There is no "featured", "recommended" or "related products" surface.** No endpoint exposes a featured flag, and recommendations are out of V1 scope (BRD § 3.2). The section is the newest listings, and it says so.

### States

- **Loading:** eight skeleton `ProductCard` components fill the grid while the first page resolves.
- **Empty (no products):** `EmptyState` with `icon="category"`, `title="No products yet"`, `message="Check back soon — the catalog is being stocked."` The category tiles still render, so navigation works with an empty grid.
- **End of list:** "Load more" is replaced by the "End of list" caption. The buyer has no page count to infer this from, so it is stated.
- **Error:** `mat-card.error-banner` above the grid — "Could not load products. Try again." with a Retry action.

### Interactions

- Hero search submits on Enter or the arrow button → `/search?q={query}`.
- Category tile → `/search?categoryId={id}`.
- `addToCart` from a card adds the card's offer at quantity 1 — see [Screen 3](#screen-3-pdp) for the add-to-cart contract, which is identical.

### Mobile

- Category grid `minmax(80px, 1fr)`; product grid `minmax(160px, 1fr)` (two columns on handset).

---

<a id="screen-2-search-results"></a>
## Screen 2 — Search Results

**Route:** `/search?q=&categoryId=&priceMin=&priceMax=&currency=&inStock=&sortBy=`  
**Auth:** None required

Query-parameter names match [search.md § Product search](../technical-design/api-design/search.md#product-search) exactly: `categoryId`, `priceMin`, `priceMax`, `currency`, `inStock`, `sortBy` with camelCase values (`relevance`, `priceAsc`, `priceDesc`, `newest`). There is **no `page`, no `pageSize` and no cursor in the URL** — see [Pagination](#pagination) above. There is **no `minRating`**: no rating field exists in the search index, the ERD or any result object.

### Layout

```
div.search-layout [display: flex; gap: 24px]

  <!-- Sidebar — desktop only; on mobile the same accordion opens in a MatBottomSheet -->
  aside.filter-sidebar [width: 260px; flex-shrink: 0] *ngIf="isDesktop"
    div.filter-section
      h3 mat-headline-6 — "Filters"
      button mat-stroked-button (click)="clearAllFilters()" *ngIf="activeFilterCount > 0" — Clear all

    mat-accordion
      mat-expansion-panel [expanded]
        mat-expansion-panel-header
          mat-panel-title — "Category"
        mat-tree [dataSource]="categoryTree" [treeControl]
          mat-tree-node *matTreeNodeDef — mat-checkbox + label per category leaf, with the facet count
          mat-nested-tree-node *matTreeNodeDef="let node; when: hasChildren" — expandable group

      mat-expansion-panel [expanded]
        mat-expansion-panel-header — "Price Range"
        div.price-inputs [display: flex; gap: 8px]
          <aliceut-currency-input [flex: 1]
            label="Min" [currencyCode]="displayCurrency"
            [min]="facets.priceRange.displayMin" [max]="facets.priceRange.displayMax"
            [formControl]="priceMinCtrl">
          <aliceut-currency-input [flex: 1]
            label="Max" [currencyCode]="displayCurrency"
            [min]="facets.priceRange.displayMin" [max]="facets.priceRange.displayMax"
            [formControl]="priceMaxCtrl">
        p.price-note mat-caption — Prices shown in {{ displayCurrency }}. Converted amounts are estimates.

      mat-expansion-panel
        mat-expansion-panel-header — "Availability"
        mat-slide-toggle [formControl]="inStockOnlyCtrl" — In stock only

    button mat-flat-button color="primary" [fullWidth] (click)="applyFilters()" — Apply Filters

  <!-- Main results area -->
  main.results-area [flex: 1; min-width: 0]
    div.results-header [display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-bottom: 16px]
      p mat-body-2 *ngIf="query" — Results for "{{ query }}"
      div.active-filters [display: flex; gap: 8px; flex-wrap: wrap; flex: 1]
        mat-chip-listbox aria-label="Active filters"
          mat-chip *ngFor="let f of activeFilters; trackBy: trackByFilterKey" [removable]="true" (removed)="removeFilter(f)"
            {{ f.label }}
            mat-icon matChipRemove — cancel
      mat-form-field [appearance=outline; width: 200px; subscriptSizing=dynamic]
        mat-label — Sort by
        mat-select [formControl]="sortCtrl"
          mat-option value="relevance" — Relevance
          mat-option value="priceAsc"  — Price: Low to High
          mat-option value="priceDesc" — Price: High to Low
          mat-option value="newest"    — Newest

    <!-- Mobile filter trigger -->
    button mat-stroked-button color="primary" (click)="openFilterSheet()" *ngIf="!isDesktop" [margin-bottom: 16px]
      mat-icon — filter_list
      span — Filters {{ activeFilterCount > 0 ? '(' + activeFilterCount + ')' : '' }}

    <!-- Product grid -->
    div.product-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px]
      <aliceut-product-card *ngFor="let r of results; trackBy: trackByProductId"
        [product]="r.product" [effectivePrice]="r.effectivePrice" [inStock]="r.inStock"
        (addToCart)="addToCart($event)" (cardClick)="openPdp($event)">
      <aliceut-product-card *ngFor="let s of skeletonSlots" [loading]="true" *ngIf="loading">

    <!-- No results -->
    <aliceut-empty-state *ngIf="!loading && results.length === 0"
      icon="search_off" title="No matches for '{{ query }}'"
      message="Try different keywords or remove some filters.">
      div — Suggested categories: [category chip list from facets.categories]
    </aliceut-empty-state>

    <!-- Cursor pagination footer — Previous / Next only -->
    div.results-footer *ngIf="results.length > 0" [display: flex; align-items: center; gap: 16px; justify-content: center]
      button mat-button (click)="previousPage()" [disabled]="!hasPrevious || loading" — Previous
      span.row-count mat-caption — {{ results.length }} results on this page
      button mat-button (click)="nextPage()" [disabled]="!hasMore || loading" — Next
      span.end-of-list mat-caption *ngIf="!hasMore" — End of list

    <!-- Search unavailable -->
    mat-card.error-banner *ngIf="searchError" [color=warn-light; margin-bottom: 16px]
      mat-icon — error_outline
      span — Search is temporarily unavailable — try again shortly.
      button mat-button (click)="retry()" — Retry
```

### Data source and mapping

`GET /search/products`. Each result carries `productId`, `title`, `brand`, `categoryId`, `categoryPath`, `images[].storageKey`, `lowestOffer`, `inStock` and `score`. `lowestOffer` maps to `ProductCard.effectivePrice`; its `displayAmount` / `displayCurrency` / `fxRate` / `fxAsOf` / `fxStale` fields drive the `≈` prefix and the indicative-rate tooltip inside `PriceDisplay`. `lowestOffer.priceType` is only ever `LIST` or `SALE` — `B2B_TIER` is not a V1 price type.

`facets.categories` supplies the per-category counts beside the tree checkboxes. `facets.priceRange` supplies `displayMin` / `displayMax`, which bound the two `CurrencyInput` fields; both are `null` together when no FX rate exists for the pair, and the fields then have no bounds.

**The price filter is two `CurrencyInput` fields, not a slider.** A numeric `mat-slider` binds a JS `number` to money, which FR-P-04 forbids, and `CurrencyInput` is the control the design system designates for both ends of a price range. Bounds are passed as decimal **strings** through `min` / `max`. The filter is applied by Elasticsearch against the pre-indexed `display_prices` value for the requested currency, so results may lag an FX-rate change by the index freshness window (NFR-13).

**No rating filter.** The panel is removed, not hidden behind a flag.

### States

- **Loading:** sort control and filter sidebar disabled; skeleton product cards fill the grid.
- **Zero results:** `EmptyState` with suggested category chips drawn from `facets.categories`.
- **Search service down:** error banner above the grid; a previously loaded page stays visible.
- **Active filters:** a chip row in the results header, each chip removable individually.
- **First page / last page:** Previous is disabled on the first page (the cursor stack is empty); Next is disabled when `meta.hasMore` is false and the "End of list" caption appears.

### Mobile

- Sidebar hidden, replaced by the "Filters (N)" button opening a `MatBottomSheet` with the same accordion and an Apply button pinned at the bottom.
- Product grid `minmax(160px, 1fr)`; sort control full width below the Filters button.

---

<a id="screen-3-pdp"></a>
## Screen 3 — Product Detail Page (PDP)

**Route:** `/products/:id`  
**Auth:** None required. A guest may add to cart — the item goes to the `localStorage` guest cart and is merged on sign-in (US-B-08, [cart.md](../technical-design/api-design/cart.md)). Sign-in is required at checkout, not here.

### Data sources

Two reads, because the display-currency fields and the seller name are returned only by the second form of the offer resource:

- `GET /catalog/products/:productId` — title, brand, description, `attributes`, `variants[]`, `images[]`, and `offers[]` with `effectivePrice` (native currency), `availableQty`, `status`.
- `GET /catalog/products/:productId/offers?currency=` — the same offers with `sellerName` and the `displayAmount` / `displayCurrency` / `fxRate` / `fxAsOf` / `fxStale` fields. `currency` defaults to the caller's `preferredCurrency`, then `USD`.

### Layout

```
div.pdp-layout [display: grid; grid-template-columns: 1fr 380px; gap: 32px; align-items: start] [desktop]
  <!-- Left: gallery + description -->
  div.pdp-left
    nav.breadcrumb [display: flex; gap: 4px; align-items: center; margin-bottom: 16px] aria-label="Breadcrumb"
      a mat-button routerLink="/" — Home
      mat-icon [font-size: 16px] — chevron_right
      a mat-button *ngFor="let crumb of breadcrumbs; trackBy: trackByCategoryId"
        [routerLink]="['/search']" [queryParams]="{ categoryId: crumb.id }" — {{ crumb.name }}

    div.image-gallery
      div.primary-image [aspect-ratio: 1; border-radius: 8px; overflow: hidden; border: 1px solid divider]
        img [src]="imageUrl(selectedImage)" [alt]="product.title" loading="eager"
          [object-fit: cover; width: 100%; height: 100%]
      div.thumbnail-strip [display: flex; gap: 8px; margin-top: 8px; overflow-x: auto]
        button.thumb *ngFor="let img of product.images; let i = index; trackBy: trackByStorageKey"
          (click)="selectImage(img)" [attr.aria-label]="'View image ' + (i + 1)"
          img [src]="imageUrl(img)" alt="" loading="lazy" [class.selected]="img === selectedImage"
          [width: 64px; height: 64px; border-radius: 4px; border: 2px solid transparent]

    mat-tab-group [marginTop: 32px]
      mat-tab label="Description"
        div.product-description [padding: 16px 0] [innerHTML]="sanitizedDescription"
      mat-tab label="Details"
        mat-list
          mat-list-item *ngFor="let entry of product.attributes | keyvalue; trackBy: trackByAttributeKey"
            span mat-list-item-title — {{ entry.key }}
            span mat-list-item-line — {{ entry.value }}

    <!-- Other sellers (FR-P-05) -->
    div.other-sellers *ngIf="otherOffers.length > 0" [margin-top: 32px]
      h3 mat-headline-6 — "Other sellers offering this product"
      mat-list
        mat-list-item *ngFor="let offer of otherOffers; trackBy: trackByOfferId"
          mat-icon matListItemIcon — storefront
          span mat-list-item-title — {{ offer.sellerName }}
          <aliceut-price-display matListItemMeta
            [amount]="priceOf(offer)" [currency]="currencyOf(offer)"
            [priceType]="offer.effectivePrice.priceType"
            [compareAtAmount]="offer.effectivePrice.compareAtAmount"
            [converted]="isFxEstimate(offer)" [estimatedFrom]="offer.effectivePrice.currency"
            [fxAsOf]="offer.effectivePrice.fxAsOf" [fxStale]="offer.effectivePrice.fxStale"
            [saleEndsAt]="offer.effectivePrice.saleEndsAt">
          button mat-stroked-button (click)="selectOffer(offer)" *ngIf="offer.id !== selectedOffer.id" — Select
          mat-chip *ngIf="offer.id === selectedOffer.id" color="primary" — Selected

  <!-- Right: buy box -->
  aside.buy-box [position: sticky; top: 88px]
    mat-card [padding: 24px]
      h1 mat-headline-3 [margin-bottom: 8px] — {{ product.title }}

      div.seller-line [display: flex; align-items: center; gap: 8px; margin-bottom: 16px]
        mat-icon [font-size: 16px] — storefront
        span mat-body-2 — Sold by
        span mat-body-2 [font-weight: 500] — {{ selectedOffer.sellerName }}

      <aliceut-price-display
        [amount]="priceOf(selectedOffer)" [currency]="currencyOf(selectedOffer)"
        [priceType]="selectedOffer.effectivePrice.priceType"
        [compareAtAmount]="selectedOffer.effectivePrice.compareAtAmount"
        [converted]="isFxEstimate(selectedOffer)"
        [estimatedFrom]="selectedOffer.effectivePrice.currency"
        [fxAsOf]="selectedOffer.effectivePrice.fxAsOf"
        [fxStale]="selectedOffer.effectivePrice.fxStale"
        [saleEndsAt]="selectedOffer.effectivePrice.saleEndsAt">

      <!-- Variant selector -->
      div.variant-selectors *ngIf="variantGroups.length > 0" [margin-top: 16px]
        div *ngFor="let group of variantGroups; trackBy: trackByAttributeKey" [margin-bottom: 12px]
          p mat-body-2 [margin-bottom: 4px] — {{ group.key }}: <strong>{{ selectedVariantValues[group.key] }}</strong>
          div.variant-options [display: flex; gap: 8px; flex-wrap: wrap]
            button mat-stroked-button *ngFor="let opt of group.values; trackBy: trackByAttributeValue"
              (click)="selectVariantValue(group.key, opt)"
              [attr.aria-pressed]="selectedVariantValues[group.key] === opt"
              [disabled]="!isAvailable(group.key, opt)"
              — {{ opt }}

      <!-- Availability -->
      div.availability-badge [margin-top: 12px; display: flex; align-items: center; gap: 8px]
        mat-icon [color]="stockBadge.color" — {{ stockBadge.icon }}
        span mat-body-2 [color]="stockBadge.color" — {{ stockBadge.label }}
          ← "In stock" · "Only N left" · "Out of stock", from selectedOffer.availableQty

      <!-- Quantity -->
      div.quantity-selector [display: flex; align-items: center; gap: 16px; margin-top: 16px]
        p mat-body-2 — Quantity
        div [display: flex; align-items: center; gap: 8px]
          button mat-icon-button [disabled]="qty <= 1" (click)="setQty(qty - 1)" aria-label="Decrease quantity" — remove
          span mat-headline-6 [min-width: 32px; text-align: center] — {{ qty }}
          button mat-icon-button [disabled]="qty >= selectedOffer.availableQty" (click)="setQty(qty + 1)" aria-label="Increase quantity" — add

      <!-- Add to Cart -->
      button mat-flat-button color="accent" [fullWidth] [disabled]="!canAddToCart || addingToCart"
        (click)="addToCart()" [margin-top: 16px]
        mat-spinner *ngIf="addingToCart" [diameter]="20"
        span *ngIf="!addingToCart" — {{ inStock ? 'Add to Cart' : 'Out of Stock' }}

      mat-error *ngIf="addToCartError" — {{ addToCartError }}
```

### Variant selector derivation

There is no `variantGroups` field in the catalog contract. The selector is derived: one option group per attribute key found across `product.variants[].attributes`, its values being the distinct values of that key. A variant's availability is the `availableQty` of the offer whose `variantId` matches it; a variant with no eligible offer is disabled. On load the first in-stock variant is selected; when every variant is out of stock the first is shown with the out-of-stock badge and Add to Cart disabled (US-B-05).

### Effective price

Resolution is server-side and picks a `price_type` by current time only — `SALE` (live window) → `LIST` fallback. Account type and quantity are not inputs (BRD FR-P-06b). **There is no currency ambiguity:** an offer has exactly one pricing currency, `effectivePrice.currency`, and a seller wanting a second currency publishes a second offer. When the resolved `priceType` is `SALE`, `compareAtAmount` holds the live LIST amount and is bound to `PriceDisplay` for struck-through display (US-B-05).

### Add to cart

- **Signed in:** `POST /cart/items { offerId, quantity }`. The request **adds** to the stored quantity for an offer already in the cart; it does not replace it. `422` on a resulting quantity above `availableQty` — the stored quantity is left unchanged and the message is "Only N available." `422` also on the 50-distinct-offer cart limit — "Cart limit reached. Remove an item to continue." `404` when the offer is no longer `ACTIVE`.
- **Guest:** the offer id and quantity go to the `localStorage` guest cart. On sign-in the client posts them to `POST /cart/merge`, which sums quantities per offer and caps at live stock — see [Screen 4](#screen-4-cart) for the merge report.
- Success shows a `MatSnackBar` (3s, bottom-center) and the header badge increments.

### States

- **Loading:** skeleton layout — grey rectangle for the image, skeleton lines for title, price and buttons.
- **Out-of-stock variant:** Add to Cart disabled with the label "Out of Stock"; badge red "Out of stock".
- **All variants out of stock:** first variant selected, out-of-stock badge, CTA disabled.
- **FX estimate:** `PriceDisplay` renders the `≈` prefix and the info tooltip naming both currencies. A stale rate is still shown, labelled indicative.
- **No rate for the pair:** `displayAmount` is `null`; the native amount is shown alone with no `≈`.
- **SALE:** SALE chip with countdown from `saleEndsAt`. The struck-through list price is rendered from `compareAtAmount` — bound to `PriceDisplay.[compareAtAmount]`.
- **Error:** product load failure renders an error banner with a Retry action; a `404` routes to the not-found page.

### Mobile (< 960px)

Two columns collapse to one. The buy box renders below the gallery and is not sticky. Gallery is full width; variant buttons wrap.

### Accessibility

`<h1>` on the product title. Image `alt` is the product title; thumbnails are `alt=""` with `aria-label="View image N"` on the button. Variant buttons carry `aria-pressed`. The availability badge pairs colour with text.

---

<a id="screen-4-cart"></a>
## Screen 4 — Cart

**Route:** `/cart`  
**Auth:** None required. A guest cart is supported and lives in `localStorage`; the checkout CTA sends a guest to sign in.

The route deliberately carries **no `authGuard`**. US-B-08 requires a guest cart to survive reloads and tabs, and `cart.md` puts guest carts in browser storage with `POST /cart/merge` reconciling them at login; a guard on this route would make that story unreachable.

### Data source

`GET /cart` returns fully resolved, server-computed totals and **is the checkout preview** — there is no separate preview endpoint, and none is to be added ([cart.md § Get cart](../technical-design/api-design/cart.md#get-cart)). Prices are re-resolved live on every read, so a seller's price edit or a SALE starting is reflected on entry. `POST /cart/items`, `PATCH /cart/items/:id` and `POST /cart/merge` all return the whole cart in the same shape, so the page never recomputes a total after a quantity change.

For a guest the page renders from `localStorage`; per-line prices and availability are unresolved until sign-in, and the summary shows no totals.

### Layout

```
h1 mat-headline-3 — "Shopping Cart" ({{ itemCount }} items)

div.cart-layout [display: grid; grid-template-columns: 1fr 340px; gap: 24px; align-items: start] [desktop]

  <!-- Cart items -->
  div.cart-items
    <!-- Unavailable-line warning -->
    mat-card.error-banner *ngIf="unavailableItems.length > 0" [margin-bottom: 16px]
      mat-icon color="warn" — error_outline
      span — {{ unavailableItems.length }} item(s) are no longer available. Remove them to continue to checkout.

    mat-list [margin-bottom: 16px]
      div.cart-item *ngFor="let item of cart.items; trackBy: trackByCartItemId"
        [display: flex; gap: 16px; padding: 16px 0; border-bottom: 1px solid divider]

        div.item-thumb [width: 80px; height: 80px; border-radius: 4px]
          [product image for the line — see Open contract dependencies; placeholder icon until the field exists]

        div.item-details [flex: 1]
          p mat-body-1 [font-weight: 500] — {{ item.productTitle }}
          p mat-caption *ngIf="item.variantLabel" — {{ item.variantLabel }}
          p mat-body-2 — Sold by: {{ item.sellerName }}

          <!-- Unavailable line -->
          mat-chip color="warn" *ngIf="item.offerStatus !== 'ACTIVE'" — Unavailable
          p mat-caption color="warn" *ngIf="item.offerStatus !== 'ACTIVE'" — This offer is no longer active.

          <!-- Quantity controls (hidden on an unavailable line) -->
          div.qty-controls *ngIf="item.offerStatus === 'ACTIVE'" [display: flex; align-items: center; gap: 8px; margin-top: 8px]
            button mat-icon-button [disabled]="item.quantity <= 1" (click)="setQty(item, item.quantity - 1)" aria-label="Decrease quantity" — remove
            span mat-body-1 — {{ item.quantity }}
            button mat-icon-button [disabled]="item.quantity >= item.availableQty" (click)="setQty(item, item.quantity + 1)" aria-label="Increase quantity" — add
            mat-error *ngIf="item.qtyError" — {{ item.qtyError }}   ← "Only N available."

        div.item-price [text-align: right]
          <aliceut-price-display
            [amount]="item.lineTotal.displayAmount ?? item.lineTotal.amount"
            [currency]="item.lineTotal.displayAmount ? item.lineTotal.displayCurrency : item.lineTotal.currency"
            [priceType]="'LIST'"
            [converted]="!!item.lineTotal.displayAmount && item.lineTotal.displayCurrency !== item.lineTotal.currency"
            [estimatedFrom]="item.lineTotal.currency"
            [fxAsOf]="item.lineTotal.fxAsOf" [fxStale]="item.lineTotal.fxStale">
          button mat-button color="warn" (click)="removeItem(item)" — Remove

  <!-- Order summary -->
  aside.order-summary
    mat-card [padding: 24px]
      h2 mat-headline-6 [margin-bottom: 16px] — Order Summary
      mat-divider [margin-bottom: 16px]

      <!-- Per seller/currency group, exactly as checkout will group them -->
      div.summary-rows
        div.summary-row *ngFor="let group of cart.groups; trackBy: trackByGroupKey"
          [display: flex; justify-content: space-between; margin-bottom: 8px]
          span mat-body-2 — {{ group.sellerName }} ({{ group.currency }})
          <aliceut-price-display
            [amount]="group.displaySubtotal ?? group.subtotal"
            [currency]="group.displaySubtotal ? group.displayCurrency : group.currency"
            [priceType]="'LIST'"
            [converted]="!!group.displaySubtotal && group.displayCurrency !== group.currency"
            [estimatedFrom]="group.currency"
            [fxAsOf]="group.fxAsOf" [fxStale]="group.fxStale">

        mat-divider [margin: 12px 0]

        div.summary-row [display: flex; justify-content: space-between; margin-bottom: 8px]
          span mat-body-2 — Item subtotal
          <aliceut-price-display [amount]="cart.itemSubtotal.displayAmount" [currency]="cart.itemSubtotal.displayCurrency" [priceType]="'LIST'">
        div.summary-row [display: flex; justify-content: space-between; margin-bottom: 8px]
          span mat-body-2 — Shipping
          <aliceut-price-display [amount]="cart.shippingTotal.displayAmount" [currency]="cart.shippingTotal.displayCurrency" [priceType]="'LIST'">
        div.summary-row [display: flex; justify-content: space-between; margin-bottom: 8px]
          span mat-body-2 — Tax
          <aliceut-price-display [amount]="cart.taxTotal.displayAmount" [currency]="cart.taxTotal.displayCurrency" [priceType]="'LIST'">

      mat-divider [margin: 16px 0]

      div.summary-row.total [display: flex; justify-content: space-between; font-weight: 500]
        span mat-body-1 — Total
        <aliceut-price-display [amount]="cart.grandTotal.displayAmount" [currency]="cart.grandTotal.displayCurrency" [priceType]="'LIST'">

      <!-- FR-P-02 disclosure for the two cross-group totals; see Totals below -->
      p mat-caption color="secondary" *ngIf="cart.grandTotal.fxAsOf" [margin-top: 8px]
        mat-icon [font-size: 14px] — info_outline
        span — Estimated total in {{ cart.displayCurrency }} — includes converted amounts, at rates as of {{ cart.grandTotal.fxAsOf | date:'medium' }}.
        span *ngIf="cart.grandTotal.fxStale" — These rates are indicative.

      p mat-caption color="warn" *ngIf="!cart.grandTotal.complete" [margin-top: 8px]
        mat-icon [font-size: 14px] — warning_amber
        span — Some items could not be converted to {{ cart.displayCurrency }}. This total covers the rest.

      p mat-caption color="secondary" *ngIf="cart.groups.length > 1" [margin-top: 8px]
        mat-icon [font-size: 14px] — info_outline
        span — Your cart spans several sellers. Each is charged separately in its own currency.

      button mat-flat-button color="accent" [fullWidth] [disabled]="!canCheckout" (click)="goToCheckout()"
        — Proceed to Checkout
      p mat-caption color="warn" [text-align: center; margin-top: 8px] *ngIf="unavailableItems.length > 0"
        — Remove unavailable items to continue.
      p mat-caption color="warn" [text-align: center; margin-top: 8px] *ngIf="cart.items.length === 0"
        — Your cart is empty.

      button mat-button [fullWidth] routerLink="/" [margin-top: 8px] — Continue Shopping
```

### Totals

Every figure in the summary is a server-computed string. **Nothing on this page is multiplied, added or rounded in the browser** (FR-P-04a):

| Row | Field | Notes |
|---|---|---|
| Per-seller row | `groups[].displaySubtotal`, falling back to `subtotal` | The sum of that group's line totals. It is rendered in the buyer's display currency (`displaySubtotal` / `displayCurrency`) with the group's own `currency` as `estimatedFrom`, so a converted group subtotal carries the FR-P-02 label — exactly as a line total does. The group's native `subtotal` in `groups[].currency` is the fallback when no rate exists. `cartItemIds` lets the page group lines without regrouping client-side. |
| Item subtotal | `itemSubtotal.displayAmount` | The sum of every group's display subtotal, in the display currency — the only currency all groups share. `complete: false` means one group could not be converted, and the caption above says so instead of presenting the figure as the cart total. |
| Shipping | `shippingTotal.displayAmount` | Always `"0.00"` in V1, seeded from platform configuration. Real shipping is out of scope (BRD § 3.2). |
| Tax | `taxTotal.displayAmount` | Always `"0.00"` in V1. Phase 1 defines no tax engine, tax-rate table or jurisdiction model. |
| Total | `grandTotal.displayAmount` | `itemSubtotal + shippingTotal + taxTotal`, summed on the server, and it carries its own `complete` flag. |

`grandTotal` means the **grand total**. The sum of the line items is `itemSubtotal`. While shipping and tax are zero the two figures are numerically equal, which is exactly why every binding is to the field it means rather than to whichever one happens to match today. Neither zero field carries a `complete` flag — a constant needs no conversion.

**How FR-P-02's "estimated" disclosure reaches each row.** Three of the five rows are converted amounts and each discloses it differently, because only two of them have a single native currency to name:

- **Line totals and per-seller subtotals** have one native currency each, so they bind the full FX prop set on `PriceDisplay` — `[converted]`, `[estimatedFrom]` (the native code), `[fxAsOf]`, `[fxStale]` — and the component renders the `≈` prefix and the info tooltip itself. `converted` is derived in the template, never read from the response: a non-null display amount whose `displayCurrency` differs from the native `currency`. There is no server-side `converted` flag ([cart.md § Get cart](../technical-design/api-design/cart.md#get-cart)). When no rate exists for the pair the display field is `null` and `fxAsOf` / `fxStale` are `null` with it; the fallback binds the native amount, `converted` evaluates to `false`, and the figure is shown alone with no `≈` — the same three-case behaviour as [§ Money](#money).
- **`itemSubtotal` and `grandTotal`** carry `fxAsOf` / `fxStale` / `complete` and so are converted amounts too, but they are sums *across* groups with no single native currency, and `estimatedFrom` is required whenever `converted = true` ([design-system.md § PriceDisplay](../../conventions/design-system.md#83-pricedisplay)). Rather than invent a native code these totals do not have, the disclosure is the **caption on the summary block**, shown whenever `grandTotal.fxAsOf` is non-null. Per `cart.md`, that `fxAsOf` is the **oldest** constituent rate, so the caption says "rates as of" it rather than implying one rate governed the whole total; `fxStale` adds the indicative sentence. `[converted]` stays unbound on both rows for this reason and this reason only.
- **Shipping and tax** are structural `"0.00"` constants and their response objects carry no FX fields at all, so nothing is disclosed and nothing is bound beyond `amount` / `currency` / `priceType`.

Shipping and tax are labelled with their `"0.00"` value, not with "Calculated at checkout": there is nothing further to calculate, and the checkout totals are the same fields.

### Unavailable lines

There is no `isStale` flag. A line is unavailable when `offerStatus !== 'ACTIVE'` — the domain is `ACTIVE | INACTIVE | REMOVED | FLAGGED`, and `DRAFT` does not exist because a listing goes live on submit. Such a line is labelled "Unavailable", its quantity controls are withdrawn, and the checkout CTA stays disabled until it is removed (US-B-06). There is no price-changed banner and no per-line "price updated" badge: the cart re-resolves prices on every read and carries no previous-price field, and the buyer's confirmation of a price move belongs to checkout, where `409 PRICE_CHANGED` supplies both the old and the new amount.

### States

- **Empty cart:** `EmptyState` with `icon="shopping_cart"`, `title="Your cart is empty"` and a "Continue Shopping" CTA in the content slot.
- **Unavailable items:** error banner at the top, "Remove" on each affected line, checkout CTA disabled.
- **Loading:** three skeleton rows.
- **Error:** error banner with Retry; the guest cart still renders from `localStorage`.
- **Guest cart:** lines render from `localStorage` with no resolved price and no totals; the CTA reads "Sign in to check out" and navigates to `/login?returnUrl=/checkout`.
- **Cart merge (post-login):** when `POST /cart/merge` reports work done, a `MatSnackBar` shows for 5 seconds, bottom-center:
  - `addedCount > 0` → "N item(s) from your guest session were added to your cart."
  - `cappedItems` non-empty → append "Some quantities were adjusted to match available stock."
  - `skippedItems` non-empty → append "N item(s) could not be added." The reason per item is `OFFER_UNAVAILABLE`, `OUT_OF_STOCK` or `CART_LIMIT_REACHED`; nothing is dropped silently.

  Rendered by `BuyerShellComponent` from `CartMergeService.mergeResult$` on the post-login redirect.

### Mobile

Two columns collapse to one with the summary below the items. Thumbnail shrinks to 64×64; quantity controls reduce in size.

---

<a id="screen-5-checkout"></a>
## Screen 5 — Checkout

**Route:** `/checkout`  
**Auth:** Required, and the account must be email-verified. An unauthenticated buyer is sent to `/login?returnUrl=/checkout`; an unverified one is sent to the verification-pending screen, because `POST /orders` is guarded on `EMAIL_VERIFIED`.

### Three steps, not four

The stepper is **Shipping address → Payment → Review**. There is no shipping-method step: `POST /orders` accepts no `shippingMethodId`, no endpoint lists shipping methods, and V1 has mock shipping only (BRD § 3.2). The mock service name recorded on the fulfillment comes from seeded platform configuration and the shipping cost is a structural `"0.00"`, so there is nothing for the buyer to choose between. The Review step states the shipping line as a zero rather than offering options.

### Layout

```
h1 mat-headline-3 — "Checkout"

div.checkout-layout [display: grid; grid-template-columns: 1fr 340px; gap: 24px; align-items: start] [desktop]
  mat-stepper [linear] #stepper [flex: 1]

    <!-- Step 1: Shipping address -->
    mat-step [label]="'Shipping Address'" [stepControl]="addressForm"
      form [formGroup]="addressForm"
        <!-- Saved addresses are the primary path: POST /orders takes a shippingAddressId -->
        div.saved-addresses *ngIf="savedAddresses.length > 0"
          p mat-body-2 — Ship to a saved address:
          mat-radio-group [formControl]="addressForm.controls.shippingAddressId"
            mat-radio-button *ngFor="let addr of savedAddresses; trackBy: trackByAddressId" [value]="addr.id"
              span — {{ addr.label }} — {{ addr.recipientName }}, {{ addr.addressLine1 }}, {{ addr.city }} {{ addr.postalCode }}, {{ addr.countryCode }}
              mat-chip *ngIf="addr.isDefault" — Default

        button mat-stroked-button color="primary" (click)="openAddressDialog()"
          [disabled]="savedAddresses.length >= 10" — Add a new address
        mat-error *ngIf="savedAddresses.length >= 10" — Address limit reached (10). Remove one in Account Settings to add another.

        div [text-align: right; margin-top: 16px]
          button mat-flat-button color="primary" matStepperNext [disabled]="addressForm.invalid" — Next

    <!-- Step 2: Payment -->
    mat-step [label]="'Payment'" [stepControl]="paymentForm"
      form [formGroup]="paymentForm"
        mat-card [padding: 16px; margin-bottom: 16px]
          mat-icon color="primary" [font-size: 32px] — credit_card
          p mat-body-1 — Demo Payment (Mock)
          p mat-caption color="secondary" — This is a simulated payment. No real transaction will occur and no card details leave your browser.
        mat-form-field [appearance=outline; fullWidth]
          mat-label — Card Number (demo)
          input matInput formControlName="cardNumber" placeholder="4111 1111 1111 1111" maxlength="19" autocomplete="off"
        div.two-col-grid [display: grid; grid-template-columns: 1fr 1fr; gap: 16px]
          mat-form-field — mat-label "Expiry (MM/YY)" — input formControlName="expiry" placeholder="12/27"
          mat-form-field — mat-label "CVV" — input formControlName="cvv" placeholder="123" autocomplete="off"
        div [text-align: right; margin-top: 16px; display: flex; gap: 8px; justify-content: flex-end]
          button mat-button matStepperPrevious — Back
          button mat-flat-button color="primary" matStepperNext [disabled]="paymentForm.invalid" — Next

    <!-- Step 3: Review & place order -->
    mat-step [label]="'Review'"
      div.review-section
        h3 mat-headline-6 — Shipping to
        p mat-body-2 — {{ selectedAddressSummary }}
        mat-divider [margin: 12px 0]
        h3 mat-headline-6 — Shipping
        p mat-body-2 — Standard delivery, no shipping charge in this release.
        mat-divider [margin: 12px 0]
        h3 mat-headline-6 — Order Items
        mat-list
          mat-list-item *ngFor="let item of cart.items; trackBy: trackByCartItemId"
            span mat-list-item-title — {{ item.productTitle }}
            span mat-list-item-line — {{ item.variantLabel }} × {{ item.quantity }}
            <aliceut-price-display matListItemMeta
              [amount]="item.lineTotal.displayAmount ?? item.lineTotal.amount"
              [currency]="item.lineTotal.displayAmount ? item.lineTotal.displayCurrency : item.lineTotal.currency"
              [priceType]="'LIST'"
              [converted]="!!item.lineTotal.displayAmount && item.lineTotal.displayCurrency !== item.lineTotal.currency"
              [estimatedFrom]="item.lineTotal.currency"
              [fxAsOf]="item.lineTotal.fxAsOf" [fxStale]="item.lineTotal.fxStale">

        <!-- Price-changed confirmation (409 PRICE_CHANGED) -->
        mat-card.warning-banner *ngIf="updatedPrices.length > 0" [margin-top: 16px; background: warn-100]
          mat-icon color="warn" — warning_amber
          h4 mat-headline-6 — Prices have changed
          div *ngFor="let change of updatedPrices; trackBy: trackByOfferId"
            p mat-body-2
              — {{ change.productTitle }}: was
              <aliceut-price-display [amount]="change.shownAmount" [currency]="change.currency" [priceType]="'LIST'">
              , now
              <aliceut-price-display [amount]="change.newAmount" [currency]="change.currency" [priceType]="'LIST'">
          mat-checkbox [formControl]="priceChangeConfirmed" — I understand and accept the updated prices
          p mat-caption — You must confirm the updated prices to place the order.

        div [text-align: right; margin-top: 24px; display: flex; gap: 8px; justify-content: flex-end]
          button mat-button matStepperPrevious — Back
          button mat-flat-button color="accent"
            [disabled]="isPlacingOrder || (updatedPrices.length > 0 && !priceChangeConfirmed.value)"
            (click)="placeOrder()"
            mat-spinner *ngIf="isPlacingOrder" [diameter]="20"
            span *ngIf="!isPlacingOrder" — Place Order

  <!-- Right: summary panel -->
  aside.checkout-summary [position: sticky; top: 88px]
    mat-card [padding: 24px]
      h2 mat-headline-6 — Order Summary
      mat-list [dense]
        mat-list-item *ngFor="let item of cart.items; trackBy: trackByCartItemId"
          span mat-list-item-title — {{ item.productTitle }} × {{ item.quantity }}
          <aliceut-price-display matListItemMeta
            [amount]="item.lineTotal.displayAmount ?? item.lineTotal.amount"
            [currency]="item.lineTotal.displayAmount ? item.lineTotal.displayCurrency : item.lineTotal.currency"
            [priceType]="'LIST'"
            [converted]="!!item.lineTotal.displayAmount && item.lineTotal.displayCurrency !== item.lineTotal.currency"
            [estimatedFrom]="item.lineTotal.currency"
            [fxAsOf]="item.lineTotal.fxAsOf" [fxStale]="item.lineTotal.fxStale">
      mat-divider [margin: 12px 0]
      div.totals
        div.summary-row *ngFor="let group of cart.groups; trackBy: trackByGroupKey" [display: flex; justify-content: space-between]
          span mat-body-2 — {{ group.sellerName }} ({{ group.currency }})
          <aliceut-price-display
            [amount]="group.displaySubtotal ?? group.subtotal"
            [currency]="group.displaySubtotal ? group.displayCurrency : group.currency"
            [priceType]="'LIST'"
            [converted]="!!group.displaySubtotal && group.displayCurrency !== group.currency"
            [estimatedFrom]="group.currency"
            [fxAsOf]="group.fxAsOf" [fxStale]="group.fxStale">
        mat-divider [margin: 8px 0]
        div [display: flex; justify-content: space-between]
          span mat-body-2 — Item subtotal
          <aliceut-price-display [amount]="cart.itemSubtotal.displayAmount" [currency]="cart.itemSubtotal.displayCurrency" [priceType]="'LIST'">
        div [display: flex; justify-content: space-between]
          span mat-body-2 — Shipping
          <aliceut-price-display [amount]="cart.shippingTotal.displayAmount" [currency]="cart.shippingTotal.displayCurrency" [priceType]="'LIST'">
        div [display: flex; justify-content: space-between]
          span mat-body-2 — Tax
          <aliceut-price-display [amount]="cart.taxTotal.displayAmount" [currency]="cart.taxTotal.displayCurrency" [priceType]="'LIST'">
        mat-divider [margin: 8px 0]
        div [display: flex; justify-content: space-between; font-weight: 500]
          span mat-body-1 — Total
          <aliceut-price-display [amount]="cart.grandTotal.displayAmount" [currency]="cart.grandTotal.displayCurrency" [priceType]="'LIST'">
        <!-- FR-P-02 disclosure for the two cross-group totals; same rule as the cart summary -->
        p mat-caption color="secondary" *ngIf="cart.grandTotal.fxAsOf" [margin-top: 8px]
          mat-icon [font-size: 14px] — info_outline
          span — Estimated total in {{ cart.displayCurrency }} — includes converted amounts, at rates as of {{ cart.grandTotal.fxAsOf | date:'medium' }}.
          span *ngIf="cart.grandTotal.fxStale" — These rates are indicative.
        p mat-caption color="warn" *ngIf="!cart.grandTotal.complete" [margin-top: 8px]
          mat-icon [font-size: 14px] — warning_amber
          span — Some items could not be converted to {{ cart.displayCurrency }}. This total covers the rest.
```

### Totals

Checkout renders the **same `GET /cart` fields** as Screen 4 and follows Screen 4's rules unchanged — the same bindings on line totals and per-seller subtotals, the same caption on `itemSubtotal` and `grandTotal`, the same nothing on the two structural zeroes. See [Screen 4 § Totals](#totals) for the field-by-field table and for how FR-P-02's "estimated" disclosure reaches each row; this screen restates none of it. There is no checkout-preview endpoint and no second computation of these figures ([cart.md § Get cart](../technical-design/api-design/cart.md#get-cart)).

### Address step

`POST /orders` takes a `shippingAddressId` that must reference one of the buyer's own `identity.address` rows, so the step **selects** an address rather than typing one into the order. "Add a new address" opens a dialog over `POST /profile/addresses` (fields `label`, `recipientName`, `addressLine1`, `addressLine2`, `city`, `stateRegion`, `postalCode`, `countryCode`; `countryCode` is ISO 3166-1 alpha-2 from the full country list). The created row is returned with its id and is selected. The first address saved on an account becomes the default; the list is capped at 10, and an eleventh attempt is a `422`. Saved addresses come from `GET /profile/addresses`, which is not paginated because of that cap.

The order snapshots the address as JSONB at checkout, so editing or deleting the saved row later does not change a historical order.

### Placing the order

`POST /orders` with a required `Idempotency-Key: <client-uuid>` header and the body `{ shippingAddressId, paymentMethod: "FAKE_CARD", maskedPaymentDetail, cartItems[], confirmedPrices[]? }`.

- **`maskedPaymentDetail` is the only thing the payment step transmits.** The client sends the already-masked display string (`"XXXX-XXXX-XXXX-4242"`); a full card number is never sent, never logged, and the field is named so that an unmasked number cannot reach it.
- `cartItems[]` are the ids of the lines being purchased. There is **no `currency` field**: the buyer's display currency is resolved server-side from the profile at submission time and snapshotted per fulfillment, so a later preference change does not alter historical order display. The client cannot choose the capture currency.
- On `201` the response carries the whole order — `orderId`, `displayId`, `placementOutcome`, `fulfillments[]`, `skippedItems[]`, `failedGroups[]` — and the page navigates to `/checkout/confirmation?orderId={orderId}` **carrying that response**, because part of it is available nowhere else (see [Screen 6](#screen-6-order-confirmation)).
- A replay of the same `Idempotency-Key` with the same body returns `200` with the existing order and creates nothing; the client may safely retry a request whose response it lost. `409` means the same key was presented with a *different* body.

### Price revalidation

`409` with `message: "PRICE_CHANGED"` carries `updatedPrices[]` of `{ offerId, productTitle, shownAmount, newAmount, currency }`, and **no order is created**. The Review step renders each change with both amounts as server strings, requires the confirmation checkbox, and re-submits with the **same** `Idempotency-Key` plus `confirmedPrices[]` of `{ offerId, amount, currency }`.

The confirmation is checked against a fresh resolution: if a price moves again between the confirmation and the re-submission, another `409 PRICE_CHANGED` comes back and the buyer confirms again. There is no bound on the repeats and no "confirm once, accept anything" path — an order is never created at a price the buyer has not seen and confirmed. The checkbox resets on every new `409`.

### States

- **Step validation:** Next is disabled until the current step's form is valid.
- **Placing order:** the CTA shows a spinner and every input is disabled.
- **Price changed:** the warning card appears inline in Review with the mandatory checkbox; the CTA stays disabled until it is ticked.
- **Nothing purchasable (`422`):** an error card — "None of the items in your cart can be ordered right now." — with a link back to the cart. No order was created.
- **Network or server error:** `MatSnackBar`, persistent until dismissed — "Failed to place order. Please try again." The same `Idempotency-Key` is reused on retry, so a retry cannot double-place.
- **Empty cart on entry:** redirect to `/cart`.

### Mobile

The stepper switches to `orientation="horizontal"` with icon-only step labels. The summary panel collapses into a `mat-expansion-panel` above the stepper.

---

<a id="screen-6-order-confirmation"></a>
## Screen 6 — Order Confirmation

**Route:** `/checkout/confirmation?orderId=`  
**Auth:** Required

### Where the data comes from

The screen renders the **`POST /orders` response**, handed over by the checkout page. That response is the only place `skippedItems[]` and `failedGroups[]` ever appear: an order contains what was placed, no table holds the lines a checkout deliberately left out, and `GET /orders/:orderId` therefore does not return them.

On a reload or a direct visit the response is gone, and the page falls back to `GET /orders/:orderId` for the order and its fulfillments. In that state the skipped and failed sections are **not** rendered — the page shows an informational note that any items that could not be ordered are still in the cart, with a link to `/cart`, where they are labelled "Unavailable". This is stated rather than worked around, so that nobody later adds a skipped-items list to the order-detail contract to make a refresh look the same.

### Layout

```
div.confirmation [text-align: center; padding: 48px 24px] *ngIf="order.placementOutcome === 'FULLY_PLACED'"
  mat-icon [font-size: 64px; color: success] — check_circle_outline
  h1 mat-headline-3 — Order Placed
  p mat-body-1 — Your order {{ order.displayId }} has been confirmed.

div.confirmation [text-align: center; padding: 48px 24px] *ngIf="order.placementOutcome === 'PARTIALLY_PLACED'"
  mat-icon [font-size: 64px; color: warn] — warning_amber
  h1 mat-headline-3 — Order Partially Placed
  p mat-body-1 — Order {{ order.displayId }} was placed for some of your items. The rest are still in your cart — details below.

div.sections [max-width: 800px; margin: 0 auto]

  <!-- Order total -->
  mat-card [margin-bottom: 16px]
    div [display: flex; justify-content: space-between; font-weight: 500]
      span — Order total
      <aliceut-price-display [amount]="order.buyerCurrencyGrandTotal" [currency]="order.buyerDisplayCurrency" [priceType]="'LIST'">
    div [display: flex; justify-content: space-between]
      span mat-body-2 — Shipping
      <aliceut-price-display [amount]="order.shippingTotal" [currency]="order.buyerDisplayCurrency" [priceType]="'LIST'">
    div [display: flex; justify-content: space-between]
      span mat-body-2 — Tax
      <aliceut-price-display [amount]="order.taxTotal" [currency]="order.buyerDisplayCurrency" [priceType]="'LIST'">

  <!-- One card per placed fulfillment -->
  mat-card *ngFor="let f of order.fulfillments; trackBy: trackByFulfillmentId" [margin-bottom: 16px]
    mat-card-header
      mat-icon mat-card-avatar — local_shipping
      mat-card-title — {{ f.sellerName }}
      mat-card-subtitle — Fulfillment {{ f.displayId }}
    mat-card-content
      p mat-body-2 — Status: <aliceut-status-badge [status]="f.status" [statusType]="'fulfillment'">
      p mat-body-2 — Tracking: <strong>{{ f.trackingNumber }}</strong>
      p mat-body-2 — Estimated delivery: <strong>{{ f.estimatedDeliveryAt | date:'mediumDate' }}</strong>
      mat-divider [margin: 12px 0]
      mat-list [dense]
        mat-list-item *ngFor="let item of f.items; trackBy: trackByOfferId"
          span mat-list-item-title — {{ item.productTitle }} × {{ item.quantity }}
          span mat-list-item-line *ngIf="item.variantLabel" — {{ item.variantLabel }}
          <aliceut-price-display matListItemMeta
            [amount]="item.buyerCurrencyLineTotal" [currency]="item.buyerDisplayCurrency" [priceType]="'LIST'">
      mat-divider [margin: 12px 0]
      div [display: flex; justify-content: space-between; font-weight: 500]
        span — Fulfillment total
        <aliceut-price-display [amount]="f.buyerCurrencyTotal" [currency]="f.buyerDisplayCurrency" [priceType]="'LIST'">
      p mat-caption color="secondary" *ngIf="f.currency !== f.buyerDisplayCurrency"
        — Charged as <aliceut-price-display [amount]="f.totalAmount" [currency]="f.currency" [priceType]="'LIST'"> by this seller.

  <!-- Items excluded before placement -->
  mat-card.warning-section *ngIf="order.skippedItems?.length > 0" [margin-bottom: 16px]
    mat-card-header
      mat-icon mat-card-avatar color="warn" — info_outline
      mat-card-title — Items Not Ordered
    mat-card-content
      p mat-body-2 — These items were in your cart but could not be ordered. They are still in your cart.
      mat-list [dense]
        mat-list-item *ngFor="let item of order.skippedItems; trackBy: trackByOfferId"
          span mat-list-item-title — {{ item.productTitle }}
          span mat-list-item-line — {{ skippedReasonLabel(item.reason) }}

  <!-- Groups that failed reservation -->
  mat-card.error-section *ngIf="order.failedGroups?.length > 0" [margin-bottom: 16px]
    mat-card-header
      mat-icon mat-card-avatar color="warn" — error_outline
      mat-card-title — Could Not Be Reserved
    mat-card-content
      p mat-body-2 — These sellers' items could not be reserved and are still in your cart.
      div *ngFor="let group of order.failedGroups; trackBy: trackBySellerId"
        p mat-body-2 [font-weight: 500] — {{ group.sellerName }} — {{ failedReasonLabel(group.reason) }}
        mat-list [dense]
          mat-list-item *ngFor="let item of group.items; trackBy: trackByOfferId"
            span mat-list-item-title — {{ item.productTitle }}

  <!-- Shown instead of the two sections above when the page was reloaded -->
  mat-card.info-banner *ngIf="reloadedWithoutCheckoutResponse && order.placementOutcome === 'PARTIALLY_PLACED'"
    mat-icon — info_outline
    span — Some items could not be ordered. They are still in your cart, labelled "Unavailable".
    button mat-button routerLink="/cart" — View Cart

div.confirmation-actions [text-align: center; margin-top: 24px; display: flex; gap: 16px; justify-content: center]
  button mat-flat-button color="primary" routerLink="/orders" — View Orders
  button mat-stroked-button routerLink="/" — Continue Shopping
  button mat-stroked-button color="warn" routerLink="/cart"
    *ngIf="order.skippedItems?.length > 0 || order.failedGroups?.length > 0" — View Cart
```

### Placement outcome and reasons

`placementOutcome` is `FULLY_PLACED` or `PARTIALLY_PLACED`. There is no third value: a checkout in which **every** group failed creates no order and returns `422`, so this screen is never reached in that case.

**No price is shown on a skipped or failed line.** Nothing was captured for them, so there is no amount to show; the lines carry `productTitle` and a reason and nothing else. Reason labels:

| Field | Value | Label |
|---|---|---|
| `skippedItems[].reason` | `OFFER_UNAVAILABLE` | "No longer available from this seller" |
| `failedGroups[].reason` | `OUT_OF_STOCK` | "Not enough stock left" |
| `failedGroups[].reason` | `OFFER_UNAVAILABLE` | "No longer available from this seller" |

An unrecognised reason renders the generic "Could not be ordered" rather than the raw enum symbol.

### Money on this screen

Buyer-facing amounts are the `buyerCurrency*` snapshots in `buyerDisplayCurrency`, taken at capture and read as-is. The seller-native capture (`totalAmount` in `currency`) is shown as a secondary caption only where the two currencies differ, so the buyer can reconcile a card statement. **Nothing here is converted at read time and nothing is summed** — order-level `shippingTotal` and `taxTotal` are summed over fulfillments by the server, and `buyerCurrencyGrandTotal` is a stored snapshot.

### States

- **FULLY_PLACED:** green check hero; no skipped or failed sections.
- **PARTIALLY_PLACED:** amber hero; the sections that apply are rendered, each naming the reason per line.
- **Loading (direct visit with `?orderId=`):** skeleton layout while `GET /orders/:orderId` resolves.
- **Reloaded:** as described above — the order renders, the skipped and failed sections do not, and the info banner points at the cart.
- **Error / unknown order:** `404` renders an `EmptyState` with `icon="receipt_long"`, `title="Order not found"` and a link to `/orders`. A foreign order id is a `404`, not a `403`.

---

<a id="screen-7-order-history"></a>
## Screen 7 — Order History

**Route:** `/orders`  
**Auth:** Required

### Data source

`GET /orders?status=&limit=&cursor=`. Each row of `data[]` is one **order** (`ORD-…`) carrying its per-seller `fulfillments[]`; it is not a flat list of fulfillments. `status` filters on the derived `orderStatus`. The list deliberately carries **no shipping and no tax figure** — those belong to the detail response, and an order row shows the grand total only.

### Layout

```
h1 mat-headline-3 — "My Orders"

mat-tab-group [color=primary] [margin-bottom: 16px] (selectedTabChange)="applyStatusFilter($event)"
  mat-tab label="All Orders"     ← no status param
  mat-tab label="Pending"        ← status=PENDING
  mat-tab label="Shipped"        ← status=SHIPPED
  mat-tab label="Completed"      ← status=COMPLETED
  mat-tab label="Refunded"       ← status=REFUNDED
  mat-tab label="Cancelled"      ← status=CANCELLED

<aliceut-data-table
  [dataSource]="ordersDataSource" [loading]="loading"
  emptyMessage="No orders in this status."
  [hasMore]="hasMore" [hasPrevious]="hasPrevious"
  (nextPage)="nextPage()" (previousPage)="previousPage()" (sortChange)="onSort($event)">

  ng-container matColumnDef="displayId"
    th mat-header-cell scope="col" — Order
    td mat-cell — {{ order.displayId }}
  ng-container matColumnDef="placedAt"
    th mat-header-cell scope="col" mat-sort-header — Date
    td mat-cell — {{ order.placedAt | date:'mediumDate' }}
  ng-container matColumnDef="orderStatus"
    th mat-header-cell scope="col" — Status
    td mat-cell — <aliceut-status-badge [status]="order.orderStatus" [statusType]="'order'">
  ng-container matColumnDef="placementOutcome"
    th mat-header-cell scope="col" — Placement
    td mat-cell
      mat-chip color="warn" *ngIf="order.placementOutcome === 'PARTIALLY_PLACED'" — Partial
  ng-container matColumnDef="fulfillments"
    th mat-header-cell scope="col" — Sellers
    td mat-cell — {{ fulfillmentSummary(order) }}   ← "2 of 3 shipped", derived from the row's fulfillments[]
  ng-container matColumnDef="itemCount"
    th mat-header-cell scope="col" — Items
    td mat-cell — {{ order.itemCount }}
  ng-container matColumnDef="total"
    th mat-header-cell scope="col" — Total
    td mat-cell
      <aliceut-price-display [amount]="order.buyerCurrencyGrandTotal" [currency]="order.buyerDisplayCurrency" [priceType]="'LIST'">
  ng-container matColumnDef="actions"
    th mat-header-cell scope="col" — <span class="cdk-visually-hidden">Actions</span>
    td mat-cell
      button mat-icon-button [routerLink]="['/orders', order.id]" aria-label="View order" — visibility icon

</aliceut-data-table>
```

### Pagination

`DataTable` owns the Previous / Next footer and the current page's row count; **there is no separate paginator and no page-number control.** The page component owns the cursor stack: push `meta.nextCursor` on `nextPage`, pop on `previousPage`. Next is disabled with the "End of list" caption when `meta.hasMore` is false. Switching tabs resets the stack, because a cursor is only valid for the filter set it was issued under.

`fulfillmentSummary()` counts statuses in the row's own `fulfillments[]` — a count over data already returned, not a server field and not a monetary computation.

### States

Handled by `DataTable`: skeleton rows on first load, a progress overlay on refresh, `EmptyState` with `emptyMessage` when a page is empty, and the end-of-list caption on the last page. A load failure renders an error banner above the table with a Retry action.

### Notes

**Derived statuses that get no tab.** `IN_PROGRESS`, `PARTIALLY_SHIPPED`, `PARTIALLY_DELIVERED` and `PARTIALLY_REFUNDED` are real `orderStatus` values and appear under "All Orders" only; the status badge on each row is the disambiguation. This is a deliberate V1 simplification, not an omission.

There is deliberately **no "Delivered" tab**: the derived table never yields a bare `DELIVERED` at order level — an order whose every fulfillment is delivered is `COMPLETED` — so a Delivered tab would always be empty.

### Mobile

The table collapses to a card list: each card shows the `ORD-` id, the date, the status badge, the seller summary, the total, and a View action.

---

<a id="screen-8-order-detail"></a>
## Screen 8 — Order Detail

**Route:** `/orders/:id`  
**Auth:** Required

`:id` addresses an order by UUID or by `ORD-` display id. Fulfillments are nested; there is no top-level fulfillment route on the buyer portal. A foreign order is a `404`, never a `403`.

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/orders" aria-label="Back to orders" — arrow_back
  h1 mat-headline-4 — Order {{ order.displayId }}
  <aliceut-status-badge [status]="order.orderStatus" [statusType]="'order'">
  mat-chip color="warn" *ngIf="order.placementOutcome === 'PARTIALLY_PLACED'" — Partial

p mat-body-2 — Placed on {{ order.placedAt | date:'long' }}

mat-card.info-banner [margin-bottom: 16px]
  mat-icon — info_outline
  span — Need to cancel? Contact the seller directly. Buyer-initiated cancellation is not available in this release.

<!-- Shipping address snapshot -->
mat-card [margin-bottom: 16px]
  mat-card-header
    mat-card-title — Shipping to
  mat-card-content
    p mat-body-2 — {{ order.shippingAddress.fullName }}
    p mat-body-2 — {{ order.shippingAddress.addressLine1 }}
    p mat-body-2 *ngIf="order.shippingAddress.addressLine2" — {{ order.shippingAddress.addressLine2 }}
    p mat-body-2 — {{ order.shippingAddress.city }}{{ order.shippingAddress.stateProvince ? ', ' + order.shippingAddress.stateProvince : '' }} {{ order.shippingAddress.postalCode }}
    p mat-body-2 — {{ countryName(order.shippingAddress.countryCode) }}
    p mat-body-2 *ngIf="order.shippingAddress.phone" — {{ order.shippingAddress.phone }}
    p mat-caption color="secondary" — This is the address as it was at checkout.

<!-- Order totals -->
mat-card [margin-bottom: 16px]
  div [display: flex; justify-content: space-between]
    span mat-body-2 — Shipping
    <aliceut-price-display [amount]="order.shippingTotal" [currency]="order.buyerDisplayCurrency" [priceType]="'LIST'">
  div [display: flex; justify-content: space-between]
    span mat-body-2 — Tax
    <aliceut-price-display [amount]="order.taxTotal" [currency]="order.buyerDisplayCurrency" [priceType]="'LIST'">
  mat-divider [margin: 8px 0]
  div [display: flex; justify-content: space-between; font-weight: 500]
    span mat-body-1 — Order total
    <aliceut-price-display [amount]="order.buyerCurrencyGrandTotal" [currency]="order.buyerDisplayCurrency" [priceType]="'LIST'">

div.fulfillments
  mat-card *ngFor="let f of order.fulfillments; trackBy: trackByFulfillmentId" [margin-bottom: 16px]
    mat-card-header
      mat-icon mat-card-avatar — storefront
      mat-card-title — {{ f.sellerName }}
      mat-card-subtitle
        span — Fulfillment {{ f.displayId }}
        <aliceut-status-badge [status]="f.status" [statusType]="'fulfillment'">
    mat-card-content
      <!-- Timeline derived from the fulfillment's own timestamps -->
      div.timeline [margin-bottom: 16px]
        div.timeline-step *ngFor="let step of timelineOf(f); trackBy: trackByStepKey" [display: flex; align-items: center; gap: 8px]
          mat-icon [color]="step.reached ? 'primary' : 'disabled'" — [step.reached ? 'check_circle' : 'radio_button_unchecked']
          span mat-body-2 [color]="step.reached ? 'primary-text' : 'disabled-text'" — {{ step.label }}
          span mat-caption color="secondary" *ngIf="step.at" — {{ step.at | date:'medium' }}

      p mat-body-2 — Shipping method: {{ f.shippingMethod }}
      p mat-body-2 *ngIf="f.trackingNumber" — Tracking: <strong>{{ f.trackingNumber }}</strong>
      p mat-body-2 *ngIf="f.estimatedDeliveryAt" — Estimated delivery: <strong>{{ f.estimatedDeliveryAt | date:'mediumDate' }}</strong>

      mat-divider [margin: 12px 0]
      mat-list [dense]
        mat-list-item *ngFor="let item of f.items; trackBy: trackByOfferId"
          span mat-list-item-title — {{ item.productTitle }}
          span mat-list-item-line
            — {{ item.variantLabel }} × {{ item.quantity }} · {{ item.buyerCurrencyUnitPrice | currencyDisplay:item.buyerDisplayCurrency }} each
          <aliceut-price-display matListItemMeta
            [amount]="item.buyerCurrencyLineTotal" [currency]="item.buyerDisplayCurrency" [priceType]="'LIST'">
      mat-divider [margin: 12px 0]
      div [display: flex; justify-content: space-between]
        span mat-body-2 — Shipping
        <aliceut-price-display [amount]="f.shippingCost" [currency]="f.currency" [priceType]="'LIST'">
      div [display: flex; justify-content: space-between]
        span mat-body-2 — Tax
        <aliceut-price-display [amount]="f.taxTotal" [currency]="f.currency" [priceType]="'LIST'">
      div [display: flex; justify-content: flex-end; font-weight: 500]
        <aliceut-price-display [amount]="f.buyerCurrencyTotal" [currency]="f.buyerDisplayCurrency" [priceType]="'LIST'">
      p mat-caption color="secondary" *ngIf="f.currency !== f.buyerDisplayCurrency"
        — Captured as <aliceut-price-display [amount]="f.totalAmount" [currency]="f.currency" [priceType]="'LIST'">
          at a rate of {{ f.items[0].fxRateUsedAtCapture }} on the order date.
```

### Status timeline

Steps are **Ordered → Shipped → Delivered**, with **Refunded** or **Cancelled** appended when the fulfillment reached that state. Each step's reached flag and timestamp come from the fulfillment's own `placedAt`, `shippedAt`, `deliveredAt`, `refundedAt` and `cancelledAt` fields, all of which the detail response carries; nothing is inferred from the status string alone and there is no server-supplied timeline object. Reached steps render in primary colour, future steps in disabled grey, and each pairs its colour with a label.

### Amounts

Every amount on this screen is read from an immutable snapshot. `fxRateUsedAtCapture` is always present and is `"1.00000000"` when the seller's native currency equals the buyer's display currency, so no template branches on a null rate. **No amount is re-derived from live pricing or a live FX rate** (FR-P-03), and the per-fulfillment `shippingCost` and `taxTotal`, the line `tax`, and the order-level pair are all the `"0.00"` structural zeroes.

**Skipped items are not shown here.** An order contains what was placed; the lines a checkout left out are reported once, in the checkout response, and remain in the cart.

### States

- **Loading:** skeleton page header plus two skeleton fulfillment cards.
- **Not found / foreign order:** `EmptyState` with `icon="receipt_long"`, `title="Order not found"`, `message="This order does not exist or is not yours."` and a link back to `/orders`.
- **Error:** error banner with a Retry action; the page header stays visible.
- There is no empty state for fulfillments: an order always has at least one, because a checkout in which every group failed creates no order.

### Mobile

Cards stack full width. The timeline stays vertical. Line items wrap the unit-price caption below the title.

---

<a id="screen-9-login"></a>
## Screen 9 — Login

**Route:** `/login`  
**Auth:** None (an already-authenticated visitor is redirected home)

### Layout

The card shell, the email and password fields, the error banner and the submit button are the shared auth pattern in [shared-components.md § 8.1–8.3](shared-components.md#8-auth-screen-pattern). Title "Sign in to AliceUT", the AliceUT logo as the portal mark, footer "Don't have an account? Register" → `/register`. What this screen adds:

```
mat-card-content
  <!-- Shown when ?returnUrl contains '/checkout' -->
  mat-card.info-banner *ngIf="hasCheckoutIntent"
    mat-icon — shopping_cart
    span — Sign in to complete your purchase

  [shared form: email + password + error banner + "Sign In" submit]

  div [display: flex; justify-content: flex-end; margin: 4px 0 16px]
    a mat-button routerLink="/forgot-password" — Forgot password?

  mat-divider [margin: 24px 0]
    span mat-body-2 color="secondary" — or continue with

  div [display: flex; gap: 12px; margin-bottom: 24px]
    button mat-stroked-button [flex: 1] (click)="loginWithGoogle()"
      img [src=google-icon.svg; alt=""; height=18px; margin-right: 8px]
      span — Google
    button mat-stroked-button [flex: 1] (click)="loginWithFacebook()"
      img [src=facebook-icon.svg; alt=""; height=18px; margin-right: 8px]
      span — Facebook
```

### Request and outcomes

`POST /auth/login` with `{ email, password, portal: "BUYER" }`. The `portal` field and the `401` / `403` / `429` outcomes are the cross-portal rules in [shared-components.md § 8.5](shared-components.md#8-auth-screen-pattern). Rate limit on this form is 10 attempts per IP per 15 minutes.

On `200` the access token is held **in memory only** by `AuthService` and the refresh token arrives as an HttpOnly cookie the client never reads. If `user.emailVerified` is `false` the client navigates to the verification-pending screen; otherwise it honours `?returnUrl=` — validated to be a relative path, to prevent open redirects — or goes home.

**There is no resend-verification control on this page.** `POST /auth/resend-verification` is JWT-guarded, and an unverified account that has just signed in is routed to the verification-pending screen, which holds the resend action.

### OAuth

The Google and Facebook buttons navigate to `GET /auth/google` / `GET /auth/facebook`. The provider returns to `/auth/callback?code=<one-time-code>`, and the SPA immediately exchanges that code with `POST /auth/oauth/exchange` for the session. **No access token, and no refresh token, ever appears in a URL** — the code is opaque, single-use and expires in 60 seconds. OAuth is buyer-only; the seller and admin portals are email and password exclusively.

### States

- **Submitting:** button spinner; the form is disabled.
- **Error:** inline `error-banner` with the generic message.
- **Rate limited:** the banner names the retry interval and the submit button stays disabled until it elapses.
- **Checkout intent:** the info banner appears when `?returnUrl` contains `/checkout`. Purely contextual — it changes no form behaviour.
- **Guest cart present:** after a successful sign-in the client calls `POST /cart/merge` and shows the merge toast described in [Screen 4](#screen-4-cart).

---

<a id="screen-10-register"></a>
## Screen 10 — Register

**Route:** `/register`  
**Auth:** None

### Layout (same card shell as Login)

```
mat-card [max-width: 440px]
  mat-card-title — Create your AliceUT account
  form [formGroup]="registerForm" (ngSubmit)="register()"
    mat-form-field [appearance=outline; fullWidth; subscriptSizing=dynamic]
      mat-label — Full Name
      input matInput formControlName="fullName" autocomplete="name"
    mat-form-field [appearance=outline; fullWidth; subscriptSizing=dynamic]
      mat-label — Email address
      input matInput type="email" formControlName="email" autocomplete="email"
      mat-error *ngIf="email.hasError('emailTaken')" — This email is already registered
    mat-form-field [appearance=outline; fullWidth; subscriptSizing=dynamic]
      mat-label — Password
      input matInput type="password" formControlName="password" autocomplete="new-password"
      mat-hint — At least 8 characters, 1 letter, 1 number
    mat-checkbox formControlName="isBusinessAccount" — This is a business account
      mat-icon [matTooltip]="'Branding only — the same shopping experience as a personal account'" — info_outline
    button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="registerForm.invalid || isLoading"
      mat-spinner *ngIf="isLoading" [diameter]="20"
      span *ngIf="!isLoading" — Create Account
  mat-divider — or
  div [Google / Facebook buttons, identical to Login]
  mat-card-footer — Already have an account? <a routerLink="/login">Sign in</a>
```

`POST /auth/register` with `{ email, password, fullName, accountType }`, where `accountType` is `"B2B"` when the business checkbox is ticked and `"B2C"` otherwise. B2B differentiation in V1 is branding only — a badge, the business name and the logo on invoices; there is no bulk pricing, no invoicing screen and no separate B2B catalogue. `409` maps to the `emailTaken` error on the email field.

The password field, its hint and the policy behind it are the shared ones in [shared-components.md § 8.2](shared-components.md#8-auth-screen-pattern) and [§ 8.4](shared-components.md#8-auth-screen-pattern) — the pattern, the bounds and the three validator messages live there and are not restated per portal.

### Post-registration

`201` **opens a session** — it returns an access token and sets the refresh cookie — because the account must be created *and* signed in, and because the resend-verification endpoint is JWT-guarded and would otherwise be unreachable. The client then navigates to the verification-pending screen. The account may browse and hold a cart while unverified; only `POST /orders` is blocked. An OAuth registration is verified by the provider and goes straight home.

### States

- **Submitting:** button spinner; form disabled.
- **Email taken (`409`):** field-level error on the email input.
- **Validation:** `mat-error` shown only after a field is touched or the form is submitted.
- **Rate limited (`429`):** banner naming the retry interval — 5 registrations per IP per 15 minutes.

---

<a id="screen-11-account-settings"></a>
## Screen 11 — Account Settings

**Route:** `/account`  
**Auth:** Required

### Layout

```
h1 mat-headline-3 — Account Settings

mat-tab-group [vertical on desktop; horizontal on mobile]

  mat-tab label="Profile"
    form [formGroup]="profileForm" [max-width: 560px] (ngSubmit)="saveProfile()"
      mat-form-field [appearance=outline; fullWidth] — mat-label "Full Name" — input formControlName="fullName"
      mat-form-field [appearance=outline; fullWidth]
        mat-label — Email address
        input matInput [value]="user.email" disabled
        mat-hint — Email change is not available in this release.
      mat-form-field [appearance=outline; fullWidth]
        mat-label — Account Type
        input matInput [value]="user.accountType" disabled
      mat-form-field [appearance=outline; fullWidth]
        mat-label — Preferred Display Currency
        mat-select formControlName="preferredCurrency"
          mat-option [value]="null" — Automatic (from browser language)
          mat-option value="USD" — USD — US Dollar
          mat-option value="THB" — THB — Thai Baht
          mat-option value="JPY" — JPY — Japanese Yen
          mat-option value="SGD" — SGD — Singapore Dollar
        mat-hint — Converted prices are estimates. Orders are charged in the seller's currency.
      mat-form-field *ngIf="user.accountType === 'B2B'" [appearance=outline; fullWidth]
        mat-label — Business Name
        input matInput formControlName="businessName"

      <!-- B2B only -->
      div.business-logo-section *ngIf="user.accountType === 'B2B'"
        h3 mat-headline-6 — Business Logo (optional)
        div.logo-preview *ngIf="user.businessLogoUrl"
          img [src]="user.businessLogoUrl" alt="Your business logo" [max-height: 64px]
        <aliceut-file-upload
          accept="image/jpeg,image/png,image/webp"
          [maxSizeMb]="2" [multiple]="false" [maxFiles]="1"
          (filesChange)="onLogoSelected($event)">
        p mat-caption — JPG, PNG or WebP, up to 2 MB. Larger images are resized to fit 800 × 800.

      p mat-caption — Member since {{ user.createdAt | date:'mediumDate' }}
      button mat-flat-button color="primary" type="submit"
        [disabled]="profileForm.pristine || profileForm.invalid" — Save Changes

  mat-tab label="Addresses"
    div [max-width: 560px]
      mat-list
        mat-list-item *ngFor="let addr of addresses; trackBy: trackByAddressId"
          mat-icon matListItemIcon — home
          span mat-list-item-title — {{ addr.label }} — {{ addr.recipientName }}
          span mat-list-item-line — {{ addr.addressLine1 }}, {{ addr.city }} {{ addr.postalCode }}, {{ addr.countryCode }}
          mat-chip *ngIf="addr.isDefault" — Default
          div matListItemMeta
            button mat-button (click)="setDefault(addr)" *ngIf="!addr.isDefault" — Make default
            button mat-icon-button (click)="editAddress(addr)" aria-label="Edit address" — edit
            button mat-icon-button (click)="deleteAddress(addr)" color="warn" aria-label="Delete address" — delete_outline
      button mat-stroked-button color="primary" (click)="addAddress()" *ngIf="addresses.length < 10" — Add Address
      mat-error *ngIf="addresses.length >= 10" — Address limit reached (10). Remove one to add another.

  mat-tab label="Security"
    div [max-width: 560px]
      h3 mat-headline-6 — {{ user.hasLocalPassword ? 'Change Password' : 'Set a Password' }}
      form [formGroup]="passwordForm" (ngSubmit)="submitPassword()"
        mat-form-field *ngIf="user.hasLocalPassword" [appearance=outline; fullWidth]
          mat-label — Current Password
          input matInput type="password" formControlName="currentPassword" autocomplete="current-password"
        mat-form-field [appearance=outline; fullWidth]
          mat-label — {{ user.hasLocalPassword ? 'New Password' : 'Password' }}
          input matInput type="password" formControlName="newPassword" autocomplete="new-password"
          mat-hint — At least 8 characters, 1 letter, 1 number
        mat-form-field [appearance=outline; fullWidth]
          mat-label — Confirm Password
          input matInput type="password" formControlName="confirmPassword" autocomplete="new-password"
        mat-error *ngIf="passwordForm.hasError('passwordMismatch')" — Passwords do not match
        button mat-flat-button color="primary" type="submit" [disabled]="passwordForm.invalid"
          — {{ user.hasLocalPassword ? 'Change Password' : 'Set Password' }}
        p mat-caption — Changing your password signs you out of every other device.

      mat-divider [margin: 24px 0]
      h3 mat-headline-6 — Sessions
      button mat-stroked-button color="warn" (click)="signOutEverywhere()" — Sign out of all devices
      p mat-caption — This signs out every device, including this one. You will need to sign in again.
```

### Endpoints

| Control | Endpoint | Notes |
|---|---|---|
| Profile read | `GET /profile/me` | Returns `preferredCurrency`, `accountType`, `businessName`, `businessLogoUrl`, `emailVerified`, `sellerKycStatus`, `sellerSuspensionStatus`. |
| Save profile | `PATCH /profile/me` | `{ fullName?, preferredCurrency?, businessName? }`. `422` when a business field is sent on a non-B2B account. |
| Logo upload | `POST /profile/me/logo` | `multipart/form-data`, single file field `logo`. JPEG/PNG/WebP, ≤ 2 MB. Oversized **dimensions** are not an error: the server resizes down to fit 800 × 800, preserving aspect ratio. `422` on a non-B2B account. The response carries a presigned `businessLogoUrl` with a 1-hour TTL, so the preview is refreshed from `GET /profile/me` rather than cached indefinitely. The logo appears on order-confirmation email and invoices (US-P-07). |
| Address list | `GET /profile/addresses` | **Not paginated** — capped at 10 rows, default first. |
| Add / edit | `POST /profile/addresses`, `PATCH /profile/addresses/:addressId` | `422` at the 10-address cap. The first address on an account is created as the default. |
| Make default | `PATCH /profile/addresses/:addressId/default` | Demotes the previous default in the same transaction. |
| Delete | `DELETE /profile/addresses/:addressId` | `409` when the row is the default and other addresses exist — "Set another address as default before deleting this one." Deleting the only address is allowed and leaves the account with no default. Confirmed through `ConfirmDialog`. |
| Change password | `PATCH /auth/change-password` | `{ currentPassword, newPassword }`. The caller's own session is identified server-side from the refresh cookie, which the client cannot read; **every other** session is revoked. `401` on a wrong current password. |
| Set password (OAuth-only account) | `POST /auth/set-password` | Shown when the account has no local password. |
| Sign out everywhere | `POST /auth/logout-all` | Revokes **all** sessions including the caller's, and returns `{ sessionsRevoked }`. The label and caption say so, and the client clears its in-memory token and routes to `/login`. |

**Preferred currency.** The "Automatic" option sends `preferredCurrency: null`, which is the Auto setting: the display currency is then resolved from `Accept-Language` per request, falling back to `USD`. **There is no `"AUTO"` value** — the column is an ISO 4217 code with a foreign key to the currency table, and `AUTO` is not a currency. The choice affects display only; a placed order keeps the currency snapshotted at checkout.

### States

- **Loading:** skeleton form rows per tab.
- **Saving:** submit button spinner; the form is disabled and stays disabled until the response.
- **Saved:** `MatSnackBar` success toast (3s, bottom-center).
- **Validation / conflict:** `mat-error` on the offending field; `409` and `422` render as an inline banner naming the reason.
- **Empty addresses:** `EmptyState` with `icon="home"`, `title="No saved addresses"` and the Add Address CTA in the content slot.
- **Upload in progress / failed:** per-file progress bar and inline error inside `FileUpload`, with its Retry action.

---

<a id="screen-12-email-verification-pending"></a>
## Screen 12 — Email Verification Pending

**Route:** `/email-verification-pending`  
**Auth:** Required — registration opens a session, and the resend endpoint is JWT-guarded

```
div [text-align: center; padding: 64px 24px; max-width: 480px; margin: 0 auto]
  mat-icon [font-size: 64px; color: accent] — mark_email_unread
  h1 mat-headline-4 — Check your email
  p mat-body-1 — We sent a verification link to <strong>{{ email }}</strong>. Open it to activate your account.
  p mat-body-2 — You can browse the catalog and fill your cart while you wait, but you will need to verify before placing an order.
  button mat-flat-button color="primary" (click)="resend()" [disabled]="resendDisabled || resendLoading" [margin-top: 24px]
    mat-spinner *ngIf="resendLoading" [diameter]="20"
    span *ngIf="!resendLoading" — Resend verification email
  p mat-caption *ngIf="resendCooldown" — You can request another email in {{ resendCooldown }}.
  p mat-caption *ngIf="resendLimitReached" color="warn" — Resend limit reached. Try again after {{ limitResetTime }}.
  button mat-button routerLink="/" [margin-top: 16px] — Continue browsing
```

`POST /auth/resend-verification` takes no body — the recipient is the authenticated user — and answers `202`. Rate limit is **3 per hour per user**; `429` sets the limit-reached caption from `Retry-After`. `409` means the address is already verified, and the screen then routes home with a success toast. The verification link itself has a 24-hour TTL and is single-use.

### States

- **Idle:** resend enabled.
- **Sending:** button spinner.
- **Cooldown:** button disabled with the countdown caption.
- **Limit reached (`429`):** warning caption naming the reset time; button disabled.
- **Already verified (`409`):** navigate home with "Your email is already verified."

---

<a id="screen-13-forgot-password"></a>
## Screen 13 — Forgot Password

**Route:** `/forgot-password`  
**Auth:** Public

```
mat-card [max-width: 440px; margin: 48px auto]
  mat-card-title — Reset your password
  p mat-body-2 — Enter the email you registered with. If an account exists, we'll send a reset link.
  form [formGroup]="forgotForm" (ngSubmit)="requestReset()"
    mat-form-field [appearance=outline; fullWidth; subscriptSizing=dynamic]
      mat-label — Email address
      input matInput type="email" formControlName="email" autocomplete="email"
    button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="forgotForm.invalid || isLoading"
      mat-spinner *ngIf="isLoading" [diameter]="20"
      span *ngIf="!isLoading" — Send reset link
  mat-card.success-banner *ngIf="submitted"
    mat-icon color="primary" — check_circle_outline
    span — If an account with that email exists, we sent a reset link. Check your inbox.
  a mat-button routerLink="/login" — Back to sign in
```

`POST /auth/forgot-password` with `{ email, portal: "BUYER" }`. The byte-identical `202`, the 3-per-hour-per-email rate limit and the terminal submitted state are the cross-portal rules in [shared-components.md § 8.5](shared-components.md#8-auth-screen-pattern).

The emailed link points at `/reset-password?token=<raw>&mode=reset|set` — `mode` is the buyer-only display hint described in [Screen 14](#screen-14-reset-password).

### States

- **Idle / submitting / submitted:** as above; the submitted state is terminal for the page.
- **Rate limited:** banner naming the retry interval; the button stays disabled.

---

<a id="screen-14-reset-password"></a>
## Screen 14 — Reset Password

**Route:** `/reset-password?token=&mode=reset|set`  
**Component:** `ResetPasswordComponent`  
**Auth:** Public

### Layout

```html
<div [ngSwitch]="viewState">
  <form *ngSwitchCase="'form'" [formGroup]="resetForm" (ngSubmit)="submit()">
    <h1>{{ mode === 'set' ? 'Set a password for your account' : 'Choose a new password' }}</h1>
    <mat-form-field appearance="outline" subscriptSizing="dynamic">
      <mat-label>{{ mode === 'set' ? 'Password' : 'New password' }}</mat-label>
      <input matInput type="password" formControlName="password" autocomplete="new-password">
      <mat-hint>At least 8 characters, 1 letter, 1 number</mat-hint>
    </mat-form-field>
    <mat-form-field appearance="outline" subscriptSizing="dynamic">
      <mat-label>Confirm password</mat-label>
      <input matInput type="password" formControlName="confirmPassword" autocomplete="new-password">
    </mat-form-field>
    <mat-error *ngIf="resetForm.hasError('passwordMismatch')">Passwords do not match</mat-error>
    <button mat-flat-button color="primary" type="submit" [disabled]="resetForm.invalid || isLoading">
      <mat-spinner *ngIf="isLoading" diameter="20"></mat-spinner>
      <span *ngIf="!isLoading">{{ mode === 'set' ? 'Set Password' : 'Set New Password' }}</span>
    </button>
  </form>
  <div *ngSwitchCase="'invalid'">
    <p>This reset link has expired, has already been used, or is not valid for this portal.</p>
    <button mat-button routerLink="/forgot-password">Request a new reset link</button>
  </div>
</div>
```

`POST /auth/reset-password` with `{ token, newPassword, portal: "BUYER" }`. The optimistic form, the single indistinguishable `400`, the 5-attempts-per-token-per-hour limit, the session revocation on success and the `?passwordReset=true` redirect are the cross-portal rules in [shared-components.md § 8.5](shared-components.md#8-auth-screen-pattern).

`mode` is a **display hint only**, carried on the link so the SPA can render the "Set a password" wording for an OAuth-only account without a round trip. It is buyer-only — the seller link carries no `mode`. The server validates the token and applies the same update either way, so a tampered `mode` changes nothing.

---

<a id="screen-15-email-verification-callback"></a>
## Screen 15 — Email Verification Callback

**Route:** `/verify-email?token=`  
**Component:** `EmailVerificationCallbackComponent`  
**Auth:** Public

### Layout

```html
<div [ngSwitch]="verifyState">
  <mat-spinner *ngSwitchCase="'loading'"></mat-spinner>
  <div *ngSwitchCase="'success'">Email verified. Taking you to sign in…</div>
  <div *ngSwitchCase="'alreadyVerified'">
    <p>This email is already verified.</p>
    <button mat-button routerLink="/login">Sign in</button>
  </div>
  <div *ngSwitchCase="'invalid'">
    <p>This verification link has expired or has already been used.</p>
    <!-- Signed in: the resend endpoint is reachable -->
    <button mat-flat-button color="primary" *ngIf="isLoggedIn" (click)="resendVerification()">
      Resend verification email
    </button>
    <!-- Not signed in: it is not -->
    <ng-container *ngIf="!isLoggedIn">
      <p>Sign in to send yourself a new link.</p>
      <button mat-flat-button color="primary" routerLink="/login">Sign in</button>
    </ng-container>
  </div>
</div>
```

`POST /auth/verify-email { token }` is **public** — the buyer may open the link in a browser where they are not signed in. `POST /auth/resend-verification` is **JWT-guarded**, so the resend button can only be offered to a visitor who has a session. An unauthenticated visitor with a dead link is sent to sign in, and the verification-pending screen holds the resend action once they are in.

### States

- **Loading:** spinner while `POST /auth/verify-email` resolves.
- **Success (`200`):** confirmation message, then an automatic redirect to `/login?verified=true` after 2 seconds.
- **Already verified (`409`):** its own state with a sign-in link, not an error.
- **Invalid or expired (`400`):** as above, branching on whether a session exists.

---

<a id="screen-16-notifications"></a>
## Screen 16 — Notifications

**Route:** `/notifications`  
**Guard:** authenticated  
**Component:** `BuyerNotificationsComponent`

### Layout, rendering and API calls

The layout, the client-side composition of each row's two lines, the cursor-paging rules, the API call table and the four states are the shared notifications pattern in [shared-components.md § 9](shared-components.md#9-notifications-page-pattern). This portal's specifics:

- Heading is `h1 mat-headline-4 — Notifications`; the header carries no filter control, only "Mark all as read".
- Paging is the **"Load more"** variant: `button mat-stroked-button (click)="loadMore()" [disabled]="loadingMore"` with a 16px spinner while loading, replaced by the "End of list" caption once `hasMore` is false.
- `EmptyState` copy: `icon="notifications_none"`, `title="No notifications yet"`, `message="Order updates and alerts will appear here."`
- `titleFor(n)` / `bodyFor(n)` / `typeIcon(n.type)` resolve against the [appendix](#appendix-buyer-notifications) table below. An order notification navigates to `/orders/{orderId}` from the ids in `payload`.

### Notification types displayed

`ORDER_PLACED`, `ORDER_COMPLETED`, `SHIPMENT_UPDATE`, `DELIVERY_UPDATE`, `FULFILLMENT_CANCELLED`, `REFUND_ISSUED` — the buyer-relevant subset of the `type` enum in [notifications.md](../technical-design/api-design/notifications.md). This list and the appendix table below are the same six types. Seller- and admin-only types (`KYC_*`, `LOW_STOCK`, `LISTING_*`, `SELLER_*`, `SUSPENSION_EXPIRED`) never reach a buyer account and are not rendered here.

---

<a id="appendix-buyer-notifications"></a>
## Appendix — Buyer Notification Types

The in-app types a buyer account receives, rendered by `<aliceut-notification-bell>` and the `/notifications` page. The API supplies `type` and an opaque `payload`; the icon and the message are composed client-side from this table, with each bracketed value taken from `payload`.

| Type | Icon | Message pattern |
|---|---|---|
| `ORDER_PLACED` | `receipt` | "Your order [order display id] has been placed." |
| `ORDER_COMPLETED` | `check_circle` | "Your order [order display id] is complete." |
| `SHIPMENT_UPDATE` | `local_shipping` | "Your item from [seller name] has shipped. Tracking: [tracking number]" |
| `DELIVERY_UPDATE` | `done_all` | "Your order from [seller name] has been delivered." |
| `FULFILLMENT_CANCELLED` | `cancel` | "A seller cancelled part of your order [order display id]." |
| `REFUND_ISSUED` | `currency_exchange` | "A refund of [amount] has been processed." — covers both a seller-issued refund and an automatic refund triggered by seller suspension. The amount is a string rendered with `currencyDisplay` against its own currency code. |

Order display ids render in the `ORD-` form and fulfillment display ids in the `FUL-` form; a message about one seller's shipment names the order it belongs to, never a fulfillment id in place of an order id.
