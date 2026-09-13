# EPIC: PLATFORM — Outbox + Kafka Infrastructure

**Sprint:** 1
**Total Tasks:** 8

Transactional outbox (write-side), Avro serialization via Schema Registry, Kafka producer/relay, and consumer-side idempotency + DLQ routing. Shared infrastructure every other module's Kafka integration depends on.

---

## PLATFORM-001 — Platform Schema Migrations

- **US Ref:** US-P-10
- **Estimate:** L
- **Dependencies:** INFRA-004
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes**

- File: `libs/platform/src/infrastructure/migrations/001_platform_schema.sql`
- Raw-SQL migration (per conventions — no decorator schema sync). Creates `platform` schema, `outbox_event` and `processed_event` tables, and all supporting enum types (outbox `status` enum: `PENDING`/`PUBLISHED`/`FAILED`):

```sql
CREATE SCHEMA IF NOT EXISTS platform;

CREATE TYPE platform.outbox_status AS ENUM ('PENDING', 'PUBLISHED', 'FAILED');

CREATE TABLE platform.outbox_event (
  id              UUID PRIMARY KEY DEFAULT uuidv7(),
  aggregate_type  VARCHAR(100) NOT NULL,
  aggregate_id    UUID NOT NULL,
  event_type      VARCHAR(200) NOT NULL,
  event_version   SMALLINT NOT NULL DEFAULT 1,
  payload         JSONB NOT NULL,
  correlation_id  UUID,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  status          platform.outbox_status NOT NULL DEFAULT 'PENDING',
  retry_count     SMALLINT NOT NULL DEFAULT 0,
  published_at    TIMESTAMPTZ,
  failed_reason   TEXT
);
CREATE INDEX idx_outbox_pending ON platform.outbox_event (occurred_at)
  WHERE status = 'PENDING';

CREATE TABLE platform.processed_event (
  event_id        UUID PRIMARY KEY,
  consumer_group  VARCHAR(200) NOT NULL,
  processed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_processed_event_group ON platform.processed_event (consumer_group, processed_at);
```

**Done Criteria**

- Migration runs cleanly on fresh DB: `platform.outbox_event` and `platform.processed_event` exist
- `outbox_event.status` rejects values outside the enum
- `processed_event` primary key prevents duplicate `event_id` insert per row

---

## PLATFORM-002 — OutboxEvent Entity + Repository

- **US Ref:** US-P-10
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `libs/platform/src/outbox/outbox-event.entity.ts`
- TypeORM entity mapped read-only to the `platform.outbox_event` columns (migration owns DDL, per repo convention)
- `OutboxRepository` interface (`libs/platform/src/outbox/outbox.repository.ts`) — portability seam per NFR-18:
  ```ts
  interface OutboxRepository {
    append(em: EntityManager, event: NewOutboxEvent): Promise<void>;
    claimPending(limit: number): Promise<OutboxEvent[]>;
    markPublished(id: string): Promise<void>;
    markFailed(id: string, reason: string): Promise<void>;
  }
  ```
- `append()` is the method every domain module calls inside its own transaction (`EntityManager` passed in) so the outbox row commits atomically with the domain change
- TypeORM implementation registered behind the interface via DI token (`OUTBOX_REPOSITORY`)

**Done Criteria**

- `append()` called inside a domain transaction persists the outbox row only if the transaction commits (rollback test: domain write fails → no outbox row)
- `claimPending()` returns rows ordered by `occurred_at ASC`

---

## PLATFORM-003 — ProcessedEvent Entity + IdempotencyHelper

- **US Ref:** US-P-13
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/platform/src/idempotency/processed-event.entity.ts`, `libs/platform/src/idempotency/idempotency-helper.service.ts`
- `IdempotencyHelper.isProcessed(eventId, consumerGroup): Promise<boolean>` and `markProcessed(em, eventId, consumerGroup): Promise<void>` — the latter always called inside the same transaction as the consumer's side-effect
- Repository behind an interface (`ProcessedEventRepository`) for the same portability reason as PLATFORM-002

**Done Criteria**

- `markProcessed` + side-effect commit atomically (rollback test: side-effect throws → no `processed_event` row)
- `isProcessed` returns `true` after `markProcessed` for the same `(eventId, consumerGroup)` pair

---

## PLATFORM-004 — Avro Serializer Service

- **US Ref:** US-P-13
- **Estimate:** L
- **Dependencies:** INFRA-008
- **Spec References:** `phase-1/technical-design/kafka-events.md`

**Implementation Notes**

- File: `libs/platform/src/kafka/schema-registry.service.ts`
- Wraps `@kafkajs/confluent-schema-registry`; registers the domain-event envelope schema under subject `domain-event-value` on startup and ensures registry-level compatibility is `BACKWARD` (`PUT /config`)
- Per-topic payload schemas registered under `<topic>-value`, per the catalog in `kafka-events.md` §2
- `getSchemaId(subject): Promise<number>` cached in-memory after first fetch
- `encode(schemaId, payload)` / `decode(buffer)` are the only entry points producers/consumers use — no raw registry calls elsewhere

**Done Criteria**

- `GET /subjects` on Schema Registry includes `domain-event-value` after service startup
- Registry compatibility level is `BACKWARD`
- Schema registration is idempotent (running startup twice does not error on duplicate schema)

---

## PLATFORM-005 — Kafka Producer Service

- **US Ref:** US-P-10
- **Estimate:** M
- **Dependencies:** PLATFORM-004
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/docker-compose-topology.md`

**Implementation Notes**

- File: `libs/platform/src/kafka/kafka-producer.service.ts`
- KafkaJS producer; `send(event)` Avro-encodes the envelope (via PLATFORM-004) using the schema for `event.event_type` as topic name, `acks: 'all'`
- On startup, ensures all topics from the catalog in `kafka-events.md` §1 exist via `admin.createTopics` (`numPartitions: 1`, `replicationFactor: 1` for single-broker local dev) — KafkaJS no-ops on already-existing topics
  - Topic list is exactly the catalog in `kafka-events.md` §1 Topic Summary table; do not add topics not defined there (no `cart.checkout_initiated` — not a defined topic)

**Done Criteria**

- `send()` produces an Avro-encoded message consumable by a Schema Registry-aware consumer
- On workers startup, all catalog topics from `kafka-events.md` exist in Kafka (verified via `admin.listTopics()`)
- Restarting workers does not throw on duplicate topic creation

---

## PLATFORM-006 — Outbox Relay Worker

- **US Ref:** US-P-10
- **Estimate:** L
- **Dependencies:** PLATFORM-005
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `apps/workers/src/schedulers/outbox-relay.scheduler.ts`
- Runs on configurable interval (`OUTBOX_RELAY_INTERVAL_MS`, default 500ms); polls via `OutboxRepository.claimPending()`:
  ```sql
  SELECT * FROM platform.outbox_event
  WHERE status = 'PENDING'
  ORDER BY occurred_at ASC
  LIMIT 50
  FOR UPDATE SKIP LOCKED
  ```
- For each row: `KafkaProducerService.send()` → mark `PUBLISHED`; on failure increment `retry_count`, and set `status = 'FAILED'` + `failed_reason` once `retry_count >= 3`
- `FOR UPDATE SKIP LOCKED` allows multiple relay instances without double-publish

**Done Criteria**

- Writing an outbox row with `status='PENDING'` results in a Kafka message within ≤1s under low load
- If Kafka is unavailable: rows remain `PENDING`, retry count increments, no crash; relay resumes after recovery
- Two concurrent relay instances never both publish the same row (integration test)

---

## PLATFORM-007 — Consumer Idempotency Decorator/Helper

- **US Ref:** US-P-13
- **Estimate:** M
- **Dependencies:** PLATFORM-003
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `libs/platform/src/kafka/base-consumer.ts`
- Abstract base class every module's Kafka consumer extends:
  ```ts
  abstract class BaseKafkaConsumer {
    protected abstract topic: string;
    protected abstract groupId: string;
    protected abstract handle(event: DomainEvent, em: EntityManager): Promise<void>;

    async processMessage(message: KafkaMessage): Promise<void> {
      const event = await this.registry.decode(message.value);
      if (await this.idempotency.isProcessed(event.event_id, this.groupId)) return;

      await this.dataSource.transaction(async (em) => {
        await this.handle(event, em);
        await this.idempotency.markProcessed(em, event.event_id, this.groupId);
      });
    }
  }
  ```
- Manual offset commit strategy: commit **after** the transaction (side-effect + `ProcessedEvent` insert) succeeds — `autoCommit: false` on the KafkaJS consumer config
- Uses `IdempotencyHelper` from PLATFORM-003 for the check-then-mark logic

**Done Criteria**

- Receiving the same `event_id` twice on the same consumer group: second call is a no-op
- Offset commit only happens after side-effect + idempotency-mark transaction succeeds

---

## PLATFORM-008 — DLQ Routing

- **US Ref:** US-P-14
- **Estimate:** M
- **Dependencies:** PLATFORM-005
- **Spec References:** `phase-1/technical-design/kafka-events.md`

**Implementation Notes**

- File: `libs/platform/src/kafka/base-consumer.ts` (`onError` hook alongside PLATFORM-007's base class)
- On `handle()` throwing (or exceeding max retry): route the raw message to `<source-topic>.dlq.<consumer-group>` via `KafkaProducerService`, preserving the error message in a header
- DLQ topics are created alongside their source topics in PLATFORM-005's provisioning step (one per registered consumer group)

**Done Criteria**

- Side-effect handler throws: message is routed to its DLQ topic (not committed as processed on the source topic)
- Unit test: mock `handle()` to throw; verify DLQ message is produced with the error in headers
