# ADR-0003: Product images are uploaded through `POST /seller/products/images`

**Status:** Accepted
**Date:** 2026-10-09
**Affects:** `phase-1/technical-design/api-design/seller.md`
**Implemented by:** aliceut-ecom-backend#24, aliceut-ecom-frontend#17

## Context

`POST /seller/products` requires 1–10 image storage keys, and `seller.md` says
"images are uploaded before this call and referenced by storage key", with the
per-image error states (retryable failure, unsupported format, partial success,
"at least 1 image is required") belonging to that upload step.

No such endpoint existed anywhere in the design. The only documented upload
path is KYC documents, and the `product-images` bucket is created by compose
but written by nothing. So a seller had no way to obtain a storage key, which
made the one required field of create-product unsatisfiable — the reason seller
listings were imageless.

## Decision

Add `POST /seller/products/images` (`SELLER_ACTIVE`): one `multipart/form-data`
file per request, JPEG, PNG or WebP, at most 5 MB, returning
`{"data": {"storageKey": "..."}}`. The key is `products/<sellerProfileId>/<uuidv7>.<ext>`
in the `product-images` bucket.

One file per call, not a batch: the design's "partial success" error state is
then just a per-request failure the client retries for that file alone, with no
partial-batch response shape to specify. Format and size are validated here, as
the design requires, so create-product validates only the shape of the key.

The prefix carries the seller's profile id so one seller's uploads stay
together, and is **not** an authorization check — a key is accepted on
create-product because it is well-formed, and the bucket is
anonymous-readable by design (`mc anonymous set download local/product-images`).

## Consequences

An uploaded key that is never used in a create-product call leaves an orphaned
object. Nothing reaps those yet; it belongs with the other scheduled cleanup
jobs in `cleanup-jobs.md` and is recorded in `spec-compliance.md`.

create-product does not verify that each key exists in the bucket, so a caller
can pass a well-formed key for an object that was never uploaded and the
product will carry a broken image reference. Verifying would cost a storage
round trip per image on every create; the cheaper guard is that the key format
is unguessable, so the realistic case is a client bug rather than abuse.

This is the first use of MinIO in the backend — the `minio` package was a
declared dependency with no code behind it. It arrives as
`ObjectStorageService` in `libs/shared`, which the profile-logo upload
(`POST /profile/me/logo`, still unbuilt) should reuse rather than reimplement.

## Alternatives considered

**Presigned PUT URLs.** The seller would upload straight to MinIO and the API
would never hold the bytes. Better at scale, and worth revisiting, but it moves
format and size validation to the client or to a post-upload hook — and the
design is explicit that both are validated at upload time.

**Accept any string as a storage key and build no endpoint.** Rejected: it
leaves the design's upload step undefined and lets a seller write arbitrary
strings into a field the buyer-facing PDP and search thumbnails read.

**Verify each key against the bucket on create-product.** Rejected as the
default for the round-trip cost noted above; it stays the fallback if broken
references turn up in practice.
