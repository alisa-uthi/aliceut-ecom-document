# Buyer Stories (US-B-*)

Maps to BRD FR-B-* functional requirements. See [README](README.md) for format legend and cross-role index.

**Design reference:** [AliceUT_Buyer_Portal.png](../../screens/AliceUT_Buyer_Portal.png) is the high-level desktop UI baseline. It informs layout and terminology below; it does not extend the signed V1 scope. Mock-only elements such as personalized recommendations, customer reviews, AliceUT Premium, and returns flows require a separate approved requirement before implementation.

---

## US-B-00 — Login and session management
**As a** registered user, **I want** to sign in with my credentials or OAuth, **so that** I can access my cart, orders, and seller/admin dashboard.  
Priority: Must — trace: FR-B-01, NFR-05, NFR-06

**Acceptance criteria**
- Given I submit a valid email and password on the login page
  Then I am signed in and redirected to the page I was trying to reach (or home).
- Given I submit an incorrect password
  Then I see: "Incorrect email or password." (no indication of which field is wrong).
- Given I submit an email that has no account
  Then I see: "Incorrect email or password." (no email enumeration).
- Given my account's email is not yet verified
  When I attempt to log in
  Then I am shown the verification-pending prompt with a one-click resend action; I cannot proceed until verified.
- Given I click "Continue with Google"
  When Google returns a verified email matching an existing account
  Then I am signed in.
- Given I click "Continue with Facebook"
  When Facebook returns a verified email matching an existing account
  Then I am signed in.
- OAuth login (Google/Facebook) is available on the buyer portal only. Seller and admin portals are separate and use email/password exclusively; OAuth buttons are not present on those pages.
- JWT access token expires after a short TTL (configurable via env var, default 15 min); the client silently refreshes using the refresh token without requiring re-login.
- Refresh token rotation: each use of a refresh token issues a new refresh token and invalidates the prior one. Token family detection: reuse of an invalidated refresh token invalidates the entire family (all sessions for that account).
- Single-device logout: invalidates the current session's refresh token only.
- All-sessions logout (accessible from Account → Security): invalidates all refresh tokens for the account.
- Role-based routing on login success (buyer portal `/login` only):
  - `BUYER` / `BUSINESS_BUYER` → buyer home.
  - A single account may hold both BUYER and SELLER roles. The seller portal is accessed via `/seller/login` (email/password only); the buyer portal does not route to the seller dashboard.
  - Seller and admin accounts are not accessible via the buyer login portal.
- Admin role is set at account creation via seed script; it is not self-assignable.

**Notes:** OAuth registrations and logins share the same session mechanism as email/password accounts. JWT payload includes `sub` (user ID), `roles`, and `email_verified`.

---

## US-B-01 — Register account
**As a** visitor, **I want** to register with email/password or Google/Facebook OAuth, **so that** I can save my cart, orders, and addresses across sessions.  
Priority: Must — trace: FR-B-01, NFR-05, NFR-06

**Acceptance criteria**
- Given I am on the register page
  When I submit valid email, password (≥ 8 chars, ≥ 1 letter, ≥ 1 number), and full name
  Then my account is created and I am logged in.
- Given I click "Continue with Google"
  When Google returns a verified email
  Then account is created (or linked if email exists) and I am logged in.
- Given I submit an email already in use with a different auth method
  Then I see: "This email is registered via Google. Sign in with Google or reset password to link accounts."
- On email/password register: system sends a verification email immediately after account creation. Account may browse catalog and maintain a cart but **cannot place orders** until email is verified. Verification link TTL 24 h; single-use; resend available from login prompt and account settings (rate-limited: 3 resends per hour per email).
- Given I open an expired or already-used verification link
  Then I see "This link has expired — request a new one" with a one-click resend action.
- Given I click "Continue with Facebook"
  When Facebook returns a verified email
  Then account is created (or linked if email exists) and I am logged in. OAuth accounts are considered pre-verified.
- Given I have requested 3 verification email resends within one hour, when I request another, then I see: "Resend limit reached. You can request another verification email after [time remaining]." The response does not confirm whether the email is registered.
- OAuth registrations are considered pre-verified (provider already verified the email); no additional step required.
- Given I click "Continue with Facebook" and Facebook returns an email already linked to a Google OAuth account,
  Then I see: "This email is registered via Google. Sign in with Google or use password login."

**Notes:** B2B account type chosen at register time via checkbox "This is a business account" (branding differ, same UX per FR-P-06d). OAuth-registered buyer accounts that later apply for seller status must first set a local password (US-B-15), since `/seller/login` requires email/password authentication.

---

## US-B-02 — Search products by keyword
**As a** shopper, **I want** to search products by keyword with typo tolerance, **so that** I can find items even when I misspell.  
Priority: Must — trace: FR-B-02, NFR-02

**Acceptance criteria**
- Given catalog contains "Sony WH-1000XM5"
  When I search "sonny headphon"
  Then results include the product (fuzzy match on title + description).
- Empty query → shows featured / recent products.
- Zero results → shows "No matches for '<query>'" + suggested categories.
- If Elasticsearch is unavailable: API returns HTTP 503; buyer sees "Search is temporarily unavailable — try again shortly." Empty-query / featured-products page falls back to a curated static list served from Postgres.
- Search errors are never surfaced as unhandled exceptions or raw 500 responses.

---

## US-B-03 — Filter search results
**As a** shopper, **I want** to filter by category, price range, and in-stock only, **so that** I narrow to viable options.  
Priority: Must — trace: FR-B-03

**Acceptance criteria**
- Filters applied combine via AND.
- Price range shown in buyer's display currency; display-only estimate (FR-P-02).
- "In stock only" filter hides offers with no available stock.
- Rating is an imported product attribute in V1 and supports a minimum-rating filter; creating or submitting reviews remains out of scope.
- **UI layout:** left-side sidebar (min-width 240px) with collapsible filter groups: Category (multi-select checkbox tree), Price range (slider with input boxes or configured price bands), Rating (minimum stars), and In-stock (toggle). Mobile: sticky bottom sheet or drawer. Clear all / Apply buttons at bottom.
- Selected filters show as chips in results header with individual close (×) buttons.
- **Price filter implementation:** The price range filter is applied against the buyer's preferred-currency display price as pre-indexed in Elasticsearch. The search index maintains a `display_prices` map keyed by ISO currency code, updated whenever a price or FX rate changes (via Kafka consumers consuming price-write and FX-rate events). Filter bounds are applied against this pre-converted value at query time; filter results may lag FX rate changes by up to the search index freshness window (NFR-13).

**Notes:** The mock also depicts Brand Partner and Shipping Speed facets. They are design candidates only: add them to V1 only with a BRD change that defines their data and behaviour. The mock's rating displays do not imply review authoring. Rating stars are imported product attributes from the catalog seed data — the UI displays a tooltip on the star widget: "Based on third-party data — reviews not available in V1."

---

## US-B-04 — Sort search results
**As a** shopper, **I want** to sort by relevance, price asc/desc, or newest, **so that** I can compare offers on my preferred axis.  
Priority: Must — trace: FR-B-04

**Acceptance criteria**
- Default sort = relevance.
- Price sort uses cheapest available price in buyer's preferred currency.
- Newest = most recently listed first.
- Sort persists in URL query string (`?sort=price_asc`) for share/back-button.
- **UI placement:** dropdown menu in results header, right-aligned next to filter chips. Options: Relevance (default), Price: Low to High, Price: High to Low, Newest.

**Notes:** The mock labels its dropdown "Featured Partners." That is not a signed V1 sort option; use "Relevance" or obtain approval to define the ranking semantics.

---

## US-B-05 — View product detail page (PDP)
**As a** shopper, **I want** to see product images, description, variants, seller info, price, and availability, **so that** I can decide whether to buy.  
Priority: Must — trace: FR-B-05, FR-P-01, FR-P-05

**Acceptance criteria**
- PDP shows: title, gallery (≥ 1 image), description, category breadcrumb, variant selector (color/size), effective price (with strikethrough on SALE), currency, seller name, availability badge (in stock / out of stock).
- Variant selection updates the availability badge and add-to-cart CTA to reflect the selected variant's available quantity. Out-of-stock variant: add-to-cart is disabled, badge shows "Out of stock." On page load, default variant is the first in-stock variant; if all variants are OOS, the first variant is shown with the OOS badge.
- For B2B accounts: if a B2B_TIER price exists for the selected offer, PDP shows the tier threshold and tier price below the effective price (e.g., "Buy 10 or more: $Y each"). Tier price applies automatically when buyer sets quantity ≥ minimum.
- Rating display (imported product attribute) includes a tooltip on the star widget: "Based on third-party data — reviews not available in V1." No review tab or review count link rendered.
- If multiple sellers offer same product → "Other sellers" section listing offers sorted by lowest price in buyer currency (FR-P-05).
- Effective price resolved by: account type (B2C uses LIST or SALE; B2B_TIER only if qty ≥ min_qty) × current time × selected qty.
- If price in buyer currency missing: show cheapest available price converted via FX with "≈" prefix and tooltip "Estimated in <currency>".
- Product description is rendered as formatted HTML from the Markdown source (bold, italic, ordered/unordered lists, headings, safe links). Rendering uses a sanitised parser (e.g. `marked` + `DOMPurify`) that strips disallowed HTML tags; raw Markdown characters are never displayed to buyers. US-P-09 DTO validation enforces the 5000-character input limit at write time.
- **UI layout:** show category breadcrumbs, a thumbnail gallery with a primary image, seller name, price/list-price treatment, availability/fulfilment message, quantity control, and the add-to-cart CTA. Specifications may be shown in a product-details tab.
- Customer-review content or a review tab is excluded from V1 unless separately approved.

---

## US-B-06 — Add to cart
**As a** shopper, **I want** to add a chosen variant + quantity to my cart, **so that** I can proceed to checkout later.  
Priority: Must — trace: FR-B-06

**Acceptance criteria**
- Given I select variant + qty on PDP
  When I click "Add to cart"
  Then the item is added (or quantity updated) in my cart.
- Cart badge in header increments.
- Cart page shows each line item's image, product and seller, unit price, quantity decrement/increment controls, line total, and a remove action; it also shows item subtotal, shipping, tax, total estimate, and a checkout CTA.
- Updating quantity immediately recalculates the line and cart totals and revalidates available inventory.
- Adding qty > available inventory → error: "Only N available."
- Adding an item from a different seller does not conflict — cart supports multi-seller.
- On cart page entry, each line re-resolves the current price (picks up seller price edits, SALE start/end, etc.) and reflects updated amounts immediately. Price is locked at order submission (FR-P-03).
- Stale items (inactive offer) are visibly labelled "Unavailable" with a "Remove" action. Checkout CTA is disabled while any stale item remains in the cart (in addition to the empty-cart case). Buyer must remove all stale items before proceeding.
- Given my cart already contains 50 distinct line items (offer + variant combinations),
  When I attempt to add a 51st distinct item,
  Then I see: "Cart limit reached. Remove an item to continue."
  And the item is not added to the cart.

---

## US-B-07 — Persistent logged-in cart
**As a** logged-in buyer, **I want** my cart to persist across devices and sessions, **so that** I don't lose items when I switch phone → laptop.  
Priority: Must — trace: FR-B-07

**Acceptance criteria**
- Login on a new device → cart hydrates from server.
- If a guest cart exists at login → merge: sum quantities per offer, cap at available inventory **checked live at merge time** (not at the time the guest originally added the item). Show toast: "N item(s) from your guest session were added to your cart." If any quantities were capped, append: "Some quantities adjusted to match available stock."
- On offer becoming inactive (seller delisted) → item marked stale in cart with "Unavailable — remove" action.

---

## US-B-08 — Guest cart persistence
**As a** guest, **I want** my cart to survive page reloads and browser tabs, **so that** I don't lose items before deciding to register.  
Priority: Should — trace: FR-B-08

**Acceptance criteria**
- Guest cart persisted in browser storage.
- TTL: 30 days.
- Given my guest cart TTL (30 days) has expired,
  When I next visit the site,
  Then the cart is silently cleared and the cart icon shows 0 items.
  And no error state or notification is shown for TTL expiry.
- On register/login → merge into server cart per US-B-07.

---

## US-B-09 — Checkout with fake payment
**As a** buyer, **I want** to enter shipping address, choose fake payment, and place order, **so that** I complete a purchase.  
Priority: Must — trace: FR-B-09, FR-P-03, FR-P-04, NFR-14

**Acceptance criteria**
- Checkout page shows: cart line items, shipping form, a mock shipping-method choice with its displayed cost and delivery estimate, fake payment selector, order total per currency, and "Place order" button.
- The page presents the stages in the mock's order: Shipping Address, Shipping Method, then Payment Method. Exact mock shipping-service names, fees, and estimates are seeded configuration — not a real carrier integration.
- Multi-currency carts: system groups all per-seller-currency fulfillments under one order. Buyer submits once and sees a single confirmation page listing placed and failed fulfillments. Each fulfillment progresses independently; seller sees only their own fulfillment and currency.
- **Order ID format:** `ORD-` prefix + first 8 uppercase hex chars of the Order's UUID (e.g. `ORD-3F2A1B9C`). UI shows without `#` prefix; `#` is display-only convention in copy.
- On submit:
  1. Validate address (all fields required, country in allowed list).
  2. Identify stale/inactive-offer items in the cart; exclude them from this checkout without removing them; collect as `skipped_items`. If no valid items remain after exclusion → error: "No purchasable items in cart." Skipped items are shown to the buyer on the order detail page; they remain in cart.
  3. Create the order (container for fulfillments).
  4. For each seller/currency group of valid items, independently:

     a. Reserve inventory (hold TTL 15 min).

     b. If reservation succeeds: snapshot item prices/quantities, create fulfillment (`PENDING`), clear those cart items — all atomically.

     c. If reservation fails: mark that group as failed; those cart items remain in cart.
  5. Set placement outcome:
     - `FULLY_PLACED` — all groups succeeded.
     - `PARTIALLY_PLACED` — ≥ 1 group failed; failed cart items remain in cart.
  6. Return order response including fulfillments, skipped items, and failed groups.
- Submitting the same checkout twice (same idempotency key) returns the original order without creating a new one.
- **Price revalidation at submit:** Immediately before creating the order, the system re-resolves the effective price for each valid line item. If any price differs from the price shown on the checkout summary page (configurable tolerance, e.g. ±0.01 in offer currency), the submission is halted and the buyer is presented with a "Price updated" notification listing the changed items and their new prices. The buyer must confirm before re-submitting. The order is not created until the buyer confirms the updated prices.
- If a price changes again after the buyer confirms updated prices but before the order is actually created, the submission is rejected once more and the buyer is shown another "Price updated" notification. The buyer must confirm each time. An order is never created at a price the buyer has not seen and confirmed.
- The buyer's preferred currency is resolved at checkout submission time. The resolved currency is stored immutably as `fulfillment.buyer_display_currency` on each fulfillment. Subsequent changes to the buyer's preferred currency setting do not alter historical order display.

**Order lifecycle**

The first persisted Fulfillment state is `PENDING`; a cart is not an order state. The server validates the cart, offer status, effective price, buyer currency preference, address, and stock during checkout. Each seller/currency group is processed independently — partial placement is allowed.

**Order.status (derived from placed Fulfillment states)**

| Placed fulfillment states | Order Status |
|---|---|
| All `PENDING` | `PENDING` |
| All `SHIPPED` | `SHIPPED` |
| All `DELIVERED` | `COMPLETED` |
| All `REFUNDED` | `REFUNDED` |
| All `CANCELLED` | `CANCELLED` |
| All `REFUNDED` or `CANCELLED` (mix) | `REFUNDED` |
| Any `REFUNDED` + any `PENDING` or `SHIPPED` | `IN_PROGRESS` |
| Any `CANCELLED` + any `PENDING` or `SHIPPED` | `IN_PROGRESS` |
| `DELIVERED` + `REFUNDED` only | `PARTIALLY_REFUNDED` |
| `DELIVERED` + `CANCELLED` only (no `REFUNDED`) | `PARTIALLY_DELIVERED` |
| `DELIVERED` + `REFUNDED` + `CANCELLED` | `PARTIALLY_REFUNDED` |
| Any `DELIVERED` + `PENDING`/`SHIPPED`, no `REFUNDED`, no `CANCELLED` | `PARTIALLY_DELIVERED` |
| `PENDING` + `SHIPPED`, no `DELIVERED`, no `REFUNDED`, no `CANCELLED` | `PARTIALLY_SHIPPED` |
| Any other combination | `IN_PROGRESS` |

**Placement outcome**

| Value | Meaning |
|---|---|
| `FULLY_PLACED` | All seller/currency groups created as `PENDING` fulfillments. |
| `PARTIALLY_PLACED` | ≥ 1 group failed inventory reservation; remaining fulfillments placed. Buyer emailed. Failed cart items retained. |

**Fulfillment states**

| From | Actor / trigger | To |
|---|---|---|
| — | Inventory reservation succeeds for a seller group | `PENDING` |
| — | Inventory reservation fails or TTL expires | (no fulfillment created) |
| `PENDING` | Seller marks shipment | `SHIPPED` |
| `SHIPPED` | Mock-delivery scheduler reaches ETA (US-P-15) | `DELIVERED` |
| `PENDING` | Seller issues full refund | `REFUNDED` |
| `SHIPPED` | Seller issues full refund | `REFUNDED` |
| `PENDING` | Seller cancels unfulfillable order (US-S-11) | `CANCELLED` |
| `PENDING` | Auto-refund monitor: seller suspended + window expired (US-P-16) | `REFUNDED` |

`DELIVERED`, `REFUNDED`, and `CANCELLED` are terminal. `DELIVERED → REFUNDED` (post-delivery returns), buyer cancellation, partial refunds, and manual delivery confirmation are out of scope for V1.

**Note — guest checkout:** Checkout requires an authenticated account. Guest users must register or log in before placing an order. Guest cart survives and merges on login per US-B-07 and US-B-08. Guest checkout is deferred to a future phase.

**Guest checkout interception:** Given a guest navigates to `/checkout` with items in cart, the platform redirects to `/login?next=/checkout` with the prompt "Sign in to complete your purchase." After successful login or registration, the guest cart merges per US-B-07 and the buyer is forwarded to `/checkout`. If the merged cart has no purchasable items after merge, the buyer sees the empty-cart state.

---

## US-B-10 — Order confirmation with mock tracking
**As a** buyer, **I want** confirmation with a mock tracking number and estimated delivery, **so that** I feel the purchase was received.  
Priority: Must — trace: FR-B-10

**Acceptance criteria**
- Confirmation page shown after checkout completes. Shows Order ID (Order `ORD-<uuid8>`). Order total covers placed fulfillments only — skipped and failed items excluded. Up to three sections:
  - **Placed items:** each fulfillment with currency total, per-item snapshot pricing, mock tracking `TRK-<first 8 uppercase hex chars of id>`, and ETA; grouped by seller.
  - **Skipped items** (if any `skipped_items`): items whose offer was inactive at submit time; shown with product name and reason "No longer available"; remain in cart.
  - **Failed items** (if `PARTIALLY_PLACED`): items that could not be reserved; shown with product name and reason (e.g. "Out of stock"); remain in cart.
- Tracking number assigned at `PENDING` placement, retained at shipment, never regenerated.
- One summary email sent per order; covers placed fulfillments, skipped items, and failed groups.

---

## US-B-11 — View order history + status
**As a** buyer, **I want** to see past and current orders with status, **so that** I can track fulfillment.  
Priority: Must — trace: FR-B-11

**Acceptance criteria**
- `/orders` lists past orders paginated, newest first. Pagination: offset-based — `page` (1-based) and `limit` (default 20, max 100) query params; response envelope `{ data, total, page, limit }`. Default sort: `placed_at DESC`. Each row shows: Order ID (Order `ORD-<uuid8>`), `placed_at`, fulfillment currency totals, Order status badge, partial-placement warning (if `PARTIALLY_PLACED`), and sub-line "N of M fulfillments shipped" for count context.
- **Empty state:** if buyer has placed no orders, show "No orders yet — browse the catalog to get started" with a Browse CTA.
- **Order status badge** (derived from placed Fulfillments only; always shown) — see table in US-B-09.
- **Placement outcome warning** (permanent, set at checkout):
  - `FULLY_PLACED` → no badge.
  - `PARTIALLY_PLACED` → warning badge "Partial — some items unavailable".
- Expanding an order shows each fulfillment independently with its own status, tracking number, and snapshotted line items (never live-priced — FR-P-03).
- Status transitions: `SHIPPED` by seller, `DELIVERED` by mock-delivery scheduler, `REFUNDED` by seller full refund. Each fulfillment progresses independently.
- No buyer-initiated cancel action in V1 (out of scope per BRD §3.2). Order detail page shows a static note: "Need to cancel? Contact the seller directly."

---

## US-B-12 — Order lifecycle email notifications
**As a** buyer, **I want** to receive email at each key order milestone, **so that** I stay informed without checking the app.  
Priority: Must — trace: FR-B-10, FR-B-11

**Acceptance criteria**
- All emails dispatched asynchronously — never inline in API handlers.

**Email triggers**

| Trigger event | To | Template | Key content |
|---|---|---|---|
| Order placement finalized | Buyer | [ET-01](email-templates.md#et-01----order-summary-orderfinalized) | Order ID and placement outcome; placed fulfillments with snapshot pricing, mock tracking numbers, and ETAs; skipped items section (if any) with reason "No longer available"; failed groups section (if partially placed). One email per order regardless of fulfillment count. |
| Fulfillment shipped | Buyer | [ET-02](email-templates.md#et-02----fulfillment-shipped-fulfillmentshipped) | Order `ORD-<uuid8>`, seller name, tracking number TRK-<first 8 uppercase hex chars of id>, ETA, items in shipment. |
| Fulfillment delivered | Buyer | [ET-03](email-templates.md#et-03----fulfillment-delivered-fulfillmentdelivered) | Order `ORD-<uuid8>`, seller name, items delivered. |
| Fulfillment refunded | Buyer | [ET-04](email-templates.md#et-04----fulfillment-refunded-fulfillmentrefunded) | Order `ORD-<uuid8>`, seller name, refunded items with snapshot pricing, refund amount. |
| Order fully completed | Buyer | [ET-05](email-templates.md#et-05----order-completed-ordercompleted) | Order `ORD-<uuid8>` complete — all items delivered. Only sent when order had ≥ 2 fulfillments; single-fulfillment orders rely on ET-03. |

**Notes:**
- Order placement email fires once per order regardless of fulfillment count.
- Shipped/delivered/refunded emails fire per fulfillment — multi-seller order produces independent emails per seller.
- Order completed email fires once when all placed fulfillments are delivered; skipped for single-fulfillment orders.

---

## US-B-13 — Reset forgotten password
**As a** registered user, **I want** to reset my forgotten password via email link, **so that** I can regain access to my account without contacting support.  
Priority: Must — trace: FR-B-01, NFR-05

**Acceptance criteria**
- **Stage 1 — email submission (enumeration-safe):** Given I click "Forgot password?" on the login page and submit any email address, Then I see: "If an account with that email exists, we sent a reset link." The response is identical whether the email is registered, unregistered, or OAuth-only — no email enumeration at this stage.
- Reset email (ET-19) contains a single-use link with 60-minute TTL. ET-19 is only dispatched when a matching account is found; the generic response is shown regardless.
- **Stage 2 — link destination (determined by token, not email submission):** The reset link contains a signed token that encodes whether the account has a local password. On click:
  - Local-auth accounts → standard "Enter new password" form.
  - OAuth-only accounts (no local password set) → "Set password" variant form; on completion the account gains local auth alongside existing OAuth login.
- Given I open a valid reset link, When I submit a new password meeting requirements (≥ 8 chars, ≥ 1 letter, ≥ 1 number), Then password is updated, all other active sessions are signed out, and I am redirected to login with a success message "Password updated — please sign in."
- Given I open an expired or already-used reset link, Then I see: "This link has expired or was already used. Request a new one."
- On successful password reset or change (US-B-15), an email notification is sent to the account holder (→ ET-20) confirming the change. This fires even if the reset was initiated by the legitimate owner, as a security alert for unauthorized changes.

---

## US-B-14 — Manage delivery addresses
**As a** registered buyer, **I want** to save, edit, and delete delivery addresses in my account, **so that** I can reuse them at checkout without re-entering details.  
Priority: Should — trace: FR-B-09

**Acceptance criteria**
- Buyer can add a new address: full name, address lines, city, state/province, postal code, country (from allowed list), phone number (optional).
- Country field is a searchable dropdown populated from the full ISO 3166-1 alpha-2 country list. No countries are restricted in V1.
- Buyer can edit any saved address. Editing does not alter historical order snapshots.
- Buyer can delete any address. Deleting the current default address prompts the buyer to choose or set a new default first. Deleting does not alter historical order snapshots.
- One address may be designated as the default shipping address.
- Maximum 10 saved addresses per account; adding beyond the limit shows: "Address limit reached. Remove an address to add a new one."
- Checkout shipping form pre-fills from the default address. Buyer may switch to any other saved address or enter a one-time address (not persisted unless buyer checks "Save this address").
- Address list accessible from Account → Addresses. Each entry shows name, city, country, and a default badge if applicable.

---

## US-B-15 — Manage account profile
**As a** registered buyer, **I want** to view and update my profile details, **so that** my name, password, and business information stay current.  
Priority: Should — trace: FR-B-01

**Acceptance criteria**
- Buyer can update display name (2–80 chars). Change is reflected immediately in header and order history.
- Buyer can change password: must provide current password + new password meeting requirements. On success, all other active sessions are signed out.
- OAuth-only accounts (no local password) see "Set password" instead of "Change password." Setting a password links local auth without disrupting OAuth login.
- B2B accounts: business name field is editable (max 120 chars); updated value appears on invoice header and "Business" tag in page header.
- B2B account holders see an additional "Business Logo" field in profile settings.
  Upload constraints: JPEG, PNG, or WebP only; max 2 MB; max dimensions 800×800 px (resized server-side if larger).
  Stored in MinIO using the same upload flow as product images.
  Displayed on order confirmations and email invoices (ET-01).
- Buyer can set preferred display currency: USD, THB, JPY, SGD, or Auto (default). "Auto" resolves to the currency matching the browser's `Accept-Language` locale at render time; if the resolved currency is not in the supported set, falls back to USD. The setting drives all price display, FX estimates (US-P-02), and the aggregate total in order emails (ET-01). Preference stored server-side; survives logout.
- Email address is read-only on the profile page (tied to auth identity). Email change is deferred (requires re-verification flow, out of V1 scope).
- Profile accessible from Account → Profile. Page displays: display name, email (read-only with "Email change — coming soon" label), preferred display currency selector, account type badge (Consumer / Business), and member since date.
