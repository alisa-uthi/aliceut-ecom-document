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

**Notes:** The mock also depicts Brand Partner and Shipping Speed facets. They are design candidates only: add them to V1 only with a BRD change that defines their data and behaviour. The mock's rating displays do not imply review authoring.

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
- PDP shows: title, gallery (≥ 1 image), description, category breadcrumb, variant selector (color/size), effective price (with strikethrough on SALE), currency, seller name, availability badge (in stock / low stock / out of stock).
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

---

## US-B-07 — Persistent logged-in cart
**As a** logged-in buyer, **I want** my cart to persist across devices and sessions, **so that** I don't lose items when I switch phone → laptop.
Priority: Must — trace: FR-B-07

**Acceptance criteria**
- Cart stored server-side keyed by `user_id`.
- Login on a new device → cart hydrates from server.
- If a logged-out cart exists at login → merge: sum quantities per offer, cap at available inventory, show toast "Merged N items from guest cart."
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
- Multi-currency carts: system splits into N orders — one per seller currency. Buyer confirms totals per currency separately.
- On submit:
  1. Validate address (all fields required, country in allowed list).
  2. Reserve inventory (decrement `available_qty`, hold TTL 15 min).
  3. Snapshot on each `OrderItem`: `unit_price` (Decimal string), `currency`, `tax` (Decimal), `fx_rate_used_at_capture` (nullable), `quantity` — per FR-P-03.
  4. Publish `order.placed` to Kafka via transactional outbox (same Postgres tx as order insert).
  5. Return order confirmation.
- Idempotency: same `Idempotency-Key` header → same order returned.
- Kafka publish failure → order stays in Postgres, outbox relay retries (NFR-14 at-least-once).
- All amounts serialized as strings in API response (FR-P-04b).

**Order lifecycle**

The first persisted order state is `PENDING`; a cart is not an order state. The server alone validates the cart, offer status, effective price, buyer currency preference, address, and stock during checkout. It creates one `PENDING` order per seller and currency only after the fake payment succeeds.

| From | Actor / trigger | To | Required effects |
|---|---|---|---|
| Cart | Buyer submits checkout | `PENDING` | Lock or reserve stock for the payment attempt (maximum 15 minutes), then consume the successful reservation; create immutable order/item snapshots, mock payment record, tracking number, ETA, and `order.placed` outbox event in one transaction. |
| Payment/reservation failure or expiry | System | Cart remains unchanged | Release any active reservation; create no order and return an actionable error. |
| `PENDING` | Seller marks shipment | `SHIPPED` | Preserve the tracking number issued at placement; write `order.shipped` through the outbox. |
| `SHIPPED` | Mock-delivery scheduler reaches ETA | `DELIVERED` | Write `order.delivered` through the outbox. |
| `PENDING`, `SHIPPED`, or `DELIVERED` | Seller issues full refund | `REFUNDED` | Record fake-payment reversal and `order.refunded`; restore stock only when goods have not shipped. |

`REFUNDED` is terminal. Buyer cancellation, returns, partial refunds, and manual delivery confirmation are out of scope for V1. Repeating an already completed checkout request or transition must return its recorded result without creating a second order, payment reversal, stock movement, or event.

---

## US-B-10 — Order confirmation with mock tracking
**As a** buyer, **I want** confirmation with a mock tracking number and estimated delivery, **so that** I feel the purchase was received.
Priority: Must — trace: FR-B-10

**Acceptance criteria**
- Confirmation page renders on synchronous checkout response — does not wait for Kafka fan-out.
- Shows order ID, per-item snapshot pricing, mock tracking `TRK-<uuid8>`, and ETA = today + 3–7 days (deterministic per order_id seed).
- The tracking number is assigned when the `PENDING` order is placed and is retained when the seller marks it shipped; it is never regenerated during fulfilment.
- Email dispatched via `order.placed` consumer (async, not blocking).

---

## US-B-11 — View order history + status
**As a** buyer, **I want** to see past and current orders with status, **so that** I can track fulfillment.
Priority: Must — trace: FR-B-11

**Acceptance criteria**
- `/orders` lists orders paginated, newest first, showing: order_id, placed_at, total per currency, status (`PENDING`, `SHIPPED`, `DELIVERED`, `REFUNDED`).
- Order detail shows snapshotted line items (never live-priced — FR-P-03).
- Status updates arrive via Kafka projection to Postgres read model.
- Status has only the transitions defined in US-B-09: seller shipment creates `SHIPPED`, the mock-delivery scheduler creates `DELIVERED`, and a seller full refund creates `REFUNDED`. Each split seller/currency order progresses independently.
