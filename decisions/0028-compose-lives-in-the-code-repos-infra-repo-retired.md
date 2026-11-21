# ADR-0028: Local compose lives in the code repos; `aliceut-ecom-infra` is retired

**Status:** Accepted
**Date:** 2026-11-21
**Affects:** `CLAUDE.md`, `README.md`, `architecture-overview.md` (§ 10), `guidelines/development-flow.md` (§ 1, § 2), `guidelines/templates/workspace-CLAUDE.md`, `phase-1/technical-design/docker-compose-topology.md` (§ 1, § 2, § 6, § 10, § 13), `phase-1/tasks.csv` and `scripts/github-issues/TEMPLATE.md` (task `IN-03`)
**Implemented by:** aliceut-ecom-backend (compose + mounted config), aliceut-ecom-frontend (portal compose + nginx), aliceut-ecom-utility-pipeline (dev / sit / uat deployment)

## Context

The specs put `docker-compose.yml` and every config it mounts in a fourth
repository, `aliceut-ecom-infra`. Its bind mounts reach into the other repos
(`../aliceut-ecom-backend`, `../aliceut-ecom-frontend/dist/<app>`), so the four
repos had to be cloned as siblings and compose had to run from the infra repo
root. That layout was documented as load-bearing.

Two problems follow. A backend change that needs a new service or config (a
Kafka topic, a Prometheus scrape target) lands as two PRs in two repos. And the
infra repo is a thin third home for a stack the backend alone defines, while
the real per-environment concern (dev, sit, uat) has no home at all.

## Decision

**The infra repo is retired.** Four repos remain: `document`, `backend`,
`frontend`, `utility-pipeline`.

**Local stack — owned by the code repos.**

- **Backend repo** holds `docker-compose.yml`, `.env.example` and the mounted
  config under `docker/` (`alloy`, `prometheus`, `grafana/provisioning`). It runs
  every service except the three portal nginx containers: `api`, `workers`,
  `postgres`, `mongodb`, `redis`, `minio` + `minio-init`, `kafka` + `kafka-init`,
  `schema-registry` + `schema-init`, `kafka-ui`, `elasticsearch`, `mailpit`,
  `alloy`, `loki`, `prometheus`, `grafana`. Every bind mount is relative to the
  backend repo root; no path leaves it.
- **Frontend repo** holds its own `docker-compose.yml` running only
  `buyer-nginx` (4200), `seller-nginx` (4201) and `admin-nginx` (4202), with the
  nginx configs beside it and `./dist/<app>` mounted. Portals reach the API at
  `localhost:3000`, so the backend stack runs separately. `ng serve` stays the
  day-to-day path.

**Dev / sit / uat — owned by `aliceut-ecom-utility-pipeline`.** The pipeline repo
holds the final per-environment compose files or overlays, env config, nginx and
observability config, and the deploy workflows. Secrets stay in GitHub Secrets.
The local files in the code repos are the base; an environment overrides them and
does not copy them. The pipeline repo's scope grows from "CI utility workflows"
to "environment deployment".

**Cloning.** The sibling layout is no longer required for compose. Cloning the
repos under one parent folder remains the convention for the workspace
`CLAUDE.md` and the document repo's relative links, but no repo's compose file
reads a path in another.

## Consequences

- A service or config change is one PR in one repo. The compose spec in
  `docker-compose-topology.md` is split by owner: § 6 describes the backend file,
  and a new subsection describes the frontend portal file.
- Image-name and volume-prefix text that assumed the project directory name
  `aliceut-ecom-infra` (for example the `aliceut-ecom-infra_postgres_data`
  backup command) now uses the compose project name of the backend repo.
- Task `IN-03` is re-homed from the infra repo to the backend and frontend repos.
  Per the repo rules the change is made in `phase-1/tasks.csv` and the importer
  re-run; the issue is not edited by hand.
- Accepted risk: with no shared compose, a portal developer needs two stacks to
  see a portal talking to a real API. `ng serve` against a running backend stack
  covers the common case.
- Earlier ADRs that name `aliceut-ecom-infra` under "Implemented by" (0004, 0005,
  0010, 0012, 0023, 0024, 0027) are history and are not edited; read the repo name
  there as "the backend repo (compose)".

## Alternatives considered

**Keep the infra repo, shrink it to dev / sit / uat config.** Rejected: leaves a
repo with no code of its own and splits a service change across two repos for
local work, which is the cost this ADR removes.

**One compose in the backend repo that also mounts the frontend `dist/`.**
Rejected: it keeps the cross-repo sibling dependency this ADR exists to drop, and
the backend would break on a missing frontend build.

**Drop the portal nginx containers from local compose entirely.** Rejected: the
nginx configs prove the portal's proxy and caching behaviour before it reaches an
environment; they stay, owned by the frontend repo.

**Replace MinIO (and the other stateful services) with the AWS Emulator
(`aws/aws-emulator`, CC0) in the local stack.** Rejected, evaluated 2026-11-21. The
emulator costs nothing and needs no AWS account, but it does not fit as a local
compose service:

- *Scope.* Only S3 was a candidate. ElastiCache, DocumentDB and OpenSearch were
  dropped without a test: the emulator models AWS control-plane APIs, its
  data-plane fidelity "varies by service", and nothing published says it serves
  Redis, MongoDB or OpenSearch wire protocols on the endpoints it returns.
- *S3 spike.* Bucket and object CRUD, `LastModified` (ADR-0004 orphan sweep),
  lifecycle and CORS calls, a 5 MB roundtrip, and presigned GET/PUT including the
  7-day TTL (ADR-0023) all worked. Three things did not:
  1. **HTTPS only, self-signed, new CA on every start.** No plain-HTTP option. A
     browser cannot load a presigned product image without trusting a CA that
     changes each restart, and the backend needs `NODE_EXTRA_CA_CERTS`. MinIO
     serves plain HTTP today.
  2. **State is in memory only.** A container restart returned an empty bucket
     list. A `docker compose down` or an out-of-memory stop would lose uploaded
     images and KYC documents and force a reseed and bucket recreation on every
     start.
  3. **The public-read `product-images` bucket only works with `--auth off`.**
     With auth on, an anonymous GET stayed 403 after Block Public Access was
     disabled and a public-read policy applied. With auth off it returned 200, but
     then every request is accepted unsigned.
- *Smaller costs.* No prebuilt image: it is built from a Dockerfile that downloads
  an unpinned `LTS/latest` RPM. With auth on, credentials are regenerated per start,
  so `.env` cannot hold static keys. Backend-to-emulator TLS across the compose
  network (hostname `emulator`, not `127.0.0.1`) was not tested.

MinIO stays the local object store; no spec changes follow. **Revisit when** the
emulator offers plain HTTP or a stable local CA, and persistence across restarts.
Until then it is a candidate only for backend integration tests, where in-memory
state and per-run credentials are an advantage, as an alternative to a MinIO
testcontainer. That would be a change to `testing-guidelines.md` and needs its own
decision.
