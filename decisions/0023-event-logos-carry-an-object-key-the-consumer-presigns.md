# ADR-0023: Event logos carry an object key; the consumer presigns at send time

**Status:** Accepted
**Date:** 2026-10-18
**Affects:** `phase-1/technical-design/kafka-events.md` (`order.finalized`), `phase-1/technical-design/consumer-field-matrix.md` (ET-01), `phase-1/technical-design/docker-compose-topology.md` (env, `minio-init`), `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/data-model-erd.md` (`identity.user.business_logo_storage_key`), `guidelines/development-flow.md` (§ 9)
**Implemented by:** aliceut-ecom-backend (order.finalized, notification.order-summary), aliceut-ecom-infra (`MINIO_PUBLIC_ENDPOINT`, `LOGO_URL_TTL_SECONDS`)

## Context

`order.finalized` carried `buyer_business_logo_url`, a presigned MinIO URL
valid for one hour, minted by checkout. ET-01 is opened hours or days after it
is sent, so the logo image died in the inbox (`spec-compliance.md`, "Event
logo URL lifetime"). The URL was also signed for the in-network host
(`minio:9000`), which a recipient cannot reach.

An earlier version of this ADR (merged the same day) made a `logos/` prefix
publicly readable. The user reversed that: **business logos stay private.**

## Decision

1. **The event carries the key, not a URL.** `order.finalized` gains
   `buyer_business_logo_key` (`["null","string"]`, default `null`): the
   `identity.user.business_logo_storage_key` value, read inside the checkout
   transaction like `buyer_email`. B2B buyers with a logo only; otherwise null.
2. **`buyer_business_logo_url` is deprecated, not removed.** It stays in the
   schema, always `null`, and consumers ignore it. Removing a field would be a
   second schema break for nothing; the new field has a default, so the change
   is BACKWARD-compatible and is registered by the ordinary CI step
   ([ADR-0012](0012-avro-subjects-registered-by-ci-and-schema-init.md)).
3. **The consumer presigns at send time.** `notification.order-summary` builds
   a GET URL for `user-assets/{buyer_business_logo_key}` just before rendering
   ET-01. It reads no `identity` table (consumer-field-matrix § 1 is intact):
   the key comes from the payload, and the only I/O is local signing.
4. **TTL 7 days**, config `LOGO_URL_TTL_SECONDS`, default `604800`. That is
   the S3 SigV4 maximum, so it is also the ceiling; larger values are clamped.
5. **Public presign host.** The host is part of an S3 signature, so a URL
   signed for `minio:9000` cannot be fixed up afterwards. A second MinIO client
   is built for `MINIO_PUBLIC_ENDPOINT` (default `http://localhost:9000`), with
   a pinned region so signing needs no network call. Profile responses
   (`businessLogoUrl`, 1 hour) use the same host so a browser can load them.
6. **Failure is cosmetic.** A presign error drops the logo block from ET-01; the
   email is still sent.
7. **`minio-init` makes `user-assets/logos` private again** (`mc anonymous set
   none`), because the superseded design may already have been applied to a
   volume. No bucket is public except `product-images`.

**V1 local-dev limit.** `http://localhost:9000` resolves only on the
developer's machine, so an email opened on another device shows a broken image,
and the link stops working after 7 days. V2 sets `MINIO_PUBLIC_ENDPOINT` to a
real public domain (or presigns through a CDN/proxy); no code change.

## Consequences

**Logos stay private** and are never reachable without a valid signature.

**An emailed link is a bearer URL for seven days.** Anyone holding the email
can fetch that one logo until it expires. Accepted: it is brand material the
buyer chose to put in their order email.

**Logos in an email still expire** after seven days. This is longer than any
realistic receipt-reading window but is not "never"; the user accepted it.

**Events already on the topic** carry a presigned URL in the deprecated field
and no key, so their ET-01 renders without a logo. Accepted; the topic has no
production data.

**A mail retry re-presigns**, so a redelivered event gets a fresh 7 days.

## Alternatives considered

**Public `logos/` prefix (this ADR's first version).** Rejected by the user:
logos are not meant to be anonymously fetchable.

**Longer-lived URL from checkout.** Still capped at 7 days by SigV4, and would
sign at checkout rather than at send, shortening the usable window.

**Remove `buyer_business_logo_url`.** Rejected: a needless breaking change.
