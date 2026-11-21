# ADR-0034: Avro envelope fields have no defaults

**Status:** Accepted  
**Date:** 2026-11-21  
**Affects:** `phase-1/technical-design/kafka-events.md` (the 29 Avro schemas), `libs/contracts/avro/*.avsc`  
**Implemented by:** aliceut-ecom-backend (`libs/contracts`)  

## Context

`conventions/kafka-events.md` § 1 defines the envelope with no defaults on any
field. The event catalogue added `"default": "<topic>"` to `event_type` and
`"default": 1` to `event_version` in all 29 schemas. The two documents disagreed,
found while the schemas were committed and registered.

## Decision

The envelope fields (`event_id`, `event_type`, `event_version`, `occurred_at`,
`correlation_id`, `payload`) carry no `default`. The two defaults are removed
from every schema in the catalogue. A producer must set every envelope field.

## Consequences

A field with a default is optional to a writer: a producer that forgets
`event_type` or `event_version` would still serialize, and a default such as
`"seller.kyc.submitted"` is wrong on every other topic. The outbox row always
sets both (`NOT NULL` columns), so no producer needs the default. Removing a
default is a BACKWARD-compatible change in Avro, so subjects already registered
accept the new version. The schemas must be re-registered, and the 29 files in
`libs/contracts/avro` change.

## Alternatives considered

- **Keep the catalogue's defaults.** Lets an unset field serialize silently.
- **Add defaults to the convention.** Spreads the same hazard to every future event.
