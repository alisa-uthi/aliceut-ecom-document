# Email Templates — Phase 1

Notification emails triggered by order and fulfillment lifecycle events (see US-B-12). All amounts shown with explicit currency.

---

## ET-01 — Order Summary (order.finalized)

**Trigger:** Order placement finalized  
**To:** buyer  
**Subject:** `Your order {{order_id}} — summary`

```
Hi {{buyer.full_name}},

Thank you for your purchase. Here's your order summary.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Placed: {{placed_at}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

YOUR ITEMS                     (groups repeated per seller)

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
[SKIPPED ITEMS]                (section omitted if no skipped items)

The following items were not included because their listing became
unavailable before checkout completed. They remain in your cart.

  • {{item.product_title}} — No longer available
  (repeat per skipped item)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[COULD NOT BE RESERVED]        (section omitted if no failed items)

The following items could not be reserved. They remain in your cart.

  • {{item.product_title}} — {{reason}}
  (repeat per failed item)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

View your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `order_id` | Order identifier |
| `placed_at` | When the order was placed |
| `buyer.full_name` / `buyer.email` | Buyer's name and email address |
| `buyer.preferred_currency` | Buyer's preferred display currency |
| `seller_name` | Seller's display name |
| `item.product_title` | Product name |
| `item.quantity` | Quantity purchased |
| `item.unit_price_display` | Unit price in buyer's currency |
| `item.line_total_display` | Total for this line item |
| `fulfillment.subtotal_display` / `shipping_display` / `tax_display` / `grand_total_display` | Seller group subtotal, shipping, tax, and total |
| `tracking_number` | Shipment tracking number |
| `eta` | Estimated delivery date |
| `session.grand_total_display` | Grand total across all sellers |
| `any_fx_applied` | True when totals were converted from a different currency (shows `≈` prefix) |
| `skipped_items[].product_title` | Name of each item skipped at checkout |
| `failed_groups[].items[].product_title` / `reason` | Name and reason for each item that could not be reserved |
| `base_url` | Website base URL |

---

## ET-02 — Fulfillment Shipped (fulfillment.shipped)

**Trigger:** Seller marks fulfillment as shipped  
**To:** buyer  
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
  (repeat per item)

Track your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `order_id` | Order identifier |
| `seller_name` | Seller's display name |
| `tracking_number` | Shipment tracking number |
| `eta` | Estimated delivery date |
| `item.product_title` / `item.quantity` | Product name and quantity |

---

## ET-03 — Fulfillment Delivered (fulfillment.delivered)

**Trigger:** Mock-delivery scheduler marks fulfillment as delivered  
**To:** buyer  
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
  (repeat per item)

View your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `order_id` | Order identifier |
| `seller_name` | Seller's display name |
| `item.product_title` / `item.quantity` | Product name and quantity |

---

## ET-04 — Fulfillment Refunded (fulfillment.refunded)

**Trigger:** Seller issues full refund  
**To:** buyer  
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
  (repeat per item)

Refund total: {{≈ if fx_applied}}{{fulfillment.grand_total_display}} {{buyer.preferred_currency}}

Note: Refunds are processed to your original payment method.
Processing time depends on your payment provider (mock in V1).

View your order at:
{{base_url}}/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `order_id` | Order identifier |
| `seller_name` | Seller's display name |
| `buyer.preferred_currency` | Buyer's preferred display currency |
| `refunded_at` | When the refund was processed |
| `item.product_title` / `item.quantity` | Product name and quantity |
| `item.unit_price_display` / `item.line_total_display` | Refunded unit price and line total |
| `fulfillment.grand_total_display` | Total refund amount |
| `fx_applied` | True when total was converted from a different currency (shows `≈` prefix) |

---

## ET-05 — Order Completed (order.completed)

**Trigger:** All fulfillments in an order are delivered (orders with ≥ 2 fulfillments only)  
**To:** buyer  
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

| Variable | Description |
|---|---|
| `order_id` | Order identifier |
| `placed_at` | When the order was placed |
| `buyer.full_name` / `buyer.email` | Buyer's name and email address |
| `base_url` | Website base URL |
