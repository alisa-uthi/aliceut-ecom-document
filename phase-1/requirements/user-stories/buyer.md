# Buyer Stories (US-B-*)

Maps to BRD FR-B-* functional requirements. See [README](README.md) for format legend and cross-role index.

**Design reference:** [AliceUT_Buyer_Portal.png](../../screens/AliceUT_Buyer_Portal.png) is the high-level desktop UI baseline. It informs layout and terminology below; it does not extend the signed V1 scope. Mock-only elements such as personalized recommendations, customer reviews, AliceUT Premium, and returns flows require a separate approved requirement before implementation.

---

## US-B-01 — Register account
**As a** visitor, **I want** to register with email/password or Google/Facebook OAuth, **so that** I can save my cart, orders, and addresses across sessions.
Priority: Must — trace: FR-B-01, NFR-05, NFR-06

**Acceptance criteria**
- Given I am on the register page
  When I submit valid email, password (≥ 8 chars, ≥ 1 letter, ≥ 1 number), and full name
  Then my account is created with `role=CONSUMER` and I am logged in with JWT + refresh token.
- Given I click "Continue with Google"
  When Google returns a verified email
  Then account is created (or linked if email exists) and I am logged in.
- Given I submit an email already in use with a different auth method
  Then I see: "This email is registered via Google. Sign in with Google or reset password to link accounts."
- Password stored via argon2id; plaintext never logged.
- Rate limit: 5 register attempts per IP per 15 min.
- On email/password register: system sends a verification email immediately after account creation. Account may browse catalog and maintain a cart but **cannot place orders** until email is verified. Verification link TTL 24 h; single-use; resend available from login prompt and account settings (rate-limited: 3 resends per hour per email).
- Given I open an expired or already-used verification link
  Then I see "This link has expired — request a new one" with a one-click resend action.
- OAuth registrations are considered pre-verified (provider already verified the email); no additional step required.

**Notes:** B2B account type chosen at register time via checkbox "This is a business account" (branding differ, same UX per FR-P-06d).

---

## US-B-02 — Search products by keyword
**As a** shopper, **I want** to search products by keyword with typo tolerance, **so that** I can find items even when I misspell.
Priority: Must — trace: FR-B-02, NFR-02

**Acceptance criteria**
- Given catalog contains "Sony WH-1000XM5"
  When I search "sonny headphon"
  Then results include the product (fuzzy match on title + description).
- Response p95 ≤ 500ms (NFR-02).
- Empty query → shows featured / recent products.
- Zero results → shows "No matches for '<query>'" + suggested categories.
- Search hits Elasticsearch index, not Postgres.

---

## US-B-03 — Filter search results
**As a** shopper, **I want** to filter by category, price range, and in-stock only, **so that** I narrow to viable options.
Priority: Must — trace: FR-B-03

**Acceptance criteria**
- Filters applied combine via AND.
- Price range in buyer's display currency; ES facet uses converted min/max via cached FX (display-only per FR-P-02).
- "In stock only" filter uses `inventory.changed` projection; hides offers with `available_qty = 0`.
- Rating is an imported product attribute in V1 and supports a minimum-rating filter; creating or submitting reviews remains out of scope.
- **UI layout:** left-side sidebar (min-width 240px) with collapsible filter groups: Category (multi-select checkbox tree), Price range (slider with input boxes or configured price bands), Rating (minimum stars), and In-stock (toggle). Mobile: sticky bottom sheet or drawer. Clear all / Apply buttons at bottom.
- Selected filters show as chips in results header with individual close (×) buttons.

**Notes:** The mock also depicts Brand Partner and Shipping Speed facets. They are design candidates only: add them to V1 only with a BRD change that defines their data and behaviour. The mock's rating displays do not imply review authoring. Rating stars are imported product attributes from the catalog seed data — the UI displays a tooltip on the star widget: "Based on third-party data — reviews not available in V1."

---

## US-B-04 — Sort search results
**As a** shopper, **I want** to sort by relevance, price asc/desc, or newest, **so that** I can compare offers on my preferred axis.
Priority: Must — trace: FR-B-04

**Acceptance criteria**
- Default sort = relevance (ES `_score`).
- Price sort uses cheapest available `Price` in buyer's preferred currency (or FX-converted for display ordering).
- Newest = `product.created_at desc`.
- Sort persists in URL query string (`?sort=price_asc`) for share/back-button.
- **UI placement:** dropdown menu in results header, right-aligned next to filter chips. Options: Relevance (default), Price: Low to High, Price: High to Low, Newest.

**Notes:** The mock labels its dropdown "Featured Partners." That is not a signed V1 sort option; use "Relevance" or obtain approval to define the ranking semantics.

---

## US-B-05 — View product detail page (PDP)
**As a** shopper, **I want** to see product images, description, variants, seller info, price, and availability, **so that** I can decide whether to buy.
Priority: Must — trace: FR-B-05, FR-P-01, FR-P-05

**Acceptance criteria**
- PDP shows: title, gallery (≥ 1 image), description, category breadcrumb, variant selector (color/size), effective price (with strikethrough on SALE), currency, seller name, availability badge (in stock / out of stock).
- Variant selection updates the availability badge and add-to-cart CTA to reflect the selected variant's `available_qty`. Out-of-stock variant: add-to-cart is disabled, badge shows "Out of stock." On page load, default variant is the first in-stock variant; if all variants are OOS, the first variant is shown with the OOS badge.
- For B2B accounts: if a B2B_TIER price row exists for the selected offer, PDP shows the tier threshold and tier price below the effective price (e.g., "Buy 10 or more: $Y each"). Tier price applies automatically when buyer sets quantity ≥ `min_qty`.
- Rating display (imported product attribute) includes a tooltip on the star widget: "Based on third-party data — reviews not available in V1." No review tab or review count link rendered.
- If multiple sellers offer same product → "Other sellers" section listing offers sorted by lowest price in buyer currency (FR-P-05).
- Effective price resolved by: account_type (B2C uses LIST or SALE; B2B_TIER only if qty ≥ min_qty) × current time × selected qty.
- If price in buyer currency missing: show cheapest available price converted via FX with "≈" prefix and tooltip "Estimated in <currency>".
- **UI layout:** show category breadcrumbs, a thumbnail gallery with a primary image, seller name, price/list-price treatment, availability/fulfilment message, quantity control, and the add-to-cart CTA. Specifications may be shown in a product-details tab.
- Customer-review content or a review tab is excluded from V1 unless separately approved.
- Load p95 ≤ 2s cold cache (NFR-01).

---

## US-B-06 — Add to cart
**As a** shopper, **I want** to add a chosen variant + quantity to my cart, **so that** I can proceed to checkout later.
Priority: Must — trace: FR-B-06

**Acceptance criteria**
- Given I select variant + qty on PDP
  When I click "Add to cart"
  Then a `CartItem` referencing the chosen `Offer` is created/upserted.
- Cart badge in header increments.
- Cart page shows each line item's image, product and seller, unit price, quantity decrement/increment controls, line total, and a remove action; it also shows item subtotal, shipping, tax, total estimate, and a checkout CTA.
- Updating quantity immediately recalculates the line and cart totals and revalidates available inventory.
- Adding qty > available inventory → error: "Only N available."
- Adding an item from a different seller does not conflict — cart supports multi-seller.
- On cart page entry, each line re-resolves effective price from live `Offer`/`Price` rows (picks up seller price edits, SALE start/end, etc.) and reflects updated amounts immediately. Price snapshot for FulfillmentItem is taken at checkout submit, not on cart load (FR-P-03).
- Stale items (inactive offer) are visibly labelled "Unavailable" with a "Remove" action. Checkout CTA is disabled while any stale item remains in the cart (in addition to the empty-cart case). Buyer must remove all stale items before proceeding. Server still validates for stale items on checkout submit as defense-in-depth against direct API calls — see US-B-09 step 2 for server-side handling.

---

## US-B-07 — Persistent logged-in cart
**As a** logged-in buyer, **I want** my cart to persist across devices and sessions, **so that** I don't lose items when I switch phone → laptop.
Priority: Must — trace: FR-B-07

**Acceptance criteria**
- Cart stored server-side keyed by `user_id`.
- Login on a new device → cart hydrates from server.
- If a guest cart exists at login → merge: sum quantities per offer, cap at available inventory. Show toast: "N item(s) from your guest session were added to your cart." If any quantities were capped, append: "Some quantities adjusted to match available stock."
- On offer becoming inactive (seller delisted) → item marked stale in cart with "Unavailable — remove" action.

---

## US-B-08 — Guest cart persistence
**As a** guest, **I want** my cart to survive page reloads and browser tabs, **so that** I don't lose items before deciding to register.
Priority: Should — trace: FR-B-08

**Acceptance criteria**
- Guest cart persisted in `localStorage` keyed by anonymous session ID.
- TTL: 30 days.
- On register/login → merge into server cart per US-B-07.

---

## US-B-09 — Checkout with fake payment
**As a** buyer, **I want** to enter shipping address, choose fake payment, and place order, **so that** I complete a purchase.
Priority: Must — trace: FR-B-09, FR-P-03, FR-P-04, NFR-14

**Acceptance criteria**
- Checkout page shows: cart line items, shipping form, a mock shipping-method choice with its displayed cost and delivery estimate, fake payment selector, order total per currency, and "Place order" button.
- The page presents the stages in the mock's order: Shipping Address, Shipping Method, then Payment Method. Exact mock shipping-service names, fees, and estimates are seeded configuration—not a real carrier integration.
- Multi-currency carts: system groups all per-seller-currency fulfillments under one `Order` (e.g. Order ORD-3F2A1B9C). Buyer submits once and sees a single confirmation page listing placed and failed fulfillments. Each fulfillment progresses independently; seller sees only their own fulfillment and currency.
- **Order ID format:** Stored as `Order.display_id` — `ORD-` prefix + first 8 uppercase hex chars of the Order's UUID (e.g. `ORD-3F2A1B9C`). Generated at insert time. UI shows without `#` prefix; `#` is display-only convention in copy.
- On submit:
  1. Validate address (all fields required, country in allowed list).
  2. Identify stale/inactive-offer items in the cart; exclude them from this checkout without removing them; collect as `skipped_items`. If no valid items remain after exclusion → error 422: "No purchasable items in cart." Skipped items are returned in the response and shown to the buyer on the order detail page; they remain in cart.
  3. Create `Order` record (container for fulfillments).
  4. For each seller/currency group of valid items, independently:

     a. Reserve inventory (decrement `available_qty`, hold TTL 15 min).
   
     b. If reservation succeeds: snapshot `FulfillmentItem` fields (`unit_price`, `currency`, `tax`, `fx_rate_used_at_capture`, `quantity` — FR-P-03), create `Fulfillment` (`PENDING`), clear those `CartItem` rows, publish `fulfillment.placed` outbox event — all in one Postgres transaction.
    
     c. If reservation fails: mark that group as failed in `Order`; those `CartItem` rows remain in cart.
  5. Set `Order.placement_outcome`:
     - `FULLY_PLACED` — all groups succeeded.
     - `PARTIALLY_PLACED` — ≥ 1 group failed; failed `CartItem` rows remain in cart.
  6. Publish one `order.finalized` outbox event (same Postgres tx as placement_outcome write) with payload: `order_id`, `placement_outcome`, `fulfillments[]`, `skipped_items[]`, `failed_groups[]`. Fires for both `FULLY_PLACED` and `PARTIALLY_PLACED`.
  7. Return `Order` response including `fulfillments[]`, `skipped_items[]`, `failed_groups[]`.
- `skipped_items` also published in each `fulfillment.placed` event payload (same outbox tx) so non-email downstream consumers know which cart items were silently dropped.
- Idempotency: same `Idempotency-Key` header → same `Order` and its fulfillments returned, no re-processing.
- Kafka publish failure → orders stay in Postgres, outbox relay retries (NFR-14 at-least-once).
- All amounts serialized as strings in API response (FR-P-04b).

**Order lifecycle**

The first persisted Fulfillment state is `PENDING`; a cart is not an order state. The server alone validates the cart, offer status, effective price, buyer currency preference, address, and stock during checkout. Each seller/currency group is processed independently — partial placement is allowed.

**Order fields set at checkout (immutable after placement)**

| Field | Values | Meaning |
|---|---|---|
| `Order.placement_outcome` | `FULLY_PLACED` | All seller/currency groups created as `PENDING` fulfillments. |
| | `PARTIALLY_PLACED` | ≥ 1 group failed inventory reservation; remaining fulfillments placed. Buyer emailed. Failed `CartItem` rows retained. |

**Order.status (derived, projected read model)**

`Order.status` is not stored at checkout; it is projected from the states of its placed Fulfillments via Kafka consumer and follows the same logic as the fulfilment badge in US-B-11. Starts at `PENDING` once any fulfillment is placed; progresses as individual fulfillments advance.

**Fulfillment states**

| From | Actor / trigger | To | Required effects |
|---|---|---|---|
| — | Inventory reservation succeeds for a seller group | `PENDING` | Consume reservation; create immutable fulfillment/item snapshots, mock payment record, tracking number (`TRK-<uuid8>`), ETA (today + 3–7 days deterministic), and `fulfillment.placed` outbox event in one Postgres tx; clear those `CartItem` rows. |
| — | Inventory reservation fails or TTL expires | (no fulfillment created) | Release any active reservation; those `CartItem` rows remain in cart; `Order` records the failure; buyer receives `order.finalized` email if other groups succeeded. |
| `PENDING` | Seller marks shipment | `SHIPPED` | Preserve tracking number from placement; write `fulfillment.shipped` outbox event. |
| `SHIPPED` | Mock-delivery scheduler reaches ETA | `DELIVERED` | Write `fulfillment.delivered` outbox event. |
| `PENDING` | Seller issues full refund | `REFUNDED` | Record fake-payment reversal; write `fulfillment.refunded` outbox event; restore `available_qty`. |
| `SHIPPED` | Seller issues full refund | `REFUNDED` | Record fake-payment reversal; write `fulfillment.refunded` outbox event; stock not restored (goods in transit). _(V1 UI exposes this; full carrier-intercept/return flow deferred to future scope.)_ |

`DELIVERED` and `REFUNDED` are terminal. `DELIVERED → REFUNDED` (post-delivery returns), buyer cancellation, partial refunds, and manual delivery confirmation are out of scope for V1. Repeating an already-completed checkout request (same `Idempotency-Key`) returns the recorded `Order` without creating new fulfillments, stock movements, or events.

**Note — guest checkout:** Checkout requires an authenticated account. Guest users must register or log in before placing an order. Guest cart survives and merges on login per US-B-07 and US-B-08. Guest checkout is deferred to a future phase.

---

## US-B-10 — Order confirmation with mock tracking
**As a** buyer, **I want** confirmation with a mock tracking number and estimated delivery, **so that** I feel the purchase was received.
Priority: Must — trace: FR-B-10

**Acceptance criteria**
- Confirmation page renders on synchronous checkout response — does not wait for Kafka fan-out.
- Shows `Order` ID (Order ORD-<uuid8>). Order total covers placed fulfillments only — skipped and failed items excluded. Up to three sections:
  - **Placed items:** each fulfillment with currency total, per-item snapshot pricing, mock tracking `TRK-<uuid8>`, and ETA; grouped by seller.
  - **Skipped items** (if any `skipped_items`): items whose offer was inactive at submit time; shown with product name and reason "No longer available"; remain in cart.
  - **Failed items** (if `PARTIALLY_PLACED`): items that could not be reserved; shown with product name and reason (e.g. "Out of stock"); remain in cart.
- Tracking number assigned at `PENDING` placement, retained at shipment, never regenerated.
- One summary email dispatched per `Order` via `order.finalized` consumer (async, not blocking); covers placed fulfillments, skipped items, and failed groups in a single email.

---

## US-B-11 — View order history + status
**As a** buyer, **I want** to see past and current orders with status, **so that** I can track fulfillment.
Priority: Must — trace: FR-B-11

**Acceptance criteria**
- `/orders` lists past orders paginated, newest first. Each row shows: `Order` ID (Order ORD-<uuid8>), `placed_at`, fulfillment currency totals, `Order.status` badge, partial-placement warning (if `PARTIALLY_PLACED`), and sub-line "N of M fulfillments shipped" for count context.
- **`Order.status` badge** (derived live from placed Fulfillments only; always shown):

  | Placed fulfillment states | Order Status         |
  |---|----------------------|
  | All `PENDING` | `PENDING`            |
  | All `SHIPPED` | `SHIPPED`            |
  | All `DELIVERED` | `COMPLETED`          |
  | All `REFUNDED` | `REFUNDED`           |
  | Any `REFUNDED` + any `PENDING` or `SHIPPED` | `IN_PROGRESS`        |
  | `DELIVERED` + `REFUNDED` only | `PARTIALLY_REFUNDED` |
  | Any `DELIVERED` + `PENDING`/`SHIPPED`, no `REFUNDED` | `PARTIALLY_DELIVERED` |
  | `PENDING` + `SHIPPED`, no `DELIVERED`, no `REFUNDED` | `PARTIALLY_SHIPPED`  |
  | Any other combination | `IN_PROGRESS`        |

- **`Order.placement_outcome` warning** (permanent, set at checkout):
  - `FULLY_PLACED` → no badge.
  - `PARTIALLY_PLACED` → warning badge "Partial — some items unavailable".

- Expanding an order shows each fulfillment independently with its own status, tracking number, and snapshotted line items (never live-priced — FR-P-03).
- Status updates arrive via Kafka projection to Postgres read model.
- Status transitions per US-B-09: `SHIPPED` by seller, `DELIVERED` by mock-delivery scheduler, `REFUNDED` by seller full refund. Each fulfillment progresses independently.
- No buyer-initiated cancel action in V1 (out of scope per BRD §3.2). Order detail page shows a static note: "Need to cancel? Contact the seller directly."

---

## US-B-12 — Order lifecycle email notifications
**As a** buyer, **I want** to receive email at each key order milestone, **so that** I stay informed without checking the app.
Priority: Must — trace: FR-B-10, FR-B-11

**Acceptance criteria**
- All emails dispatched asynchronously via Kafka consumers — never inline in API handlers.
- Each consumer is idempotent (dedupe on `event_id`); at-least-once delivery with DLQ per consumer group.

**Email triggers**

| Kafka event | Consumer | To | Template | Key content |
|---|---|---|---|---|
| `order.finalized` | `notification.order-summary` | Buyer | [ET-01](email-templates.md#et-01----order-summary-orderfinalized) | `Order` ID and `placement_outcome`; placed fulfillments with snapshot pricing, mock tracking numbers, and ETAs; skipped items section (if any `skipped_items`) with reason "No longer available"; failed groups section (if `PARTIALLY_PLACED`) with reason per group. One email per order regardless of fulfillment count. |
| `fulfillment.shipped` | `notification.fulfillment-shipped` | Buyer | [ET-02](email-templates.md#et-02----fulfillment-shipped-fulfillmentshipped) | Order ORD-<uuid8>, seller name, tracking number `TRK-<uuid8>`, ETA, items in shipment. |
| `fulfillment.delivered` | `notification.fulfillment-delivered` | Buyer | [ET-03](email-templates.md#et-03----fulfillment-delivered-fulfillmentdelivered) | Order ORD-<uuid8>, seller name, items delivered. |
| `fulfillment.refunded` | `notification.fulfillment-refunded` | Buyer | [ET-04](email-templates.md#et-04----fulfillment-refunded-fulfillmentrefunded) | Order ORD-<uuid8>, seller name, refunded items with snapshot pricing, refund amount as string (FR-P-04). |
| `order.completed` | `notification.order-completed` | Buyer | [ET-05](email-templates.md#et-05----order-completed-ordercompleted) | Order ORD-<uuid8> complete — all items delivered. Only sent when Order had ≥ 2 fulfillments; single-fulfillment orders rely on ET-03. |

**Notes:**
- `order.finalized` fires once per `Order` after `placement_outcome` is set; one summary email regardless of fulfillment count.
- `fulfillment.shipped`, `fulfillment.delivered`, `fulfillment.refunded` each fire per fulfillment transition — multi-seller order produces independent emails per seller.
- `order.completed` fires once when all placed Fulfillments reach `DELIVERED` (`Order.status = COMPLETED`); published by the orders read-model projector after processing the final `fulfillment.delivered` event. Skipped for single-fulfillment orders.
- Email body amounts serialized as strings (FR-P-04); currency shown explicitly.

---

## US-B-13 — Reset forgotten password
**As a** registered user, **I want** to reset my forgotten password via email link, **so that** I can regain access to my account without contacting support.
Priority: Must — trace: FR-B-01, NFR-05

**Acceptance criteria**
- Given I click "Forgot password?" on the login page and submit an email address
  Then I see: "If an account with that email exists, we sent a reset link." Response is identical whether the email is registered or not (no email enumeration).
- Reset email contains a single-use link with 60-minute TTL.
- Given I open a valid reset link
  When I submit a new password meeting requirements (≥ 8 chars, ≥ 1 letter, ≥ 1 number)
  Then password is updated, all existing refresh tokens for the account are revoked, and I am redirected to login with a success message.
- Given I open an expired or already-used reset link
  Then I see: "This link has expired or was already used. Request a new one."
- Rate limit: 3 reset requests per email per hour.
- OAuth-only accounts (no local password set) land on a "Set password" variant of the same flow; on completion the account gains local auth alongside OAuth.

---

## US-B-14 — Manage delivery addresses
**As a** registered buyer, **I want** to save, edit, and delete delivery addresses in my account, **so that** I can reuse them at checkout without re-entering details.
Priority: Should — trace: FR-B-09

**Acceptance criteria**
- Buyer can add a new address: full name, address lines, city, state/province, postal code, country (from allowed list), phone number (optional).
- Buyer can edit any saved address. Editing does not alter historical order snapshots — `FulfillmentItem` stores an immutable address copy taken at checkout time.
- Buyer can delete any address. Deleting the current default address prompts the buyer to choose or set a new default first.
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
- Buyer can change password: must provide current password + new password meeting requirements. On success, all refresh tokens **except the current session** are revoked; no forced re-login.
- OAuth-only accounts (no local password) see "Set password" instead of "Change password." Setting a password links local auth without disrupting OAuth login.
- B2B accounts: business name field is editable (max 120 chars); updated value appears on invoice header and "Business" tag in page header.
- Email address is read-only on the profile page (tied to auth identity). Email change is deferred (requires re-verification flow, out of V1 scope).
- Profile accessible from Account → Profile. Page displays: display name, email (read-only with "Email change — coming soon" label), account type badge (Consumer / Business), and member since date.
