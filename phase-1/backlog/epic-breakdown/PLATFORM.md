# EPIC: PLATFORM — Platform Infrastructure

**Sprint:** 2  
**Total Tasks:** 8  

Transactional outbox relay, Kafka consumer base (idempotency + DLQ routing), processed-event deduplication table, audit log writer, FX rate store + scheduler, and the `platform` schema migrations. These components are shared infrastructure that every other module's Kafka integration depends on.

---

## PLATFORM-001 — Platform Schema Migrations

- **US Ref:** —
- **Estimate:** M (1d)
- **Dependencies:** INFRA-004, SHARED-005
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `libs/platform/src/infrastructure/migrations/001_platform_schema.sql`
- Creates `platform` PostgreSQL schema and all tables:

```sql
CREATE SCHEMA IF NOT EXISTS platform;

-- Outbox events (written in same TX as domain change)
CREATE TABLE platform.outbox_event (
  id              UUID PRIMARY KEY DEFAULT uuidv7(),
  aggregate_type  VARCHAR(100) NOT NULL,
  aggregate_id    UUID NOT NULL,
  event_type      VARCHAR(200) NOT NULL,
  event_version   SMALLINT NOT NULL DEFAULT 1,
  payload         JSONB NOT NULL,
  correlation_id  UUID,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  status          VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING', 'PUBLISHED', 'FAILED')),
  retry_count     SMALLINT NOT NULL DEFAULT 0,
  published_at    TIMESTAMPTZ,
  failed_reason   TEXT
);
CREATE INDEX idx_outbox_pending ON platform.outbox_event (occurred_at)
  WHERE status = 'PENDING';

-- Idempotency: mark consumed events
CREATE TABLE platform.processed_event (
  event_id        UUID PRIMARY KEY,
  consumer_group  VARCHAR(200) NOT NULL,
  processed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_processed_event_group ON platform.processed_event (consumer_group, processed_at);

-- FX rates
CREATE TABLE platform.fx_rate (
  base_currency   CHAR(3) NOT NULL,
  quote_currency  CHAR(3) NOT NULL,
  rate            NUMERIC(19,8) NOT NULL,
  fetched_at      TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (base_currency, quote_currency)
);
```

**Done Criteria**

- Migration runs cleanly on fresh DB: all three tables exist in `platform` schema
- `platform.outbox_event` accepts NULL for optional fields; rejects `status` values not in check constraint
- Idempotency table primary key prevents duplicate `event_id + consumer_group` inserts

---

## PLATFORM-002 — Outbox Relay (Workers App)

- **US Ref:** FR-P-09
- **Estimate:** L (2d)
- **Dependencies:** PLATFORM-001, INFRA-008, SHARED-005
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `apps/workers/src/schedulers/outbox-relay.scheduler.ts`
- Runs on configurable interval (`OUTBOX_RELAY_INTERVAL_MS`, default 500ms)
- Polling query (advisory lock prevents double-processing with multiple worker instances):
  ```sql
  SELECT * FROM platform.outbox_event
  WHERE status = 'PENDING'
  ORDER BY occurred_at ASC
  LIMIT 50
  FOR UPDATE SKIP LOCKED
  ```
- For each row: serialize to Avro (via `@kafkajs/confluent-schema-registry`), produce to Kafka topic matching `event_type`, mark `status = 'PUBLISHED'`
- On Kafka produce failure: increment `retry_count`; if `retry_count >= 3`, set `status = 'FAILED'` + `failed_reason`
- Avro schema for event envelope (registered with Schema Registry on startup):
  ```json
  {
    "type": "record",
    "name": "DomainEvent",
    "namespace": "com.aliceut.events",
    "fields": [
      { "name": "event_id", "type": "string" },
      { "name": "event_type", "type": "string" },
      { "name": "event_version", "type": "int" },
      { "name": "occurred_at", "type": "long", "logicalType": "timestamp-millis" },
      { "name": "correlation_id", "type": ["null", "string"], "default": null },
      { "name": "payload", "type": "string" }
    ]
  }
  ```
  `payload` is JSON-stringified inner payload (typed per topic)
- Topic name → Kafka topic mapping: `event_type` IS the topic name (e.g. `product.changed`, `fulfillment.placed`)
- Use KafkaJS `producer.send()` with `acks: 'all'` for durability

**Done Criteria**

- Writing an outbox row with `status='PENDING'` results in corresponding Kafka message within ≤1s (on low load)
- Kafka message is Avro-encoded; can be deserialized by Schema Registry consumer
- If Kafka is unavailable: rows remain `PENDING`, retry count increments, no crash
- After Kafka recovers: relay resumes processing remaining `PENDING` rows
- `FOR UPDATE SKIP LOCKED` prevents two relay instances processing same row (integration test with 2 concurrent relays)

---

## PLATFORM-003 — Kafka Consumer Base Class (Idempotency + DLQ)

- **US Ref:** FR-P-12
- **Estimate:** L (2d)
- **Dependencies:** PLATFORM-001, INFRA-008
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `libs/platform/src/kafka/base-consumer.ts`
- Abstract base class all Kafka consumers extend:
  ```ts
  abstract class BaseKafkaConsumer {
    protected abstract topic: string;
    protected abstract groupId: string;
    protected abstract handle(event: DomainEvent, em: EntityManager): Promise<void>;
    
    async processMessage(message: KafkaMessage): Promise<void> {
      const event = await this.registry.decode(message.value);
      
      // idempotency check
      const alreadyProcessed = await em.findOneBy(ProcessedEvent, {
        eventId: event.event_id, consumerGroup: this.groupId
      });
      if (alreadyProcessed) return; // skip duplicate
      
      await this.dataSource.transaction(async (em) => {
        await this.handle(event, em);
        await em.save(ProcessedEvent, {
          eventId: event.event_id,
          consumerGroup: this.groupId,
        });
      });
    }
    
    async onError(message: KafkaMessage, error: Error): Promise<void> {
      // route to DLQ topic: `${this.topic}.dlq.${this.groupId}`
      await this.producer.send({
        topic: `${this.topic}.dlq.${this.groupId}`,
        messages: [{ value: message.value, headers: { error: error.message } }],
      });
    }
  }
  ```
- Consumer commit strategy: **manual offset commit AFTER** side-effect + `ProcessedEvent` insert in same transaction
- DLQ topic naming: `<source-topic>.dlq.<consumer-group>` (e.g. `product.changed.dlq.search.product-changed`)
- Avro decode: `await this.registry.decode(message.value)` using `@kafkajs/confluent-schema-registry`
- KafkaJS consumer config: `autoCommit: false` (mandatory); `sessionTimeout: 30000`

**Done Criteria**

- Receiving same `event_id` twice: second call is a no-op (no duplicate side effects)
- Side-effect handler throws: message routed to DLQ (not committed as processed)
- Manual offset commit only happens after both side-effect AND `ProcessedEvent` insert succeed
- Unit test: mock `handle()` to throw; verify DLQ message produced

---

## PLATFORM-004 — Audit Log Writer (MongoDB)

- **US Ref:** US-P-09, US-P-10
- **Estimate:** M (1d)
- **Dependencies:** INFRA-005, INFRA-001
- **Spec References:** `phase-1/technical-design/data-model-mongodb.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `libs/platform/src/audit/audit-log.service.ts`
- Mongoose schema (`audit_logs` collection in `aliceut_audit` MongoDB database):
  ```ts
  const AuditLogSchema = new Schema({
    eventId:       { type: String, required: true, index: true },
    eventType:     { type: String, required: true, index: true },
    actorId:       { type: String, index: true },       // user ID or 'system'
    actorRole:     String,                              // 'buyer'|'seller'|'admin'|'system'
    targetType:    String,                              // e.g. 'Product', 'Order'
    targetId:      String,
    ipAddress:     String,
    userAgent:     String,
    payload:       Schema.Types.Mixed,
    occurredAt:    { type: Date, default: Date.now, index: true },
  }, { timestamps: false });
  ```
- `AuditLogService.log(entry: CreateAuditLogDto): Promise<void>` — fire-and-forget (no await in callers for performance); errors caught internally and logged to console
- Called from: admin actions (KYC decisions, suspensions, moderation), auth events (login, password change), order state transitions
- TTL index: 90 days (`expireAfterSeconds: 7776000`) for automatic cleanup
- Collection is append-only; no updates or deletes

**Done Criteria**

- `AuditLogService.log(...)` inserts a document in MongoDB `audit_logs` collection
- Documents older than TTL are automatically purged by MongoDB
- Invalid entries (missing required field) are caught and logged, not thrown to caller
- `GET /admin/audit-logs` endpoint (ADMIN epic) can query this collection by `targetType + targetId`

---

## PLATFORM-005 — FX Rate Service + Scheduler

- **US Ref:** US-P-17
- **Estimate:** M (1d)
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `apps/workers/src/schedulers/fx-rate.scheduler.ts` + `libs/platform/src/fx/fx-rate.service.ts`
- Scheduler: cron `0 * * * *` (hourly) calls `FxRateService.refresh()`
- `refresh()`: calls `GET ${FX_API_URL}?base=USD&symbols=THB,JPY,SGD,USD` (exchangerate.host or similar free API)
  - On success: upsert rows in `platform.fx_rate` with `fetched_at = now()`
  - On failure: log error; retain existing rates (stale but functional)
- `FxRateService.getRate(base: string, quote: string): Promise<Decimal>`:
  - Query `platform.fx_rate`; if no row found or `fetched_at < now() - FX_STALENESS_THRESHOLD_HOURS`, log warning but still return the rate (best-effort)
  - Throw `FxRateUnavailableException` only if no rate exists at all
- FX rate published to Kafka on change: emit `fx_rate.updated` event via outbox (triggers Search module to update currency-dependent fields in ES)
- V1 supported currency pairs: `USD/THB`, `USD/JPY`, `USD/SGD` (and inverse computed: `THB/USD = 1 / USD/THB`)

**Done Criteria**

- `FxRateService.refresh()` populates `platform.fx_rate` table from external API
- `getRate('USD', 'THB')` returns a `Decimal` value matching current exchange rate
- If external API is down: existing rates are served with a warning log (no exception)
- Scheduler fires on startup (immediate) and then hourly
- `fx_rate.updated` outbox event is written when rates change

---

## PLATFORM-006 — Kafka Topic Provisioning (Workers Startup)

- **US Ref:** —
- **Estimate:** M (1d)
- **Dependencies:** INFRA-008, PLATFORM-003
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/docker-compose-topology.md`

**Implementation Notes**

- File: `apps/workers/src/startup/kafka-provisioner.service.ts`
- On workers app startup (`OnModuleInit`): connect KafkaJS admin client, create missing topics
- All 24 topics from `phase-1/technical-design/kafka-events.md` plus their DLQ variants:
  ```ts
  const TOPICS = [
    'product.changed', 'offer.changed',
    'inventory.changed', 'inventory.low_stock', 'inventory.reservation_expired',
    'cart.checkout_initiated',
    'fulfillment.placed', 'fulfillment.shipped', 'fulfillment.delivered',
    'fulfillment.cancelled', 'fulfillment.refund_suspended_seller',
    'order.finalized', 'order.completed',
    'seller.kyc.submitted', 'seller.kyc.decided',
    'seller.suspended', 'seller.reinstated', 'seller.suspension_expired',
    'moderation.listing.removed', 'listing.flagged', 'listing.soft_deleted',
    'fx_rate.updated',
    'auth.email_verification_requested', 'auth.password_reset_requested', 'auth.password_changed',
  ];
  
  // Also create DLQ topics for each consumer group
  const DLQ_TOPICS = CONSUMER_GROUPS.flatMap(({ topic, groupId }) =>
    [`${topic}.dlq.${groupId}`]
  );
  ```
- Topic config: `numPartitions: 1`, `replicationFactor: 1` (single-broker local dev); `createTopics` with `waitForLeaders: true`
- Use `admin.createTopics({ validateOnly: false, waitForLeaders: true, topics: [...] })` — KafkaJS silently skips existing topics

**Done Criteria**

- Workers start: all 24+ topics appear in Kafka UI
- DLQ topics created for each consumer group
- Restarting workers does not throw on duplicate topic creation
- `admin.listTopics()` returns all expected topic names

---

## PLATFORM-007 — Global Exception Filter + Request Logger

- **US Ref:** —
- **Estimate:** S (½d)
- **Dependencies:** SHARED-004, INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `apps/api/src/filters/all-exceptions.filter.ts`
- Catches ALL unhandled exceptions (not just `DomainException`); logs stack trace; returns generic 500 JSON
- Request logger middleware (`apps/api/src/middleware/request-logger.middleware.ts`):
  ```ts
  logger.log(`${method} ${url} ${status} ${duration}ms ${userAgent}`);
  ```
  Applied globally; excludes `GET /health` to reduce noise
- Correlation ID: extract `X-Correlation-ID` header or generate new UUIDv7; attach to `AsyncLocalStorage` context; include in every response header and log line
- Structured log format (JSON): `{ level, timestamp, correlationId, method, url, status, duration, message }`
- `LOG_LEVEL` env var controls verbosity (default `info`; use `debug` in dev for verbose output)

**Done Criteria**

- Unhandled exception returns `{ "error": "INTERNAL_SERVER_ERROR", "message": "An unexpected error occurred" }` (not stack trace)
- Request log line appears for every API call with correct status and duration
- `X-Correlation-ID` present in every response header

---

## PLATFORM-008 — Schema Registry Avro Schema Registration

- **US Ref:** FR-P-09
- **Estimate:** M (1d)
- **Dependencies:** INFRA-008, PLATFORM-002
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `libs/platform/src/kafka/schema-registry.service.ts`
- On workers startup: register envelope schema + per-event payload schemas with Confluent Schema Registry
- Compatibility mode: ensure global setting is `BACKWARD` (call `PUT /config` on startup):
  ```ts
  await axios.put(`${SCHEMA_REGISTRY_URL}/config`, { compatibility: 'BACKWARD' });
  ```
- Register envelope schema under subject `domain-event-value`
- Per-topic payload schemas registered under `<topic>-value` subjects
- Minimal payload schemas for Phase 1 (typed JSONB payloads stored as string in envelope; full per-topic Avro schemas for payload deferred to individual epic tasks)
- `SchemaRegistryService.getSchemaId(subject: string): Promise<number>` — cached in-memory after first fetch
- All producers use `registry.encode(schemaId, payload)` before sending; all consumers use `registry.decode(message.value)` after receiving

**Done Criteria**

- `GET http://localhost:8081/subjects` returns at least `['domain-event-value']` after workers start
- Compatibility mode set to `BACKWARD` at registry level (`GET /config` returns `{ "compatibilityLevel": "BACKWARD" }`)
- Producing with old schema version; consuming with new schema (added optional field) succeeds
- Schema registration idempotent: running workers twice doesn't error on duplicate schema
