# ADR-0018: `Money` renders through `toWire(scale)`, not `toJSON(scale)`

**Status:** Accepted
**Date:** 2026-10-16
**Affects:** `conventions/backend-coding-standards.md` (§ 3.1, § 3.2, § 3.3), ADR-0008 (method name only)
**Implemented by:** aliceut-ecom-backend#69

## Context

backend-coding-standards § 3.1 names the scale-aware renderer
`Money.toJSON(scale: number)`. `JSON.stringify` calls any `toJSON` method it
finds with the property **key** as its argument, so stringifying a `Money` —
directly, or nested in a response or log object — calls
`toFixed("amount")` or `toFixed("")` and either throws or emits the wrong
digits. The name invites exactly the call the method cannot survive.

The § 3.2 refresh snippet had a related flaw: `setInterval(() => void
this.refresh())` discards the promise, so a failed reload is an unhandled
rejection, which crashes Node. The code (backend#46) catches, logs and keeps
the loaded scales. `spec-compliance.md` entry 1 recorded both.

## Decision

The renderer is **`Money.toWire(scale: number): string`**. `Money.toJSON()`
throws, telling the caller to use `toWire` with the currency's scale. Every API amount is still produced by an explicit call with the
currency's scale, half-up (ADR-0008 is unchanged except for the name). § 3.1
and § 3.3 show `toWire`. § 3.2's refresh timer catches a failed reload, logs
it and keeps the scales already loaded.

## Consequences

**Stringifying a `Money` fails loudly.** `JSON.stringify` reaching a `Money`
throws with a message naming `toWire`, so an unrendered amount can never reach
a response or a log silently. A log call that stringifies an object holding a
`Money` throws too; log the rendered string instead.

**Callers change name only.** No wire format, client or migration changes.

**A failed scale reload is survivable.** Scales are ISO 4217 constants, so
serving the previous set until the next refresh is correct.

## Alternatives considered

**Define no `toJSON`.** `JSON.stringify` would emit the private fields as a
plain object. Rejected in implementation: an object where a string amount
belongs is easier to miss than an exception.

**Keep `toJSON` and accept the key argument** (render at storage scale when
the argument is not a number). Rejected: it would emit four-digit amounts
silently whenever a `Money` reached `JSON.stringify`, which FR-P-04 forbids.

**Keep the name and document the trap.** Rejected: the name itself is the
trap.
