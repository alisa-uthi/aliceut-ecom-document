# MongoDB Data Model — Phase 1

**Status:** Complete  
**Source of truth:** [BRD v1.4](../requirements/BRD.md)  
**Related:** [kafka-events.md](kafka-events.md), [cleanup-jobs.md](cleanup-jobs.md), [conventions/observability.md](../../conventions/observability.md)

Collections used for high-write append data: admin accountability, PII access accountability, and domain lifecycle events. All writes come from the single `platform.audit` Kafka consumer group (see [kafka-events.md](kafka-events.md)).

**The write path is Kafka, and only Kafka.** No request handler writes any collection in this document. A document exists because the `platform.audit` consumer group processed an event whose `platform.outbox_event` row was written in the same PostgreSQL transaction as the domain change it records (FR-P-11). An API handler that inserts an audit document inline is a defect, not a second supported path: it produces audit rows for transactions that later rolled back, loses the rows of transactions whose response never completed, and cannot be replayed from the topic.

**Modelling convention:** All MongoDB `_id` fields use UUIDv7 in standard UUID binary representation (BinData subtype 4). Do not use `ObjectId` for domain or audit documents. Every other UUID-valued field uses the same representation, so an `entity_id` here compares directly against a Postgres `uuid` column without conversion. `correlation_id` is the one deliberate exception — it is stored as a string so a `correlationId` copied out of a Loki log line can be pasted straight into a Mongo query.

---

## Summary

- [Consumer routing](#consumer-routing)
- [Common document fields](#common-document-fields)
- [1. `audit_logs`](#audit-logs)
- [2. `activity_events`](#activity-events)
- [3. `pii_access_logs`](#pii-access-logs)
- [TTL ownership](#ttl-ownership)

<a id="consumer-routing"></a>
## Consumer routing

The `platform.audit` consumer group subscribes to every topic except the two named as not persisted below, and routes by `event_type`. Every topic in [kafka-events.md §1](kafka-events.md#topic-summary) appears below; a topic that is deliberately not persisted is named as such rather than left out. `inventory.changed` is the only topic occupying two rows, for the reason stated immediately after this paragraph.

**One event type routes on its payload, and it is the only one.** `inventory.changed` splits by `payload.change_reason`: a seller's deliberate stock correction is an accountability record and belongs in a two-year collection, while an adjustment a consumer applied on the system's own initiative is lifecycle data and belongs in a ninety-day one. This is a named exception, not a pattern to follow — no other row below is decided by anything beneath the envelope, and a topic added later is routed by `event_type` alone unless a decision says otherwise.

**An `UNKNOWN` `change_reason` routes to `audit_logs`.** The Avro enum declares `"default": "UNKNOWN"` so that a consumer on an older schema survives a symbol appended later ([kafka-events.md](kafka-events.md)), which means a document can reach this consumer recording a stock movement whose cause this build cannot name. It is written to `audit_logs` with `action: 'STOCK_ADJUSTED'`, `actor_id: null` and `actor_role: 'SYSTEM'`, on the ground that an unclassifiable change to a quantity is the record most likely to be asked about later and the least safe to expire in ninety days. Routing it to `activity_events` instead would let a lag in deploying a schema silently shorten the retention of exactly those records.

| Route | Collection | Event types |
|---|---|---|
| Admin accountability | `audit_logs` | `seller.kyc.submitted`, `seller.kyc.decided`, `seller.suspended`, `seller.suspension_amended`, `seller.reinstated`, `seller.suspension_expired`, `listing.flagged`, `moderation.listing.removed`, `keyword_blocklist.changed` |
| Credential accountability | `audit_logs` | `auth.email_verification_requested`, `auth.password_reset_requested`, `auth.password_changed` |
| Stock adjustment accountability | `audit_logs` | `inventory.changed` when `payload.change_reason` is `MANUAL_UPDATE`, `BULK_UPDATE` or `UNKNOWN` |
| PII access accountability | `pii_access_logs` | `pii.accessed` |
| Domain lifecycle | `activity_events` | `fulfillment.placed`, `fulfillment.shipped`, `fulfillment.delivered`, `fulfillment.refunded`, `fulfillment.cancelled`, `fulfillment.refund_suspended_seller`, `order.finalized`, `order.completed`, `product.changed`, `offer.changed`, `listing.soft_deleted`, `inventory.changed` when `payload.change_reason` is `RESERVATION`, `SHIPMENT`, `REFUND_RESTORE` or `CANCEL_RESTORE`, `inventory.low_stock`, `inventory.reservation_expired` |
| Not persisted | — | `fx_rate.updated` — the FX table is a per-pair display cache refreshed by upsert in place, and its previous values are neither accountability nor lifecycle data. The topic has one consumer group (`search.fx-rate-updated`) and no audit consumer. `seller.profile_changed` — a seller editing their own business name is not a decision made about another person, and `seller.seller_profile` keeps the current value with its `updated_at`. Persisting it later takes a row here, an `action` symbol in [`audit_logs`](#audit-logs) and the topic in the group's subscription list, in that order: an unrouted `event_type` is dead-lettered rather than written. |

**Unrouted event types are never dropped.** An event whose `event_type` matches no row above is a routing gap — a topic was added without extending this table. The consumer logs it at `error` with the `event_type`, `event_id` and `correlation_id`, does **not** commit the offset as processed, and lets the retry/DLQ path move the message to `platform.audit.dlq`, where the non-empty-DLQ alert ([docker-compose-topology.md](docker-compose-topology.md)) surfaces it. Writing such an event to a default collection would hide the gap; silently acknowledging it would lose the record.

**One consumer group, three collections.** The group stays single (`platform.audit`, spelled that way everywhere — `consumer_group` is half the primary key of `platform.processed_event` and it names the DLQ topic, so a second spelling would be a second group projecting every event again) rather than splitting per topic family: the routing decision is one `switch` on `event_type` plus the single payload branch named above, and one group means one offset set, one dedupe key namespace in `platform.processed_event` and one DLQ to watch.

<a id="common-document-fields"></a>
## Common document fields

Every document in every collection below carries the full Kafka event envelope — `event_id`, `event_type`, `event_version`, `occurred_at`, `correlation_id` and `payload` ([conventions/kafka-events.md](../../conventions/kafka-events.md)). `event_version` is stored, not derived: once a v2 payload shape ships, a document written under v1 is only interpretable if it records which shape it holds.

**`correlation_id` is propagated, never generated here.** It originates from the inbound `X-Correlation-ID` request header — or is generated at the request boundary when that header is absent — and travels unchanged through the `platform.outbox_event` row, the Kafka envelope, and into the document ([conventions/observability.md §4](../../conventions/observability.md#correlation-id)). Scheduled work with no inbound request generates one per run and uses it for the whole run. The consumer copies the field; it never mints a new value, because doing so would break the chain from the HTTP call to the document.

**Payload masking is mandatory.** Before insert, the consumer masks every `payload` key matching `DEFAULT_SENSITIVE_KEYS` in [conventions/observability.md §2](../../conventions/observability.md#nestjs-logger) — `password`, `token`, `authorization`, `cookie`, `tax_id`, `secret`, `refresh_token` and the rest of that list, matched case- and separator-insensitively — writing `"***"` in place of the value at any depth. This is a requirement of the collections, not a recommendation on the consumer:

- `auth.email_verification_requested` and `auth.password_reset_requested` legitimately carry the **raw single-use token** on the wire, because the notification consumer cannot build the email link otherwise and reading `identity.email_verification_token` from the notifications module would be a cross-schema read.
- Seller KYC payloads carry `tax_id`.
- `audit_logs` retention is **two years**. An unmasked token or tax id written here outlives its own TTL by two years, in a store whose whole purpose is to be queried later.

The same list governs log lines, so masking is one shared sanitizer, not a per-consumer reimplementation. The consumer side of this rule is stated at [kafka-events.md §audit masking](kafka-events.md#audit-masking); the shortened retention that bounds the same token's exposure in the Kafka log itself is at [§topic retention](kafka-events.md#topic-retention). Masking here and short retention there are two independent limits on one secret, not alternatives — the topic retention protects the log, and only the masking protects a two-year collection.

**Idempotency.** `event_id` carries a unique index in every collection. The consumer records `platform.processed_event (consumer_group, event_id)` after the insert and commits the offset after that, so an at-least-once redelivery is either skipped by the dedupe row or rejected by the unique index — never written twice.

---

<a id="audit-logs"></a>
## 1. `audit_logs`

Admin, moderation, credential and seller stock-correction actions. Answers: *who did what, and why.*

| Field | Type | Notes |
|---|---|---|
| `_id` | UUID (UUIDv7, BinData subtype 4) | |
| `event_id` | UUID (BinData subtype 4) | envelope `event_id`; equals `platform.outbox_event.id`; unique index — idempotency key |
| `event_type` | string | indexed |
| `event_version` | int | envelope field; the payload schema version this document was written under |
| `occurred_at` | Date | indexed |
| `correlation_id` | string | indexed; propagated from `X-Correlation-ID` |
| `actor_id` | UUID (BinData subtype 4) \| null | the acting user; `null` when `actor_role` is `SYSTEM` |
| `actor_role` | `ADMIN` \| `SELLER` \| `USER` \| `SYSTEM` | `SELLER` for a seller's own KYC submission or stock correction, `USER` for a credential action on one's own account, `SYSTEM` for automated expiry and for an unclassifiable stock change |
| `entity_type` | `SELLER` \| `OFFER` \| `USER` \| `KEYWORD_BLOCKLIST` | |
| `entity_id` | UUID (BinData subtype 4) | indexed — `seller_profile_id`, `offer_id`, `user_id` or `blocklist_entry_id` |
| `action` | string | `KYC_SUBMITTED` \| `KYC_RESUBMITTED` \| `KYC_APPROVED` \| `KYC_REJECTED` \| `SELLER_SUSPENDED` \| `SELLER_SUSPENSION_AMENDED` \| `SELLER_REINSTATED` \| `SUSPENSION_EXPIRED` \| `LISTING_FLAGGED` \| `LISTING_REMOVED` \| `EMAIL_VERIFICATION_REQUESTED` \| `PASSWORD_RESET_REQUESTED` \| `PASSWORD_CHANGED` \| `STOCK_ADJUSTED` \| `BLOCKLIST_TERM_ADDED` \| `BLOCKLIST_TERM_REMOVED` \| `BLOCKLIST_TERM_CHANGED` |
| `decision_reason` | string \| null | reason text a person typed — rejection, suspension, removal, or the seller's stock-adjustment reason; `null` where the path collects none |
| `payload` | object | full Kafka payload snapshot, **masked** per [Common document fields](#common-document-fields) |

`actor_id` plus `actor_role` is the same actor representation `activity_events` uses. A `SYSTEM` actor is `actor_id: null` with `actor_role: 'SYSTEM'` — never the string `"SYSTEM"` in the id field, which would make `actor_id` a union of UUIDs and magic strings and break the index's type.

`KYC_RESUBMITTED` is written when `seller.kyc.submitted` carries `is_resubmission: true`; the topic is the same for both.

**Vocabulary:** the entity is `OFFER` in this collection and in `activity_events`, because `entity_type` names the table that holds the row. `LISTING` is buyer- and admin-facing vocabulary; it appears in event names (`listing.flagged`) and action names (`LISTING_REMOVED`) but never as an `entity_type`.

**`payload.matched_terms` stays an array.** `listing.flagged` carries the blocklist terms that matched as an array of strings, and the consumer writes it into `payload` unchanged — one JSON array inside one document, never flattened to a delimited string and never split into a document per term, which would turn a single flagging event into several accountability records. The array is **empty, not null**, when the flag came from a source that matches no terms — a prohibited category or a manual admin flag — so a reader can tell "nothing matched" from "this field was never populated". It is not masked: `matched_terms` is not in `DEFAULT_SENSITIVE_KEYS`, and a blocklist term is admin-authored vocabulary rather than a secret. These terms do not go in `decision_reason`, which holds reason text a person typed.

**Blocklist mutations map `change_type` onto three actions.** `keyword_blocklist.changed` carries a `change_type` of `ADDED`, `REMOVED` or `UNKNOWN`, and the action follows it — `BLOCKLIST_TERM_ADDED`, `BLOCKLIST_TERM_REMOVED`, and `BLOCKLIST_TERM_CHANGED` for `UNKNOWN`, which records that the list changed without claiming a direction the payload did not state. `entity_type` is `KEYWORD_BLOCKLIST` and `entity_id` the `blocklist_entry_id`, per the rule above that `entity_type` names the table holding the row. `actor_role` is `ADMIN`; `payload.term` is written unmasked for the same reason as `matched_terms`, and so is `payload.enforcement` — the `BLOCK` or `FLAG` tier the term is stored with ([data-model-erd.md](data-model-erd.md#table-admin-keyword-blocklist)), which is what makes these documents answer *what* the change did rather than only that one happened: a term moved from `FLAG` to `BLOCK` is the difference between a reviewed listing and a refused submit. Both live in the `payload` snapshot and neither is projected to a top-level field. In particular `decision_reason` is `null` on all three actions — an admin editing the list types no reason, and neither a blocklist term nor its tier is reason text a person typed. Removal here means `is_active = false` — the row itself is never deleted, so the document and the row it names both survive.

**Neither `UNKNOWN` on this event dead-letters.** `change_type = UNKNOWN` becomes `BLOCKLIST_TERM_CHANGED` as above, and `enforcement = UNKNOWN` is likewise stored as it arrived rather than routed to the DLQ. The general rule that an `UNKNOWN` enum symbol dead-letters ([conventions/kafka-events.md § 2](../../conventions/kafka-events.md#schema-registry)) is stated for a consumer about to write the symbol into the Postgres enum column it mirrors, where the column rejects it and the insert fails. This consumer writes no Postgres row: it stores the masked payload verbatim in a schemaless document, where an unrecognised symbol is legible evidence instead of a failed write. Dead-lettering would discard the only record that the list changed, which is the accountability this collection exists for — so both `UNKNOWN`s are recorded, and both mean the same thing to a reader, that the producer was ahead of this consumer's schema when the document was written. Consumers that do persist `enforcement` into `admin.keyword_blocklist.enforcement` follow the general rule unchanged.

**Adding a term flags nothing retroactively.** A new term applies at the next listing-time scan and no consumer of this topic rescans the catalogue; there is no rescan job in V1 and none is to be added because this topic exists ([cleanup-jobs.md](cleanup-jobs.md)). The documents here answer *who changed the list and when*, which is what was previously recorded nowhere — not *which listings a term would have caught*.

**`STOCK_ADJUSTED` is the one action here that is not an admin or credential action.** It is written from `inventory.changed` when the change originated with a seller — `payload.change_reason` of `MANUAL_UPDATE` for a single edit or `BULK_UPDATE` for a CSV import — with `actor_role: 'SELLER'`, `entity_type: 'OFFER'` and `entity_id` the `offer_id` the stock row is keyed on. It sits in this collection rather than in `activity_events` because PostgreSQL keeps no `stock_adjustment` table: the justification for not having one is that a disputed quantity stays reconcilable from the event trail, and a trail that expires in ninety days does not deliver that. `decision_reason` carries `payload.adjustment_reason`, the free-text reason the seller typed on the inline edit — the same projection every other action in this collection makes, so one query returns the stated reason for a suspension and for a stock correction alike. It is `null` on the `BULK_UPDATE` path, which collects no reason because `BULK_UPDATE` is self-describing, and the value is written **unmasked**: it is the operator's own prose about their own stock, not a secret. The remaining four `change_reason` values are consumer-applied and stay in [`activity_events`](#activity-events).

**Indexes**
```javascript
db.audit_logs.createIndex({ event_id: 1 }, { unique: true })
db.audit_logs.createIndex({ entity_id: 1, occurred_at: -1 })
db.audit_logs.createIndex({ event_type: 1, occurred_at: -1 })
db.audit_logs.createIndex({ actor_id: 1, occurred_at: -1 })
db.audit_logs.createIndex({ correlation_id: 1 })
db.audit_logs.createIndex({ occurred_at: 1 }, { expireAfterSeconds: 63072000 }) // 2-year TTL
```

**Retention — 2 years.** These are accountability records for decisions a person made about another person's account or listing, or about a quantity a buyer relied on: a KYC rejection, a suspension, a removal, a stock correction. The window is set by how long the platform must be able to answer "who decided this, and on what grounds" after the fact, not by any TTL of the underlying row — the `seller.kyc_application` row outlives the audit document. Two years covers a full dispute-and-review cycle with margin; nothing in Phase 1 reads these documents on a hot path, so the storage cost is the only cost.

---

<a id="activity-events"></a>
## 2. `activity_events`

Domain lifecycle events. Answers: *what happened to this order/product/offer.*

| Field | Type | Notes |
|---|---|---|
| `_id` | UUID (UUIDv7, BinData subtype 4) | |
| `event_id` | UUID (BinData subtype 4) | envelope `event_id`; unique index — idempotency key |
| `event_type` | string | indexed |
| `event_version` | int | envelope field; the payload schema version this document was written under |
| `occurred_at` | Date | indexed |
| `correlation_id` | string | indexed — traces full request flow |
| `entity_type` | `ORDER` \| `FULFILLMENT` \| `PRODUCT` \| `OFFER` \| `INVENTORY` \| `RESERVATION` | |
| `entity_id` | UUID (BinData subtype 4) | indexed — `order_id` / `fulfillment_id` / `product_id` / `offer_id` / `reservation_id` |
| `actor_id` | UUID (BinData subtype 4) \| null | `buyer_id` or `seller_profile_id`; `null` for SYSTEM-initiated events |
| `actor_role` | `BUYER` \| `SELLER` \| `SYSTEM` \| null | |
| `payload` | object | full Kafka payload snapshot, **masked** per [Common document fields](#common-document-fields) |

**This is the canonical `entity_type` → `entity_id` mapping.** The consumer-group rows in [kafka-events.md § 2](kafka-events.md) name the pair per event for legibility and defer to this collection's definition; where the two disagree, this document is the one to follow, and the other is the one to correct. `OFFER` covers `offer.changed` and `listing.soft_deleted`; `INVENTORY` covers `inventory.changed` and `inventory.low_stock`, whose `entity_id` is the `offer_id` the stock row is keyed on; `RESERVATION` covers `inventory.reservation_expired`, whose `entity_id` is the `reservation_id` — not the `offer_id`, which would leave "what happened to this reservation" unanswerable while `inventory.stock_reservation` is the row that changed state.

**The stock trail spans two collections.** PostgreSQL has no `stock_adjustment` table and `inventory.stock` carries no actor or reason columns, so the `inventory.changed` documents are the only account of why a stock row moved. `payload.change_reason` both distinguishes them and decides which collection holds them ([Consumer routing](#consumer-routing)): `MANUAL_UPDATE` and `BULK_UPDATE`, a seller's manual edit and CSV import, go to [`audit_logs`](#audit-logs) as `STOCK_ADJUSTED` and are kept two years; `RESERVATION` for the `reserved_qty` increase a placed fulfillment applies, `SHIPMENT` for the shipment decrement, and `REFUND_RESTORE` and `CANCEL_RESTORE` for the two restoration paths stay here for ninety days ([kafka-events.md](kafka-events.md) is the canonical list of values). The split follows `actor_role`, which is `SELLER` on the two seller-initiated reasons and `SYSTEM` on the four a consumer writes: the four kept here have no person to hold accountable, only a side effect to confirm ran.

**Every `inventory.changed` document is self-sufficient.** `payload.delta` is a required signed integer giving the change to `on_hand_qty` for that one event, carried alongside the three absolute quantities — zero on `RESERVATION`, where only `reserved_qty` moves. It is carried rather than derived because deriving it means diffing against the previous document for the same offer, which has nothing to diff against on the oldest document in a retention window and nothing again across the boundary where the two collections split. The four documents kept here carry `adjustment_reason: null` — the field exists on every `inventory.changed` payload, but only the seller's inline edit collects a value, and those documents are in [`audit_logs`](#audit-logs).

`SHIPMENT` is the reason that gives the on-hand decrement an audit record at all. `on_hand_qty` falls at shipment rather than at reservation, so shipment is the only event in which the physical quantity drops — `fulfillment.delivered` moves no stock and has no `change_reason` of its own, being a status transition on the fulfillment and nothing more, so a delivery produces a lifecycle document and never an `inventory.changed` one. The consumer group that applies the shipment decrement writes PostgreSQL and emits `inventory.changed`, and writes nothing in this document store itself. Because `on_hand_qty` and `reserved_qty` fall together, `available_qty` does not move across a shipment — a reader watching only the available figure would see nothing happen, which is why the payload carries all three quantities plus `delta` and why the document is the trail rather than the stock row. `SHIPMENT` is a new `change_reason` value on an existing topic, not a new topic, so the `platform.audit` group's subscription list is unchanged by it; only the payload branch in [Consumer routing](#consumer-routing) has to place it.

**Indexes**
```javascript
db.activity_events.createIndex({ event_id: 1 }, { unique: true })
db.activity_events.createIndex({ entity_id: 1, occurred_at: -1 })
db.activity_events.createIndex({ actor_id: 1, occurred_at: -1 })
db.activity_events.createIndex({ correlation_id: 1 })
db.activity_events.createIndex({ event_type: 1, occurred_at: -1 })
db.activity_events.createIndex({ occurred_at: 1 }, { expireAfterSeconds: 7776000 }) // 90-day TTL
```

**Retention — 90 days.** This is an operational trail, not an accountability record: its use is reconstructing what happened to one order or offer while the question is still live, and confirming that a consumer's side effect actually ran. 90 days covers the longest Phase 1 order lifecycle (placement through the mock delivery window and the refund window that follows it) plus a debugging buffer, per [conventions/data-lifecycle.md](../../conventions/data-lifecycle.md). The authoritative state of every entity referenced here lives in PostgreSQL and is unaffected by expiry.

---

<a id="pii-access-logs"></a>
## 3. `pii_access_logs`

Reads of another person's personal data. Answers: *who read this buyer's shipping address, and when.*

NFR-09 requires PII access to be logged. Three Phase 1 reads qualify: a seller opening the order detail view, which shows the buyer's full unmasked shipping address (US-S-05b, `user-stories/seller.md`); an admin opening a KYC document during review (BRD §8 NFR-09); and an admin opening a single seller's detail page, which returns that seller's tax ID in full.

**One record per disclosure, which is why the seller *list* returns no tax ID.** The detail read is the only place a tax ID is disclosed, so one `pii.accessed` row per call to that endpoint is a complete account of who has seen it. Were the paginated list to return the field, honesty would require a record per row per page load, and the collection would fill with rows nobody can act on. Searching by `tax_id` writes no record either: the admin is matching a value they already hold, and with the list field gone the search discloses none back.

The KYC read is narrow by construction: the bucket is private, the only read path is a presigned URL issued to an authenticated ADMIN, and the document downloads rather than rendering inline. V1 does not scan those uploads for malware; that accepted risk and its V2 remedy are recorded in [docker-compose-topology.md](docker-compose-topology.md) and in the upload endpoint's own spec, not here. What this collection contributes is that every issue of such a URL is attributable to one admin at one time.

**Fed by events, like every other collection here.** The request handler that serves the address writes an outbox row in the transaction that serves it; the `platform.audit` consumer writes this document from `pii.accessed`. It is not written synchronously from the handler — that would put a second store's availability on the read path of an order detail page, and would produce access records for requests that failed after the write.

| Field | Type | Notes |
|---|---|---|
| `_id` | UUID (UUIDv7, BinData subtype 4) | |
| `event_id` | UUID (BinData subtype 4) | envelope `event_id`; unique index — idempotency key |
| `event_type` | string | `pii.accessed` |
| `event_version` | int | envelope field; the payload schema version this document was written under |
| `occurred_at` | Date | indexed — the moment the data was read |
| `correlation_id` | string | indexed — ties the access to the HTTP request that performed it, and so to its log lines |
| `resource_type` | `BUYER_ADDRESS` \| `KYC_DOCUMENT` \| `SELLER_TAX_ID` | |
| `resource_id` | UUID (BinData subtype 4) | the `fulfillment_id` whose shipping snapshot was read, the `kyc_application_id`, or the `seller_profile_id` whose tax ID was returned |
| `subject_user_id` | UUID (BinData subtype 4) | indexed — the person the data is about |
| `accessor_user_id` | UUID (BinData subtype 4) | indexed — the person who read it |
| `accessor_role` | `SELLER` \| `ADMIN` | |
| `payload` | object | full Kafka payload snapshot, **masked** per [Common document fields](#common-document-fields). the disclosed value itself — address or tax ID — is never copied into the document; the record is *that* it was read, by whom. `tax_id` is in `DEFAULT_SENSITIVE_KEYS`, so masking would catch it even if a producer put it there |

**Indexes**
```javascript
db.pii_access_logs.createIndex({ event_id: 1 }, { unique: true })
db.pii_access_logs.createIndex({ subject_user_id: 1, occurred_at: -1 })
db.pii_access_logs.createIndex({ accessor_user_id: 1, occurred_at: -1 })
db.pii_access_logs.createIndex({ resource_type: 1, resource_id: 1, occurred_at: -1 })
db.pii_access_logs.createIndex({ correlation_id: 1 })
db.pii_access_logs.createIndex({ occurred_at: 1 }, { expireAfterSeconds: 63072000 }) // 2-year TTL
```

`{ subject_user_id: 1, occurred_at: -1 }` is the index that answers the question NFR-09 exists to answer — *who read this buyer's address* — as a single indexed range scan per subject. `{ accessor_user_id: 1, occurred_at: -1 }` answers its mirror, *what did this seller read*, which is how bulk harvesting is spotted.

**Retention — 2 years.** Same class of record as `audit_logs`, and set to the same window for the same reason: a PII access complaint arrives long after the access, and a subject-access request must be answerable for the whole period the platform claims to log. A shorter window than `audit_logs` would leave decisions auditable while the data reads behind them were not.

---

<a id="ttl-ownership"></a>
## TTL ownership

Every collection above is expired by its own MongoDB TTL index, listed with the collection. **No scheduled job in [cleanup-jobs.md](cleanup-jobs.md) deletes from any of these collections** — a job doing the same work would race the TTL monitor, duplicate a retention rule in two places, and let the two drift. The TTL index is the single retention mechanism for MongoDB; `cleanup-jobs.md` covers PostgreSQL only.
