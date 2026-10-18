# ADR-0023: Business logos are served from a public path, not presigned

**Status:** Accepted
**Date:** 2026-10-18
**Affects:** `phase-1/technical-design/kafka-events.md` (§ 2.x `order.finalized`, `buyer_business_logo_url`), `phase-1/technical-design/consumer-field-matrix.md` (ET-01), `phase-1/technical-design/docker-compose-topology.md` (`minio-init`, env), `phase-1/technical-design/api-design/profile.md`, `phase-1/technical-design/data-model-erd.md` (`identity.user.business_logo_storage_key`), `guidelines/development-flow.md` (§ 9)
**Implemented by:** aliceut-ecom-infra (minio-init, `MINIO_PUBLIC_BASE_URL`), aliceut-ecom-backend

## Context

`order.finalized` carried `buyer_business_logo_url` as a presigned MinIO URL
valid for one hour. ET-01 is read long after it is sent, so the image died in
the inbox (`spec-compliance.md`, "Event logo URL lifetime"). A presigned URL
also embeds the in-network host (`minio:9000`) the API signs against, which a
recipient's mail client cannot resolve.

## Decision

The user decided that business logos are served from a **public** path.

1. **Bucket policy.** The `user-assets` bucket stays private, except the
   `logos/` prefix, which gets an anonymous `download` policy
   (`mc anonymous set download local/user-assets/logos`). Logo keys are
   `logos/{userId}/{uuid}.{ext}` and nothing else is written under `logos/`.
   KYC documents live in `kyc-documents`, a different bucket that is never
   made public; nothing else lives in `user-assets`.
2. **Stable public base URL.** A new env var `MINIO_PUBLIC_BASE_URL`
   (default `http://localhost:9000`) is the externally reachable MinIO base.
   It is never `http://minio:9000`. A logo URL is
   `{MINIO_PUBLIC_BASE_URL}/user-assets/{business_logo_storage_key}`.
3. **Producers send the stable URL.** `order.finalized.buyer_business_logo_url`
   and the profile responses (`businessLogoUrl`, upload response) carry that
   URL. The Avro field is unchanged (same name, same `["null","string"]`),
   so no schema registration is needed; only its doc string changes.
   Consumers render the URL as-is.
4. **Presign code for logos is removed.** The key is still the stored value
   (Postgres never holds a URL); the URL is derived at read time.

**V1 local-dev behaviour.** `http://localhost:9000` is reachable only from the
developer's machine, so an email opened elsewhere will not load the image. V1
accepts this; it is the same MinIO that the rest of the stack uses. **V2** puts
a CDN (or a public object-store domain) in front of the bucket and sets
`MINIO_PUBLIC_BASE_URL` to its origin; no code changes.

## Consequences

**Logos never expire**, in emails or in the UI. Because each upload gets a new
uuid key, replacing a logo gives a new URL; old emails keep showing the old
logo while that object exists. Old objects are not deleted on replacement (no
cleanup job today, unchanged).

**Anyone with the URL can fetch a logo.** The key contains an unguessable
uuidv7 and the userId, but it is not a secret. Business logos are brand
material meant to be shown to buyers' recipients, which the user accepted.

**Existing events** already on the topic carry presigned URLs and will expire;
the field is a plain string, so consumers need no handling.

**Rule going forward:** anything written under `user-assets/logos/` is public.
A private user asset must use another prefix or bucket.

## Alternatives considered

**Longer presign TTL (up to 7 days).** Still dies eventually, and still
embeds the in-network host.

**Consumer presigns from a key in the payload.** Moves the problem to send
time but the email is still opened later. Rejected for the same reason.

**Public `user-assets` bucket.** Rejected: it would expose every future user
asset. Only the `logos/` prefix is opened.
