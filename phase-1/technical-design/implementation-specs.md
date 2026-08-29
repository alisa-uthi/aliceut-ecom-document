# Implementation Specs — Phase 1

Pre-decided implementation constraints extracted from user stories (2026-08-29). Use when authoring detailed design docs (ERD, API specs, event schemas). All decisions here are consistent with BRD §12 locked stack.

---

## Auth

- Password hashing: **argon2id**; plaintext never logged
- Session: **JWT + refresh token rotation**
- Register rate limit: **5 attempts per IP per 15 min**
- Email verification link: **24h TTL, single-use**; resend rate-limited to **3 per hour per email**
- Password reset link: **60-minute TTL, single-use**
- On password reset: **all refresh tokens revoked** (forces re-login on all other devices)
- On password change (profile page): **all refresh tokens revoked except current session**
- OAuth-only accounts have no local password; reset flow creates a password and links local auth

### Seller suspension API guard

Check `SellerProfile.suspension_status` on every seller-only endpoint:
- `ACTIVE` → full seller access.
- `SUSPENDED` → permit only: `GET /seller/orders`, `GET /seller/orders/:id`, `POST /seller/orders/:id/ship`. All other seller endpoints return HTTP 403 `{ "message": "Your account is suspended." }`. Each permitted access under suspension is logged to MongoDB `AuditLog` (`seller_id`, `endpoint`, `timestamp`).

---

## Search

- Search index: **Elasticsearch** (not Postgres); writes async from Kafka events
- Relevance sort: ES `_score`
- Newest sort: `product.created_at desc`
- Price sort: cheapest available `Price` in buyer's preferred currency (FX-converted for display ordering)
- Filter price range: ES facet with min/max converted via cached FX rate (display-only; FR-P-02)
- In-stock filter: checks `available_qty > 0` on the `inventory.changed` projection
- Search index update lag p95 ≤ 5s (NFR-13)
- PDP cold-cache load p95 ≤ 2s (NFR-01)
- Search response p95 ≤ 500ms (NFR-02)

---

## Cart

- Logged-in cart: stored server-side, keyed by `user_id`
- Guest cart: **browser localStorage**, anonymous session ID key, **30-day TTL**
- Cart page re-resolves effective price from live `Offer`/`Price` rows on load
- Price snapshot for `FulfillmentItem` taken at checkout submit, NOT on cart load (FR-P-03)
- Stale-item re-validation on checkout submit (server-side defense-in-depth)

---

## Checkout & Orders

- **Order display ID:** `ORD-` prefix + first 8 uppercase hex chars of UUID (e.g. `ORD-3F2A1B9C`)
- **Tracking number:** `TRK-<uuid8>`, generated at `PENDING`, immutable
- **Mock ETA:** `today + 3–7 days` (deterministic)
- **Inventory reservation TTL:** 15 minutes per seller/currency group
- **Checkout idempotency:** `Idempotency-Key` header; same key returns original `Order`
- **Checkout error:** 422 when no purchasable items after stale-item exclusion
- **API amounts:** always strings in JSON (FR-P-04b)
- **Order.status:** projected read model from Fulfillment states — not stored at checkout

### Checkout Postgres tx (per seller/currency group)

0. Re-verify effective price (inside tx) = confirmed price ± tolerance. If mismatch: abort → HTTP 409 with updated prices; buyer re-enters the confirmation flow. (Closes the race between confirmation dialog and tx commit — see US-B-09 price revalidation note.)
1. Decrement `available_qty` (reserve)
2. Snapshot `FulfillmentItem`: `unit_price`, `currency`, `tax`, `fx_rate_used_at_capture`, `quantity`
3. Create `Fulfillment` (`PENDING`)
4. Clear `CartItem` rows for this group
5. Write `fulfillment.placed` outbox event

Single `order.finalized` outbox event in same tx as `placement_outcome` write.

### Placement outcomes

| Value | Meaning |
|---|---|
| `FULLY_PLACED` | All seller/currency groups → `PENDING` |
| `PARTIALLY_PLACED` | ≥ 1 group failed reservation; remaining placed |

### Fulfillment state machine

| From | Actor | To | Internal effects |
|---|---|---|---|
| — | Reservation succeeds | `PENDING` | Snapshots + mock payment + `TRK-<uuid8>` + ETA + `fulfillment.placed` outbox — one Postgres tx; clear CartItems |
| — | Reservation fails / TTL | (none) | Release reservation; CartItems stay; Order records failure |
| `PENDING` | Seller ships | `SHIPPED` | `fulfillment.shipped` outbox with original `correlation_id` |
| `SHIPPED` | Mock scheduler | `DELIVERED` | `fulfillment.delivered` outbox |
| `PENDING` | Seller refund | `REFUNDED` | Fake reversal; `fulfillment.refunded` outbox; restore `available_qty` |
| `SHIPPED` | Seller refund | `REFUNDED` | Fake reversal; `fulfillment.refunded` outbox; stock NOT restored |

`order.completed` event fires only when Order had ≥ 2 fulfillments.

---

## Kafka — Transactional Outbox

Pattern: `outbox_event(id, topic, key, payload, occurred_at, published_at NULL)` in same Postgres tx as domain change. Relay polls `published_at IS NULL`, publishes, marks done. No direct Kafka publish outside outbox (enforce via architecture test).

### Topics

| Topic | Trigger |
|---|---|
| `seller.kyc.submitted` | Seller submits application |
| `seller.kyc.decided` | Admin approves/rejects (`decision`, `reason`) |
| `seller.suspended` | Admin suspends seller |
| `fulfillment.placed` | Reservation success |
| `fulfillment.shipped` | Seller marks shipped |
| `fulfillment.delivered` | Mock scheduler |
| `fulfillment.refunded` | Seller full refund |
| `order.finalized` | Placement outcome set |
| `order.completed` | All fulfillments DELIVERED (≥ 2 only) |
| `product.changed` | Product create/update |
| `offer.changed` | Offer create/update/deactivate |
| `inventory.changed` | Inventory updated |
| `inventory.low_stock` | SKU below threshold |
| `moderation.listing.removed` | Admin removes listing |

### Event envelope (all events)

`event_id` (UUID), `event_type`, `event_version`, `occurred_at`, `correlation_id`, `payload`

### Schema registry

Avro per topic in Confluent Schema Registry; BACKWARD compatibility.

### Consumer idempotency

`processed_events(event_id, consumer_group, processed_at)` — 7-day TTL. Template: dedupe → handle → commit offset.

### DLQs

- Unhandled exception → `<consumer_group>.dlq` → commit original offset; DLQ non-empty → alert
- SMTP failure: retry 3× exponential → `email.outbound.dlq` + alert

### Notification consumers

| Topic | Consumer group | Template |
|---|---|---|
| `order.finalized` | `notification.order-summary` | ET-01 |
| `fulfillment.shipped` | `notification.fulfillment-shipped` | ET-02 |
| `fulfillment.delivered` | `notification.fulfillment-delivered` | ET-03 |
| `fulfillment.refunded` | `notification.fulfillment-refunded` | ET-04 |
| `order.completed` | `notification.order-completed` | ET-05 |
| `seller.kyc.decided` | `notification.kyc-decided` | — seller email |
| `inventory.low_stock` | `notification.low-stock` | — seller alert |
| `moderation.listing.removed` | `notification.listing-removed` | — seller email + search deindex |
| `seller.suspended` | `notification.seller-suspended` | — deindex + email + audit |

---

## Money Handling

- DB: `NUMERIC(19,4)` monetary; `NUMERIC(19,8)` FX rates
- TypeORM maps money to `string`; services use **decimal.js**
- ESLint: ban `number` on fields matching `/price|amount|tax|fee/i`
- Frontend: parse via decimal.js; format via `Intl.NumberFormat` at display boundary only
- Template helpers must not cast to `number`
- FX rates: hourly cron from `exchangerate.host`
- FX failure: last-known rate within `staleness_threshold` (default 4 h, configurable via env var); else hide conversion

---

## Data Entities & Key Fields

- `FulfillmentItem`: `unit_price NUMERIC(19,4)`, `currency CHAR(3)`, `tax NUMERIC(19,4)`, `fx_rate_used NUMERIC(19,8) NULL`, `quantity INT`
- `SellerProfile.status`: `PENDING_KYC` → `APPROVED` | `REJECTED` | `SUSPENDED`
- `User.roles` (array, multi-value): `BUYER`, `SELLER`, `ADMIN`. One account may hold `BUYER` + `SELLER` simultaneously; `ADMIN` is never co-held with `BUYER` or `SELLER`. `SELLER` role is assigned at seller registration (KYC form submitted); KYC gating uses `SellerProfile.kyc_status`, not a separate role value. JWT payload `roles` is always an array (e.g. `["BUYER","SELLER"]`).
- `User.account_type`: `CONSUMER` | `BUSINESS` (B2B/B2C distinction; orthogonal to roles)
- `Offer.status`: `ACTIVE` | `INACTIVE` (soft delete) | `REMOVED` (admin)
- `Product.status`: `ACTIVE` | `REMOVED` (when all offers removed)
- Ownership check: `offer.seller_id === current_user.seller_id`; else 403
- Cart: server-side `CartItem` references `Offer`; keyed by `user_id`

---

## API Contracts

- NestJS global `ValidationPipe`: `whitelist: true, forbidNonWhitelisted: true, transform: true`
- Every controller input: DTO class with **class-validator** decorators
- Validation errors: HTTP 400 + `{ field, message }[]`
- Unknown fields → 400
- Checkout idempotency: `Idempotency-Key` header

---

## Email Templates

- Storage: `email_template` DB table keyed by `template_key` (e.g. `checkout.summary`)
- Engine: **Handlebars or Mustache** (NestJS consumer)
- Format: **multipart/alternative** (HTML + plain-text fallback)
- HTML: **inline CSS** for email client compat
- No unsubscribe link in V1 (transactional only)
- `{{base_url}}` from env config

### Template variable → DB source mapping

| Variable | Source |
|---|---|
| `order_id` | `Order.display_id` |
| `placed_at` / `buyer.*` | `Order` + `User` |
| `buyer.preferred_currency` | `User.preferred_currency` (ISO 4217) |
| `seller_name` | `Fulfillment.seller_name` snapshot |
| `item.product_title` / `item.quantity` | `FulfillmentItem` snapshots |
| `item.unit_price_display` | decimal.js convert via `FulfillmentItem.fx_rate_used_at_capture` |
| `item.line_total_display` | `unit_price_display × quantity` (decimal.js) |
| `tracking_number` | `Fulfillment.tracking_number` |
| `eta` | `Fulfillment.eta` |
| `fulfillment.*_display` | decimal.js convert via snapshot FX rate |
| `any_fx_applied` | true if any `FulfillmentItem.fx_rate_used_at_capture` applied |
| `skipped_items[].product_title` | `order.finalized` event payload |
| `failed_groups[].items[].product_title` / `reason` | event payload |
| `refunded_at` | `Fulfillment.refunded_at` |
| `base_url` | env config |

---

## Inventory

- `available = on_hand − reserved`
- Default low-stock threshold: **5 per SKU**
- Low-stock: `inventory.low_stock` event → email + in-app banner
- CSV: `sku, on_hand, low_stock_threshold`; max 5MB, ≤ 10k rows; single Postgres tx per SKU; one `inventory.changed` event per SKU

---

## KYC & Audit

- Uploads: **encrypted bucket** (NFR-09)
- Admin doc views: logged to **MongoDB `AuditLog`** with `admin_id`, `doc_id`, `timestamp`
- Moderation + suspension actions: logged to Mongo `AuditLog`

---

## Secrets & Config

- `.env.example` checked in; `.env` gitignored
- Startup fails fast on missing required env vars
- CI pattern-scan for secrets → build fails
- Seed: `pnpm run seed`; idempotent
