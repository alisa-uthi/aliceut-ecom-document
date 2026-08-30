# Kafka Event Conventions

**Status:** Draft  
**Source of truth:** [BRD v1.1](../phase-1/requirements/BRD.md), [implementation-specs](../phase-1/technical-design/implementation-specs.md)

Phase-specific event schemas and topic summary: [phase-1/technical-design/kafka-events.md](../phase-1/technical-design/kafka-events.md)

---

## 1. Event envelope (all events)

Every Avro record includes the following envelope fields as the outer record. Topic-specific `payload` is a nested record within the envelope.

```json
{
  "namespace": "com.aliceut.events",
  "type": "record",
  "name": "<EventName>",
  "fields": [
    { "name": "event_id",      "type": "string", "doc": "UUIDv7 — globally unique event identifier" },
    { "name": "event_type",    "type": "string", "doc": "Fully-qualified event type e.g. seller.kyc.submitted" },
    { "name": "event_version", "type": "int",    "doc": "Schema version starting at 1; increment on BACKWARD-compatible changes" },
    { "name": "occurred_at",   "type": "string", "doc": "ISO 8601 UTC timestamp of domain event" },
    { "name": "correlation_id","type": "string", "doc": "UUIDv7 propagated from the originating HTTP request or job" },
    { "name": "payload",       "type": { "type": "record", "name": "Payload", "fields": [...] } }
  ]
}
```

---

## 2. Schema registry

- One `<topic>-value` subject per topic in Confluent Schema Registry.
- Compatibility mode: `BACKWARD` on all subjects.
- **BACKWARD compat rules:** adding optional fields (`"default": null` on union `["null", "..."]`) is allowed; removing or renaming fields or changing a field type is a breaking change that requires a new `event_version` and coordinated consumer migration.
- Avro schemas committed to `backend/libs/contracts/avro/` and registered to Schema Registry by CI before deployment.

---

## 3. Partition keys

Each topic uses a partition key to co-locate related events and preserve ordering within an aggregate. Partition key per topic is defined in the phase-specific event catalog.

---

## 4. Consumer idempotency template

```
1. Check platform.processed_event(consumer_group, event_id)
   → if found: skip (already processed)
2. Execute side effect (write Postgres row, send email, update ES, etc.)
3. INSERT INTO platform.processed_event (consumer_group, event_id, processed_at, outcome)
4. Commit Kafka offset
```

On unhandled exception: route to `<consumer_group>.dlq`, then commit offset. DLQ non-empty triggers alert.

---

## 5. DLQ topology

Each consumer group has a dedicated DLQ topic: `<consumer_group>.dlq`

- DLQ message includes the original event envelope + error metadata (`error_type`, `error_message`, `failed_at`, `attempt_count`).
- DLQ non-empty → alert (Kafka UI monitoring or a health check endpoint exposed by workers).
- SMTP failures: retry 3× with exponential backoff, then route to `email.outbound.dlq`.

---

## 6. BACKWARD compatibility protocol

When adding a new field to an existing event payload:
1. Add it as a union with null and a default: `"type": ["null", "string"], "default": null`
2. Increment `event_version`
3. Update the Schema Registry subject; validate BACKWARD compatibility passes before deploying
4. Update all consumers to handle the new field (null-safe)

When removing a field, changing a type, or renaming: this is a **breaking change**. Create a new topic `<topic>.v2` or bump the major version; deprecate the old topic after all consumers migrate.
