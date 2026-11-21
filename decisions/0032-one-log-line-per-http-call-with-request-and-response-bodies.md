# ADR-0032: One log line per HTTP call, incoming and outgoing, with `requestBody` and `responseBody`

**Status:** Accepted  
**Date:** 2026-11-21  
**Affects:** `conventions/observability.md` (§ 2 setup, `LoggingInterceptor`, Outgoing HTTP; § 3 envelope; § 4 flow)  
**Implemented by:** aliceut-ecom-backend (`libs/shared` logger, `GlobalExceptionFilter`, `HttpLoggingModule`)  

## Context

Running the stack and reading the trace in Loki showed that one HTTP call took
two or three log lines: an incoming request logged `request completed` (no
response body) and a separate `Response` line (the response body); an outgoing
call logged `Outgoing request` and `Outgoing response`. To answer "what did this
call send, what came back and how long did it take" a reader joined lines by
hand, and a table of calls could not show a call as one row.

`body` also meant different things on different lines (the request body on one,
the response body on another), and only the failure line used `requestBody` and
`responseBody`. The incoming `req` object, including the request body, was
repeated on every log line of a request, because the pino-http child logger
binds it.

## Decision

**One line per call, written when the call finishes, in the shape of the
existing failure line:**

```json
{
  "message": "Outgoing request failed",
  "direction": "outgoing",
  "method": "POST",
  "url": "https://api.example.com/payments",
  "status": 404,
  "durationMs": 292,
  "context": { "error": "Request failed with status code 404", "code": "ERR_BAD_REQUEST" },
  "requestBody":  { "…": "…" },
  "responseBody": { "…": "…" }
}
```

- **Outgoing** (a call we make through `HttpLoggingModule`): `direction:
  "outgoing"`, message `Outgoing request`, or `Outgoing request failed` when the
  status is 400 or above or no response arrived. `status` is absent when no
  response arrived (timeout, connection refused). `context` carries `error` and
  `code` and appears on a failure only. `Outgoing response` no longer exists.
- **Incoming** (a call we receive): `direction: "incoming"`, message `Incoming
  request`, or `Incoming request failed` at status 400 or above, with the same
  `method`, `url`, `status`, `durationMs`, `requestBody`, `responseBody`.
  pino-http writes it on response finish. The response body is put on
  `res.locals.responseBody` by `LoggingInterceptor` (success) or by
  `GlobalExceptionFilter` (4xx and 5xx) and read when the line is written.
  `request completed`, `request errored` and the separate `Response` line no
  longer exist.
- **Level follows the outcome:** `info` below 400, `warn` for 4xx, `error` for
  5xx and for an outgoing call with no response.
- **`requestBody` and `responseBody` on every call line.** The key `body` is not
  used on any HTTP line. Bodies pass through the sanitizer as before.
- **`status` on both directions**, so one column serves both. The key
  `statusCode` is not used on log lines.
- **`quietReqLogger: true`.** The incoming `req` object is no longer bound to
  every other line of the request; the one `Incoming request` line carries
  `method`, `url` and `requestBody` itself.
- A 5xx still writes the separate operator-diagnosis line (`Server error`, with
  the rate-limited stack). That line is a different kind of record, not a
  second copy of the call.

## Consequences

A call is one row in a table, and a trace in Loki has fewer HTTP lines. The line
is written only when the call finishes, so a request that never finishes
(process killed mid-request) leaves no line, where before the request line
existed; the container's own exit covers that case. The response body must reach
pino-http through the response object, which couples `LoggingInterceptor`,
`GlobalExceptionFilter` and the pino options. Anything querying the old messages
(`request completed`, `Outgoing response`) or the keys `body` and `statusCode`
must change; the starter dashboard is rebuilt on the new shape. "Failed" means a
status of 400 or above for both directions, so a client's 404 on an incoming
call reads as a failed call at `warn` level, not a server fault.

## Alternatives considered

- **Keep separate request and response lines and join them in Grafana.** Works
  only by `correlationId`, which several calls in one request share, so calls
  cannot be told apart.
- **Log the incoming line from the interceptor alone.** Misses requests that
  fail before an interceptor runs, so errors would need a second path anyway.
- **Keep `body` on success lines and `requestBody`/`responseBody` on failures.**
  What the code did; one key with two meanings.
- **`inbound`/`outbound` and `statusCode`.** Cleaner words, but they change
  names the failure line already used and the spec already documents
  (`direction: outgoing`, `status`).
