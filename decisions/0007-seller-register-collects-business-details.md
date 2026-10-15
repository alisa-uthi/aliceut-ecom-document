# ADR-0007: `POST /seller/register` collects the business details the seller profile requires

**Status:** Accepted
**Date:** 2026-10-15
**Affects:** `phase-1/technical-design/api-design/seller.md` (§ DB Mapping, § Register as seller, § Submit KYC application), `phase-1/ui-design/seller-portal.md` (§ Screen 2 — Seller Register), `phase-1/requirements/user-stories/seller.md` (US-S-01 Step 1)
**Implemented by:** aliceut-ecom-document#153, aliceut-ecom-backend#45, aliceut-ecom-frontend#20

## Context

`seller.md § Register as seller` designed registration as account-only: the
body was `{ email, password, fullName }`, and both branches of the sequence
inserted the seller profile with `business_name=NULL, tax_id=NULL` and no
address at all. The business details were to arrive one step later with
`POST /seller/kyc`, whose sequence `UPDATE`s `business_name` and `tax_id` on a
profile it assumes exists.

The schema refuses that insert. Migration `0007_seller_schema` — and the ERD
(`seller.seller_profile`: `business_name` required, `tax_id` required, first
address line required) — makes `business_name`, `tax_id`, `address_line_1`,
`city`, `postal_code` and `country_code` `NOT NULL`. The designed register
could not run.

The code worked around it in two places. `POST /seller/register` created no
profile at all and returned only `{ userId }`, with no session; and
`POST /seller/kyc` created the profile itself when none existed
(`createProfileUntilRegisterDoes` in `seller-kyc.service.ts`), pulling the
required address columns out of the free-form `submittedData` JSON. This was
item #5 in `spec-compliance.md`, together with register's other gaps: no
password check when linking an existing account, and an uncatalogued
`platform.seller.registered` event.

The same sequence also inserted `identity.user` with `account_type=NULL`.
`identity.user.account_type` is `NOT NULL` too, and US-S-01 already says a new
seller account is `account_type = 'B2C'`.

## Decision

The user chose to change the spec, not the schema. `POST /seller/register`
requires, besides `email`, `password` and `fullName`:

- `businessName` (1–200 chars) and `taxId` (1–50 chars), and
- `businessAddress`, an object with the fields of `PATCH /seller/profile`
  (ADR-0006): `addressLine1` (required), `addressLine2` (optional, nullable),
  `city` (required), `stateRegion` (optional, nullable), `postalCode`
  (required), `countryCode` (required, ISO 3166-1 alpha-2).

These are required on both paths, new account and linked account, because
both insert the profile. Every `NOT NULL` column of `seller.seller_profile`
gets its value from the request, and the schema stays as it is.

`seller.md § Register as seller` now carries the new request body, a
field-to-column table, and a sequence whose `INSERT seller.seller_profile`
names every column it writes. The sequence runs in one transaction from the
account lookup (`FOR UPDATE`) to the refresh-session insert. It shows the
`401` / `409 PASSWORD_REQUIRED_FOR_LINK` branches in the standard error shape,
and it inserts `identity.user` with `account_type='B2C'`, as US-S-01 says.

Two further rules follow from register now opening a session. **A linked
account that is `SUSPENDED` or `BANNED` is `403 Account suspended`**, the gate
`POST /auth/login` applies (auth.md § Login (local)). Without it, registration would
hand a session to an account that login refuses. **No event is emitted**: the
event catalogue (`kafka-events.md`) has no registration topic and the sequence
never had one, so `platform.seller.registered` is dropped and nothing replaces
it.

`POST /seller/kyc` no longer creates a profile. An account with no profile
gets `404`, the same as `POST /seller/kyc/resubmit`. Its sequence is
unchanged: it still writes `business_name` and `tax_id` from the application,
so a seller can correct them at KYC time. `seller-portal.md § Screen 2` adds a
business-details section to the register form, and US-S-01 Step 1 lists the
new fields.

## Consequences

**Registration is a longer form.** A prospective seller has to enter a legal
business name, tax ID and business address before they have an account, where
before they gave only email, password and name. The KYC form still asks for
business name, tax ID and country, so the seller types them twice. The KYC
step could later prefill from `GET /seller/profile`. That is a UI change and
needs no ADR, but `GET /seller/profile` does not return the address yet (see
ADR-0006, Consequences).

**The seller profile exists from the first request.** Every `SELLER` account
created from now on has a profile with valid columns. The KYC fallback and its
`submittedData` address parsing are deleted. Without that, the
`seller_profile` address would have had two writers with different validation.

**Accounts registered before this change** hold the `SELLER` role but no
profile. `POST /seller/kyc` now answers them `404`, and registering again is
`409` only when a profile exists, so such an account can call
`POST /seller/register` again (it verifies the password) to create its
profile. No migration is needed.

**Breaking change for clients.** The request gains required fields. The
response changes from `{ data: { userId } }` to the designed
`{ data: { accessToken, sellerProfileId, user, kycStatus, nextStep } }`, and a
refresh cookie is set. The OpenAPI spec and the generated client are
regenerated, and the seller portal's register form and session handling change
in the same pass.

**The refresh cookie is auth's cookie.** Register sets the cookie
`POST /auth/login` sets, with the same name, attributes and path, so
`POST /auth/refresh` can rotate it. auth.md and this document show it as
`refreshToken` with `SameSite=Strict`. The running auth routes use
`refresh_token` with `SameSite=Lax`. That divergence belongs to the auth
routes and is out of scope here; it is raised for the `spec-compliance.md`
tracker.

## Alternatives considered

**Relax the schema: make `business_name`, `tax_id` and the address columns
nullable until KYC.** The design as written would then run. Rejected by the
user. Every reader of the profile (invoices, fulfilment
`seller_name_snapshot`, the admin seller list) would have to handle a seller
with no name, and the moment a profile becomes complete would turn into an
implicit state that no column records.

**Keep creating the profile at KYC time (the shipped workaround).** Register
would stay account-only. Rejected: the address columns would keep coming from
untyped `submittedData` JSON, and the seller session step 2 needs would have
to come from a separate login, because register cannot issue profile claims
for a profile that does not exist.

**Insert placeholder values (`''`) at register and fill them at KYC.** This
satisfies `NOT NULL` in form only, and every downstream reader gets an empty
string it cannot tell apart from real data.
