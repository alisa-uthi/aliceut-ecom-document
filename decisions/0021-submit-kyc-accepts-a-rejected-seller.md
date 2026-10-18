# ADR-0021: `POST /seller/kyc` accepts a new application from a seller whose latest one was `REJECTED`

**Status:** Accepted
**Date:** 2026-10-18
**Affects:** `phase-1/technical-design/api-design/seller.md` (Submit KYC application, Resubmit KYC application, DB Mapping, endpoint index), `phase-1/technical-design/data-model-erd.md` (`kyc_application`), `phase-1/requirements/user-stories/seller.md` (US-S-01), `phase-1/technical-design/spec-compliance.md` (the `POST /seller/kyc` entry, closed by the lead)
**Implemented by:** aliceut-ecom-backend (PR number below once opened); no frontend change

## Context

seller.md answered `409` from `POST /seller/kyc` for a `PENDING`, `UNDER_REVIEW`
or `APPROVED` latest application and sent a rejected seller to
`POST /seller/kyc/resubmit`. The sequence listed no `REJECTED` branch, while
backend#40 answered `409` with a pointer to the resubmit endpoint, so spec and
code disagreed and the gap sat in `spec-compliance.md`. The user decided on
2026-10-18 that a rejected seller may submit a new application through
`POST /seller/kyc` itself. `GET /seller/kyc` already derives `isResubmission`
from `supersedes_application_id` and `priorRejectionReason` from the superseded
row, so the read side needs nothing new.

## Decision

`POST /seller/kyc` inserts a new application when the seller has none **or the
latest is `REJECTED`**. In the rejected case it behaves exactly as
`POST /seller/kyc/resubmit` does: the new row's `supersedes_application_id`
points at the rejected row (which is left untouched), `seller_profile.kyc_status`
returns to `PENDING_KYC` in the same transaction, and `seller.kyc.submitted` is
published with `is_resubmission: true`, `prior_application_id` and
`prior_rejection_date`, keyed on the seller profile. `GET /seller/kyc` therefore
reports `isResubmission: true` and the prior reason for either route. The `409`
remains for a `PENDING`, `UNDER_REVIEW` or `APPROVED` latest application, and
no longer points at `/resubmit`. The response is the first-submission shape
(`applicationId`, `sellerProfileId`, `status`, `kycStatus`, `submittedAt`).

`POST /seller/kyc/resubmit` is **kept unchanged** (SELLER, not suspended;
`409` unless the latest application is `REJECTED`): removing it would break
existing clients for no gain. The two endpoints share one insert path in the
backend, so they cannot diverge. The tolerated difference is the guard: `POST
/seller/kyc` stays JWT + SELLER with no suspension check. A suspension requires
`kyc_status = APPROVED`, so a suspended seller never has a `REJECTED` latest
application and the difference is unreachable.

## Consequences

**The seller app is unaffected.** The seller app already submits
through `POST /seller/kyc` for every state and never called `/resubmit`; after
this change its rejected-seller form works without a `409`.

**Two endpoints now cover the rejected case.** That is redundancy, accepted
for compatibility; a later ADR can deprecate `/resubmit`.

**The data model, event schema and admin queue are unchanged.** The
supersedes chain, `is_resubmission` and the "Resubmit" badge derive from the
inserted row, not from the route.

## Alternatives considered

**Delete `/resubmit`.** Rejected: nothing requires it, and it is an API break.

**Keep the `409` and route the seller app to `/resubmit`.** Rejected by the
user's decision; it also left the first endpoint unable to submit the form the
seller is looking at.
