# Buyer Portal — UI Design Specification
## buyer-app (port 4200)

**Status:** Draft  
**Stack:** Angular 17+ + Angular Material + `libs/ui/` shared components  
**Auth:** JWT; guest access allowed on catalog routes; checkout requires authenticated account

---

## Shell Layout

```
mat-toolbar [color=primary] [sticky top-0 z-100]
  a routerLink="/"
    img.logo [src=aliceut-logo.svg, alt="AliceUT", height=36]
  div.search-bar [flex: 1; max-width: 640px; margin: 0 24px]
    mat-form-field [appearance=outline; subscriptSizing=dynamic; width=100%]
      mat-icon matPrefix — search
      input matInput placeholder="Search products..." [formControl]="searchCtrl"
        (keyup.enter)="onSearch()"
  div.toolbar-actions
    button mat-icon-button routerLink="/cart" [matBadge]="cartCount" [matBadgeHidden]="cartCount===0" aria-label="Cart"
      mat-icon — shopping_cart
    <aliceut-notification-bell> [hidden if not logged in]
    button mat-button [matMenuTriggerFor]="userMenu" *ngIf="isLoggedIn"
      mat-icon — account_circle
      span.user-name — {{ displayName }}
      span.business-badge *ngIf="isB2B" — Business   ← mat-chip, small, accent color
    button mat-flat-button color="primary" routerLink="/login" *ngIf="!isLoggedIn" — Sign In
    button mat-button routerLink="/register" *ngIf="!isLoggedIn" — Register
  mat-menu #userMenu
    button mat-menu-item routerLink="/orders" — receipt_long icon — My Orders
    button mat-menu-item routerLink="/account" — settings icon — Account Settings
    mat-divider
    button mat-menu-item (click)="logout()" — logout icon — Sign Out

main.page-content [max-width: 1440px; margin: 0 auto; padding: 24px 16px]
  router-outlet
```

**Mobile (< 600px):** Search bar collapses to a search icon button that expands inline. Logo + search icon + cart icon + hamburger menu icon. User menu becomes a drawer slide-in.

---

## Screen 1 — Home Page

**Route:** `/`  
**Auth:** None required

### Layout

```
section.hero-search [text-align: center; padding: 48px 24px; bg: primary light]
  h1 mat-display-2 — "Find your next great deal"
  mat-form-field [width: 100%; max-width: 640px; appearance=outline]
    mat-icon matPrefix — search
    input matInput placeholder="What are you looking for?" [(ngModel)]="heroQuery"
    button mat-icon-button matSuffix (click)="search(heroQuery)"
      mat-icon — arrow_forward

section.categories [padding: 24px 0]
  h2 mat-h2 — "Shop by Category"
  div.category-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 16px]
    mat-card.category-tile *ngFor="let cat of categories" (click)="filterByCategory(cat)" [routerLink]="['/search']" [queryParams]="{category: cat.id}"
      mat-icon [font-size: 40px] — [cat.icon]
      span mat-body-2 — [cat.name]

section.featured-products [padding: 24px 0]
  h2 mat-h2 — "Featured Products"
  mat-divider
  div.product-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; margin-top: 16px]
    <aliceut-product-card *ngFor="let p of featuredProducts" [product]="p" [loading]="loading">
  div.load-more *ngIf="!loading && hasMore" [text-align: center; margin-top: 24px]
    button mat-stroked-button color="primary" (click)="loadMore()" — Load more
```

### States

- **Loading:** 8 skeleton `ProductCard` components while API responds.
- **Empty (no featured products):** `EmptyState` with `icon="category"`, `title="No products yet"`, `message="Check back soon — the catalog is being stocked."` [DESIGN DECISION: Show static category tiles even when product grid is empty so navigation still works.]
- **Error:** `mat-card.warning-banner` at top — "Could not load featured products. Try refreshing."

### Interactions

- Hero search submits on Enter or arrow button click → navigates to `/search?q={query}`.
- Category tile click → `/search?category={categoryId}`.

### Mobile

- Categories grid: `minmax(80px, 1fr)` (smaller tiles, icon only visible on XS).
- Product grid: `minmax(160px, 1fr)` (2-column on XS handset).

---

## Screen 2 — Search Results

**Route:** `/search?q=&category=&minPrice=&maxPrice=&minRating=&inStock=&sort=&page=`  
**Auth:** None required

### Layout

```
div.search-layout [display: flex; gap: 24px]

  <!-- Sidebar — Desktop only (hidden on mobile, shown in bottom sheet) -->
  aside.filter-sidebar [width: 260px; flex-shrink: 0] *ngIf="isDesktop"
    div.filter-section
      h3 mat-h5 — "Filters"
      button mat-stroked-button (click)="clearAllFilters()" [hidden if no active filters] — Clear all

    mat-accordion
      mat-expansion-panel [expanded]
        mat-expansion-panel-header
          mat-panel-title — "Category"
        mat-tree [dataSource]="categoryTree" [treeControl]
          mat-tree-node *matTreeNodeDef — checkbox + label per category leaf
          mat-nested-tree-node *matTreeNodeDef="let node; when: hasChildren" — expandable group

      mat-expansion-panel [expanded]
        mat-expansion-panel-header — "Price Range"
        mat-slider [min]="minBound" [max]="maxBound" [step]="1" discrete [displayWith]="currencyFormat">
        div.price-inputs [display: flex; gap: 8px]
          mat-form-field [flex: 1]
            mat-label — Min
            input matInput type="text" [formControl]="minPriceCtrl"
          mat-form-field [flex: 1]
            mat-label — Max
            input matInput type="text" [formControl]="maxPriceCtrl"
        p.price-note mat-caption — Prices shown in {{ preferredCurrency }}. Estimates may vary.

      mat-expansion-panel
        mat-expansion-panel-header — "Rating"
        p mat-body-2 — Minimum rating
        div.star-filter
          button mat-icon-button *ngFor="let s of [1,2,3,4,5]" (click)="setMinRating(s)"
            mat-icon [class.filled]="s <= selectedMinRating" — [s <= selectedMinRating ? 'star' : 'star_outline']
        p mat-caption style="color: var(--secondary-text)" — Based on third-party data — reviews not available in V1.

      mat-expansion-panel
        mat-expansion-panel-header — "Availability"
        mat-slide-toggle [formControl]="inStockOnly" — In stock only

    button mat-flat-button color="primary" [fullWidth] (click)="applyFilters()" — Apply Filters

  <!-- Main Results Area -->
  main.results-area [flex: 1; min-width: 0]
    <!-- Results header -->
    div.results-header [display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-bottom: 16px]
      p mat-body-2 — "{{ total }} results for '{{ query }}'"
      div.active-filters [display: flex; gap: 8px; flex-wrap: wrap; flex: 1]
        mat-chip-listbox aria-label="Active filters"
          mat-chip *ngFor="let f of activeFilters" [removable]="true" (removed)="removeFilter(f)"
            [f.label]
            mat-icon matChipRemove — cancel
      mat-form-field [appearance=outline; width: 200px; subscriptSizing=dynamic]
        mat-label — Sort by
        mat-select [formControl]="sortCtrl"
          mat-option value="relevance" — Relevance
          mat-option value="price_asc" — Price: Low to High
          mat-option value="price_desc" — Price: High to Low
          mat-option value="newest" — Newest

    <!-- Mobile filter button -->
    button mat-stroked-button color="primary" (click)="openFilterSheet()" *ngIf="!isDesktop" [margin-bottom: 16px]
      mat-icon — filter_list
      span — Filters {{ activeFilterCount > 0 ? '(' + activeFilterCount + ')' : '' }}

    <!-- Product grid -->
    div.product-grid [display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px]
      <aliceut-product-card *ngFor="let p of results" [product]="p" (addToCart)="addToCart($event)" (cardClick)="navigateToPdp($event)">
      <aliceut-product-card *ngFor="let _ of [1,2,3,4,5,6]" [loading]="true" *ngIf="loading">

    <!-- No results -->
    <aliceut-empty-state *ngIf="!loading && results.length === 0"
      icon="search_off" title="No matches for '{{ query }}'"
      message="Try different keywords or remove some filters.">
      div — Suggested categories: [category chip list]
    </aliceut-empty-state>

    <!-- Pagination -->
    mat-paginator [length]="total" [pageSize]="24" [pageSizeOptions]="[12, 24, 48]" *ngIf="results.length > 0">

    <!-- Search unavailable error -->
    mat-card.error-banner *ngIf="searchError" [color=warn-light; margin-bottom: 16px]
      mat-icon — error_outline
      span — Search is temporarily unavailable — try again shortly.
      button mat-button (click)="retry()" — Retry
```

### States

- **Loading:** Sort dropdown disabled; filter sidebar disabled; skeleton product cards fill grid.
- **Zero results:** `EmptyState` with suggested category chips.
- **Search service down:** Error banner at top; previously loaded results remain visible if present.
- **Active filters:** Chip row below results count; each chip has × to remove individually.

### Mobile

- Filter sidebar hidden; replaced by "Filters (N)" `mat-stroked-button` that opens a `MatBottomSheet` containing the accordion filter panel with an "Apply" button at the bottom.
- Product grid: `minmax(160px, 1fr)` (2-column on handset).
- Sort dropdown: full-width below the "Filters" button.

---

## Screen 3 — Product Detail Page (PDP)

**Route:** `/products/:id`  
**Auth:** None required; Add to Cart requires authenticated account (redirects to login if guest)

### Layout

```
div.pdp-layout [display: grid; grid-template-columns: 1fr 380px; gap: 32px; align-items: start] [desktop]
  <!-- Left: Gallery + Description -->
  div.pdp-left
    nav.breadcrumb [display: flex; gap: 4px; align-items: center; margin-bottom: 16px]
      a mat-button routerLink="/" — Home
      mat-icon [font-size: 16px] — chevron_right
      a mat-button *ngFor="let crumb of breadcrumbs" — [crumb.name]

    div.image-gallery
      div.primary-image [aspect-ratio: 1; border-radius: 8px; overflow: hidden; border: 1px solid divider]
        img [src]="selectedImage" [alt]="product.title" [object-fit: cover; width: 100%; height: 100%]
      div.thumbnail-strip [display: flex; gap: 8px; margin-top: 8px; overflow-x: auto]
        button.thumb *ngFor="let img of product.images" (click)="selectImage(img)"
          img [src]="img.url" [alt]="" [class.selected]="img === selectedImage"
          [width: 64px; height: 64px; border-radius: 4px; border: 2px solid transparent]

    mat-tab-group [marginTop: 32px]
      mat-tab label="Description"
        div.product-description [padding: 16px 0] [innerHTML]="sanitizedDescription"
      mat-tab label="Specifications"
        mat-list
          mat-list-item *ngFor="let spec of product.specifications"
            span mat-list-item-title — [spec.key]
            span mat-list-item-line — [spec.value]

    <!-- Other sellers (FR-P-05) -->
    div.other-sellers *ngIf="otherOffers.length > 0" [margin-top: 32px]
      h3 mat-h5 — "Other sellers offering this product"
      mat-list
        mat-list-item *ngFor="let offer of otherOffers"
          mat-icon matListItemIcon — storefront
          span mat-list-item-title — [offer.sellerName]
          <aliceut-price-display matListItemMeta [amount]="offer.price" [currency]="offer.currency" [isFxEstimate]="offer.isFxEstimate">
          button mat-stroked-button (click)="selectOffer(offer)" *ngIf="offer.id !== selectedOffer.id" — Select
          mat-chip *ngIf="offer.id === selectedOffer.id" color="primary" — Selected

  <!-- Right: Buy Box -->
  aside.buy-box [position: sticky; top: 88px]
    mat-card [padding: 24px]
      h1 mat-h3 [margin-bottom: 8px] — {{ product.title }}

      div.seller-line [display: flex; align-items: center; gap: 8px; margin-bottom: 16px]
        mat-icon [font-size: 16px] — storefront
        span mat-body-2 — Sold by
        a mat-button [font-size: 14px] — {{ selectedOffer.sellerName }}

      div.rating-line [display: flex; align-items: center; gap: 4px; margin-bottom: 16px] *ngIf="product.rating"
        mat-icon *ngFor="let s of ratingStars(product.rating)" [class.filled]="s.filled" — [s.filled ? 'star' : 'star_outline']
        span mat-caption — {{ product.rating.toFixed(1) }}
        mat-icon [matTooltip]="'Based on third-party data — reviews not available in V1'" [font-size: 16px; color: secondary-text] — info_outline

      <aliceut-price-display [amount]="effectivePrice.amount" [currency]="effectivePrice.currency"
        [listAmount]="effectivePrice.listAmount" [isFxEstimate]="effectivePrice.isFxEstimate"
        [offerCurrency]="selectedOffer.currency" [saleEndsAt]="effectivePrice.saleEndsAt"
        [tierMinQty]="effectivePrice.tierMinQty" [tierAmount]="effectivePrice.tierAmount">

      <!-- Variant selector -->
      div.variant-selectors *ngIf="product.variantGroups.length > 0" [margin-top: 16px]
        div *ngFor="let group of product.variantGroups" [margin-bottom: 12px]
          p mat-body-2 [margin-bottom: 4px] — {{ group.name }}: <strong>{{ selectedVariants[group.name] }}</strong>
          div.variant-options [display: flex; gap: 8px; flex-wrap: wrap]
            button mat-stroked-button *ngFor="let opt of group.options"
              (click)="selectVariant(group.name, opt)"
              [class.selected]="selectedVariants[group.name] === opt.value"
              [disabled]="!opt.inStock"
              — {{ opt.value }}

      <!-- Availability -->
      div.availability-badge [margin-top: 12px; display: flex; align-items: center; gap: 8px]
        mat-icon [color]="stockBadge.color" — {{ stockBadge.icon }}
        span mat-body-2 [color]="stockBadge.color" — {{ stockBadge.label }}
          ← "In stock", "Only 3 left", "Out of stock"

      <!-- Quantity -->
      div.quantity-selector [display: flex; align-items: center; gap: 16px; margin-top: 16px]
        p mat-body-2 — Quantity
        div [display: flex; align-items: center; gap: 8px]
          button mat-icon-button [disabled]="qty <= 1" (click)="qty = qty - 1" — remove
          span mat-h6 [min-width: 32px; text-align: center] — {{ qty }}
          button mat-icon-button [disabled]="qty >= maxQty" (click)="qty = qty + 1" — add

      <!-- Add to Cart CTA -->
      button mat-flat-button color="accent" [fullWidth] [disabled]="!canAddToCart" (click)="addToCart()" [margin-top: 16px]
        mat-spinner *ngIf="addingToCart" [diameter]="20"
        span *ngIf="!addingToCart" — {{ inStock ? 'Add to Cart' : 'Out of Stock' }}

      mat-error *ngIf="addToCartError" — {{ addToCartError }}
```

### States

- **Loading:** Skeleton layout — grey rectangle for image, skeleton lines for title/price/buttons.
- **Out of stock variant:** Add to Cart button disabled, label "Out of Stock", badge shows red "Out of stock".
- **FX estimate:** `PriceDisplay` shows `≈` prefix + info tooltip.
- **SALE price:** Strikethrough on list price, SALE chip with countdown.
- **B2B tier:** Tier price hint below main price when `isB2B && tierMinQty != null`.
- **All OOS:** First variant shown selected with OOS badge; Add to Cart disabled.

### Mobile (< 960px)

- Two-column `grid-template-columns` collapses to single column. Buy box renders below the gallery (not sticky). Image gallery full-width. Variant chips wrap.

### Accessibility

- `<h1>` on product title. Image `alt` = product title. Thumbnail buttons: `aria-label="View image N"`. Variant buttons: `aria-pressed` for selected state. Star icons: `role="img"`, `aria-label="Rating: N out of 5 stars"`.

---

## Screen 4 — Cart

**Route:** `/cart`  
**Auth:** None required (guest cart supported)

### Layout

```
h1 mat-h3 — "Shopping Cart" ({{ itemCount }} items)

div.cart-layout [display: grid; grid-template-columns: 1fr 340px; gap: 24px; align-items: start] [desktop]

  <!-- Cart items -->
  div.cart-items
    <!-- Price-updated banner -->
    mat-card.warning-banner *ngIf="priceChangedItems.length > 0" [margin-bottom: 16px]
      mat-icon color="warn" — warning_amber
      span — Prices have updated for {{ priceChangedItems.length }} item(s). Review before checkout.

    <!-- Stale item warning -->
    mat-card.error-banner *ngIf="staleItems.length > 0" [margin-bottom: 16px]
      mat-icon color="warn" — error_outline
      span — {{ staleItems.length }} item(s) are no longer available. Remove them to continue to checkout.

    mat-list [margin-bottom: 16px]
      div.cart-item *ngFor="let item of cartItems" [display: flex; gap: 16px; padding: 16px 0; border-bottom: 1px solid divider]
        img [src]="item.imageUrl" [alt]="item.productTitle" [width: 80px; height: 80px; border-radius: 4px; object-fit: cover]

        div.item-details [flex: 1]
          a mat-button [routerLink]="['/products', item.productId]" — {{ item.productTitle }}
          p mat-caption — {{ item.variantLabel }}
          p mat-body-2 — Sold by: {{ item.sellerName }}

          <!-- Stale item badge -->
          mat-chip color="warn" *ngIf="item.isStale" — Unavailable
          p mat-caption color="warn" *ngIf="item.isStale" — This offer is no longer active.

          <!-- Quantity controls (disabled if stale) -->
          div.qty-controls *ngIf="!item.isStale" [display: flex; align-items: center; gap: 8px; margin-top: 8px]
            button mat-icon-button [disabled]="item.qty <= 1" (click)="decrementQty(item)" — remove
            span mat-body-1 — {{ item.qty }}
            button mat-icon-button [disabled]="item.qty >= item.maxQty" (click)="incrementQty(item)" — add
            mat-error *ngIf="item.qtyError" — {{ item.qtyError }}

        div.item-price [text-align: right]
          <aliceut-price-display [amount]="item.lineTotal" [currency]="item.currency" [listAmount]="item.originalLineTotal">
          p mat-caption *ngIf="item.priceChanged" color="warn" — Price updated
          button mat-button color="warn" (click)="removeItem(item)" — Remove

  <!-- Order Summary -->
  aside.order-summary
    mat-card [padding: 24px]
      h2 mat-h5 [margin-bottom: 16px] — Order Summary
      mat-divider [margin-bottom: 16px]

      div.summary-rows
        div.summary-row *ngFor="let group of currencyGroups" [display: flex; justify-content: space-between; margin-bottom: 8px]
          span mat-body-2 — {{ group.sellerName }} ({{ group.currency }})
          <aliceut-price-display [amount]="group.subtotal" [currency]="group.currency">
        div.summary-row [display: flex; justify-content: space-between; margin-top: 8px]
          span mat-body-2 — Shipping
          span mat-body-2 — Calculated at checkout
        div.summary-row [display: flex; justify-content: space-between; margin-top: 8px]
          span mat-body-2 — Tax
          span mat-body-2 — Calculated at checkout

      mat-divider [margin: 16px 0]

      p mat-caption color="secondary" [margin-bottom: 16px]
        mat-icon [font-size: 14px] — info_outline
        span — Multi-currency cart. Final totals shown per seller at checkout.

      button mat-flat-button color="accent" [fullWidth] [disabled]="!canCheckout" routerLink="/checkout"
        — Proceed to Checkout
      p mat-caption color="warn" [text-align: center; margin-top: 8px] *ngIf="staleItems.length > 0"
        — Remove unavailable items to continue.
      p mat-caption color="warn" [text-align: center; margin-top: 8px] *ngIf="cartItems.length === 0"
        — Your cart is empty.

      button mat-button [fullWidth] routerLink="/" [margin-top: 8px] — Continue Shopping
```

### States

- **Empty cart:** `EmptyState` with `icon="shopping_cart"` and "Continue Shopping" CTA.
- **Stale items:** Error banner at top; "Remove" button on each stale item; checkout CTA disabled.
- **Price changed:** Warning banner at top; "Price updated" label on changed items.
- **Loading:** Skeleton rows (3 rows) with grey rectangles.
- **Guest cart:** Normal display; checkout CTA redirects to `/login?returnUrl=/checkout`.
- **Cart merge notification (post-login):** After login redirect, if guest cart items were merged with the logged-in cart, display a `MatSnackBar` at bottom-center for 5 seconds:
  - Primary message: 'N item(s) from your guest session were added to your cart.'
  - Optional second line (if quantities were adjusted): 'Some quantities were adjusted to match available stock.'

  Triggered from `CartMergeService.mergeResult$` observable on post-login redirect. Rendered in `BuyerShellComponent`.

### Mobile

- Two-column grid collapses to single column (summary below items). Item image shrinks to 64×64. Quantity controls reduce in size.

---

## Screen 5 — Checkout

**Route:** `/checkout`  
**Auth:** Required (redirects to `/login?returnUrl=/checkout` if guest)

### Layout

```
h1 mat-h3 — "Checkout"

div.checkout-layout [display: grid; grid-template-columns: 1fr 340px; gap: 24px; align-items: start] [desktop]
  <!-- Stepper -->
  mat-stepper [linear] #stepper [flex: 1]

    <!-- Step 1: Shipping Address -->
    mat-step [label]="'Shipping Address'" [stepControl]="addressForm"
      form [formGroup]="addressForm"
        mat-form-field [appearance=outline; fullWidth] — mat-label "Full Name" — input formControlName="fullName"
        div.two-col-grid [display: grid; grid-template-columns: 1fr 1fr; gap: 16px]
          mat-form-field — mat-label "Address Line 1" — input formControlName="line1"
          mat-form-field — mat-label "Address Line 2 (optional)" — input formControlName="line2"
          mat-form-field — mat-label "City" — input formControlName="city"
          mat-form-field — mat-label "State / Province" — input formControlName="state"
          mat-form-field — mat-label "Postal Code" — input formControlName="postalCode"
          mat-form-field — mat-label "Country"
            mat-select formControlName="country"
              mat-option *ngFor="let c of countries" [value]="c.code" — {{ c.name }}
        mat-form-field — mat-label "Phone (optional)" — input formControlName="phone"

        div.saved-addresses *ngIf="savedAddresses.length > 0" [margin-bottom: 16px]
          p mat-body-2 — Or select a saved address:
          mat-radio-group [formControl]="savedAddressCtrl" (change)="fillSavedAddress($event)"
            mat-radio-button *ngFor="let addr of savedAddresses" [value]="addr.id"
              {{ addr.fullName }}, {{ addr.city }}, {{ addr.country }}

        mat-checkbox formControlName="saveAddress" *ngIf="isLoggedIn" — Save this address
        div [text-align: right; margin-top: 16px]
          button mat-flat-button color="primary" matStepperNext [disabled]="addressForm.invalid" — Next

    <!-- Step 2: Shipping Method -->
    mat-step [label]="'Shipping Method'" [stepControl]="shippingForm"
      form [formGroup]="shippingForm"
        mat-radio-group formControlName="shippingMethodId" [display: flex; flex-direction: column; gap: 12px]
          mat-card.shipping-option *ngFor="let method of shippingMethods" (click)="selectShipping(method)"
            mat-radio-button [value]="method.id"
              div [display: flex; justify-content: space-between; align-items: center]
                div
                  span mat-body-1 — {{ method.name }}
                  p mat-caption — Estimated delivery: {{ method.etaLabel }}
                <aliceut-price-display [amount]="method.cost" [currency]="method.currency">
        div [text-align: right; margin-top: 16px; display: flex; gap: 8px; justify-content: flex-end]
          button mat-button matStepperPrevious — Back
          button mat-flat-button color="primary" matStepperNext [disabled]="shippingForm.invalid" — Next

    <!-- Step 3: Payment Method -->
    mat-step [label]="'Payment'" [stepControl]="paymentForm"
      form [formGroup]="paymentForm"
        mat-card [padding: 16px; margin-bottom: 16px]
          mat-icon color="primary" [font-size: 32px] — credit_card
          p mat-body-1 — Demo Payment (Mock)
          p mat-caption color="secondary" — This is a simulated payment. No real transaction will occur.
        mat-form-field [appearance=outline; fullWidth]
          mat-label — Card Number (demo)
          input matInput formControlName="cardNumber" placeholder="4111 1111 1111 1111" maxlength="19"
        div.two-col-grid [display: grid; grid-template-columns: 1fr 1fr; gap: 16px]
          mat-form-field — mat-label "Expiry (MM/YY)" — input formControlName="expiry" placeholder="12/27"
          mat-form-field — mat-label "CVV" — input formControlName="cvv" placeholder="123"
        div [text-align: right; margin-top: 16px; display: flex; gap: 8px; justify-content: flex-end]
          button mat-button matStepperPrevious — Back
          button mat-flat-button color="primary" matStepperNext [disabled]="paymentForm.invalid" — Next

    <!-- Step 4: Review & Place Order -->
    mat-step [label]="'Review'"
      div.review-section
        h3 mat-h5 — Shipping to
        p mat-body-2 — {{ addressSummary }}
        mat-divider [margin: 12px 0]
        h3 mat-h5 — Shipping
        p mat-body-2 — {{ selectedShipping.name }} — {{ selectedShipping.etaLabel }}
        mat-divider [margin: 12px 0]
        h3 mat-h5 — Order Items
        mat-list
          mat-list-item *ngFor="let item of cartItems"
            img [src]="item.imageUrl" [alt]="" matListItemAvatar
            span mat-list-item-title — {{ item.productTitle }}
            span mat-list-item-line — {{ item.variantLabel }} × {{ item.qty }}
            <aliceut-price-display matListItemMeta [amount]="item.lineTotal" [currency]="item.currency">

        <!-- Price-changed warning at review step -->
        mat-card.warning-banner *ngIf="priceChangedAtRevalidation.length > 0" [margin-top: 16px; background: warn-100]
          mat-icon color="warn" — warning_amber
          h4 mat-h6 — Prices have changed
          div *ngFor="let change of priceChangedAtRevalidation"
            p mat-body-2 — {{ change.title }}: was {{ change.old }}, now {{ change.new }}
          mat-checkbox [formControl]="priceChangeConfirmed" — I understand and accept the updated prices
          p mat-caption — You must confirm the updated prices to proceed.

        div [text-align: right; margin-top: 24px; display: flex; gap: 8px; justify-content: flex-end]
          button mat-button matStepperPrevious — Back
          button mat-flat-button color="accent" [disabled]="isPlacingOrder || (priceChangedAtRevalidation.length > 0 && !priceChangeConfirmed.value)" (click)="placeOrder()"
            mat-spinner *ngIf="isPlacingOrder" [diameter]="20"
            span *ngIf="!isPlacingOrder" — Place Order

  <!-- Right: Order Summary Panel -->
  aside.checkout-summary [position: sticky; top: 88px]
    mat-card [padding: 24px]
      h2 mat-h5 — Order Summary
      mat-list [dense]
        mat-list-item *ngFor="let item of cartItems"
          span mat-list-item-title — {{ item.productTitle }} × {{ item.qty }}
          <aliceut-price-display matListItemMeta [amount]="item.lineTotal" [currency]="item.currency">
      mat-divider [margin: 12px 0]
      div.totals *ngFor="let group of currencyGroups"
        div [display: flex; justify-content: space-between]
          span mat-body-2 — Subtotal ({{ group.currency }})
          <aliceut-price-display [amount]="group.subtotal" [currency]="group.currency">
        div [display: flex; justify-content: space-between] *ngIf="shippingCost"
          span mat-body-2 — Shipping
          <aliceut-price-display [amount]="group.shippingCost" [currency]="group.currency">
```

### States

- **Step validation:** "Next" button disabled until current step's form is valid.
- **Price re-validation (submit):** Modal price-changed warning inline in Review step with mandatory checkbox before re-submitting.
- **Placing order:** Place Order button shows spinner; all inputs disabled.
- **Network error:** `mat-snack-bar` error — "Failed to place order. Please try again."

### Mobile

- Stepper switches to `orientation="horizontal"` with icon-only step labels.
- Order summary collapses to an expandable `mat-expansion-panel` above the stepper.

---

## Screen 6 — Order Confirmation

**Route:** `/checkout/confirmation?orderId=`  
**Auth:** Required

### Layout

```
div.confirmation [text-align: center; padding: 48px 24px] *ngIf="placement === 'FULLY_PLACED'"
  mat-icon [font-size: 64px; color: success] — check_circle_outline
  h1 mat-h3 — Order Placed!
  p mat-body-1 — Your order {{ order.displayId }} has been confirmed.

div.confirmation [text-align: center; padding: 48px 24px] *ngIf="placement === 'PARTIALLY_PLACED'"
  mat-icon [font-size: 64px; color: warn] — warning_amber
  h1 mat-h3 — Partial Order Placed
  p mat-body-1 — Some items could not be reserved. See details below.

div.sections [max-width: 800px; margin: 0 auto]

  <!-- Placed items -->
  mat-card *ngFor="let fulfillment of order.fulfillments" [margin-bottom: 16px]
    mat-card-header
      mat-icon mat-card-avatar — local_shipping
      mat-card-title — {{ fulfillment.sellerName }}
      mat-card-subtitle — Fulfillment {{ fulfillment.displayId }}
    mat-card-content
      p mat-body-2 — Status: <aliceut-status-badge [status]="'PENDING'" [statusType]="'fulfillment'">
      p mat-body-2 — Tracking: <strong>{{ fulfillment.trackingNumber }}</strong>
      p mat-body-2 — Estimated delivery: <strong>{{ fulfillment.eta | date:'mediumDate' }}</strong>
      mat-divider [margin: 12px 0]
      mat-list [dense]
        mat-list-item *ngFor="let item of fulfillment.items"
          img matListItemAvatar [src]="item.imageUrl" [alt]=""
          span mat-list-item-title — {{ item.productTitle }} × {{ item.qty }}
          <aliceut-price-display matListItemMeta [amount]="item.lineTotal" [currency]="fulfillment.currency">
      mat-divider [margin: 12px 0]
      div [display: flex; justify-content: space-between; font-weight: 500]
        span — Fulfillment total
        <aliceut-price-display [amount]="fulfillment.total" [currency]="fulfillment.currency">

  <!-- Skipped items (if any) -->
  mat-card.warning-section *ngIf="order.skippedItems.length > 0" [margin-bottom: 16px]
    mat-card-header
      mat-icon mat-card-avatar color="warn" — info_outline
      mat-card-title — Items Not Available
    mat-card-content
      p mat-body-2 — These items were in your cart but could not be ordered. They remain in your cart.
      mat-list [dense]
        mat-list-item *ngFor="let item of order.skippedItems"
          span mat-list-item-title — {{ item.productTitle }}
          span mat-list-item-line — Reason: No longer available

  <!-- Failed groups (if PARTIALLY_PLACED) -->
  mat-card.error-section *ngIf="order.failedGroups.length > 0" [margin-bottom: 16px]
    mat-card-header
      mat-icon mat-card-avatar color="warn" — error_outline
      mat-card-title — Could Not Be Reserved
    mat-card-content
      p mat-body-2 — These items could not be reserved and remain in your cart.
      mat-list [dense]
        mat-list-item *ngFor="let item of order.failedGroups"
          span mat-list-item-title — {{ item.productTitle }}
          span mat-list-item-line — Reason: {{ item.reason }}

div.confirmation-actions [text-align: center; margin-top: 24px; display: flex; gap: 16px; justify-content: center]
  button mat-flat-button color="primary" routerLink="/orders" — View Orders
  button mat-stroked-button routerLink="/" — Continue Shopping
  button mat-stroked-button color="warn" routerLink="/cart" *ngIf="order.hasFailedOrSkipped" — View Cart
```

### States

- **FULLY_PLACED:** Green checkmark hero, all sections green.
- **PARTIALLY_PLACED:** Orange warning hero, failed/skipped sections shown.
- **Loading:** Skeleton layout while confirmation data loads (e.g. if navigated with orderId query param).

---

## Screen 7 — Order History

**Route:** `/orders`  
**Auth:** Required

### Layout

```
h1 mat-h3 — "My Orders"

mat-tab-group [color=primary] [margin-bottom: 16px]
  mat-tab label="All Orders"
  mat-tab label="Pending"
  mat-tab label="Shipped"
  mat-tab label="Delivered"
  mat-tab label="Refunded"
  mat-tab label="Cancelled"

<aliceut-data-table [dataSource]="orders" [loading]="loading" emptyMessage="No orders in this status.">
  ng-container matColumnDef="orderId"
    th mat-header-cell — Order ID
    td mat-cell — {{ order.displayId }}
  ng-container matColumnDef="date"
    th mat-header-cell mat-sort-header — Date
    td mat-cell — {{ order.placedAt | date:'mediumDate' }}
  ng-container matColumnDef="status"
    th mat-header-cell — Status
    td mat-cell — <aliceut-status-badge [status]="order.status" [statusType]="'order'">
  ng-container matColumnDef="placementOutcome"
    th mat-header-cell — Placement
    td mat-cell
      mat-chip color="warn" *ngIf="order.placementOutcome === 'PARTIALLY_PLACED'" — Partial
  ng-container matColumnDef="summary"
    th mat-header-cell — Summary
    td mat-cell — {{ order.fulfillmentSummary }}  ← e.g. "2 of 3 shipped"
  ng-container matColumnDef="actions"
    th mat-header-cell — —
    td mat-cell
      button mat-icon-button [routerLink]="['/orders', order.id]" — visibility icon

mat-paginator [pageSize]="20" [pageSizeOptions]="[10,20,50]">

<!-- Empty state -->
<aliceut-empty-state *ngIf="!loading && orders.length === 0"
  icon="receipt_long" title="No orders yet"
  message="Browse the catalog to get started.">
  button mat-flat-button color="primary" routerLink="/" — Browse Products
</aliceut-empty-state>
```

### Mobile

- Table collapses to card list: each card shows Order ID, date, status badge, fulfillment summary, and "View" button.

### Notes

**Partial and in-progress orders:** Orders with derived statuses `IN_PROGRESS`, `PARTIALLY_SHIPPED`, `PARTIALLY_DELIVERED`, `PARTIALLY_REFUNDED` appear under the 'All Orders' tab only. Dedicated tabs are not provided for these intermediate states in V1 — the status badge on each order row is the primary disambiguation mechanism. This is a deliberate V1 simplification.

---

## Screen 8 — Order Detail

**Route:** `/orders/:id`  
**Auth:** Required

### Layout

```
div.page-header [display: flex; align-items: center; gap: 16px; margin-bottom: 24px]
  button mat-icon-button routerLink="/orders" — arrow_back
  h1 mat-h4 — Order {{ order.displayId }}
  <aliceut-status-badge [status]="order.status" [statusType]="'order'">
  mat-chip color="warn" *ngIf="order.placementOutcome === 'PARTIALLY_PLACED'" — Partial

p mat-body-2 — Placed on {{ order.placedAt | date:'long' }}

<!-- Note re: no cancel in V1 -->
mat-card.info-banner [margin-bottom: 16px]
  mat-icon — info_outline
  span — Need to cancel? Contact the seller directly.

div.fulfillments
  mat-card *ngFor="let fulfillment of order.fulfillments" [margin-bottom: 16px]
    mat-card-header
      mat-icon mat-card-avatar — storefront
      mat-card-title — {{ fulfillment.sellerName }}
      mat-card-subtitle
        <aliceut-status-badge [status]="fulfillment.status" [statusType]="'fulfillment'">
    mat-card-content
      <!-- Status timeline -->
      div.timeline [margin-bottom: 16px]
        div.timeline-step *ngFor="let step of fulfillment.timeline" [display: flex; align-items: center; gap: 8px]
          mat-icon [color]="step.reached ? 'primary' : 'disabled'" — [step.reached ? 'check_circle' : 'radio_button_unchecked']
          span mat-body-2 [color]="step.reached ? 'primary-text' : 'disabled-text'" — {{ step.label }}
          span mat-caption color="secondary" *ngIf="step.date" — {{ step.date | date:'medium' }}

      p mat-body-2 *ngIf="fulfillment.trackingNumber" — Tracking: <strong>{{ fulfillment.trackingNumber }}</strong>
      p mat-body-2 *ngIf="fulfillment.eta" — Estimated delivery: <strong>{{ fulfillment.eta | date:'mediumDate' }}</strong>

      mat-divider [margin: 12px 0]
      mat-list [dense]
        mat-list-item *ngFor="let item of fulfillment.items"
          img matListItemAvatar [src]="item.imageUrl" [alt]=""
          span mat-list-item-title — {{ item.productTitle }}
          span mat-list-item-line — {{ item.variantLabel }} × {{ item.qty }} · {{ item.unitPrice | currencyDisplay:item.currency }} each
          <aliceut-price-display matListItemMeta [amount]="item.lineTotal" [currency]="fulfillment.currency">
      mat-divider [margin: 12px 0]
      div [display: flex; justify-content: flex-end]
        <aliceut-price-display [amount]="fulfillment.total" [currency]="fulfillment.currency">
```

### Status Timeline

Steps: Ordered → Shipped → Delivered (→ Refunded if applicable). Reached steps shown in primary colour; future steps in disabled grey.

---

## Screen 9 — Login

**Route:** `/login`  
**Auth:** None (redirect to home if already authenticated)

### Layout

```
div.auth-page [display: flex; justify-content: center; align-items: flex-start; padding: 48px 16px]
  mat-card [width: 100%; max-width: 440px; padding: 32px]
    mat-card-header [text-align: center; margin-bottom: 24px]
      img [src=aliceut-logo.svg; height=48px]
      mat-card-title — Sign in to AliceUT
    mat-card-content
      <!-- Shown when route has returnUrl containing '/checkout' -->
      <mat-card class="info-banner" *ngIf="hasCheckoutIntent">
        <mat-icon>shopping_cart</mat-icon>
        Sign in to complete your purchase
      </mat-card>
      form [formGroup]="loginForm" (ngSubmit)="login()">
        mat-form-field [appearance=outline; fullWidth; margin-bottom: 16px]
          mat-label — Email address
          input matInput type="email" formControlName="email" autocomplete="email"
          mat-error *ngIf="email.hasError('required')" — Email is required
          mat-error *ngIf="email.hasError('email')" — Enter a valid email

        mat-form-field [appearance=outline; fullWidth]
          mat-label — Password
          input matInput [type]="showPassword ? 'text' : 'password'" formControlName="password" autocomplete="current-password"
          button mat-icon-button matSuffix type="button" (click)="showPassword = !showPassword"
            mat-icon — {{ showPassword ? 'visibility_off' : 'visibility' }}
          mat-error *ngIf="password.hasError('required')" — Password is required

        div [display: flex; justify-content: flex-end; margin: 4px 0 16px]
          a mat-button routerLink="/forgot-password" — Forgot password?

        <!-- Server error -->
        mat-card.error-banner *ngIf="loginError" [margin-bottom: 16px]
          mat-icon — error_outline
          span — {{ loginError }}   ← always "Incorrect email or password."

        <!-- Email not verified warning -->
        mat-card.warning-banner *ngIf="emailNotVerified" [margin-bottom: 16px]
          mat-icon — warning_amber
          span — Please verify your email to place orders.
          button mat-button (click)="resendVerification()" [disabled]="resendDisabled" — Resend verification email
          p mat-caption *ngIf="resendCooldown" — Resend available in {{ resendCooldown }}

        button mat-flat-button color="primary" [fullWidth] type="submit" [disabled]="loginForm.invalid || isLoading"
          mat-spinner *ngIf="isLoading" [diameter]="20"
          span *ngIf="!isLoading" — Sign In

      mat-divider [margin: 24px 0]
        span mat-body-2 color="secondary" — or continue with

      div [display: flex; gap: 12px; margin-bottom: 24px]
        button mat-stroked-button [flex: 1] (click)="loginWithGoogle()"
          img [src=google-icon.svg; height=18px; margin-right: 8px]
          span — Google
        button mat-stroked-button [flex: 1] (click)="loginWithFacebook()"
          img [src=facebook-icon.svg; height=18px; margin-right: 8px]
          span — Facebook

    mat-card-footer [text-align: center; padding: 16px]
      span mat-body-2 — Don't have an account?
      a mat-button color="primary" routerLink="/register" — Register
```

### States

- **Submitting:** Button spinner; form disabled.
- **Error:** Inline `mat-card.error-banner` with generic "Incorrect email or password." message (no field-level enumeration).
- **Email not verified:** Warning banner with resend button; resend cooldown countdown.
- **Checkout intent:** Info banner shown above the form when `hasCheckoutIntent` is true (route's `?returnUrl` param contains `/checkout`). Purely contextual — does not change form behavior. `hasCheckoutIntent = this.route.snapshot.queryParams['returnUrl']?.includes('/checkout')`.

---

## Screen 10 — Register

**Route:** `/register`  
**Auth:** None

### Layout (similar shell to Login)

```
mat-card [max-width: 440px]
  mat-card-title — Create your AliceUT account
  form [formGroup]="registerForm"
    mat-form-field — mat-label "Full Name" — input formControlName="fullName"
    mat-form-field — mat-label "Email address" — input type="email" formControlName="email"
    mat-form-field — mat-label "Password" — input type="password" formControlName="password"
      mat-hint — At least 8 characters, 1 letter, 1 number
    mat-checkbox formControlName="isBusinessAccount" — This is a business account
      mat-icon [matTooltip]="'Branding only — same shopping experience as personal accounts'" — info_outline
    button mat-flat-button color="primary" [fullWidth] — Create Account
  mat-divider — or
  div [OAuth buttons identical to login]
  mat-card-footer — Already have an account? <a routerLink="/login">Sign in</a>
```

### Post-registration

Redirects to `/email-verification-pending` showing: "Check your inbox — we sent a verification link to `{email}`." with Resend button and rate-limit messaging. OAuth registrations bypass this and go directly to home.

---

## Screen 11 — Account Settings

**Route:** `/account`  
**Auth:** Required

### Layout

```
h1 mat-h3 — Account Settings

mat-tab-group [orientation=vertical] [on desktop; horizontal on mobile]
  mat-tab label="Profile"
    form [formGroup]="profileForm" [max-width: 560px]
      mat-form-field — mat-label "Display Name" — input formControlName="displayName"
      mat-form-field [appearance=outline; fullWidth; disabled]
        mat-label — Email address
        input [value]="user.email" [disabled]
        mat-hint — Email change — coming soon
      mat-form-field — mat-label "Account Type" — input [value]="accountTypeBadge" [disabled]
      mat-form-field — mat-label "Preferred Display Currency"
        mat-select formControlName="preferredCurrency"
          mat-option value="Auto" — Auto (browser locale)
          mat-option value="USD" — USD — US Dollar
          mat-option value="THB" — THB — Thai Baht
          mat-option value="JPY" — JPY — Japanese Yen
          mat-option value="SGD" — SGD — Singapore Dollar
      mat-form-field *ngIf="user.isBusinessAccount" — mat-label "Business Name" — input formControlName="businessName"
      <!-- B2B only: shown when accountType === 'B2B' -->
      <div *ngIf="user.isBusinessAccount" class="business-logo-section">
        <label>Business Logo (optional)</label>
        <div *ngIf="currentLogoUrl" class="logo-preview">
          <img [src]="currentLogoUrl" alt="Business logo" style="max-height:64px">
          <button mat-icon-button (click)="removeLogo()"><mat-icon>delete</mat-icon></button>
        </div>
        <aliceut-file-upload
          accept="image/jpeg,image/png,image/webp"
          [maxSizeMb]="2"
          [multiple]="false"
          (fileSelected)="onLogoSelected($event)"
          label="Upload logo (JPG/PNG/WebP, max 2MB)">
        </aliceut-file-upload>
      </div>
      p mat-caption — Member since {{ user.createdAt | date:'mediumDate' }}
      button mat-flat-button color="primary" [disabled]="profileForm.pristine || profileForm.invalid" — Save Changes

  mat-tab label="Addresses"
    div [max-width: 560px]
      mat-list
        mat-list-item *ngFor="let addr of addresses"
          mat-icon matListItemIcon — home
          span mat-list-item-title — {{ addr.fullName }}, {{ addr.city }}, {{ addr.country }}
          mat-chip *ngIf="addr.isDefault" — Default
          div matListItemMeta
            button mat-icon-button (click)="editAddress(addr)" — edit
            button mat-icon-button (click)="deleteAddress(addr)" color="warn" — delete_outline
      button mat-stroked-button color="primary" (click)="addAddress()" *ngIf="addresses.length < 10" — Add Address
      mat-error *ngIf="addresses.length >= 10" — Address limit reached (10). Remove one to add a new address.

  mat-tab label="Security"
    div [max-width: 560px]
      h3 mat-h5 — Change Password
      form [formGroup]="passwordForm"
        mat-form-field *ngIf="user.hasLocalPassword" — mat-label "Current Password"
        mat-form-field — mat-label "{{ user.hasLocalPassword ? 'New Password' : 'Set Password' }}"
        mat-form-field — mat-label "Confirm New Password"
        button mat-flat-button color="primary" [disabled]="passwordForm.invalid" — {{ user.hasLocalPassword ? 'Change Password' : 'Set Password' }}
      mat-divider [margin: 24px 0]
      h3 mat-h5 — Sessions
      button mat-stroked-button color="warn" (click)="logoutAllSessions()" — Sign out all other devices
```

### Notes

**Profile tab — Business logo upload:** Logo upload calls `POST /profile/me/logo` (multipart) or similar; returned storage key stored in `profileForm.businessLogoStorageKey`. Displayed in order confirmation emails (ET-01) and invoices per US-P-07.

---

## Screen 12 — Email Verification Pending (State)

**Route:** `/email-verification-pending`

```
div [text-align: center; padding: 64px 24px; max-width: 480px; margin: 0 auto]
  mat-icon [font-size: 64px; color: accent] — mark_email_unread
  h1 mat-h4 — Check your email
  p mat-body-1 — We sent a verification link to <strong>{{ email }}</strong>. Click the link to activate your account.
  p mat-body-2 — You can browse the catalog and add items to your cart while you wait — but you'll need to verify before placing an order.
  button mat-flat-button color="primary" (click)="resend()" [disabled]="resendDisabled || resendLoading" [margin-top: 24px]
    mat-spinner *ngIf="resendLoading" [diameter]="20"
    span *ngIf="!resendLoading" — Resend verification email
  p mat-caption *ngIf="resendCooldown" — You can request another email in {{ resendCooldown }}.
  p mat-caption *ngIf="resendLimitReached" color="warn" — Resend limit reached. Try again after {{ limitResetTime }}.
  button mat-button routerLink="/login" [margin-top: 16px] — Back to sign in
```

---

## Screen 13 — Forgot Password

**Route:** `/forgot-password`

```
mat-card [max-width: 440px; margin: 48px auto]
  mat-card-title — Reset your password
  p mat-body-2 — Enter the email you registered with. If an account exists, we'll send a reset link.
  form (ngSubmit)="requestReset()"
    mat-form-field [appearance=outline; fullWidth] — mat-label "Email address" — input type="email"
    button mat-flat-button color="primary" [fullWidth] — Send reset link
  <!-- Success state (always shown after submit, regardless of whether email exists) -->
  mat-card.success-banner *ngIf="submitted"
    mat-icon color="primary" — check_circle_outline
    span — If an account with that email exists, we sent a reset link. Check your inbox.
  a mat-button routerLink="/login" — Back to sign in
```

---

## Screen 14 — Reset Password

**Route:** `/reset-password` (reads `?token=` query param)  
**Component:** `ResetPasswordComponent`  
**Auth:** Public

### Layout

```html
<div [ngSwitch]="tokenState">
  <mat-spinner *ngSwitchCase="'loading'"></mat-spinner>
  <form *ngSwitchCase="'valid'" [formGroup]="resetForm">
    <mat-form-field>
      <input matInput type="password" formControlName="password" [placeholder]="passwordLabel">
    </mat-form-field>
    <mat-form-field>
      <input matInput type="password" formControlName="confirmPassword" placeholder="Confirm password">
    </mat-form-field>
    <mat-error *ngIf="resetForm.hasError('passwordMismatch')">Passwords do not match</mat-error>
    <button mat-raised-button color="primary" [disabled]="resetForm.invalid">Set New Password</button>
  </form>
  <div *ngSwitchCase="'expired'">
    <p>This reset link has expired or already been used.</p>
    <button mat-button routerLink="/forgot-password">Request a new reset link</button>
  </div>
</div>
```

### States

- **Loading:** On mount, shows form optimistically. Token validity is determined by the `POST /auth/reset-password` response on submit (400 = expired/used). No separate pre-validation endpoint exists.
- **Valid token — standard:** Show "Enter new password" + "Confirm password" fields. Password requirements hint. Submit button "Set New Password". On success: redirect to `/login?passwordReset=true`.
- **Valid token — OAuth-only account:** Same form but `passwordLabel` changes to "Set a password for your account" (user previously had no password hash). Note: shown when account has no existing password hash.
- **Expired/used token:** Error message "This reset link has expired or already been used." with a "Request a new reset link" action that navigates to `/forgot-password`.

---

## Screen 15 — Email Verification Callback

**Route:** `/verify-email` (reads `?token=` query param)  
**Component:** `EmailVerificationCallbackComponent`  
**Auth:** Public

### Layout

```html
<div [ngSwitch]="verifyState">
  <mat-spinner *ngSwitchCase="'loading'"></mat-spinner>
  <div *ngSwitchCase="'success'">Email verified! Redirecting...</div>
  <div *ngSwitchCase="'expired'">
    <p>This verification link has expired.</p>
    <button mat-button (click)="resendVerification()">Resend verification email</button>
  </div>
</div>
```

### States

- **Loading:** Spinner while calling `POST /auth/verify-email { token }`.
- **Success:** "Email verified! Redirecting to login..." then auto-redirect to `/login?verified=true` after 2s.
- **Expired/used token:** "This verification link has expired." with a "Resend verification email" button that calls `POST /auth/resend-verification` (JWT-authenticated, no request body; uses the `sub` claim from the session token).

---

## Appendix — Buyer Notification Types

In-app notification event types consumed by `<aliceut-notification-bell>` and the `/notifications` page.

| Type | Icon | Message pattern |
|---|---|---|
| `ORDER_PLACED` | `receipt` | "Your order #[display_id] has been placed." |
| `FULFILLMENT_SHIPPED` | `local_shipping` | "Your item from [seller_name] has shipped. Tracking: [tracking_number]" |
| `FULFILLMENT_DELIVERED` | `done_all` | "Your order from [seller_name] has been delivered." |
| `FULFILLMENT_REFUNDED` | `currency_exchange` | "A refund of [amount] [currency] has been processed." |
| `AUTO_REFUND_SUSPENDED_SELLER` | `warning` | "A seller's account was suspended. Your order has been automatically refunded." |
| `PARTIAL_PLACEMENT_WARNING` | `info` | "Some items in your order could not be placed due to insufficient stock." |

---

*Last updated: phase-1 design*
