# ADR-0006: `PATCH /seller/profile` writes the business address columns

**Status:** Accepted
**Date:** 2026-10-10
**Affects:** `phase-1/technical-design/api-design/seller.md` (§ Update seller profile, § DB Mapping), `phase-1/technical-design/api-design/search.md` (seller rename sequence note), `phase-1/technical-design/data-model-erd.md` (§ `seller.seller_profile`)
**Implemented by:** aliceut-ecom-backend#36 (column mapping); request-key rename pending, see Consequences

## Context

`seller.md § Update seller profile` designed the body as
`{ businessName?, submittedData? }`, `submittedData` being "business address,
contact, phone", and its sequence wrote
`UPDATE seller.seller_profile SET business_name=?, submitted_data=?`.

`seller.seller_profile` has no `submitted_data` column — not in the ERD and not
in migration `0007_seller_schema`. `submitted_data` is a column of
`seller.kyc_application`: the JSONB a seller typed at application time,
immutable once decided. What `seller_profile` does carry is the business address
of record as typed columns — `address_line_1`, `address_line_2`, `city`,
`state_region`, `postal_code`, `country_code` — and the ERD already states that
invoices read those columns and never the KYC JSONB. There is no phone or
contact column anywhere in the seller schema.

The handler as designed could not run. backend#36 implemented it by mapping
the keys of the `submittedData` object onto the six address columns and
refusing any other key (the global `forbidNonWhitelisted` pipe), leaving the
design and the code disagreeing. This was item #8 in `spec-compliance.md`.

## Decision

`PATCH /seller/profile` accepts `{ businessName?, businessAddress? }`.
`businessAddress` is an object of six optional fields — `addressLine1`,
`addressLine2`, `city`, `stateRegion`, `postalCode`, `countryCode` — each
written to its own `seller.seller_profile` column. An omitted field leaves its
column unchanged; a present field for a `NOT NULL` column must be non-empty;
`addressLine2` and `stateRegion` accept `null` to clear; `countryCode` is
ISO 3166-1 alpha-2. Any other key is a `400`. A body with no fields performs no
write. Phone, contact and registration number are not profile data: they live
in the KYC application and change only by resubmission.

`seller.md` now carries the request schema, a field-to-column table, the
validation rules, and a sequence diagram whose `UPDATE` names only the supplied
columns and no `submitted_data`. The DB Mapping row names the columns. The
`seller.profile_changed` rule is unchanged: emitted only when `business_name`
changes, never for an address edit.

## Consequences

**The request key differs from the code.** backend#36 still names the object
`submittedData`. The column mapping, validation and event behaviour already
match this ADR; the backend needs one rename — the `submittedData` property of
`UpdateSellerProfileDto` and `UpdateSellerProfileInput` to `businessAddress`
(and `SellerProfileSubmittedDataDto` to match) — plus the regenerated OpenAPI
spec and client. No frontend code calls this endpoint yet, so the rename breaks
no consumer.

The rename is the point rather than cosmetics: `submittedData` names the KYC
JSONB in `POST /seller/kyc`, `POST /seller/kyc/resubmit` and the admin KYC
views, and the same key meaning "typed address columns" on one endpoint and
"opaque application JSON" on three others is how the original
`submitted_data` sequence came to be written.

**A seller cannot record a phone number on their profile.** If one is needed
later — for order contact, say — it is a new column, a migration and a new
ADR, not a JSONB catch-all.

**The profile response still omits the address.** `GET /seller/profile` and the
`PATCH` response return `businessName` and status fields only, so a seller
editing the address cannot read the current value back from this API. That gap
predates this ADR and is not changed by it.

## Alternatives considered

**Add a `submitted_data` JSONB column to `seller_profile`, as the sequence
implied.** Rejected by the user: it creates a second, unvalidated copy of the
address beside the typed columns invoices read, with no rule for which wins.

**Keep the `submittedData` wrapper name, matching backend#36 as shipped.** No
code change, but it keeps one key meaning two unrelated things across the
seller API, which is the confusion this decision exists to remove.

**Flatten the address fields to the top level of the body.** Workable, but
`businessAddress` keeps the address a unit, mirrors how the columns are
described in the ERD, and leaves room beside it for non-address profile fields.
