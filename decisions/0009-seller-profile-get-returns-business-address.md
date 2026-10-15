# ADR-0009: `GET /seller/profile` returns the business address

**Status:** Accepted
**Date:** 2026-10-15
**Affects:** `phase-1/technical-design/api-design/seller.md` (§ Get seller profile, § Update seller profile, § DB Mapping)
**Implemented by:** aliceut-ecom-backend#48

## Context

`PATCH /seller/profile` writes the business address to the six
`seller.seller_profile` columns (ADR-0006), and `POST /seller/register`
fills the same columns from the request (ADR-0007). But the `GET
/seller/profile` response in `seller.md` lists only `id`, `businessName`,
`kycStatus`, the suspension fields, `rejectionReason` and `createdAt`. The
`PATCH` response is defined as "same shape as `GET`". So no endpoint returns
the address a seller entered. A seller who wants to fix one field cannot see
the current value, and the KYC form cannot prefill the business details it
asks for a second time.

ADR-0006 recorded this gap under Consequences and left it open. ADR-0007
noted that prefilling the KYC step needs it. `spec-compliance.md` lists it
as a spec gap under entry 1 (response models) and entry 3 (the KYC form asks
for the same fields again). The backend follows the design and leaves the
address out.

## Decision

The `GET /seller/profile` response, and so the `PATCH /seller/profile`
response, carries `businessAddress`. It has the same six fields `PATCH`
accepts, with the same names (ADR-0006): `addressLine1`, `addressLine2`
(nullable), `city`, `stateRegion` (nullable), `postalCode` and `countryCode`
(ISO 3166-1 alpha-2). Each field is read from its own column. The object is
always present, because every `NOT NULL` address column has a value from
registration on (ADR-0007). `seller.md § Get seller profile` now shows the
field in the response body and in the sequence's final arrow.
`§ Update seller profile` shows it in its sequence's final arrow, and the
DB Mapping row names the columns the read selects.

`taxId` is not returned. It is not an editable profile field (ADR-0006), and
this decision covers only what `PATCH` can write.

## Consequences

The address can be read back. The seller portal can show the current address
in an edit form and prefill the KYC form's business name and country from
the profile.

The response is bigger and carries business PII on every profile read,
including the locked dashboard's read for a suspended seller. This is the
seller's own data, behind the seller's own token, so it needs no extra
access control or `pii.accessed` audit. The buyer address on
`GET /seller/orders/:fulfillmentId` is different: that is another person's
data.

This is an additive change for clients. The regenerated OpenAPI spec and the
frontend's generated client gain the `businessAddress` property, and no
existing field changes.

If more profile fields become editable later, the request and the response
have to change together. This ADR makes them match, and any later change
should keep them matching.

## Alternatives considered

**Keep the gap.** The design stays as it is, and the seller still cannot see
the address they entered. ADR-0006 and ADR-0007 both name the gap as a
problem, so keeping it was not an option.

**Return the six fields at the top level of `data`.** Also workable, but
then the response would differ from the `businessAddress` object that
`PATCH` and `POST /seller/register` take. A client would have to map one
shape to the other to edit the address.

**A separate `GET /seller/profile/address` endpoint.** Adds an operation,
a guard entry and a client call for six columns of the row `GET
/seller/profile` already reads.
