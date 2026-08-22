# Buyer Stories (US-B-*)

Maps to BRD FR-B-* functional requirements. See [README](README.md) for format legend and cross-role index.

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
- Rating filter deferred to V2 (reviews out of scope §3.2) — placeholder disabled in UI.
- **UI layout:** left-side sidebar (min-width 240px) with collapsible filter groups: Category (multi-select checkbox tree), Price range (slider with input boxes), In-stock (toggle). Mobile: sticky bottom sheet or drawer. Clear all / Apply buttons at bottom.
- Selected filters show as chips in results header with individual close (×) buttons.

**Notes:** V1 filter set = category + price + in-stock only. Rating hidden until V2.

---

## US-B-04 — Sort search results
**As a** shopper, **I want** to sort by relevance, price asc/desc, or newest, **so that** I can compare offers on my preferred axis.
Priority: Must — trace: FR-B-04

**Acceptance criteria**
- Default sort = relevance (ES `_score`).
- Price sort uses cheapest available `Price` in buyer's preferred currency (or FX-converted for display ordering).
- Newest = `product.created_at desc`.
- Sort persists in URL query string (`?sort=price_asc`) for share/back-button.
- **UI placement:** dropdown menu in results header, label "Sort by: Relevance" (current selection), positioned right-aligned next to filter chips. Options: Relevance (default), Price: Low to High, Price: High to Low, Newest.

---

## US-B-05 — View product detail page (PDP)
**As a** shopper, **I want** to see product images, description, variants, seller info, price, and availability, **so that** I can decide whether to buy.
Priority: Must — trace: FR-B-05, FR-P-01, FR-P-05

**Acceptance criteria**
- PDP shows: title, gallery (≥ 1 image), description, category breadcrumb, variant selector (color/size), effective price (with strikethrough on SALE), currency, seller name, availability badge (in stock / low stock / out of stock).
- If multiple sellers offer same product → "Other sellers" section listing offers sorted by lowest price in buyer currency (FR-P-05).
- Effective price resolved by: account_type (B2C uses LIST or SALE; B2B_TIER only if qty ≥ min_qty) × current time × selected qty.
- If price in buyer currency missing: show cheapest available price converted via FX with "≈" prefix and tooltip "Estimated in <currency>".
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
- Checkout page shows: cart line items, shipping form, fake payment selector (mock Visa / mock PayPal), order total per currency, "Place order" button.
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

---

## US-B-10 — Order confirmation with mock tracking
**As a** buyer, **I want** confirmation with a mock tracking number and estimated delivery, **so that** I feel the purchase was received.
Priority: Must — trace: FR-B-10

**Acceptance criteria**
- Confirmation page renders on synchronous checkout response — does not wait for Kafka fan-out.
- Shows order ID, per-item snapshot pricing, mock tracking `TRK-<uuid8>`, ETA = today + 3–7 days (deterministic per order_id seed).
- Email dispatched via `order.placed` consumer (async, not blocking).

---

## US-B-11 — View order history + status
**As a** buyer, **I want** to see past and current orders with status, **so that** I can track fulfillment.
Priority: Must — trace: FR-B-11

**Acceptance criteria**
- `/orders` lists orders paginated, newest first, showing: order_id, placed_at, total per currency, status (`PENDING`, `SHIPPED`, `DELIVERED`, `REFUNDED`).
- Order detail shows snapshotted line items (never live-priced — FR-P-03).
- Status updates arrive via Kafka projection to Postgres read model.
