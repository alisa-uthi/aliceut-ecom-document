# EPIC: NOTIFICATIONS — Notifications Module

**Sprint:** 4–5  
**Total Tasks:** 8  

In-app and email notifications driven entirely by Kafka consumers. No sync writes from API handlers. MongoDB stores in-app notifications. Nodemailer sends emails from an SMTP gateway. All notification state is eventually consistent.

---

## NOTIFICATIONS-001 — Notifications MongoDB Schema

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** INFRA-005
- **Spec References:** `phase-1/technical-design/api-design/notifications.md`, `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes**

- File: `libs/notifications/src/infrastructure/mongoose/notification.schema.ts`
- `InAppNotification` collection (`in_app_notifications` in `aliceut_logs` MongoDB):
  ```ts
  const InAppNotificationSchema = new Schema({
    userId:     { type: String, required: true, index: true },
    type:       { type: String, required: true },        // e.g. 'ORDER_SHIPPED', 'KYC_APPROVED'
    title:      { type: String, required: true },
    message:    { type: String, required: true },
    isRead:     { type: Boolean, default: false, index: true },
    link:       String,                                  // frontend route (e.g. '/orders/uuid')
    metadata:   Schema.Types.Mixed,                      // event-specific data
    createdAt:  { type: Date, default: Date.now, index: true },
    readAt:     Date,
  });
  InAppNotificationSchema.index({ userId: 1, isRead: 1, createdAt: -1 });
  ```
- TTL index: 90 days auto-expiry for old notifications
- `ActivityEvent` collection (for admin audit — see PLATFORM-004): separate collection, not managed here

**Done Criteria**

- Schema created; TTL index applied
- Insert document → appears in `in_app_notifications` collection

---

## NOTIFICATIONS-002 — SMTP Email Service (Nodemailer)

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/api-design/notifications.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes**

- File: `libs/notifications/src/infrastructure/email/email.service.ts`
- Package: `nodemailer`
- Config from env: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`
- Dev default: `SMTP_HOST=localhost:1025` (MailHog/Mailpit for local testing)
- `EmailService.send(to, subject, htmlBody): Promise<void>` — fire-and-forget; errors logged, not thrown
- HTML templates: inline styles (email clients don't support external CSS)
- `EmailService.renderTemplate(templateName, vars): string` — renders HTML from `libs/notifications/src/templates/*.html` via `handlebars` or simple string interpolation
- Transport pool: `createTransport({ pool: true, maxConnections: 5 })`

**Done Criteria**

- Send email to MailHog/Mailpit → appears in web UI
- Transport failure: logged, no uncaught exception
- HTML email renders inline styles correctly

---

## NOTIFICATIONS-003 — In-App Notification API

- **US Ref:** US-B-11
- **Estimate:** M
- **Dependencies:** NOTIFICATIONS-001
- **Spec References:** `phase-1/technical-design/api-design/notifications.md`, `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes**

- `GET /notifications` — `@JwtAuthGuard`; returns paginated in-app notifications for authenticated user
  - Query MongoDB by `userId = req.user.sub`, sorted by `createdAt DESC`, limit 20
  - Includes `unreadCount` in response meta
- `PATCH /notifications/:id/read` — mark single notification as read (`isRead = true`, `readAt = now()`)
- `PATCH /notifications/read-all` — bulk mark all unread as read for user
- `GET /notifications/unread-count` — lightweight endpoint for bell badge polling (returns `{ count: N }`)
- Ownership check on PATCH: `notification.userId = authenticated user` → 404 if not

**Done Criteria**

- GET /notifications returns only authenticated user's notifications
- Mark read: `isRead = true` set in MongoDB
- Unread count matches actual unread documents

---

## NOTIFICATIONS-004 — Order / Fulfillment Notification Consumers

- **US Ref:** US-B-11
- **Estimate:** L
- **Dependencies:** PLATFORM-003, NOTIFICATIONS-001, NOTIFICATIONS-002
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/notifications.md`, `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes**

- Consumer group per topic; all extend `BaseKafkaConsumer`
- `fulfillment.placed` consumer (`notifications.fulfillment-placed`):
  - In-app notification to seller: "New order received for [product]"
  - Email to seller: Order notification template
- `fulfillment.shipped` consumer:
  - In-app + email to buyer: "Your order has been shipped! Tracking: [carrier] [number]"
- `fulfillment.delivered` consumer:
  - In-app + email to buyer: "Your order has been delivered"
- `fulfillment.cancelled` consumer:
  - In-app + email to buyer: "Your order has been cancelled. [Reason]"
- `fulfillment.refund_suspended_seller` consumer:
  - In-app + email to buyer: "Your order was cancelled due to seller suspension. Refund issued."
- Each consumer: insert MongoDB `InAppNotification` + call `EmailService.send()`

**Done Criteria**

- Ship fulfillment → buyer in-app notification created + email sent (MailHog shows it)
- All consumers idempotent (duplicate event → no duplicate notification — check by `event_id`)

---

## NOTIFICATIONS-005 — Auth Event Notification Consumers

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-003, NOTIFICATIONS-002
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/notifications.md`

**Implementation Notes**

- `auth.email_verification_requested` consumer:
  - Email to user: "Verify your email" with verification link
  - Template: verification link = `${FRONTEND_URL}/auth/verify-email?token={token}` (token from event payload)
- `auth.password_reset_requested` consumer:
  - Email: "Reset your password" with reset link = `${FRONTEND_URL}/auth/reset-password?token={token}`
- `auth.password_changed` consumer:
  - Email: "Your password was changed" security notification (no link; advise contact support if not initiated by user)
- No in-app notification for auth events (user may not be logged in)

**Done Criteria**

- Register → verification email delivered to MailHog
- Password reset request → reset email delivered
- Password changed → security notification email delivered

---

## NOTIFICATIONS-006 — Seller KYC & Admin Notification Consumers

- **US Ref:** US-S-02, US-A-01
- **Estimate:** M
- **Dependencies:** PLATFORM-003, NOTIFICATIONS-001, NOTIFICATIONS-002
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/notifications.md`

**Implementation Notes**

- `seller.kyc.submitted` consumer (admin notification):
  - In-app notification to ALL admins: "New KYC application submitted by [seller name]"
  - Email to admin: KYC review needed notification
  - Query `auth.user WHERE role = 'ADMIN'` for recipient list
- `seller.kyc.decided` consumer (after ADMIN-002 approves/rejects):
  - In-app + email to seller: "Your KYC application was [approved/rejected]. [Review notes if rejected]"
- `seller.suspended` consumer:
  - In-app + email to seller: "Your account has been suspended. Reason: [reason]. Expires: [date or indefinite]"
- `seller.reinstated` consumer:
  - In-app + email to seller: "Your account has been reinstated. You can resume selling."
- `inventory.low_stock` consumer:
  - In-app notification to seller: "Low stock alert: [product] has only [N] units remaining"

**Done Criteria**

- KYC submitted → admin receives notification
- KYC approved/rejected → seller notified via in-app + email
- Low stock event → seller in-app notification

---

## NOTIFICATIONS-007 — Email Templates (all 21 event types)

- **US Ref:** —
- **Estimate:** L
- **Dependencies:** NOTIFICATIONS-002
- **Spec References:** `phase-1/technical-design/api-design/notifications.md`

**Implementation Notes**

- File: `libs/notifications/src/templates/`
- 21 email templates (Handlebars HTML files):
  1. `email-verification.html` — verify email
  2. `password-reset.html` — reset password link
  3. `password-changed.html` — security alert
  4. `order-placed-seller.html` — seller: new order
  5. `order-shipped-buyer.html` — buyer: order shipped
  6. `order-delivered-buyer.html` — buyer: order delivered
  7. `order-cancelled-buyer.html` — buyer: order cancelled
  8. `order-refund-suspended-buyer.html` — buyer: refund due to seller suspension
  9. `kyc-submitted-admin.html` — admin: new KYC to review
  10. `kyc-approved-seller.html` — seller: KYC approved
  11. `kyc-rejected-seller.html` — seller: KYC rejected + notes
  12. `seller-suspended.html` — seller: suspension notice
  13. `seller-reinstated.html` — seller: reinstatement notice
  14. `low-stock-seller.html` — seller: low stock warning
  15. `listing-flagged-seller.html` — seller: listing flagged for review
  16. `listing-removed-seller.html` — seller: listing removed by admin
  17. `moderation-cleared-seller.html` — seller: false positive cleared
  18. `account-closed.html` — confirmation of account closure
  19. `admin-new-flagged-listing.html` — admin: new listing to moderate
  20. `admin-seller-suspension-expired.html` — admin: seller suspension expired (auto-reinstated)
  21. `admin-moderation-case-assigned.html` — admin: case assigned (V1 all cases auto-assigned to pool)
- All templates: AliceUT branding (logo placeholder), inline CSS, responsive layout
- `handlebars.compile(template)(variables)` for rendering

**Done Criteria**

- All 21 templates render without handlebars errors
- HTML validates (no broken tags)
- At least 3 templates visually reviewed in MailHog

---

## NOTIFICATIONS-008 — Notification Preferences

- **US Ref:** US-B-11
- **Estimate:** M
- **Dependencies:** NOTIFICATIONS-001
- **Spec References:** `phase-1/technical-design/api-design/notifications.md`, `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes**

- MongoDB collection `notification_preferences`:
  ```ts
  const PreferenceSchema = new Schema({
    userId: { type: String, required: true, unique: true },
    emailEnabled: { type: Boolean, default: true },
    inAppEnabled: { type: Boolean, default: true },
    orderUpdates: { type: Boolean, default: true },
    marketingEmails: { type: Boolean, default: false },
    lowStockAlerts: { type: Boolean, default: true },
  });
  ```
- `GET /notifications/preferences` — `@JwtAuthGuard`; returns user's preferences (default if not set)
- `PATCH /notifications/preferences { emailEnabled?, inAppEnabled?, orderUpdates?, marketingEmails?, lowStockAlerts? }` — partial update
- All consumers check preferences before sending: `if (!prefs.emailEnabled || !prefs.orderUpdates) skip`
- V1: preferences checked best-effort (fire-and-forget); consumer queries preferences inline

**Done Criteria**

- PATCH `emailEnabled: false` → subsequent order emails skipped
- Default preferences returned for new user (no DB row needed before first PATCH)
