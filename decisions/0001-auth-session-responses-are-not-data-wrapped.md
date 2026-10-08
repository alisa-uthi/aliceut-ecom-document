# ADR-0001: Auth session responses are not data-wrapped

**Status:** Accepted
**Date:** 2026-10-08
**Affects:** `phase-1/technical-design/api-design/auth.md`, `conventions/api-conventions.md`
**Implemented by:** aliceut-ecom-document#145, aliceut-ecom-backend#22

## Context

`conventions/api-conventions.md` applies a `{data: ...}` envelope to every
response in the API, and `auth.md` specified that envelope for the four session
routes: `POST /auth/register`, `/auth/login`, `/auth/refresh` and
`/auth/oauth/exchange`. It additionally specified a
`"message": "Verification email sent"` field on the registration response.

The implementation has always returned `{accessToken, user}` at the **top
level**, with no envelope and no `message`. The frontend reads that bare shape
in `libs/api-client/src/lib/auth.service.ts` and in all three app-level auth
services and HTTP interceptors.

This surfaced on 2026-10-08 while annotating the OpenAPI payload types: the spec
had to declare one shape or the other, and the two sides of the running system
agreed with each other rather than with the document. The 2026-10-03 contract
drift audit had not caught it, because it compared paths, verbs and guards
rather than response bodies.

## Decision

The four session routes return `{accessToken, user}` at the top level. This is
the API's single documented exception to the response envelope. `auth.md` is
corrected to show the bare shape in its three response examples and its five
sequence-diagram response lines, registration no longer claims a `message`
field, and the exception is stated under the endpoint index so a reader meets it
before the endpoints. The OpenAPI spec declares it as `AuthSessionDto`.

`PATCH /auth/change-password` and every other auth route stay data-wrapped.

## Consequences

The envelope convention now has an exception, which is a real cost: "every
response is wrapped" was a rule a client could rely on without looking, and now
it is a rule with a footnote. Mitigated by keeping the exception to exactly
these four routes, naming the DTO after the exception (`AuthSessionDto`) and
stating it in both the convention and the endpoint document.

Nothing in either repo changes behaviour, so there is no migration and no client
regeneration beyond the spec itself. The alternative would have changed four
live routes plus three frontend apps.

This ADR covers only the session envelope. The six auth routes that returned
`204` where the design specified a message body were fixed in the **code** to
match the design — no ADR, because the spec was right. See
aliceut-ecom-backend#23.

## Alternatives considered

**Wrap the four responses to match the spec.** Rejected: it buys consistency
only, and costs a coordinated change across `register`, `login`, `refresh` and
`oauth/exchange` plus the api-client and the buyer, seller and admin auth
services and interceptors — every one of them a place to get the unwrapping
wrong on a path where failure means nobody can log in.

**Leave the document saying one thing and the code doing another.** Rejected on
the grounds that an undocumented divergence in the auth contract is how the
original drift happened: the spec stopped being trustworthy, so nobody read it,
so it drifted further.

**Keep the `message` field on registration.** Rejected: "Verification email
sent" is implied by the 201 and by the account being unverified. A field that
every client ignores is one more thing to keep true.
