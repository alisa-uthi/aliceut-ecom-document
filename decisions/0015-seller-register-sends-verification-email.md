# ADR-0015: `POST /seller/register` sends the verification email

**Status:** Accepted
**Date:** 2026-10-16
**Affects:** `phase-1/technical-design/api-design/seller.md` (§ Register as seller), `phase-1/technical-design/api-design/auth.md` (§ Resend verification email), `phase-1/technical-design/kafka-events.md` (§ 2.22), `phase-1/technical-design/consumer-field-matrix.md` (ET-18), `phase-1/requirements/user-stories/email-templates.md` (ET-18), `phase-1/ui-design/seller-portal.md`, `phase-1/ui-design/navigation-routing.md` (§ 3)
**Implemented by:** aliceut-ecom-backend (this pass), aliceut-ecom-frontend (this pass)

## Context

`POST /seller/register` creates a new account with `email_verified = false`
(ADR-0007), and its design says **No event**: no outbox row is written. So a
seller account is created unverified and nothing ever sends the email that
would verify it. `POST /auth/resend-verification` works for any JWT, but it
sends ET-18, whose link opens the buyer portal's `/verify-email` and whose
text talks about placing orders.

`seller.md` is right that a seller does not need a verified email to submit
KYC: the documents are the identity check. But the `email_verified` claim is
still carried in the seller's token and shown as `emailVerified: false` in the
register response, and a mistyped address means ET-14, ET-21's outcome mails
and every later seller email go nowhere. `spec-compliance.md` entry 1 lists
the gap.

## Decision

**Registration sends the email.** When `POST /seller/register` creates a new
account (the "email unknown" case), the same transaction also inserts
`identity.email_verification_token` (24 h TTL, as in buyer register) and a
`platform.outbox_event` row on `auth.email_verification_requested`. The linking
path does not, because the account already exists and has its own
verification state. The "No event" paragraph changes to say this.
`seller.registered` and any other new topic are still not introduced.

**The event carries the portal.** `auth.email_verification_requested` (§ 2.22)
gains a `portal` field, `"BUYER" | "SELLER"`, with Avro default `"BUYER"`, so
the change is BACKWARD compatible and messages already on the topic decode as
buyer. The rule follows `auth.password_reset_requested`, which already carries
`portal` for the same reason: the notification consumer picks the link and the
text from the payload and may not read `identity.user`.

| Producer | `portal` |
|---|---|
| `POST /auth/register` | `BUYER` |
| `POST /seller/register` (new account) | `SELLER` |
| `POST /auth/resend-verification` | `BUYER` if the account holds the `BUYER` role, otherwise `SELLER` |

**ET-18 has a seller variant.** For `portal = SELLER` the link is
`${SELLER_APP_URL}/seller/verify-email?token=<raw>`, following the seller
reset-password link in `auth.md § Forgot password`. The text drops the buyer
lines about the catalog and orders:

```
Hi {{seller.full_name}},

Thanks for registering as a seller on AliceUT. Please verify your
email address so we can reach you about your application and orders.

  [VERIFY EMAIL ADDRESS]
  {{verification_link}}

This link expires in {{ttl_hours}} hours and can only be used once.

Verifying is not required to submit your KYC application.

If you didn't register, you can ignore this email.
```

**`POST /auth/verify-email` does not change.** It is public and
portal-agnostic: the token alone identifies the account.

**The seller portal gets a verification callback** at `/seller/verify-email`,
which calls `POST /auth/verify-email`. On success it goes to
`/seller/dashboard` when a session exists, otherwise to
`/seller/login?verified=true`. While `emailVerified` is false the shell shows
an info banner with a "Resend email" action (`POST /auth/resend-verification`).
Nothing on the seller portal is gated on verification.

## Consequences

Every new seller gets a verification email, and a mistyped address shows up
before KYC mail is lost. The seller's `email_verified` claim can become true.

`auth.email_verification_requested` gets a new schema version in the
registry. Consumers built before the field exist read `portal` as `"BUYER"`
through the default.

A seller who links to an existing buyer account keeps that account's
verification state. If it was unverified, the seller can resend from the
seller shell, and since the account holds `BUYER`, the resend goes out as the
buyer variant. Either link verifies the same account.

## Alternatives considered

**Mark seller accounts verified at registration.** The KYC documents prove a
business identity, not that the email address is reachable, so this would
record something nobody checked.

**A separate `seller.email_verification_requested` topic.** Duplicates the
producer, the consumer group and the audit row for one field's worth of
difference.

**Leave it open.** The seller would still be created unverified with no way to
fix it from the seller portal.
