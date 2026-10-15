# ADR-0012: Avro subjects are registered by a CI job and, locally, by a `schema-init` one-shot

**Status:** Accepted
**Date:** 2026-10-15
**Affects:** `phase-1/technical-design/docker-compose-topology.md` (§ 2 Service inventory, § 3 Networks, § 6 `docker-compose.yml`, § 9 Startup order), `phase-1/technical-design/kafka-events.md` (Schema revision state)
**Implemented by:** aliceut-ecom-backend#56, aliceut-ecom-infra#4

## Context

conventions/kafka-events.md § 2 says the Avro schemas live in
`libs/contracts/avro/` and are "registered to Schema Registry by CI before
deployment", one `<topic>-value` subject per topic at `BACKWARD`. Until now
the code published JSON and nothing was registered, so the question of how
registration happens never came up (spec-compliance tracker entry 6).

Two facts constrain the answer:

- **V1 has no deploy pipeline.** Deployment is `docker compose up` against
  the long-lived registry in that stack. A CI job cannot reach it, so "CI
  registers before deployment" has no deployment to precede.
- **Producers must not register.** If the relay registered on first publish
  (the Confluent serializer's default), whatever a producer happened to send
  would become the schema, and the `.avsc` files and the compatibility check
  would be advisory. So the relay only looks schema ids up, and a subject
  that nobody registered fails every publish to its topic.

So two registries need the schemas registered: CI's, to prove they register
and stay compatible, and the compose stack's, before `workers` publishes.

## Decision

`aliceut-ecom-backend/tools/avro/register-schemas.js` (`pnpm
schemas:register`) is the only thing that writes to a Schema Registry. Per
subject it sets `BACKWARD`, skips a schema that is already registered, tests a
changed schema against the latest version and refuses it if incompatible, then
registers it. It has no dependencies beyond Node.

- **CI** (backend `avro-schemas` job) starts a throwaway KRaft Kafka and
  `cp-schema-registry:7.7.0` as service containers. It registers the base
  commit's schemas, then this commit's, then runs the script again. That
  ephemeral registry stands in for the long-lived one: an incompatible change
  fails CI against the schemas on `main`. The rerun fails CI if the script is
  not idempotent.
- **Local compose** gains `schema-init`, a one-shot `node:22.12.0-alpine`
  container. It runs that script from a read-only bind mount of
  `../aliceut-ecom-backend` once `schema-registry` is healthy. `workers`
  waits for it to complete successfully, the same way `api` and `workers`
  wait for `kafka-init`. `api` does not wait for it: `api` only writes outbox
  rows and never talks to the registry.

docker-compose-topology.md §§ 2, 3, 6 and 9 describe the new container. The
"Schema revision state" paragraph in kafka-events.md now records that the
schemas are registered, and that `BACKWARD` binds from that registration on.

## Consequences

- The `.avsc` files are the contract in practice as well as on paper. A
  producer's payload that drifts from its schema fails at the relay. The row
  is marked `FAILED` with the offending fields logged; nothing reaches Kafka.
- Schema evolution is now enforced. The first CI registration on `main`
  ends the "unregistered v1" amendment window that conventions § 2 allows.
  From then on, any catalog change must be `BACKWARD`-compatible with
  `main`'s schema, or it must be a new topic.
- Local compose depends on the backend checkout one more way. `kafka-init`
  already reads only infra files, but `schema-init` reads backend files
  (`libs/contracts/avro`, `tools/avro`). A stack started against an older
  backend checkout registers that checkout's schemas. That is the intent:
  the registry should match the code that will run.
- The local registry keeps its subjects in the `_schemas` topic on the
  `kafka_data` volume. An incompatible schema change therefore makes
  `schema-init` fail, and `workers` will not start, until the volume is
  reset or the change is fixed. That is the same refusal CI makes, surfaced
  locally.
- Phase 2 (a real deploy pipeline) should run the same script as a
  pre-deploy step against the production registry. It needs no new
  mechanism.

## Alternatives considered

- **Producers auto-register** (Confluent serializer default). Rejected:
  this inverts the contract. The schema becomes whatever the code sent, and
  compatibility is checked only after a bad payload is already live.
- **`workers` registers at boot, before the relay starts.** Rejected. It
  puts registry write access and the compatibility gate inside an
  application process. It runs on every replica. And a refused schema
  surfaces as a workers crash-loop rather than as a CI failure.
- **CI-only registration, with no local mechanism.** Rejected: the compose
  registry would stay empty and every local publish would fail.
- **A registration script in the infra repo.** Rejected: it would duplicate
  the backend's script and could drift from it. With one script, CI and
  compose run identical logic.
- **Run `schema-init` from the backend image.** Rejected: it would make a
  one-shot wait on the full backend image build. The plain Node image plus
  a bind mount starts in seconds, and it follows how `postgres` already
  mounts `../aliceut-ecom-backend/migrations/init`.
