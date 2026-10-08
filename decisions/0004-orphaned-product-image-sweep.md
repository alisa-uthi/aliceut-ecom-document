# ADR-0004: Orphaned product images are swept by a scheduled job with a grace window

**Status:** Accepted
**Date:** 2026-10-09
**Affects:** `phase-1/technical-design/cleanup-jobs.md`
**Implemented by:** aliceut-ecom-backend#25, aliceut-ecom-infra#2

## Context

[ADR-0003](0003-product-image-upload-endpoint.md) made image upload a separate
call from product creation: a seller uploads to
`POST /seller/products/images`, gets a storage key, then passes the keys to
`POST /seller/products`. Every upload abandoned between those two calls — a
seller who closes the form, a create that `422`s on the blocklist, a browser
that dies — leaves an object in the `product-images` bucket that no
`catalog.product_image` row will ever reference and nothing will ever read.

`cleanup-jobs.md` covers no object storage at all. Its summary table lists ten
table jobs, and its companion table lists the stores that deliberately have no
job — MongoDB TTL indexes, `pricing.fx_rate`, the blocklist, order records,
reference data. MinIO appears in neither, and that document states that every
time-bounded store appears in one of the two. So the orphan was unowned rather
than deliberately tolerated.

This also matters because `mc anonymous set download local/product-images`
makes the bucket publicly readable: an orphan is an unreferenced object that is
nevertheless fetchable by anyone holding its key, so leaving it is not purely a
storage-cost question.

## Decision

Add `cleanup-orphaned-product-images` to the scheduled set: a `workers` job
under the same `pg_advisory_lock` guard and the same env-driven schedule as
every other job (`CLEANUP_PRODUCT_IMAGES_CRON`, default `40 3 * * *` UTC,
continuing the existing 3 a.m. ladder).

Two things differ from the table jobs, because the store is object storage
rather than a table, and both are deliberate:

1. **A grace window gates every candidate.** An object younger than
   `PRODUCT_IMAGE_ORPHAN_GRACE_HOURS` (default 24) is never considered. This is
   the job's safety property, not an optimisation: "not referenced yet" is the
   *normal* state of a fresh upload while the seller is still filling in the
   form, so without the window the job would delete images out from under an
   in-progress listing.
2. **The reference check runs per batch, immediately before each delete**,
   rather than once per run. A listing created while the job is walking the
   bucket then protects its own images.

The predicate is "aged, and not in `catalog.product_image.storage_key`",
evaluated against the current clock, so an interrupted run resumes on the next
tick with no persisted cursor — the same property the table jobs rely on.

## Consequences

The job reads the whole bucket listing into memory each run. A Phase 1 bucket
holds at most a few thousand objects, so this is cheaper than keeping a MinIO
stream open across per-batch database round trips; at a scale where it is not,
the listing becomes a paged walk and this ADR should be revisited.

A deletion is irreversible and the job is unattended, which is why the safety
properties above are tested rather than merely documented: the unit tests
assert that an object inside the grace window is never even checked, that a
referenced key is never deleted, that a second replica holding the lock does
nothing, and that a mid-run failure still releases the lock.

`workers` now needs MinIO credentials, which it did not before — it was a
Postgres, Kafka and Elasticsearch client only. They are optional in its env
validation so a deployment that runs no object-storage job still boots.

The window has a real cost: for up to 24 hours an abandoned upload stays
publicly fetchable by key. Shortening it trades that against the risk of
deleting an in-progress listing's images, and a seller form left open for a day
is not unusual.

## Alternatives considered

**Delete on the failure paths instead.** Have create-product clean up on a
`422`, and the form clean up on cancel. Rejected as the only mechanism: it
cannot cover a closed tab, a crashed browser or a network failure, which are
the common cases. Worth adding later as an optimisation on top of the sweep,
never as a replacement.

**Reference-count at upload time** — write a row for every uploaded key and
delete the row when it is consumed. Rejected: it adds a table and a second
source of truth for "is this image used", which the existing
`catalog.product_image` already answers.

**Tolerate the orphans.** Defensible on storage cost alone at Phase 1 volumes,
and rejected on the public-readability point plus the fact that the design
claims every time-bounded store is accounted for.
