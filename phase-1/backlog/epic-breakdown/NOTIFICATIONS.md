# EPIC: NOTIFICATIONS — Email & In-App Notifications

**Sprint:** 8  
**Total Tasks:** 8  
**Status:** Planned  

All email and in-app notification delivery. Driven exclusively by Kafka consumers — never triggered inline from API write paths. Uses SMTP for email (Nodemailer) and MongoDB for in-app notification persistence. 21 email templates (ET-01 through ET-21).

---

## NOTIFICATIONS-001 — Notifications Schema (MongoDB)

| Field | Value |
|-------|-------|
| **US Ref** | US-P-04 |
| **Estimate** | S (½d) |
| **Dependencies** | INFRA-005 |

**Implementation Notes**

- Mongoose schemas in `libs/notifications/src/infrastructure/`
- `InAppNotification` schema (`in_app_notification` collection):
  ```ts
  const InAppNotificationSchema = new Schema({
    userId:       { type: String, required: true, index: true },
    type:         { type: String, required: true },  // e.g. 'ORDER_PLACED', 'KYC_APPROVED'
    title:        String,
    body:         String,
    metadata:     Schema.Types.Mixed,   // { orderId, fulfillmentId, etc. }
    isRead:       { type: Boolean, default: false },
    readAt:       Date,
    createdAt:    { type: Date, default: Date.now, index: true },
  }, { timestamps: false });
  
  InAppNotificationSchema.index({ userId: 1, createdAt: -1 });
  InAppNotificationSchema.index({ userId: 1, isRead: 1 });
  ```
- `ActivityEvent` schema (`activity_events` collection) — audit log for notification delivery:
  ```ts
  const ActivityEventSchema = new Schema({
    channel:      String,             // 'EMAIL' | 'IN_APP'
    recipient:    String,             // email address or userId
    eventType:    String,
    templateId:   String,             // e.g. 'ET-01'
    status:       String,             // 'SENT' | 'FAILED' | 'SKIPPED'
    failReason:   String,
    deliveredAt:  Date,
    createdAt:    { type: Date, default: Date.now },
  });
  ```

**Done Criteria**

- Mongoose schemas registered in `NotificationsModule`
- `in_app_notification` documents queryable by `userId` + `isRead`
- TTL index on `activity_events`: 30 days (`expireAfterSeconds: 2592000`)

---

## NOTIFICATIONS-002 — SMTP Email Service

| Field | Value |
|-------|-------|
| **US Ref** | — |
| **Estimate** | M (1d) |
| **Dependencies** | NOTIFICATIONS-001 |

**Implementation Notes**

- Package: `nodemailer`
- `EmailService` in `libs/notifications/src/infrastructure/email.service.ts`
- Config from env: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`
- Dev fallback: if `SMTP_HOST` absent, log email to console (dev-only mock transport)
  ```ts
  const transport = process.env.SMTP_HOST
    ? nodemailer.createTransport({ host, port, auth: { user, pass } })
    : { sendMail: async (opts) => { logger.log('EMAIL (mock):', JSON.stringify(opts)); return {}; } };
  ```
- `EmailService.send({ to, subject, htmlBody, textBody })`: sends email; on failure logs error + records `ActivityEvent { status: 'FAILED' }`; never throws to caller (fire-and-forget)
- Email templates: inline HTML strings in V1 (no templating engine; Handlebars in Phase 2)
- "From" address: `noreply@aliceut.local` (configurable via `EMAIL_FROM` env var)

**Done Criteria**

- With SMTP configured: email sent; `ActivityEvent` with `status: 'SENT'` inserted
- With no SMTP config: email logged to console; no error thrown
- SMTP failure (wrong credentials): error logged; `ActivityEvent { status: 'FAILED' }` inserted; caller not affected
- `to` address validated before send

---

## NOTIFICATIONS-003 — In-App Notification API

| Field | Value |
|-------|-------|
| **US Ref** | US-B-12, US-S-11 |
| **Estimate** | M (1d) |
| **Dependencies** | NOTIFICATIONS-001, AUTH-002 |

**Implementation Notes**

- `GET /notifications` (protected)
  - Query: `?unreadOnly=boolean&limit=20&cursor=`
  - Returns paginated in-app notifications for current user, newest first
- `POST /notifications/:id/read` (protected)
  - Sets `isRead = true`, `readAt = now()` for notification belonging to current user
- `POST /notifications/read-all` (protected)
  - Bulk-marks all unread notifications for current user as read
- `GET /notifications/unread-count` (protected)
  - Returns `{ count: number }` — used by frontend badge
- Ownership check: all queries filter by `userId = currentUser.id`

**Done Criteria**

- `GET /notifications` returns user's notifications, newest first
- `POST /notifications/:id/read` marks one as read
- `POST /notifications/read-all` marks all unread as read
- `GET /notifications/unread-count` returns correct count
- Accessing another user's notification: 404

---

## NOTIFICATIONS-004 — Order & Fulfillment Notification Consumers

| Field | Value |
|-------|-------|
| **US Ref** | US-B-12, US-P-04 |
| **Estimate** | L (2d) |
| **Dependencies** | NOTIFICATIONS-002, PLATFORM-003 |

**Implementation Notes**

- Consumer group: `notifications.order-events`
- Topics consumed: `order.finalized`, `fulfillment.placed`, `fulfillment.shipped`, `fulfillment.delivered`, `fulfillment.cancelled`, `fulfillment.refunded`, `fulfillment.refund_suspended_seller`, `order.completed`
- Per event → email template + in-app notification:

| Event | Email Template | In-App Type |
|-------|---------------|-------------|
| `order.finalized` | ET-01 (buyer order confirmation) | `ORDER_CONFIRMED` |
| `fulfillment.placed` | ET-02 (seller new order) | `NEW_ORDER` (seller) |
| `fulfillment.shipped` | ET-03 (buyer shipping notification with tracking) | `ORDER_SHIPPED` |
| `fulfillment.delivered` | ET-05 (buyer delivery confirmation) | `ORDER_DELIVERED` |
| `fulfillment.cancelled` | ET-16 (buyer + seller cancellation) | `ORDER_CANCELLED` |
| `fulfillment.refunded` | ET-13b (buyer refund confirmation) | `ORDER_REFUNDED` |
| `fulfillment.refund_suspended_seller` | ET-13 (buyer refund due to seller suspension) | `REFUND_SUSPENDED_SELLER` |
| `order.completed` | — (already sent per-fulfillment) | — |

- Each consumer handler:
  1. Load event payload (all needed data in event — no DB reads for core fields)
  2. Call `EmailService.send(...)` with inline HTML template
  3. Insert `InAppNotification` document
  4. Insert `ActivityEvent` log
- Extends `BaseKafkaConsumer` (idempotency + DLQ)

**Done Criteria**

- `order.finalized` → buyer receives email notification (mock logged to console in dev)
- `fulfillment.shipped` → in-app notification created for buyer
- Duplicate event (same `event_id`): no duplicate notification (idempotency via `ProcessedEvent`)
- `ActivityEvent` inserted for each notification attempt

---

## NOTIFICATIONS-005 — Auth Event Notification Consumers

| Field | Value |
|-------|-------|
| **US Ref** | US-B-00 |
| **Estimate** | M (1d) |
| **Dependencies** | NOTIFICATIONS-002, PLATFORM-003 |

**Implementation Notes**

- Consumer group: `notifications.auth-events`
- Topics: `auth.email_verification_requested`, `auth.password_reset_requested`, `auth.password_changed`

| Event | Email Template | Notes |
|-------|---------------|-------|
| `auth.email_verification_requested` | ET-18 (verification email with link) | URL from payload |
| `auth.password_reset_requested` | ET-19 (password reset email with link) | URL from payload |
| `auth.password_changed` | ET-20 (password changed security notice) | Security alert |

- `auth.email_verification_requested` payload includes: `{ userId, email, verificationUrl }` — URL has the raw token (pre-constructed by AUTH module)
- Email link format: `{FRONTEND_URL}/verify-email?token=<rawToken>`
- `auth.password_changed`: email sent to current email address as security notification
- No in-app notification for auth events (user may not be logged in during these flows)

**Done Criteria**

- `auth.email_verification_requested` event → verification email with correct link
- `auth.password_reset_requested` event → reset email with correct link
- `auth.password_changed` event → security notice email
- No in-app notification created for auth events

---

## NOTIFICATIONS-006 — Seller KYC & Admin Notification Consumers

| Field | Value |
|-------|-------|
| **US Ref** | US-S-00, US-A-02 |
| **Estimate** | M (1d) |
| **Dependencies** | NOTIFICATIONS-002, PLATFORM-003 |

**Implementation Notes**

- Consumer group: `notifications.seller-events`
- Topics: `seller.kyc.submitted`, `seller.kyc.decided`, `seller.suspended`, `seller.reinstated`, `seller.suspension_expired`, `moderation.listing.removed`, `inventory.low_stock`

| Event | Recipient | Template | In-App Type |
|-------|----------|---------|-------------|
| `seller.kyc.submitted` | Admin | ET-14 (new KYC submission alert) | `KYC_PENDING` (admin) |
| `seller.kyc.decided` (APPROVED) | Seller | ET-15a (approved) | `KYC_APPROVED` |
| `seller.kyc.decided` (REJECTED) | Seller | ET-15b (rejected with reason) | `KYC_REJECTED` |
| `seller.suspended` | Seller | ET-12 (suspension notice) | `SELLER_SUSPENDED` |
| `seller.reinstated` | Seller | ET-13 (reinstatement notice) | `SELLER_REINSTATED` |
| `seller.suspension_expired` | Seller | ET-11 (auto-reinstatement) | `SUSPENSION_EXPIRED` |
| `moderation.listing.removed` | Seller (digest) | ET-09 (daily digest via scheduler) | `LISTING_REMOVED` |
| `inventory.low_stock` | Seller | ET-06 (low stock alert) | `LOW_STOCK` |

- Admin email address: from `ADMIN_EMAIL` env var (can be a shared inbox)
- ET-09 (listing removal digest) emitted by scheduler (SELLER-013), not here directly — this consumer only creates in-app notification, not email
- `inventory.low_stock` payload: `{ sellerId, offerId, productTitle, currentStock, threshold }`

**Done Criteria**

- `seller.kyc.decided (APPROVED)` → seller receives approval email + in-app notification
- `seller.kyc.decided (REJECTED)` → rejection email with reason + in-app notification
- `seller.suspended` → suspension email + in-app
- `inventory.low_stock` → low stock email to seller + in-app
- Idempotent: duplicate events don't send duplicate notifications

---

## NOTIFICATIONS-007 — Email Template Content (All 21 Templates)

| Field | Value |
|-------|-------|
| **US Ref** | US-P-04 |
| **Estimate** | M (1d) |
| **Dependencies** | NOTIFICATIONS-002 |

**Implementation Notes**

- File: `libs/notifications/src/infrastructure/email/templates/`
- One file per template category; inline HTML strings
- Required templates (ET-01 through ET-21) mapped to events:

| ID | Trigger | Subject Line |
|----|---------|-------------|
| ET-01 | `order.finalized` | "Order Confirmed – ORD-{id}" |
| ET-02 | `fulfillment.placed` (seller) | "New Order – FUL-{id}" |
| ET-03 | `fulfillment.shipped` | "Your Order Has Shipped" |
| ET-04 | `fulfillment.delivered` | "Your Order Has Been Delivered" |
| ET-05 | `order.completed` | "Thank You for Your Purchase" |
| ET-06 | `inventory.low_stock` | "Low Stock Alert: {productTitle}" |
| ET-07 | Admin digest | "Daily Listing Removal Report" |
| ET-08 | `listing.flagged` (seller) | "Your Listing Has Been Flagged" |
| ET-09 | `moderation.listing.removed` (digest) | "Listing Removal Summary" |
| ET-10 | `seller.suspended` | "Account Suspended" |
| ET-11 | `seller.suspension_expired` | "Account Reinstated (Auto)" |
| ET-12 | `seller.suspended` | "Seller Account Suspended" |
| ET-13 | `fulfillment.refund_suspended_seller` (buyer) | "Refund Processed" |
| ET-13b | `fulfillment.refunded` | "Your Refund Has Been Processed" |
| ET-14 | `seller.kyc.submitted` (admin) | "New KYC Submission – {businessName}" |
| ET-15 | `seller.kyc.decided (APPROVED)` | "Your Seller Account is Approved!" |
| ET-16 | `fulfillment.cancelled` | "Order Cancellation Confirmed" |
| ET-17 | `seller.reinstated` | "Seller Account Reinstated" |
| ET-18 | `auth.email_verification_requested` | "Verify Your Email – AliceUT" |
| ET-19 | `auth.password_reset_requested` | "Reset Your Password – AliceUT" |
| ET-20 | `auth.password_changed` | "Security Alert: Password Changed" |
| ET-21 | `seller.kyc.decided` (seller) | "KYC Review Complete" |

- All templates: minimal but correct HTML; responsive (basic 600px centered container)
- All include unsubscribe footer: "Manage email preferences at {FRONTEND_URL}/account/notifications"
- V1: no Handlebars/Mustache — simple string interpolation (`template.replace('{{name}}', value)`)

**Done Criteria**

- All 21 templates produce valid HTML emails with required fields
- Subject lines contain correct dynamic values
- No broken template placeholder (missing variable = empty string, not `{{variable}}`)
- Templates rendered in browser without broken layout

---

## NOTIFICATIONS-008 — Notification Preferences

| Field | Value |
|-------|-------|
| **US Ref** | US-B-12 |
| **Estimate** | M (1d) |
| **Dependencies** | NOTIFICATIONS-003, AUTH-002 |

**Implementation Notes**

- `GET /notifications/preferences` (protected)
- `PATCH /notifications/preferences` (protected)
- Preferences stored in MongoDB `notification_preferences` collection (keyed by `userId`):
  ```ts
  {
    userId: string,
    email: {
      orderUpdates: boolean,    // default true
      promotions: boolean,      // default false
      security: boolean,        // ALWAYS true (non-configurable)
      lowStock: boolean,        // seller only
    },
    inApp: {
      all: boolean,             // default true
    }
  }
  ```
- Security emails (`auth.*` events) always sent regardless of preference
- Before sending email in consumers: check user's preferences (minor perf cost; acceptable for V1)
- Default: all order/fulfillment emails ON; promotions OFF

**Done Criteria**

- `PATCH /notifications/preferences { email: { orderUpdates: false } }`: order update emails suppressed
- Security emails (`auth.password_changed`) sent even when all preferences off
- New user: default preferences created on first `GET` (if no row exists)
- Preference check adds < 10ms to notification handler (MongoDB lookup by userId)
