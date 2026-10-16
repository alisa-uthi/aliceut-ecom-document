# ADR-0008: API amounts round half-up to the currency's `minor_unit_scale`

**Status:** Accepted (method renamed `toWire` by [ADR-0018](0018-money-renders-through-towire.md))
**Date:** 2026-10-15
**Affects:** `conventions/backend-coding-standards.md` (§ 3.1 Money value object, § 3.2 Currency scale cache)
**Implemented by:** aliceut-ecom-backend#46

## Context

`backend-coding-standards.md § 3.2` says `minor_unit_scale` "drives display
rounding and `toFixed()` precision", and § 3.1 shows `Money.toJSON(scale)`
calling `this.amount.toFixed(scale)`. Neither section names a rounding mode.
An amount held at storage scale (`NUMERIC(19,4)`) has to lose digits whenever
it is rendered at a smaller scale: `1234.5650` THB at scale 2, or a converted
JPY price such as `1500.5000` at scale 0. Which way the half goes was left to
whatever the library defaulted to.

backend#46 made every API amount render at its currency's `minor_unit_scale`.
It had to pick a mode, and it chose `ROUND_HALF_UP` from `decimal.js`, passed
explicitly in `Money.toJSON`. Half-up is also `decimal.js`'s global default
(`rounding: 4`), so the intermediate `toFixed(4)` calls on the storage and
event paths already rounded the same way without saying so. The choice was
the implementation's, not the design's, and `spec-compliance.md` recorded it
as such.

`decimal.js`'s `ROUND_HALF_UP` sends a tie away from zero, so a negative
amount rounds symmetrically (`-1.005` → `-1.01`). Postgres rounds `NUMERIC`
assignment half away from zero as well, so a value written to a
`NUMERIC(19,4)` column rounds the same way as the application.

## Decision

The user chose half-up. Every monetary amount the API returns is rounded
**half-up (`Decimal.ROUND_HALF_UP`) to the currency's `minor_unit_scale`**,
exactly once, at render time. `Money.toJSON(scale)` passes the mode
explicitly rather than relying on the `decimal.js` default.
`backend-coding-standards.md § 3.1` now shows the explicit mode in
`toJSON`, and § 3.2 states the mode where it says `minor_unit_scale` drives
display rounding. The storage scale (4 dp), FX rates (8 dp) and event payload
amounts (4 dp, kafka-events.md) are unchanged; where those are reduced from a
longer intermediate result they also round half-up.

## Consequences

**The rule is written down.** A buyer seeing `1500.5` JPY rendered as `1501`
is now the specified behaviour, not an accident of a library default, and a
change of mode needs a superseding ADR.

**Half-up carries a small upward bias.** Over many conversions, ties always
move up, so a sum of rendered amounts can drift above the rendered sum. This
is accepted because each API amount is rendered once from an unrounded
`Decimal`, and totals are computed from stored values, not from rendered ones,
so the bias never compounds. Banker's rounding would remove the bias but
surprises buyers and support staff who expect `.5` to round up.

**Nothing changes in code.** backend#46 already implements this mode. No
migration, no client regeneration: the wire format (decimal string at
`minor_unit_scale`) is the same.

**The intermediate `toFixed(4)` calls stay implicit.** They depend on the
`decimal.js` default being half-up. Nothing calls `Decimal.set` today; doing
so would silently change those paths, so a global rounding override is not
allowed.

## Alternatives considered

**Half-even (banker's rounding).** Unbiased over large aggregates and common in
accounting systems. Rejected by the user: the API renders display amounts, not
ledger entries, and buyers read `x.5 → x+1` as the correct result.

**Truncate (round down).** Never overstates a price. Rejected: it understates
every converted amount, which the seller absorbs, and it disagrees with
Postgres's own rounding of stored values.

**Leave the mode unspecified.** Rejected: an unspecified mode is one that a
library upgrade or a stray `Decimal.set` can change without anyone noticing,
and the spec is canonical (decisions/README.md).
