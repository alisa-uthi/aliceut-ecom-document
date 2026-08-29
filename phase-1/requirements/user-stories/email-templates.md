# Email Templates — Phase 1

Notification emails triggered by auth, order, and fulfillment lifecycle events (see US-B-12). All amounts shown with explicit currency.

Templates are grouped by audience: **Auth** (ET-18, ET-19, ET-20), **Buyer Order Lifecycle** (ET-01–ET-05, ET-13, ET-16), and **Seller Operations** (ET-06–ET-15, ET-17).

---

## ET-18 — Email Verification (auth.email_verification_requested)

**Trigger:** Buyer registers with email/password (US-B-01) — fires immediately on account creation  
**To:** buyer  
**Subject:** `Verify your email address — AliceUT`

```
Hi {{buyer.full_name}},

Thanks for creating an account. Please verify your email address
to complete registration.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [VERIFY EMAIL ADDRESS]
  {{verification_link}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This link expires in {{ttl_hours}} hours and can only be used once.

You can browse the catalog and manage your cart without verifying,
but you cannot place orders until your email is confirmed.

If you didn't create an account, you can ignore this email.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `buyer.full_name` | Buyer's full name as provided at registration |
| `verification_link` | Single-use verification URL with embedded token; TTL 24 h |
| `ttl_hours` | Human-readable TTL label: `24` |
| `base_url` | Website base URL |

---

## ET-19 — Password Reset (auth.password_reset_requested)

**Trigger:** Buyer submits "Forgot password?" flow (US-B-13) — fires when a matching account is found  
**To:** buyer  
**Subject:** `Reset your AliceUT password`

```
Hi {{buyer.full_name}},

We received a request to reset the password for your account.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [RESET PASSWORD]
  {{reset_link}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This link expires in {{ttl_minutes}} minutes and can only be used once.
After resetting, all other active sessions will be signed out.

If you didn't request this, your account is safe — you can
ignore this email. No changes have been made.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `buyer.full_name` | Buyer's full name |
| `reset_link` | Single-use password reset URL with embedded token; TTL 60 min |
| `ttl_minutes` | Human-readable TTL label: `60` |
| `base_url` | Website base URL |

---

## ET-20 — Password Changed (auth.password_changed)

**Trigger:** Buyer successfully resets password via email link (US-B-13) OR changes password from account settings (US-B-15) — fires in both cases  
**To:** buyer  
**Subject:** `Your AliceUT password has been changed`

```
Hi {{buyer.full_name}},

Your AliceUT password was changed successfully.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CHANGE DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Changed at: {{changed_at}}
  Method:     {{change_method}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

If you made this change, no action is needed. All other active
sessions have been signed out as a security measure.

If you did NOT make this change, your account may be compromised.
Secure your account immediately:
  {{base_url}}/account/security

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `buyer.full_name` | Buyer's full name |
| `changed_at` | Timestamp when the password was changed |
| `change_method` | `Password reset link` or `Account settings` — indicates how the change was made |
| `base_url` | Website base URL |

---

## ET-01 — Order Summary (order.finalized)

**Trigger:** Order placement finalized (US-B-12)  
**To:** buyer  
**Subject:** `Your order {{order_id}} — summary`

```
Hi {{buyer.full_name}},
{{#if buyer.business_logo_url}}<img src="{{buyer.business_logo_url}}" alt="{{buyer.business_name}}" style="max-height:60px;" />{{/if}}
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
  │ {{#if fx_applied}}Offer price: {{item.unit_price_offer_display}} {{fulfillment.offer_currency}}{{/if}} │
  └─────────────────────────────────────────────────┘
  (repeat per item)

  Sub-total:          {{fulfillment.subtotal_display}} {{buyer.preferred_currency}}
  Shipping (mock):    {{fulfillment.shipping_display}} {{buyer.preferred_currency}}
  Tax:                {{fulfillment.tax_display}} {{buyer.preferred_currency}}
  Seller total:       {{fulfillment.grand_total_display}} {{buyer.preferred_currency}}
  {{#if fx_applied}}  (Converted from {{fulfillment.offer_currency}} using rate captured at checkout){{/if}}
  Tracking number:    {{tracking_number}}
  Estimated delivery: {{eta}}

(repeat seller group)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PURCHASE TOTAL

  {{session.grand_total_display}} {{buyer.preferred_currency}}
  {{#if any_fx_applied}}All amounts converted from seller currencies using rates captured at checkout.{{/if}}

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
| `buyer.preferred_currency` | Buyer's preferred display currency — primary for all buyer-facing amounts |
| `buyer.business_logo_url` | Optional URL of the business logo (B2B accounts only); omit section when absent |
| `buyer.business_name` | Business name for logo alt text (B2B accounts only) |
| `fulfillment.offer_currency` | Seller's pricing currency for this fulfillment group — shown as reference when it differs from buyer currency |
| `seller_name` | Seller's display name |
| `item.product_title` | Product name |
| `item.quantity` | Quantity purchased |
| `item.unit_price_display` | Unit price in buyer's preferred currency (snapshot × captured FX rate; exact, not estimated) |
| `item.line_total_display` | Line total in buyer's preferred currency (snapshot × captured FX rate) |
| `item.unit_price_offer_display` | Unit price in offer currency — only rendered when `fx_applied` is true |
| `fulfillment.subtotal_display` / `shipping_display` / `tax_display` / `grand_total_display` | Seller group totals in buyer's preferred currency (snapshot × captured FX rate) |
| `fx_applied` | True when buyer's preferred currency differs from offer currency; shows offer-currency reference lines |
| `tracking_number` | Shipment tracking number |
| `eta` | Estimated delivery date |
| `session.grand_total_display` | Grand total across all sellers |
| `any_fx_applied` | True when totals were converted from a different currency (shows `≈` prefix) |
| `skipped_items[].product_title` | Name of each item skipped at checkout |
| `failed_groups[].items[].product_title` / `reason` | Name and reason for each item that could not be reserved |
| `base_url` | Website base URL |

---

## ET-02 — Fulfillment Shipped (fulfillment.shipped)

**Trigger:** Seller marks fulfillment as shipped (US-S-06, US-B-12)  
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

**Trigger:** Mock-delivery scheduler marks fulfillment as delivered (US-B-12)  
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

**Trigger:** Seller issues full refund (US-S-07, US-B-12)  
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
  │ {{#if fx_applied}}Offer price: {{item.unit_price_offer_display}} {{offer_currency}}{{/if}} │
  └─────────────────────────────────────────────────┘
  (repeat per item)

Refund total: {{fulfillment.grand_total_display}} {{buyer.preferred_currency}}
{{#if fx_applied}}(Converted from {{offer_currency}} using rate captured at checkout){{/if}}

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
| `buyer.preferred_currency` | Buyer's preferred currency — primary for all buyer-facing amounts |
| `offer_currency` | Seller's pricing currency — shown as reference when it differs from buyer currency |
| `refunded_at` | When the refund was processed |
| `item.product_title` / `item.quantity` | Product name and quantity |
| `item.unit_price_display` / `item.line_total_display` | Unit price and line total in buyer's preferred currency (snapshot × captured FX rate) |
| `item.unit_price_offer_display` | Unit price in offer currency — only rendered when `fx_applied` is true |
| `fulfillment.grand_total_display` | Total refund amount in buyer's preferred currency |
| `fx_applied` | True when buyer's preferred currency differs from offer currency; shows offer-currency reference |

---

## ET-05 — Order Completed (order.completed)

**Trigger:** All fulfillments in an order are delivered (orders with ≥ 2 fulfillments only) (US-B-12)  
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

---

## ET-13 — Order Auto-Refunded — Seller Suspended, Buyer Notice (fulfillment.refund_suspended_seller)

**Trigger:** Seller's account is suspended and an order has passed its fulfillment window without being shipped (US-A-05). Same event also sends ET-13b to the seller.
**To:** buyer
**Subject:** `Your order from {{seller_name}} could not be fulfilled — refund issued — Order {{order_id}}`

```
Hi {{buyer.full_name}},

We were unable to fulfill part of your order because the seller's
account is no longer active. We have issued a full refund for the
affected items.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Sold by: {{seller_name}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REFUNDED ITEMS

  ┌─────────────────────────────────────────────────┐
  │ {{item.product_title}}                          │
  │ Qty: {{item.quantity}}                          │
  │ {{item.unit_price_display}} {{buyer.preferred_currency}} each       │
  │ Line total: {{item.line_total_display}} {{buyer.preferred_currency}} │
  │ {{#if fx_applied}}Offer price: {{item.unit_price_offer_display}} {{offer_currency}}{{/if}} │
  └─────────────────────────────────────────────────┘
  (repeat per item)

Refund total: {{fulfillment.grand_total_display}} {{buyer.preferred_currency}}
{{#if fx_applied}}(Converted from {{offer_currency}} using rate captured at checkout){{/if}}

Refunds are processed to your original payment method.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

View your orders at:
{{base_url}}/orders/{{order_id}}

We apologise for the inconvenience.

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `order_id` | Order identifier |
| `buyer.full_name` | Buyer's full name |
| `buyer.preferred_currency` | Buyer's preferred currency — primary for all buyer-facing amounts |
| `offer_currency` | Seller's pricing currency — shown as reference when it differs from buyer currency |
| `seller_name` | Seller's display name |
| `item.product_title` / `item.quantity` | Product name and quantity |
| `item.unit_price_display` / `item.line_total_display` | Unit price and line total in buyer's preferred currency (snapshot × captured FX rate) |
| `item.unit_price_offer_display` | Unit price in offer currency — only rendered when `fx_applied` is true |
| `fulfillment.grand_total_display` | Total refund amount in buyer's preferred currency |
| `fx_applied` | True when buyer's preferred currency differs from offer currency; shows offer-currency reference |
| `base_url` | Website base URL |

---

## ET-16 — Order Cancelled by Seller (fulfillment.cancelled)

**Trigger:** Seller cancels a PENDING fulfillment they cannot fulfill (US-S-11)
**To:** buyer
**Subject:** `Your order from {{seller_name}} has been cancelled — refund issued — Order {{order_id}}`

```
Hi {{buyer.full_name}},

Your order from {{seller_name}} has been cancelled and a full refund
has been issued.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Sold by: {{seller_name}}
Cancelled at: {{cancelled_at}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SELLER'S REASON

  {{cancellation_reason}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REFUNDED ITEMS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ┌─────────────────────────────────────────────────┐
  │ {{item.product_title}}                          │
  │ Qty: {{item.quantity}}                          │
  │ {{item.unit_price_display}} {{buyer.preferred_currency}} each       │
  │ Line total: {{item.line_total_display}} {{buyer.preferred_currency}} │
  │ {{#if fx_applied}}Offer price: {{item.unit_price_offer_display}} {{offer_currency}}{{/if}} │
  └─────────────────────────────────────────────────┘
  (repeat per item)

Refund total: {{fulfillment.grand_total_display}} {{buyer.preferred_currency}}
{{#if fx_applied}}(Converted from {{offer_currency}} using rate captured at checkout){{/if}}

Refunds are processed to your original payment method.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

View your order at:
{{base_url}}/orders/{{order_id}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `order_id` | Order identifier |
| `buyer.full_name` | Buyer's full name |
| `buyer.preferred_currency` | Buyer's preferred currency — primary for all buyer-facing amounts |
| `offer_currency` | Seller's pricing currency — shown as reference when it differs from buyer currency |
| `seller_name` | Seller's display name |
| `cancelled_at` | Timestamp of cancellation |
| `cancellation_reason` | Seller-provided reason (≤ 500 chars) |
| `item.product_title` / `item.quantity` | Product name and quantity |
| `item.unit_price_display` / `item.line_total_display` | Unit price and line total in buyer's preferred currency (snapshot × captured FX rate) |
| `item.unit_price_offer_display` | Unit price in offer currency — only rendered when `fx_applied` is true |
| `fulfillment.grand_total_display` | Total refund/cancellation amount in buyer's preferred currency |
| `fx_applied` | True when buyer's preferred currency differs from offer currency; shows offer-currency reference |
| `base_url` | Website base URL |

---

## ET-06 — KYC Approved (kyc.approved)

**Trigger:** Admin approves seller KYC application (US-A-02)
**To:** seller  
**CC:** admin
**Subject:** `Your seller account is approved — start listing on AliceUT`

```
Hi {{seller.full_name}},

Your seller application for {{seller.business_name}} has been reviewed
and approved. Your account is now active.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHAT'S NEXT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You can now create product listings and receive orders.

  Create your first listing:
  {{base_url}}/seller/listings/new

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

If you have questions, visit your seller dashboard:
{{base_url}}/seller

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `seller.business_name` | Registered business name |
| `base_url` | Website base URL |

---

## ET-07 — KYC Rejected (kyc.rejected)

**Trigger:** Admin rejects seller KYC application (US-A-02)
**To:** seller  
**CC:** admin
**Subject:** `Your seller application was not approved — {{seller.business_name}}`

```
Hi {{seller.full_name}},

We've reviewed your seller application for {{seller.business_name}}
and are unable to approve it at this time.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REASON
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{{rejection_reason}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHAT TO DO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You can update your documents and resubmit your application.

  Update and resubmit:
  {{base_url}}/seller/onboarding/resubmit

Please address the reason above before resubmitting.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `seller.business_name` | Registered business name |
| `rejection_reason` | Admin-provided rejection reason (≤ 500 chars) |
| `base_url` | Website base URL |

---

## ET-08 — Listing Flagged (listing.flagged)

**Trigger:** Listing auto-flagged by keyword blocklist or prohibited category check (US-A-03, US-S-03, US-S-04)
**To:** seller
**Subject:** `Your listing is under review — {{product_title}}`

```
Hi {{seller.full_name}},

Your listing has been flagged and is temporarily hidden from the
catalog pending admin review.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LISTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Title:       {{product_title}}
  Flagged at:  {{flagged_at}}
  Flag reason: {{flag_reason}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHAT HAPPENS NEXT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

An admin will review the listing. If it complies with our policies,
it will be reinstated. If it is removed, you will receive a separate
notification with the reason.

Existing orders for this listing are not affected.

View your listings:
{{base_url}}/seller/listings

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `product_title` | Title of the flagged listing |
| `flagged_at` | Timestamp when flag was applied |
| `flag_reason` | Flag source: `Keyword match` or `Prohibited category` |
| `base_url` | Website base URL |

---

## ET-09 — Listing(s) Removed (listing.removed)

**Trigger:** `listing.removed` event per listing (US-A-04). Consumer aggregates per seller by daily time window; one email per seller per day covering all removals that day.  
**To:** seller  
**CC:** admin  
**Subject:** `{{listings_count}} listing{{#if listings_count > 1}}s{{/if}} removed from the AliceUT catalog`

```
Hi {{seller.full_name}},

The following listing{{#if listings_count > 1}}s have{{else}} has{{/if}} been removed
from the AliceUT catalog.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REMOVED LISTING{{#if listings_count > 1}}S{{/if}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ┌─────────────────────────────────────────────────┐
  │ {{listing.product_title}}                       │
  │ Removed at: {{listing.removed_at}}              │
  │ Category:   {{listing.removal_category}}        │
  │ Reason:     {{listing.removal_reason}}          │
  └─────────────────────────────────────────────────┘
  (repeat per listing)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PENDING ORDERS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Any orders placed before removal are still active. You are still
responsible for fulfilling them.

  View your orders:
  {{base_url}}/seller/orders

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHAT TO DO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You may create new, compliant listings. Removed listings
cannot be reactivated.

  Review our policies:
  {{base_url}}/seller/policies

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `listings_count` | Number of listings removed that day for this seller |
| `listings[].product_title` | Title of each removed listing |
| `listings[].removed_at` | Removal timestamp for each listing |
| `listings[].removal_category` | Per-listing dropdown: `Prohibited category`, `IP violation`, `Misleading content`, `Other` |
| `listings[].removal_reason` | Per-listing admin-provided free-text reason |
| `base_url` | Website base URL |

---

## ET-10 — Seller Suspended (seller.suspended)

**Trigger:** Admin suspends seller account (US-A-05)
**To:** seller  
**CC:** admin
**Subject:** `Your seller account has been suspended`

```
Hi {{seller.full_name}},

Your seller account for {{seller.business_name}} has been suspended.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUSPENSION DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Suspended at: {{suspended_at}}
  Duration:     {{#if is_permanent}}Permanent{{else}}{{duration_label}} (until {{suspended_until}}){{/if}}
  Reason:       {{suspension_reason}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHAT THIS MEANS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • Your listings have been removed from the catalog.
  • You cannot access your seller dashboard during this period.
  • Your buyer account is not affected.
  • You are still required to fulfill any pending orders.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PENDING ORDERS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

If you have unfulfilled orders, you must still complete them.
Failure to ship within the order window will result in automatic
refunds to buyers.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `seller.business_name` | Registered business name |
| `suspended_at` | Timestamp of suspension |
| `is_permanent` | Boolean — true for permanent suspensions |
| `duration_label` | Human-readable duration: `7 days`, `30 days`, `90 days` |
| `suspended_until` | Expiry timestamp (omitted when `is_permanent` is true) |
| `suspension_reason` | Admin-provided reason |

---

## ET-11 — Suspension Lifted — Auto-Expiry (seller.suspension_expired)

**Trigger:** Timed suspension reaches `suspended_until` and auto-lifts (US-A-05)
**To:** seller  
**CC:** admin
**Subject:** `Your seller account has been reinstated`

```
Hi {{seller.full_name}},

Your suspension period has ended and your seller account for
{{seller.business_name}} is now active again.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ACCOUNT STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Reinstated at: {{reinstated_at}}
  Your listings have been restored to the catalog.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Please review our seller policies to avoid future violations:
{{base_url}}/seller/policies

Go to your seller dashboard:
{{base_url}}/seller

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `seller.business_name` | Registered business name |
| `reinstated_at` | Timestamp when suspension lifted |
| `base_url` | Website base URL |

---

## ET-12 — Seller Reinstated by Admin (seller.reinstated)

**Trigger:** Admin manually lifts suspension early (US-A-05b)
**To:** seller  
**CC:** admin
**Subject:** `Your seller account has been reinstated`

```
Hi {{seller.full_name}},

Your seller account for {{seller.business_name}} has been reinstated
by AliceUT following a review.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ACCOUNT STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Reinstated at: {{reinstated_at}}
  Reason:        {{reinstatement_reason}}
  Your listings have been restored to the catalog.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Go to your seller dashboard:
{{base_url}}/seller

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `seller.business_name` | Registered business name |
| `reinstated_at` | Timestamp of reinstatement |
| `reinstatement_reason` | Admin-provided reason for early reinstatement |
| `base_url` | Website base URL |

---

## ET-13b — Order Auto-Refunded — Seller Suspended, Seller Notice (fulfillment.refund_suspended_seller)

**Trigger:** Same event as ET-13 (US-A-05). Informational only — seller cannot access seller dashboard while suspended.  
**To:** seller  
**CC:** admin  
**Subject:** `Auto-refund issued for order {{order_id}} — account suspended`

```
Hi {{seller.full_name}},

An automatic refund has been issued to the buyer for an order that was
not shipped within the fulfillment window while your account was suspended.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REFUNDED ITEMS

  ┌─────────────────────────────────────────────────┐
  │ {{item.product_title}}                          │
  │ Qty: {{item.quantity}}                          │
  └─────────────────────────────────────────────────┘
  (repeat per item)

Refund total: {{fulfillment.grand_total_display}} {{offer_currency}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `order_id` | Order identifier |
| `item.product_title` / `item.quantity` | Product name and quantity |
| `fulfillment.grand_total_display` | Total refund amount in offer currency |
| `offer_currency` | Currency of the seller's offer |

---

## ET-14 — KYC Application Received (kyc.received)

**Trigger:** Seller submits or resubmits onboarding application (US-S-01) — fires for both initial submissions and resubmissions
**To:** seller
**Subject:** `Your seller application has been received — AliceUT`

```
Hi {{seller.full_name}},

We've received your seller application for {{seller.business_name}}.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
APPLICATION DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Business name: {{seller.business_name}}
  Submitted at:  {{submitted_at}}
  Status:        Under review

  {{#if is_resubmission}}
  ──────────────────────────────
  Resubmission of application {{prior_application_id}}
  Previously rejected: {{prior_rejection_date}}
  {{/if}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHAT HAPPENS NEXT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Our team will review your documents. You will receive a separate
email when a decision has been made. Applications are reviewed in
submission order; SLA target is 3 business days.

You cannot list products until your application is approved.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `seller.business_name` | Registered business name |
| `submitted_at` | Timestamp of application submission |
| `is_resubmission` | Boolean — true when this is a resubmission of a previously rejected application |
| `prior_application_id` | Application reference number of the prior rejected application (omitted when `is_resubmission` is false) |
| `prior_rejection_date` | Date the prior application was rejected (omitted when `is_resubmission` is false) |

---

## ET-15 — Low Stock Alert (inventory.low_stock)

**Trigger:** Available quantity (on_hand − reserved) for a SKU drops at or below the configured threshold (US-S-08)
**To:** seller
**Subject:** `Low stock alert — {{product_title}} · {{sku_label}}`

```
Hi {{seller.full_name}},

Stock for one of your SKUs is running low.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SKU DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Product:   {{product_title}}
  Variant:   {{sku_label}}
  SKU:       {{sku_id}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CURRENT STOCK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  On hand:   {{on_hand}}
  Reserved:  {{reserved}}
  Available: {{available}}
  Threshold: {{low_stock_threshold}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Update inventory:
{{base_url}}/seller/inventory

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `product_title` | Product name |
| `sku_label` | Human-readable variant label (e.g. `Blue / L`) |
| `sku_id` | Internal SKU identifier |
| `on_hand` | Total units physically in stock |
| `reserved` | Units held by PENDING orders not yet shipped |
| `available` | `on_hand − reserved` |
| `low_stock_threshold` | Configured alert threshold for this SKU |
| `base_url` | Website base URL |

---

## ET-17 — New Order Received (fulfillment.created)

**Trigger:** New fulfillment created for this seller when an order is finalized (US-S-05)  
**To:** seller  
**Subject:** `New order received — Order {{order_id}}`

```
Hi {{seller.full_name}},

You have a new order to fulfill.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ORDER ID: {{order_id}}
Placed:   {{placed_at}}
Ship by:  {{ship_by}}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ITEMS TO SHIP

  ┌─────────────────────────────────────────────────┐
  │ {{item.product_title}}                          │
  │ Variant: {{item.variant_label}}                 │
  │ Qty: {{item.quantity}}                          │
  └─────────────────────────────────────────────────┘
  (repeat per item)

Order total: {{fulfillment.grand_total_display}} {{offer_currency}}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

View shipping address and manage this order:
{{base_url}}/seller/orders/{{order_id}}

AliceUT
```

**Variables**

| Variable | Description |
|---|---|
| `seller.full_name` | Seller's full name |
| `order_id` | Order identifier |
| `placed_at` | When the order was placed |
| `ship_by` | Expected ship-by date (mock, based on ETA window) |
| `item.product_title` | Product name |
| `item.variant_label` | Human-readable variant (e.g. `Blue / L`); omitted if product has no variants |
| `item.quantity` | Quantity ordered |
| `fulfillment.grand_total_display` | Order total in offer currency |
| `offer_currency` | Seller's pricing currency for this fulfillment |
| `base_url` | Website base URL |

**PII handling:** Shipping address is NOT included in this email. Seller retrieves it by clicking the authenticated order detail link (`{{base_url}}/seller/orders/{{order_id}}`). Access to the address page is logged for audit (NFR-09, US-S-05b).
