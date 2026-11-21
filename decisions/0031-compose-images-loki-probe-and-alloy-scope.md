# ADR-0031: Compose image pins, the Loki readiness probe and Alloy's scope follow what actually runs

**Status:** Accepted  
**Date:** 2026-11-21  
**Affects:** `phase-1/technical-design/docker-compose-topology.md` (§ 2 service table, § 6 `postgres`, `minio`, `minio-init`, `kafka-ui`, `mailpit`, `alloy`, `loki`, `grafana`), `conventions/observability.md` (§ 5 Alloy config)  
**Implemented by:** aliceut-ecom-backend (`docker-compose.yml`, `docker/`)  

## Context

Building the backend compose file from the topology spec ([ADR-0028](0028-compose-lives-in-the-code-repos-infra-repo-retired.md)) and running it
showed that several things the spec states do not work:

- `minio/minio:RELEASE.2024-11-07T00-52-20Z` and `minio/mc:latest` are not
  pullable (denied on Docker Hub, absent on quay.io).
- `axllent/mailpit:v1.41.1` does not exist (GitHub issue #144). The newest tag
  that does is `v1.34.0`.
- `provectus/kafka-ui:v0.7.2` does not exist; the project publishes as
  `provectuslabs/kafka-ui`.
- The Loki healthcheck `wget … /ready` can never pass: the `grafana/loki`
  image has no shell, `wget` or `curl`. With `alloy` and `grafana` set to
  `condition: service_healthy` on `loki`, neither ever starts.
- observability.md § 5 tails every container on the host (no discovery filter)
  and reads `__meta_docker_compose_service`, which Docker discovery does not
  expose; the compose service label is
  `__meta_docker_container_label_com_docker_compose_service`.
- The `postgres` bind mount `./migrations/init` does not exist in the backend
  repo yet, and a missing bind source makes Docker create a directory there.
- `NODE_ENV=development` makes the logger load `pino-pretty`, a devDependency
  absent from the image, and writes coloured text Alloy cannot parse as JSON.

## Decision

- **MinIO** runs the community fork `pgsty/minio` and `pgsty/mc`, pinned to
  an exact release, overridable with `MINIO_IMAGE` and `MINIO_MC_IMAGE`. The
  spec's "`minio-init` is the one unpinned tag" exception is withdrawn: both
  images are pinned.
- **Mailpit** is `axllent/mailpit:v1.34.0`. **Kafka UI** is
  `provectuslabs/kafka-ui:v0.7.2`.
- **Loki** has no container healthcheck. `alloy` and `grafana` use
  `condition: service_started` on it. Readiness is probed from outside the
  container: `curl localhost:3100/ready`, which answers 503 for about 15 s
  after start and 200 after.
- **Alloy** discovers only containers of the compose project
  (`com.docker.compose.project`) and reads the service from
  `__meta_docker_container_label_com_docker_compose_service`. The
  `/var/lib/docker/containers` mount is dropped: `loki.source.docker` uses
  the socket alone. Loki runs a mounted config with TSDB schema v13 and
  `allow_structured_metadata: true` so `correlationId` is queryable as
  structured metadata, and its data volume holds the data (the image default
  writes to `/tmp`).
- **`postgres`** mounts `./docker/postgres/init`, a tracked placeholder
  directory, until migrations exist.
- **Application containers** set `NODE_ENV=production`; local development
  from source keeps `development`.

## Consequences

The stack builds and starts from a clean machine. The MinIO fork is third-party
software holding KYC documents locally; it is acceptable for a development
stack and is exactly why the image is overridable, but it must be revisited
before any non-local use. Alloy and Grafana no longer wait on Loki being ready,
so for the first seconds Alloy retries its pushes. No container reports Loki's
health, so `docker compose ps` shows it as plain `Up`. The tags above will age
the same way the old ones did; the exact pins stay, so a rebuild is
reproducible until a registry removes one.

## Alternatives considered

- **Keep the spec's pins and fail.** The stack does not start.
- **Build MinIO from source or use another S3 emulator.** More to own for a
  local sink; rejected for V1. An AWS emulator was already rejected in ADR-0028.
- **Keep the Loki healthcheck with a sidecar probe image.** An extra container
  to check a 15 s warm-up; the external `curl` does the same job.
- **Tail every container on the host.** Ships other projects' logs into this
  Loki.
