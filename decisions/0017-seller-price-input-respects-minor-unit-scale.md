# ADR-0017: A seller price may not have more decimals than its currency's `minor_unit_scale`

**Status:** Accepted
**Date:** 2026-10-16
**Affects:** `phase-1/technical-design/api-design/seller.md` (Create offer, Add/update offer price, Update offer), `conventions/backend-coding-standards.md` (§ 4.2)
**Implemented by:** aliceut-ecom-backend#69, aliceut-ecom-frontend#32

## Context

Storage keeps every amount at four fractional digits (FR-P-04), and every API
amount renders at its currency's `minor_unit_scale`, half-up (ADR-0008). The
seller endpoints that take a price validated only that the amount is a
positive decimal string, so any currency accepted four digits. A JPY seller
who typed `1000.5` saved `1000.5000` and every buyer saw `1001`; a USD
`9.999` was shown as `10.00`. The seller never saw the price buyers were
charged against, and line totals computed from the stored value disagreed
with the rendered unit price. The spec said nothing on the point;
`spec-compliance.md` entry 1 recorded it.

## Decision

The user chose rejection. A price amount submitted to any seller endpoint
(create offer, add/update offer price, update offer, and any bulk path that
carries a price) may have **at most `minor_unit_scale` fractional digits** for
the offer's currency, counted in the submitted string: JPY takes `"1000"`
only, USD/THB/SGD take `"9.9"` or `"9.90"` but not `"9.999"`, and `"1000.00"`
is rejected for JPY. A violation is `400` in the api-conventions error shape,
with an `errors[]` entry naming the field. The scale comes from
`PricingApplicationService.getCurrencyScale()`, never a hardcoded table. The
seller app validates the same rule before submit. seller.md lists the `400` on
each affected endpoint, and backend-coding-standards § 4.2 states the rule.

## Consequences

**What the seller types is what buyers see** in the offer's own currency,
because the stored amount already sits at the display scale.

**The check cannot live in the DTO decorator alone.** The scale depends on
the offer's currency, which a price-only request does not carry, so the
service validates after loading the offer. Create-offer can validate early
because the request names the currency.

**Existing rows are not touched.** No migration reworks prices already
stored with extra digits; they render half-up as before. Every database was
rebuilt under ADR-0014, so none are expected.

**Converted amounts still use four digits.** FX conversion, cart and order
arithmetic are unaffected; only seller input is constrained.

## Alternatives considered

**Keep accepting four digits.** Rejected by the user: the seller's price and
the buyer's price differ silently.

**Round on input.** Store `1000.5` JPY as `1001`. Rejected: the server would
change a price the seller typed without telling them; a `400` lets the form
say so.
