# ADR-0030: The `error` field of an error response is an upper-snake code

**Status:** Accepted  
**Date:** 2026-11-21  
**Affects:** `conventions/api-conventions.md` (Standard Error Shape, HTTP error codes reference), `phase-1/technical-design/api-design/health.md`, `phase-1/technical-design/api-design/orders.md`  
**Implemented by:** aliceut-ecom-backend (`GlobalExceptionFilter`, shared error envelope)  

## Context

The specs disagreed about the `error` field of the error body. The api-conventions
table listed codes (`NOT_FOUND`, `INTERNAL_ERROR`), its own sample showed
`"Bad Request"`, backend-coding-standards § 5.2 emitted `INTERNAL_SERVER_ERROR`,
and the health and orders examples showed `"Service Unavailable"` and
`"Conflict"`. NestJS's own exceptions emit the HTTP reason phrase. The same 404
would therefore read `Not Found` when a handler threw `NotFoundException` and
`NOT_FOUND` when it threw an `AppError`, and a client could not match on the
field. The code review of the sprint-0 backend found the split in the
implementation.

## Decision

`error` is always an upper-snake code, on every error response, whichever
exception produced it. For a response with no `AppError` code it is the HTTP
status name: `BAD_REQUEST`, `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`,
`CONFLICT`, `UNPROCESSABLE`, `TOO_MANY_REQUESTS`, `INTERNAL_SERVER_ERROR`,
`SERVICE_UNAVAILABLE`. For an `AppError` it is the error's own `code`
(`PRODUCT_NOT_FOUND`, `INSUFFICIENT_INVENTORY`). The filter normalises
`HttpException` reason phrases to this form. api-conventions' table lists
`INTERNAL_SERVER_ERROR` in place of `INTERNAL_ERROR`, adds `SERVICE_UNAVAILABLE`,
and its sample shows `BAD_REQUEST`. The health and orders examples are updated.

## Consequences

Clients match on one stable vocabulary and never on a reason phrase. A Nest
`NotFoundException` and an `AppError` mapped to 404 differ only in whether the
code is generic (`NOT_FOUND`) or specific (`PRODUCT_NOT_FOUND`). The generated
Angular client and any frontend error handling written against `"Bad Request"`
strings must use the codes. The filter carries a status-to-code table, which
is one more thing to keep complete.

## Alternatives considered

- **HTTP reason phrases everywhere (`Not Found`).** Matches Nest's default and
  needs no normalising, but phrases are display text, collide with no
  domain-specific code, and `AppError` codes would still need a second field.
- **Keep both forms.** What the specs did; it makes the field unreliable to
  match on.
