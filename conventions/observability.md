# Observability Conventions

**Status:** Complete  
**Source of truth:** [BRD v1.4](../phase-1/requirements/BRD.md)

---

## Summary

| Section | Description |
|---|---|
| [Stack](#stack) | Collector → stores → Grafana |
| [NestJS Logger](#nestjs-logger) | `nestjs-pino` setup, sensitive field masking, outgoing HTTP |
| [Log Envelope](#log-envelope) | Mandatory fields on every log line |
| [Correlation ID](#correlation-id) | Propagation across HTTP → Kafka → async context |
| [Alloy Config](#alloy-config) | Grafana Alloy collector configuration |
| [Metrics](#metrics) | Prometheus exposition contract, cardinality, observability service definitions and mounted config |
| [E2E Testing](#e2e-testing) | Playwright CI/CD correlation strategy |

---

<a id="stack"></a>
## 1. Stack

```
NestJS services — api · workers
   │ structured JSON → stdout                 │ Prometheus text on METRICS_PATH
   ↓                                          ↓
Grafana Alloy   — log collector            Prometheus   — scrapes both directly
   ↓                                          │
Loki            — log aggregation             │
   └──────────────────┬───────────────────────┘
                      ↓
                   Grafana   — dashboards: LogQL + PromQL
```

Two pipelines, one query plane: correlate a Loki log line to a Prometheus metric in one Grafana Explore session, joined on `service`. Logs go through Alloy because container stdout has to be discovered, tailed and parsed before it means anything; metrics do not, because a scrape target is already structured — see §6. Grafana Tempo and distributed traces arrive in Phase 2, adding TraceQL to the same plane; the log envelope reserves fields for it now.

**All four services — Alloy, Loki, Prometheus, Grafana — are in the Phase 1 compose file.** They are not a later addition and not optional: the log envelope in §3 and the correlation contract in §4 exist so that these services can answer a question, and a structured log nobody collects answers nothing. Service definitions, pinned images and volumes are in [docker-compose-topology.md](../phase-1/technical-design/docker-compose-topology.md), which owns them; §6 below owns the configuration files they mount.

---

<a id="nestjs-logger"></a>
## 2. NestJS Logger — `nestjs-pino`

**Package:** [`nestjs-pino`](https://github.com/iamolegga/nestjs-pino) (wraps [pino](https://github.com/pinojs/pino)).

**Why pino over winston:**
- Natively structured JSON — zero config needed for Loki label extraction.
- `pino-http` auto-logs every HTTP request/response with request ID and timing.
- Lowest overhead logger in Node.js ecosystem.
- `pino-pretty` for local dev; raw JSON in production (Alloy handles it).

**Config (`config/log.config.ts`):**

Sensitive keys and body size limit come from environment variables — no code change or image rebuild needed to add new keys. Update `.env`, restart the container.

```typescript
// config/log.config.ts
import { registerAs } from '@nestjs/config';

// Fallback list used when LOG_SENSITIVE_KEYS is not set.
// Lowercase, no separators — the sanitizer normalizes with
// key.toLowerCase().replace(/[_-]/g, ''), so 'tax_id', 'taxId' and
// 'TAX-ID' all match the single entry 'taxid'.
const DEFAULT_SENSITIVE_KEYS = [
  'password', 'newpassword', 'currentpassword', 'passwordhash',
  'token', 'accesstoken', 'refreshtoken', 'idtoken',
  'verificationtoken', 'resettoken',
  'secret', 'apikey', 'privatekey', 'clientsecret',
  'authorization', 'cookie', 'ssn', 'cardnumber', 'cvv',
  'taxid',
];

export default registerAs('log', () => ({
  sensitiveKeys: process.env.LOG_SENSITIVE_KEYS
    ? process.env.LOG_SENSITIVE_KEYS.split(',').map((k) => k.trim().toLowerCase())
    : DEFAULT_SENSITIVE_KEYS,
  maxBodyLogBytes: parseInt(process.env.LOG_MAX_BODY_BYTES ?? '4096', 10),
}));
```

**`.env` / docker-compose env:**

```dotenv
# Comma-separated, case- and separator-insensitive. Overrides the built-in default list entirely.
LOG_SENSITIVE_KEYS=password,newpassword,currentpassword,passwordhash,token,accesstoken,refreshtoken,idtoken,verificationtoken,resettoken,secret,apikey,privatekey,clientsecret,authorization,cookie,ssn,cardnumber,cvv,taxid

LOG_MAX_BODY_BYTES=4096
```

`DEFAULT_SENSITIVE_KEYS` is the project-wide masking list, not a logging-only concern. Two other paths cite it:

- The **audit consumer** masks before insert: any Kafka payload key matching this list is written to MongoDB `audit_logs` as `"***"`. This is mandatory — `auth.email_verification_requested` and `auth.password_reset_requested` carry a raw single-use token so the notification consumer can build the email link, and the audit copy must not retain it.
- **`tax_id`** is on the list because seller KYC payloads carry it and MongoDB audit retention is measured in years.

Any override via `LOG_SENSITIVE_KEYS` must keep at minimum `password`, `token`, `authorization`, `cookie`, `taxid`, `secret` and `refreshtoken` — removing one of those is a security regression, not a configuration choice.

**To add a new key without rebuilding:**

```bash
# 1. Edit .env — append the new key to LOG_SENSITIVE_KEYS
# 2. Restart only the affected service
docker compose up -d --no-build api
```

> **Hot-reload alternative (no restart):** mount a JSON file into the container and watch it with `chokidar`. On file change, rebuild the sanitizer and swap it in the interceptor. More complex — use only if restart downtime is unacceptable (V1 docker-compose: restart is fine).

**Setup (`AppModule`) — `forRootAsync` to inject config:**

```typescript
import { LoggerModule } from 'nestjs-pino';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { buildPinoHttpOptions } from './pino-options';
import { logConfig, type LogConfig } from './log.config';

LoggerModule.forRootAsync({
  imports: [ConfigModule.forFeature(logConfig)],
  inject: [ConfigService],
  useFactory: (config: ConfigService) => {
    const log = config.getOrThrow<LogConfig>('log');
    return {
      pinoHttp: buildPinoHttpOptions({
        // Service name, level and NODE_ENV come from the Joi-validated ConfigService, never
        // process.env (backend-coding-standards §6.3). Each app sets its own SERVICE_NAME
        // (`aliceut-api`, `aliceut-workers`); the default lives in that app's Joi schema.
        service: config.getOrThrow<string>('SERVICE_NAME'),
        level: config.getOrThrow<string>('LOG_LEVEL'),
        sensitiveKeys: new Set(log.sensitiveKeys),
        maxBodyLogBytes: log.maxBodyLogBytes,
        pretty: config.get<string>('NODE_ENV') === 'development',
      }),
      renameContext: 'module', // the Nest Logger context name is logged as `module`
    };
  },
})
```

`buildPinoHttpOptions` is the one place the line shape is defined ([ADR-0032](../decisions/0032-one-log-line-per-http-call-with-request-and-response-bodies.md)):

```typescript
// libs/shared/src/logger/pino-options.ts
export function buildPinoHttpOptions(input: PinoOptionsInput): Options {
  const sanitize = buildSanitizer(input.sensitiveKeys, input.maxBodyLogBytes);

  // Flat transport fields plus both bodies. Express, not Fastify: the body is `req.body` (there is
  // no `req.raw`), and the URL is `req.originalUrl`, because `req.url` is rewritten under the
  // global prefix. The response body was left on `res.locals` by LoggingInterceptor (success) or
  // GlobalExceptionFilter (4xx and 5xx). Building the fields must never fail a request.
  const callFields = (req: ExpressLikeRequest, res: ExpressLikeResponse) => {
    try {
      return {
        direction: 'incoming',
        method: req.method,
        url: maskUrl(req.originalUrl ?? req.url, input.sensitiveKeys),
        status: res.statusCode,
        requestBody: req.body ? sanitize(req.body) : undefined,
        responseBody: res.locals?.responseBody,
      };
    } catch {
      return { direction: 'incoming' };
    }
  };

  return {
    autoLogging: true,
    // One line per incoming call, written on response finish. Neither the req nor the res object
    // is bound to any other line, and the finish line is built from flat fields below, so no
    // header (Set-Cookie included) can reach the log.
    quietReqLogger: true,
    quietResLogger: true,
    level: input.level,
    messageKey: 'message', // pino's default is `msg`; the §3 envelope says `message`
    timestamp: (): string => `,"timestamp":"${new Date().toISOString()}"`,
    formatters: { level: (label: string) => ({ level: label }) },
    base: { service: input.service },
    customAttributeKeys: { responseTime: 'durationMs' },
    // Every line, HTTP or not, carries the AsyncLocalStorage correlation context.
    mixin: () => {
      const store = correlationStorage.getStore();
      return {
        correlationId: store?.correlationId ?? null,
        requestId: store?.correlationId ?? null,
        userId: store?.userId ?? null,
      };
    },
    // The correlation middleware is the single entry point; reuse its id when it already ran.
    // A client-supplied id is accepted only when it is a valid UUID of any version (it is copied
    // into platform.outbox_event.correlation_id, a UUID column, data-model-erd.md); a missing or
    // malformed value is replaced by a minted UUIDv7. An unvalidated id would also be echoed back
    // as a response header, so a hostile value must never pass.
    genReqId: (req, res) => {
      const id = correlationStorage.getStore()?.correlationId
        ?? resolveCorrelationId(req.headers['x-correlation-id']);
      req.headers['x-correlation-id'] = id;
      res.setHeader('X-Correlation-ID', id);
      return id;
    },
    customLogLevel: (_req, res, err) => levelForStatus(res.statusCode, err !== undefined),
    customSuccessMessage: (_req, res) =>
      res.statusCode >= 400 ? 'Incoming request failed' : 'Incoming request',
    customErrorMessage: () => 'Incoming request failed',
    // pino-http's default finish objects carry `res` and `err`; replace them with the duration
    // alone so the line is flat. The HTTP fields come from customProps.
    customSuccessObject: (_req, _res, value) => ({ durationMs: value.durationMs }),
    customErrorObject: (_req, _res, _err, value) => ({ durationMs: value.durationMs }),
    customProps: (req, res) => callFields(req, res),
    redact: {
      paths: ['req.headers.authorization', 'req.headers.cookie', 'req.headers["x-api-key"]',
              'res.headers["set-cookie"]'],
      censor: '[Redacted]',
    },
    ...(input.pretty ? { transport: { target: 'pino-pretty', options: { colorize: true } } } : {}),
  };
}

/** Level follows the outcome: info below 400, warn for 4xx, error for 5xx or an error. */
export function levelForStatus(status: number, failed: boolean): 'info' | 'warn' | 'error' {
  if (failed || status >= 500) return 'error';
  return status >= 400 ? 'warn' : 'info';
}
```

`maskUrl` masks the values of sensitive query parameters in the URL (`token`, and the one-time credentials `code`, `state`, `signature`, `sig`, `otp` on top of the configured key list), because the OAuth authorization code and reset tokens travel in query strings and URLs reach the log.

**Replace NestJS built-in logger globally:**

```typescript
// main.ts
import { Logger } from 'nestjs-pino';

const app = await NestFactory.create(AppModule, { bufferLogs: true });
app.useLogger(app.get(Logger));
```

**Usage in services:**

```typescript
import { Logger } from '@nestjs/common';

@Injectable()
export class OrdersService {
  private readonly logger = new Logger(OrdersService.name);

  async place(dto: PlaceOrderDto) {
    // Domain data is always nested under `context` (§3), never spread onto the top level.
    // Pass ONE object: with nestjs-pino an object in the second argument is not merged into the line.
    this.logger.log({ message: 'Placing order', context: { orderId: dto.id, buyerId: dto.buyerId } });
  }
}
```

**Domain fields live under `context`.** Top-level keys are reserved for the §3 envelope (`timestamp`, `level`, `service`, `module`, `correlationId`, `requestId`, `userId`, `message`) and for HTTP call lines (`direction`, `method`, `url`, `status`, `durationMs`, `requestBody`, `responseBody`). A service never adds its own top-level key, so a domain field named `service` or `level` cannot collide with the envelope, and Loki queries address domain data uniformly as `context.orderId`.

### Sensitive field masking

Request and response bodies are always logged. Because bodies may contain PII, credentials, secrets, or large payloads, body logging uses the configured sanitizer before serialization. The sanitizer recursively redacts configured sensitive fields and enforces the configured maximum body size.

Two-layer approach: 
- pino `redact` for headers (fast path at serialization)
- `sanitizeBody()` for request/response bodies, and outgoing HTTP bodies (recursive, catches any depth).

**Layer 1 — pino `redact` (headers):**

| Path | Covers |
|---|---|
| `req.headers.authorization` | Bearer tokens, Basic auth |
| `req.headers.cookie` | Session/refresh token cookies |
| `req.headers["x-api-key"]` | API key headers |

**Layer 2 — `buildSanitizer()` factory (request + response bodies):**

```typescript
// shared/log-sanitizer.ts

/**
 * Returns a sanitize function bound to the provided key set and size limit.
 * Keys in sensitiveKeys must be lowercase with no separators — matching
 * normalizes with normalizeKey(), so 'Password', 'PASSWORD', 'refresh_token'
 * and 'Refresh-Token' all redact.
 */
const normalizeKey = (key: string): string =>
  key.toLowerCase().replace(/[_-]/g, '');

export function buildSanitizer(
  sensitiveKeys: Set<string>,
  maxBodyLogBytes: number,
): (body: unknown) => unknown {
  return function sanitize(body: unknown): unknown {
    if (!body) return undefined;

    const serialized = JSON.stringify(body);
    if (serialized.length > maxBodyLogBytes) {
      return { _truncated: true, _bytes: serialized.length };
    }

    return JSON.parse(serialized, (key, value) => {
      if (key !== '' && sensitiveKeys.has(normalizeKey(key))) return '[Redacted]';
      return value;
    });
  };
}
```

- **Case- and separator-insensitive:** `normalizeKey()` lowercases and strips `_` and `-` before lookup, so `Password`, `PASSWORD`, `accessToken`, `access_token` and `Access-Token` all redact against the single entry `accesstoken`. This matters because HTTP bodies are camelCase while Kafka payloads and DB rows are snake_case, and both pass through this sanitizer.
- **Recursive:** JSON replacer visits every node at every depth — no nested object escapes.
- **Size guard:** bodies over `maxBodyLogBytes` replaced with `{ _truncated: true, _bytes: N }` — protects against logging multipart uploads or large payloads.
- **Root key guard:** `key !== ''` skips the root `''` key emitted by `JSON.parse` for the top-level value.

**Response body — `LoggingInterceptor`:**

pino-http cannot read the response body (the stream is consumed), and it writes the one `Incoming request` line on response finish ([ADR-0032](../decisions/0032-one-log-line-per-http-call-with-request-and-response-bodies.md)). The interceptor therefore does **not** log: it sanitizes the handler's return value and stores it on `res.locals.responseBody`, where the pino `customProps` above picks it up. `GlobalExceptionFilter` does the same for an error body, so a 4xx or 5xx reaches the same line: an error response never reaches the interceptor's `tap`, so without the filter it would be logged with no `responseBody`. Registered globally; injects `ConfigService` to use the same sanitizer config.

```typescript
// shared/logging.interceptor.ts
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly sanitize: Sanitizer;

  constructor(config: ConfigService) {
    // getOrThrow, never a fallback to an empty key list: a missing `log` namespace must fail
    // loudly, not fail open and mask nothing.
    const log = config.getOrThrow<LogConfig>('log');
    this.sanitize = buildSanitizer(new Set(log.sensitiveKeys), log.maxBodyLogBytes);
  }

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const res = context.switchToHttp().getResponse<Response>();
    return next.handle().pipe(
      tap((body) => {
        try {
          res.locals['responseBody'] = this.sanitize(body);
        } catch {
          // Observability is best effort: a logging fault must not turn a success into a failure.
        }
      }),
    );
  }
}
```

```typescript
// main.ts — register globally after app.useLogger()
app.useGlobalInterceptors(app.get(LoggingInterceptor));
```

### Body logging rules

The global HTTP path — one `Incoming request` line from `pino-http` per incoming call, one `Outgoing request` line from `HttpLoggingModule` per outgoing call — already logs and sanitizes every request and response body, so a handler never re-logs one. Direct domain logging carries IDs and the structured fields that matter, not the whole object:

```typescript
// PREFERRED for domain events — avoid duplicating what the HTTP path already logged.
this.logger.log({ message: 'User loaded', context: { userId: user.id } });
```


### Outgoing HTTP — Axios interceptor

`pino-http` only instruments inbound requests. Outgoing calls via `HttpModule` (Axios) are silent by default. Register a module-init interceptor once in a shared module to log outbound calls and forward `X-Correlation-ID`.

```typescript
// libs/shared/src/http/http-logging.module.ts
export const DEFAULT_OUTGOING_TIMEOUT_MS = 10_000; // a stuck dependency must not hold a request open

/** Level follows the outcome: info below 400, warn for 4xx, error for 5xx or no response. */
function levelFor(status: number | undefined): 'log' | 'warn' | 'error' {
  if (status === undefined || status >= 500) return 'error';
  return status >= 400 ? 'warn' : 'log';
}

// Kept apart from the Nest module so it can be tested on a plain Axios instance. Nothing in it
// can throw, and the interceptors never change a call's result or error.
export function attachHttpLogging(
  axios: AxiosInstance,
  logger: LoggerService,
  sanitize: Sanitizer,
  sensitiveKeys: ReadonlySet<string>,
): void {
  const writeLine = (outcome: CallOutcome): void => {
    try {
      const { config, status } = outcome;
      const failed = status === undefined || status >= 400;
      logger[levelFor(status)]?.({
        message: failed ? 'Outgoing request failed' : 'Outgoing request',
        direction: 'outgoing',
        method: config?.method?.toUpperCase(),
        url: config ? describeUrl(config, sensitiveKeys) : undefined, // base + path + params, query masked
        status, // absent when no response arrived (timeout, connection refused)
        durationMs: config ? durationOf(config) : undefined,
        ...(failed ? { context: { error: outcome.error?.message, code: outcome.error?.code } } : {}),
        requestBody: bodyForLog(sanitize, outcome.requestData),
        responseBody: bodyForLog(sanitize, outcome.responseData),
      });
    } catch {
      // Best effort: a logging fault must never change the call.
    }
  };

  // Request side: forward the correlation id and record the start time. Nothing is logged yet.
  axios.interceptors.request.use((config: TimedConfig) => {
    try {
      const correlationId = getCorrelationId(); // AsyncLocalStorage
      if (correlationId !== undefined) config.headers.set('X-Correlation-ID', correlationId);
      config.metadata = { startedAt: Date.now() };
    } catch { /* the call proceeds untouched */ }
    return config;
  });

  axios.interceptors.response.use(
    (response) => {
      // A custom validateStatus can let a 4xx/5xx through here; it is still logged as a failure,
      // with a synthesised error (ERR_BAD_REQUEST for 4xx, ERR_BAD_RESPONSE for 5xx).
      const failed = response.status >= 400;
      writeLine({
        config: response.config, status: response.status,
        requestData: response.config.data, responseData: response.data,
        error: failed ? { message: `Request failed with status code ${response.status}`,
                          code: response.status >= 500 ? 'ERR_BAD_RESPONSE' : 'ERR_BAD_REQUEST' } : undefined,
      });
      return response;
    },
    (error) => {
      writeLine({
        config: error.config, status: error.response?.status,
        requestData: error.config?.data, responseData: error.response?.data,
        error: { message: error.message, code: error.code },
      });
      throw error; // the original error object, untouched
    },
  );
}

// Axios hands interceptors a request body that is already a JSON string once the request has gone
// out. A string has no keys for the sanitiser to mask, so JSON-looking strings are parsed first.
function bodyForLog(sanitize: Sanitizer, body: unknown): unknown { /* ... */ }

@Module({})
export class HttpLoggingModule implements OnModuleInit {
  // A feature module imports HttpLoggingModule.register({ ...axiosDefaults }) instead of HttpModule.
  static register(options: HttpLoggingOptions = {}): DynamicModule {
    return {
      module: HttpLoggingModule,
      imports: [
        ConfigModule.forFeature(logConfig),
        HttpModule.register({ ...options, timeout: options.timeout ?? DEFAULT_OUTGOING_TIMEOUT_MS }),
      ],
      exports: [HttpModule],
    };
  }
  // onModuleInit() calls attachHttpLogging(this.http.axiosRef, this.logger, this.sanitize, this.sensitiveKeys)
}
```

**Rules:**
- Always forward `X-Correlation-ID` on outgoing calls — propagation is the primary goal, logging is secondary.
- One line per outgoing call, written when it finishes, carrying `requestBody` and `responseBody` together, both through `buildSanitizer()` — the same `LOG_SENSITIVE_KEYS` masking and `LOG_MAX_BODY_BYTES` truncation as inbound bodies get. `status` is absent when no response arrived.
- `correlationId` is not repeated in the call: the pino `mixin` adds it to every line from the AsyncLocalStorage context.
- `direction` is `incoming` or `outgoing` and distinguishes the two kinds of call in Loki queries.
- Import `HttpLoggingModule.register({ ... })` instead of `HttpModule` in any feature module that makes outgoing HTTP calls. Options are Axios request defaults; `timeout` defaults to 10 s.
- With no correlation context (a call made outside a request, consumer message or job) the header is **not** injected and no id is minted: scheduled work generates its own by running inside `runWithCorrelation`, so an uncontexted call is a defect worth seeing, not one to hide behind a fresh id.
- Headers are never logged, so `Authorization` and cookies cannot reach the log. A failed call rethrows the original error object, and the logging can never change a call's result.

---

<a id="log-envelope"></a>
## 3. Log Envelope

Every log line emitted to stdout must be valid JSON containing these fields. `nestjs-pino` + `pino-http` emit most automatically; services add domain-specific `context`.

```json
{
  "timestamp": "2026-09-02T12:34:56.789Z",
  "level": "info",
  "service": "aliceut-api",
  "module": "OrdersService",
  "correlationId": "019268ab-0000-7000-8000-000000000001",
  "requestId": "019268ab-0000-7000-8000-000000000001",
  "userId": "019268ab-...",
  "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
  "spanId":  "00f067aa0ba902b7",
  "message": "Order placed",
  "context": {
    "orderId": "...",
    "totalAmount": "199.99",
    "currency": "THB"
  }
}
```

| Field | Required | Source |
|---|---|---|
| `timestamp` | Yes | pino auto |
| `level` | Yes | pino auto |
| `service` | Yes | `SERVICE_NAME` via the validated `ConfigService` (pino `base`); each app has its own value |
| `module` | Yes | NestJS `Logger(ClassName)` auto |
| `correlationId` | Yes | From `X-Correlation-ID` header or generated at request boundary |
| `requestId` | Yes | Same as `correlationId` for HTTP-initiated flows |
| `userId` | No | Set after JWT decode; `null` for unauthenticated |
| `traceId` / `spanId` | No | Reserved for OpenTelemetry Phase 2 |
| `message` | Yes | Log call. pino is configured with `messageKey: 'message'` (its default is `msg`) |
| `context` | No | All domain-specific structured data, nested under this one key — never top-level |
| `direction` | HTTP call lines | `incoming` (a call we receive) or `outgoing` (a call we make) |
| `method`, `url`, `status`, `durationMs` | HTTP call lines | One line per call, written when it finishes; `url` has secrets in the query string masked; `status` is absent on an outgoing call that got no response |
| `requestBody`, `responseBody` | HTTP call lines | Sanitized/truncated bodies. The key `body` is not used ([ADR-0032](../decisions/0032-one-log-line-per-http-call-with-request-and-response-bodies.md)) |

**Monetary values in logs:** same rule as API — strings, never numbers.

---

<a id="correlation-id"></a>
## 4. Correlation ID Propagation

`correlationId` is the primary key for tracing a user action end-to-end across HTTP, Kafka events, async jobs, and logs.

### Contract

Every API endpoint, without exception:

1. **Accepts** an `X-Correlation-ID` request header.
2. **Generates** one (UUIDv7) at the request boundary when the header is absent or empty. A request is never processed without a correlation id.
3. **Propagates** it — through `AsyncLocalStorage` for the whole request, onto outgoing HTTP calls as `X-Correlation-ID`, and into the `correlation_id` field of every Kafka event envelope and `platform.outbox_event` row written during that request.
4. **Echoes** it on the response as `X-Correlation-ID`, on success and error responses alike.
5. **Logs** it as `correlationId` on every log line emitted in that request's context (§3).

Consumers continue the chain: a consumer reads `correlation_id` from the event it is processing and uses it as the `correlationId` of its own log lines and of any event it publishes downstream. A side effect triggered by an HTTP request is therefore traceable from the request through to the message sitting in the Mailpit inbox.

This document governs Phase 1 in full — the correlation contract, the log envelope, the masking rules and the collection stack alike. Each `phase-1/technical-design/api-design/*` document cites this contract rather than restating it.

### HTTP flow

```
Client request
  → sends header: X-Correlation-ID: <uuidv7>   (generated by client if absent)
  → NestJS middleware reads or generates correlationId
  → stored in AsyncLocalStorage (correlation context)
  → pino-http attaches to all log lines for this request
  → one `Incoming request` line is written on response finish, with requestBody and responseBody
    (the response body is handed over by LoggingInterceptor / GlobalExceptionFilter)
  → response includes X-Correlation-ID header back to client

NestJS → downstream service
  → Axios interceptor reads correlationId from AsyncLocalStorage
  → forwards as X-Correlation-ID on the outbound request
  → downstream service continues the chain identically
  → one `Outgoing request` line is written when the call finishes (request + response body)

```

**Middleware:**

```typescript
// correlation.middleware.ts
@Injectable()
export class CorrelationMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const id = (req.headers['x-correlation-id'] as string) ?? uuidv7();
    req.headers['x-correlation-id'] = id;
    res.setHeader('X-Correlation-ID', id);
    next();
  }
}
```

### Kafka flow

`correlation_id` is a mandatory field in the Kafka event envelope, alongside `event_id`, `event_type`, `event_version`, `occurred_at` and `payload` (see [kafka-events.md](./kafka-events.md)). The producer writes the current request's correlation id into the outbox row in the same transaction as the domain change, so the envelope carries it without the relay having to reconstruct anything. Consumers that write their own logs propagate the field from the consumed event.

Kafka event bodies follow the same structured logging and sensitive-field handling conventions when logged, and payload keys are masked against `DEFAULT_SENSITIVE_KEYS` before any event is persisted to MongoDB `audit_logs` (§2).

### Async context

Use `AsyncLocalStorage` to carry `correlationId` through non-HTTP async code (scheduled jobs, queue processors) so every log line in that execution context includes it without explicit passing.

---

<a id="alloy-config"></a>
## 5. Grafana Alloy Config

`config/alloy/config.alloy` — the V1 config. Alloy's job here is logs: discover every compose container, parse the JSON envelope, label it, ship it to Loki. Metrics do not pass through Alloy — Prometheus scrapes the API and workers directly using `config/prometheus/prometheus.yml`. Traces arrive with Tempo in Phase 2 (§1); nothing in this config anticipates them.

```alloy
// Discover all Docker containers
discovery.docker "all" {
  host = "unix:///var/run/docker.sock"
}

// Add service label from Docker container name
discovery.relabel "add_service_label" {
  targets = discovery.docker.all.targets

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "service"
  }

  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_service"]
    target_label  = "compose_service"
  }
}

// Tail logs from discovered containers
loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.relabel.add_service_label.output
  forward_to = [loki.process.parse_json.receiver]
}

// Parse JSON log lines — extract correlationId, level, service as Loki labels
loki.process "parse_json" {
  forward_to = [loki.write.local.receiver]

  stage.json {
    expressions = {
      level         = "level",
      service       = "service",
      correlationId = "correlationId",
    }
  }

  stage.labels {
    values = {
      level         = "",
      service       = "",
    }
  }

  // correlationId kept as structured metadata, not a label (high cardinality)
  stage.structured_metadata {
    values = {
      correlationId = "",
    }
  }
}

loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

**Label cardinality rule:** `level`, `service`, `compose_service` → Loki labels (low cardinality). `correlationId`, `userId`, `orderId` → structured metadata or log line fields. Never index UUIDs as Loki labels.

---

<a id="metrics"></a>
<a id="docker-compose"></a>
## 6. Metrics

**Exposition contract.** Both `api` and `workers` serve Prometheus text-format metrics on `METRICS_PATH` (default `/metrics`), read from the environment like every other path in this document. `workers` has no API surface but serves this route anyway, on its unpublished `PORT_WORKERS` listener alongside its health endpoint — a process whose only job is relaying the outbox and running consumers is precisely the process whose internals are invisible without metrics.

**Prometheus scrapes both services directly.** Metrics do not pass through Alloy: the collector in §5 is logs-only in V1, and putting a metrics pipeline in front of a two-target scrape would add a hop that can fail without adding anything. Alert thresholds over these gauges — the outbox-relay lag rule among them — are owned by [docker-compose-topology.md](../phase-1/technical-design/docker-compose-topology.md), which states the alerts; this document states how the numbers get exposed.

**The metric names are not defined here.** The gauge inventory — names, types and meanings — belongs to [api-design/health.md](../phase-1/technical-design/api-design/health.md), which defines them alongside the health probe that reads the same values. Duplicating the list here would create a second copy to drift, and a metric named in two documents is a metric that will eventually be named differently in two documents. All of them carry the `aliceut_` prefix.

**Cardinality is bounded, and that is a contract rather than a guideline.** A Prometheus time series is created per distinct label combination and retained for the storage window, so a label whose value space is unbounded does not degrade the metric — it degrades the server. No metric is labelled by user id, order id, offer id, product id or correlation id. The only label in V1 is consumer group, whose value set is fixed by the event catalogue and changes only when a consumer group is added. This is the same rule §5 applies to Loki labels, for the same reason: identifiers belong in the log line or in structured metadata, never in an index key.

### Service definitions and mounted config

The `alloy`, `loki`, `prometheus` and `grafana` service definitions — pinned images, ports, volumes, healthchecks, network membership and `depends_on` conditions — live in [docker-compose-topology.md § 6](../phase-1/technical-design/docker-compose-topology.md), which owns them. They are deliberately not reproduced here: two compose fragments for the same four services are two fragments that will disagree, and the one in the topology is the one Docker reads.

What this document owns is the content of the three configuration files those services bind-mount. All three are committed files, not generated ones, and each fails quietly when absent — Docker creates a *directory* where a missing bind-mounted file was expected, so Alloy exits on a parse error, Prometheus reports healthy while scraping nothing, and Grafana renders "No data" on every panel.

**`config/alloy/config.alloy`** — specified in §5 above.

**`config/prometheus/prometheus.yml`** — two scrape targets and nothing else:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: api
    metrics_path: /metrics
    static_configs:
      - targets: ['api:3000']

  - job_name: workers
    metrics_path: /metrics
    static_configs:
      - targets: ['workers:3001']
```

Both targets are container-network addresses, so neither depends on a published port. **The values are literals on purpose:** Prometheus performs no environment-variable substitution in this file, so `PORT_WORKERS` and `METRICS_PATH` cannot be written as `${…}` here the way they are in compose. Changing either variable therefore means editing this file in the same commit, and the defaults above (`3001`, `/metrics`) are the ones the topology declares.

**`config/grafana/provisioning/datasources/datasources.yaml`** — Loki and Prometheus declared so that Grafana is query-ready on first boot, with no manual datasource step:

```yaml
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: true

  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
```

Loki is the default because a log query is the first thing anyone opens Grafana to run. `access: proxy` keeps both connections server-side, so the browser never talks to Loki or Prometheus directly.

**Anonymous access is `Viewer`, never `Admin`.** `GF_AUTH_ANONYMOUS_ENABLED=true` is the point of a development stack — a dashboard should open without a login — but `GF_AUTH_ANONYMOUS_ORG_ROLE` must be `Viewer`. An anonymous Admin on a published port can edit datasources, and a datasource is a credentialed connection to Loki and Prometheus: the exposure is a stranger repointing where the platform's logs are read from, not a defaced dashboard. Editing stays behind `GF_SECURITY_ADMIN_PASSWORD`. Any deployed environment sets `GF_AUTH_ANONYMOUS_ENABLED=false` as well.

---

<a id="e2e-testing"></a>
## 7. E2E Testing — Playwright CI/CD Correlation

**Goal**: assert UI state ↔ API response ↔ DB state in a single test with full observability trace.

### Strategy

Each Playwright test injects a deterministic `correlationId` as a request header. This ID flows through every log line, API response header, and Kafka event for that test action — creating a queryable audit trail.

### Layers of assertion

```
Playwright test
  ├── UI layer       — page.locator() / expect(page).toHaveURL()
  ├── API layer      — page.waitForResponse() / request context
  └── DB layer       — direct Postgres/Mongo query via test fixture (see below)
```

### Injecting correlationId

```typescript
// fixtures/correlation.ts
import { test as base } from '@playwright/test';
import { uuidv7 } from 'uuidv7';

export const test = base.extend({
  correlationId: async ({}, use) => {
    await use(uuidv7());
  },

  page: async ({ page, correlationId }, use) => {
    // Attach correlationId to every outbound request from this test
    await page.route('**/api/**', async (route) => {
      const headers = {
        ...route.request().headers(),
        'x-correlation-id': correlationId,
      };
      await route.continue({ headers });
    });
    await use(page);
  },
});
```

### API response assertion

```typescript
test('place order updates cart and creates order', async ({ page, correlationId }) => {
  // UI action
  await page.goto('/cart');
  await page.getByRole('button', { name: 'Checkout' }).click();

  // Assert API response inline
  const orderResponse = await page.waitForResponse(
    (res) => res.url().includes('/api/orders') && res.status() === 201
  );
  const order = await orderResponse.json();
  expect(order.data.status).toBe('PENDING');
  expect(order.data.correlationId).toBe(correlationId); // API echoes it back

  // Assert UI reflects new state
  await expect(page.getByTestId('cart-count')).toHaveText('0');
});
```

### DB assertion via test fixture

Direct DB connection in tests — scoped to test data only, never touches production rows.

```typescript
// fixtures/db.ts
import { Pool } from 'pg';

export const test = base.extend({
  db: async ({}, use) => {
    const pool = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
    await use(pool);
    await pool.end();
  },
});
```

```typescript
test('order persisted to DB', async ({ page, db, correlationId }) => {
  // ... UI action that places order ...

  // Wait for API, then verify DB state
  await page.waitForResponse((res) => res.url().includes('/api/orders'));

  const { rows } = await db.query(
    `SELECT status FROM orders WHERE correlation_id = $1`,
    [correlationId]
  );
  expect(rows[0].status).toBe('PENDING');
});
```

> **Note:** `correlation_id` column must exist on `orders` (and key domain tables) to support this pattern. Store the originating HTTP `correlationId` at row creation time.

### Post-test log query (optional, debugging)

After a failing test, query Loki directly to retrieve the full server-side trace:

```bash
# LogCLI — fetch all logs for a test's correlationId
logcli query '{service="aliceut-api"} | json | correlationId="<uuid>"' \
  --from="2026-09-02T10:00:00Z" --to="2026-09-02T10:01:00Z"
```

Or in Grafana Explore:
```logql
{service="aliceut-api"} | json | correlationId = "<uuid>"
```

### CI/CD environment notes

- Run against **local docker-compose** (`NODE_ENV=test`) or a **staging deploy** — same strategy works for both.
- `TEST_DATABASE_URL` and `BASE_URL` set per environment in CI secrets.
- DB assertions are optional per test — use them for critical write paths (orders, payments, KYC) where eventual consistency makes API polling unreliable.
- For Kafka-driven side effects (e.g. email triggered by order event), poll the read-model API or read the message out of Mailpit rather than asserting DB directly. Mailpit is a compose service in every environment this suite runs against, with the SMTP port on `1025` and an HTTP API behind the inbox on `8025` — a test can fetch the captured message and assert on its body, so an emailed verification link is assertable rather than assumed.
