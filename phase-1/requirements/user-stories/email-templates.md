# Email Templates — Phase 1

Notification emails triggered by Kafka events (see US-B-12). All consumers idempotent; dedupe on `event_id`. Amounts serialized as strings (FR-P-04). Currency shown explicitly on every amount.

---

## ET-01 — Order Summary (order.finalized)

**Trigger:** `order.finalized` event  
**Consumer:** `notification.order-summary`  
**To:** `buyer.email`  
**Subject:** `Your order {{order_id}} — summary`

```
Hi {{buyer.full_name}},

Thank you for your purchase. Here's your order summary.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Placed: {{placed_at}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

YOUR ITEMS                     (groups repeated per seller; internal Fulfillment
                                concept not exposed to buyer)

  Sold by: {{seller_name}}
  ┌─────────────────────────────────────────────────┐
  │ {{item.product_title}}                          │
  │ Qty: {{item.quantity}}                          │
  │ {{item.unit_price_display}} {{buyer.preferred_currency}} each       │
  │ Line total: {{item.line_total_display}} {{buyer.preferred_currency}} │
  └─────────────────────────────────────────────────┘
  (repeat per item)

  Sub-total:          {{fulfillment.subtotal_display}} {{buyer.preferred_currency}}
  Shipping (mock):    {{fulfillment.shipping_display}} {{buyer.preferred_currency}}
  Tax:                {{fulfillment.tax_display}} {{buyer.preferred_currency}}
  Seller total:       {{fulfillment.grand_total_display}} {{buyer.preferred_currency}}
  Tracking number:    {{tracking_number}}
  Estimated delivery: {{eta}}

(repeat seller group)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PURCHASE TOTAL

  {{≈ if any_fx_applied}}{{session.grand_total_display}} {{buyer.preferred_currency}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[SKIPPED ITEMS]                (section omitted if skipped_items is empty)

The following items were not included because their listing became
unavailable before checkout completed. They remain in your cart.

  • {{item.product_title}} — No longer available
  (repeat per skipped item)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[COULD NOT BE RESERVED]        (section omitted if failed_groups is empty)

The following items could not be reserved. They remain in your cart.

  • {{item.product_title}} — {{reason}}
  (repeat per failed item)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

View your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Source |
|---|---|
| `order_id` | `Order.display_id` (e.g. `ORD-3F2A1B9C`) |
| `placed_at` | `Order.created_at` |
| `buyer.full_name` / `buyer.email` | `User` record |
| `buyer.preferred_currency` | `User.preferred_currency` (ISO 4217) |
| `seller_name` | `Fulfillment.seller_name` snapshot |
| `item.product_title` | `FulfillmentItem.product_title` snapshot |
| `item.quantity` | `FulfillmentItem.quantity` |
| `item.unit_price_display` | consumer converts `FulfillmentItem.unit_price` to `buyer.preferred_currency` via `FulfillmentItem.fx_rate_used_at_capture` using `decimal.js` (string) |
| `item.line_total_display` | `item.unit_price_display × item.quantity` (string, `decimal.js`) |
| `fulfillment.subtotal_display` / `shipping_display` / `tax_display` / `grand_total_display` | consumer converts each `Fulfillment` aggregate field to `buyer.preferred_currency` via snapshot FX rate (strings) |
| `tracking_number` | `Fulfillment.tracking_number` |
| `eta` | `Fulfillment.eta` |
| `order.grand_total_display` | consumer sums all `fulfillment.grand_total_display` values using `decimal.js`; single total in `buyer.preferred_currency` (string) |
| `any_fx_applied` | `true` if any `FulfillmentItem.fx_rate_used_at_capture` was applied (i.e. order currency ≠ buyer's preferred currency) |
| `skipped_items[].product_title` | from event payload |
| `failed_groups[].items[].product_title` | from event payload |
| `failed_groups[].items[].reason` | from event payload |
| `base_url` | config (env) |

---

## ET-02 — Fulfillment Shipped (fulfillment.shipped)

**Trigger:** `fulfillment.shipped` event  
**Consumer:** `notification.fulfillment-shipped`  
**To:** `buyer.email`  
**Subject:** `Your order from {{seller_name}} has shipped — Order {{order_id}}`

```
Hi {{buyer.full_name}},

Good news — your order from {{seller_name}} is on its way.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Sold by: {{seller_name}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Tracking number:    {{tracking_number}}
Estimated delivery: {{eta}}

ITEMS IN THIS SHIPMENT

  ┌─────────────────────────────────────────────────┐
  │ {{item.product_title}}                          │
  │ Qty: {{item.quantity}}                          │
  └─────────────────────────────────────────────────┘
  (repeat per FulfillmentItem)

Track your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Source |
|---|---|
| `order_id` | `Order.display_id` via `Fulfillment.order_id` FK (e.g. `ORD-3F2A1B9C`) |
| `seller_name` | `Fulfillment.seller_name` snapshot |
| `tracking_number` | `Fulfillment.tracking_number` (assigned at PENDING, unchanged) |
| `eta` | `Fulfillment.eta` |
| `item.product_title` / `item.quantity` | `FulfillmentItem` snapshots |

---

## ET-03 — Fulfillment Delivered (fulfillment.delivered)

**Trigger:** `fulfillment.delivered` event (mock-delivery scheduler)  
**Consumer:** `notification.fulfillment-delivered`  
**To:** `buyer.email`  
**Subject:** `Your order from {{seller_name}} has been delivered — Order {{order_id}}`

```
Hi {{buyer.full_name}},

Your order from {{seller_name}} has been delivered.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Sold by: {{seller_name}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ITEMS DELIVERED

  ┌─────────────────────────────────────────────────┐
  │ {{item.product_title}}                          │
  │ Qty: {{item.quantity}}                          │
  └─────────────────────────────────────────────────┘
  (repeat per FulfillmentItem)

View your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Source |
|---|---|
| `order_id` | `Order.display_id` via `Fulfillment.order_id` FK (e.g. `ORD-3F2A1B9C`) |
| `seller_name` | `Fulfillment.seller_name` snapshot |
| `item.product_title` / `item.quantity` | `FulfillmentItem` snapshots |

---

## ET-04 — Fulfillment Refunded (fulfillment.refunded)

**Trigger:** `fulfillment.refunded` event  
**Consumer:** `notification.fulfillment-refunded`  
**To:** `buyer.email`  
**Subject:** `Your refund from {{seller_name}} has been processed — Order {{order_id}}`

```
Hi {{buyer.full_name}},

A refund for your order from {{seller_name}} has been processed.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Sold by: {{seller_name}}
Refunded at: {{refunded_at}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REFUNDED ITEMS

  ┌─────────────────────────────────────────────────┐
  │ {{item.product_title}}                          │
  │ Qty: {{item.quantity}}                          │
  │ {{item.unit_price_display}} {{buyer.preferred_currency}} each       │
  │ Line total: {{item.line_total_display}} {{buyer.preferred_currency}} │
  └─────────────────────────────────────────────────┘
  (repeat per FulfillmentItem)

Refund total: {{≈ if fx_applied}}{{fulfillment.grand_total_display}} {{buyer.preferred_currency}}

Note: Refunds are processed to your original payment method.
Processing time depends on your payment provider (mock in V1).

View your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Source |
|---|---|
| `order_id` | `Order.display_id` via `Fulfillment.order_id` FK (e.g. `ORD-3F2A1B9C`) |
| `seller_name` | `Fulfillment.seller_name` snapshot |
| `buyer.preferred_currency` | `User.preferred_currency` (ISO 4217) |
| `refunded_at` | `Fulfillment.refunded_at` |
| `item.product_title` / `item.quantity` | `FulfillmentItem` snapshots |
| `item.unit_price_display` / `item.line_total_display` | consumer converts via `FulfillmentItem.fx_rate_used_at_capture` using `decimal.js` (strings) |
| `fulfillment.grand_total_display` | consumer converts `Fulfillment.grand_total` to `buyer.preferred_currency` via snapshot FX rate (string) |
| `fx_applied` | `true` if `Fulfillment.currency ≠ buyer.preferred_currency` |

---

## ET-05 — Order Completed (order.completed)

**Trigger:** `order.completed` event (fires only when Order had ≥ 2 fulfillments)
**Consumer:** `notification.order-completed`
**To:** `buyer.email`
**Subject:** `Everything from order {{order_id}} has been delivered`

```
Hi {{buyer.full_name}},

All items from your order have been delivered.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Placed: {{placed_at}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your order is now complete.

View your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Source |
|---|---|
| `order_id` | `Order.display_id` (e.g. `ORD-3F2A1B9C`) |
| `placed_at` | `Order.created_at` |
| `buyer.full_name` / `buyer.email` | `User` record |
| `base_url` | config (env) |

---

## Implementation Notes

- **Template storage:** HTML body, plain-text body, and subject line for each template (ET-01 through ET-05) are stored as rows in a `email_template` config table (keyed by `template_key`, e.g. `checkout.summary`). Updating copy, layout, or subject requires only a DB update — no code deploy — provided no new variable placeholders are introduced. Adding a new variable requires a code change in the consumer to pass the new value into the render context.
- Template rendering: server-side (NestJS consumer) loads the template from DB, merges render context using a templating library (e.g. Handlebars or Mustache). No client-side rendering.
- All monetary amounts passed to templates as strings; template helpers must not cast to `number`.
- `{{base_url}}` injected from environment config — not hardcoded.
- HTML version: styled with inline CSS for email client compatibility; plain-text version required as fallback (multipart/alternative).
- No unsubscribe link required in V1 (transactional emails only).
- Review prompts, loyalty points, or upsell blocks are out of scope for V1.
