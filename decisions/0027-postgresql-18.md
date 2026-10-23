# ADR-0027: PostgreSQL 18 is the Phase 1 database version

**Status:** Accepted
**Date:** 2026-10-23
**Affects:** `phase-1/technical-design/data-model-erd.md` (§ conventions, `btree_gist` note), `phase-1/technical-design/docker-compose-topology.md` (§ 3 service table, § 4 volumes, § 6 `postgres`, § 10, design decisions), `phase-1/technical-design/cleanup-jobs.md`, `phase-1/technical-design/backend-module-architecture.md`, `phase-1/technical-design/api-design/pricing.md`, `conventions/database-migrations.md`, `guidelines/testing-guidelines.md` (§ 4.2)
**Implemented by:** aliceut-ecom-infra (compose image and volume path), aliceut-ecom-backend (testcontainers image)

## Context

The ERD declares every application-generated identifier as
`DEFAULT uuidv7()` and says "PostgreSQL 16+ is required". `uuidv7()` is a
native function only from PostgreSQL 18. On 16 or 17 the first migration that
uses it fails with `function uuidv7() does not exist`. The specs also pinned
`postgres:16-alpine` in the compose topology, the testcontainers example and
several prose notes, so the stated floor and the pinned image disagreed.

## Decision

Phase 1 runs PostgreSQL **18**.

- Image: `postgres:18-alpine` everywhere it was `postgres:16-alpine`
  (compose, testcontainers, prose).
- `DEFAULT uuidv7()` is the native function; no extension and no SQL shim.
- `btree_gist` stays a bundled contrib module, so the stock image still needs
  no Dockerfile. No `pg_cron`; scheduled work stays in `workers`.
- The stated floor becomes "PostgreSQL 18+".
- Compose mounts `postgres_data` at `/var/lib/postgresql`, not
  `/var/lib/postgresql/data`. From 18 the image keeps data in a
  version-named subdirectory (`/var/lib/postgresql/18/docker`) and declares
  the parent as its volume. Mounting the old path leaves an anonymous volume
  holding the data and `postgres_data` empty.

Identifier generation is unchanged: a column default produces the id when SQL
inserts the row; the backend's `uuidv7()` helper produces it when the id must be
known before the insert (events, correlation ids). Both emit UUIDv7.

## Consequences

- An existing `postgres_data` volume holding a PG16 cluster at its root is not
  read by 18: `PGDATA` is now `/var/lib/postgresql/18/docker`, so the container
  initialises a new, empty cluster beside the old files and the old data is
  silently ignored. Phase 1 has no deployed data: recreate the volume with
  `docker compose down -v` and re-run `npm run migration:run`. Anyone with data
  worth keeping dumps from the old server and restores into the new one.
- The volume backup command in the topology still works: it archives the
  volume root, which now contains `18/docker`.
- The image tag `postgres:18-alpine` tracks the current Alpine release, so no
  Alpine version is pinned here. `pg_isready` ships in the image and the
  healthcheck is unchanged.
- `conventions/database-migrations.md` example uses `uuidv7()`, matching the ERD.
- Upgrading to a later major is a new ADR plus a dump/restore or `pg_upgrade`
  step; the version-named data directory makes side-by-side upgrades possible.

## Alternatives considered

**Stay on 16 and use `gen_random_uuid()` (UUIDv4).** Rejected: loses time
ordering, which the ERD relies on for index locality and which the BRD
identifier decision chose on purpose.

**Stay on 16 and generate UUIDv7 only in the app.** Rejected: every writer
(seed scripts, SQL fixtures, migrations backfilling rows) would need the
helper; a column default is the single place the rule lives.

**Add a PL/pgSQL `uuidv7()` shim in migration 0001.** Rejected: a project-owned
function shadowing a built-in is a trap on the next major upgrade, and the stock
image makes 18 free.
