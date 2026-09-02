# Observability Conventions

**Status:** Draft  
**Source of truth:** [BRD v1.1](../phase-1/requirements/BRD.md)

---

## Summary

| Section | Description |
|---|---|
| [Stack](#stack) | Collector → stores → Grafana |
| [NestJS Logger](#nestjs-logger) | `nestjs-pino` setup, sensitive field masking, outgoing HTTP |
| [Log Envelope](#log-envelope) | Mandatory fields on every log line |
| [Correlation ID](#correlation-id) | Propagation across HTTP → Kafka → async context |
| [Alloy Config](#alloy-config) | Grafana Alloy collector configuration |
| [docker-compose](#docker-compose) | Service definitions |
| [E2E Testing](#e2e-testing) | Playwright CI/CD correlation strategy |

---

<a id="stack"></a>
## 1. Stack

```
NestJS services (structured JSON → stdout)
         ↓
  Grafana Alloy           — unified collector: logs + metrics + traces
    ├──→ Loki             — log aggregation
    ├──→ Prometheus        — metrics scrape
    └──→ Grafana Tempo     — distributed traces (wire up in Phase 2; reserve fields now)
         ↓
     Grafana              — dashboards: LogQL + PromQL + TraceQL
```

Single query plane: correlate a Loki log line to a Tempo trace to a Prometheus metric in one Grafana Explore session.

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
// All lowercase — sanitizer normalizes with key.toLowerCase().
const DEFAULT_SENSITIVE_KEYS = [
  'password', 'newpassword', 'currentpassword', 'passwordhash',
  'token', 'accesstoken', 'refreshtoken', 'idtoken',
  'secret', 'apikey', 'privatekey', 'clientsecret',
  'authorization', 'ssn', 'cardnumber', 'cvv',
];

export default registerAs('log', () => ({
  sensitiveKeys: process.env.LOG_SENSITIVE_KEYS
    ? process.env.LOG_SENSITIVE_KEYS.split(',').map((k) => k.trim().toLowerCase())
    : DEFAULT_SENSITIVE_KEYS,
  maxBodyLogBytes: parseInt(process.env.LOG_MAX_BODY_BYTES ?? '10000', 10),
}));
```

**`.env` / docker-compose env:**

```dotenv
# Comma-separated, case-insensitive. Overrides the built-in default list entirely.
LOG_SENSITIVE_KEYS=password,newpassword,currentpassword,passwordhash,token,accesstoken,refreshtoken,idtoken,secret,apikey,privatekey,clientsecret,authorization,ssn,cardnumber,cvv

LOG_MAX_BODY_BYTES=10000
```

**To add a new key without rebuilding:**

```bash
# 1. Edit .env — append the new key to LOG_SENSITIVE_KEYS
# 2. Restart only the affected service
docker compose up -d --no-build order-service
```

> **Hot-reload alternative (no restart):** mount a JSON file into the container and watch it with `chokidar`. On file change, rebuild the sanitizer and swap it in the interceptor. More complex — use only if restart downtime is unacceptable (V1 docker-compose: restart is fine).

**Setup (`AppModule`) — `forRootAsync` to inject config:**

```typescript
import { LoggerModule } from 'nestjs-pino';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { buildSanitizer } from './shared/log-sanitizer';
import logConfig from './config/log.config';

LoggerModule.forRootAsync({
  imports: [ConfigModule.forFeature(logConfig)],
  inject: [ConfigService],
  useFactory: (config: ConfigService) => {
    const sensitiveKeys = new Set<string>(config.get<string[]>('log.sensitiveKeys', []));
    const maxBytes = config.get<number>('log.maxBodyLogBytes', 10_000);
    const sanitize = buildSanitizer(sensitiveKeys, maxBytes);

    return {
      pinoHttp: {
        autoLogging: true,
        quietReqLogger: false,
        genReqId: (req) => req.headers['x-correlation-id'] ?? uuidv7(),
        customProps: (req) => ({
          correlationId: req.id,
          service: process.env.SERVICE_NAME,
        }),
        serializers: {
          req: (req) => ({
            method: req.method,
            url: req.url,
            body: req.raw?.body ? sanitize(req.raw.body) : undefined,
          }),
          // res body captured via LoggingInterceptor — stream consumed before this runs
        },
        redact: {
          paths: [
            'req.headers.authorization',
            'req.headers.cookie',
            'req.headers["x-api-key"]',
          ],
          censor: '[Redacted]',
        },
        transport: process.env.NODE_ENV === 'development'
          ? { target: 'pino-pretty', options: { colorize: true } }
          : undefined,
        level: process.env.LOG_LEVEL ?? 'info',
      },
    };
  },
})
```

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
    this.logger.log('Placing order', { orderId: dto.id, buyerId: dto.buyerId });
  }
}
```

### Sensitive field masking

Two-layer approach: pino `redact` for headers (fast path at serialization), `sanitizeBody()` for request/response bodies (recursive, catches any depth).

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
 * Keys in sensitiveKeys must be lowercase — matching is case-insensitive via
 * key.toLowerCase(), so 'Password', 'PASSWORD', and 'password' all redact.
 */
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
      if (key !== '' && sensitiveKeys.has(key.toLowerCase())) return '[Redacted]';
      return value;
    });
  };
}
```

- **Case-insensitive:** `key.toLowerCase()` normalizes before lookup — `Password`, `PASSWORD`, `accessToken`, `AccessToken` all redact if the lowercase form is in the config set.
- **Recursive:** JSON replacer visits every node at every depth — no nested object escapes.
- **Size guard:** bodies over `maxBodyLogBytes` replaced with `{ _truncated: true, _bytes: N }` — protects against logging multipart uploads or large payloads.
- **Root key guard:** `key !== ''` skips the root `''` key emitted by `JSON.parse` for the top-level value.

**Response body — `LoggingInterceptor`:**

pino-http cannot access the response body (stream already consumed). Capture it in a NestJS interceptor registered globally. Injects `ConfigService` to use the same sanitizer config.

```typescript
// shared/logging.interceptor.ts
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly sanitize: (body: unknown) => unknown;

  constructor(
    private readonly logger: Logger,
    private readonly config: ConfigService,
  ) {
    const sensitiveKeys = new Set<string>(
      this.config.get<string[]>('log.sensitiveKeys', []),
    );
    const maxBytes = this.config.get<number>('log.maxBodyLogBytes', 10_000);
    this.sanitize = buildSanitizer(sensitiveKeys, maxBytes);
  }

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest<Request>();
    const res = context.switchToHttp().getResponse<Response>();

    return next.handle().pipe(
      tap((body) => {
        this.logger.log('Response', {
          direction: 'outgoing',
          method: req.method,
          url: req.url,
          statusCode: res.statusCode,
          correlationId: req.headers['x-correlation-id'],
          body: this.sanitize(body),
        });
      }),
    );
  }
}
```

```typescript
// main.ts — register globally after app.useLogger()
app.useGlobalInterceptors(app.get(LoggingInterceptor));
```

**Dev rules:**

```typescript
// WRONG — logs full object; sanitize() not called on direct logger calls
this.logger.log('User loaded', { user });

// CORRECT — log IDs only; inject and call sanitize() explicitly if you must log an object
this.logger.log('User loaded', { userId: user.id });
this.logger.log('Payload received', { data: this.sanitize(dto) }); // sanitize injected via constructor
```

### Outgoing HTTP — Axios interceptor

`pino-http` only instruments inbound requests. Outgoing calls via `HttpModule` (Axios) are silent by default. Register a module-init interceptor once in a shared module to log outbound calls and forward `X-Correlation-ID`.

```typescript
// shared/http-logging.module.ts
@Module({
  imports: [HttpModule],
  exports: [HttpModule],
})
export class HttpLoggingModule implements OnModuleInit {
  constructor(
    private readonly http: HttpService,
    private readonly logger: Logger,
    private readonly als: AsyncLocalStorage<{ correlationId: string }>,
  ) {}

  onModuleInit() {
    this.http.axiosRef.interceptors.request.use((config) => {
      const { correlationId } = this.als.getStore() ?? {};
      if (correlationId) {
        config.headers['x-correlation-id'] = correlationId;
      }
      this.logger.log('Outgoing request', {
        direction: 'outgoing',
        method: config.method?.toUpperCase(),
        url: config.url,
        correlationId,
      });
      return config;
    });

    this.http.axiosRef.interceptors.response.use(
      (response) => {
        this.logger.log('Outgoing response', {
          direction: 'outgoing',
          status: response.status,
          url: response.config.url,
          correlationId: response.config.headers['x-correlation-id'],
        });
        return response;
      },
      (error: AxiosError) => {
        this.logger.error('Outgoing request failed', {
          direction: 'outgoing',
          status: error.response?.status,
          url: error.config?.url,
          message: error.message,
          correlationId: error.config?.headers['x-correlation-id'],
        });
        return Promise.reject(error);
      },
    );
  }
}
```

**Rules:**
- Always forward `X-Correlation-ID` on outbound calls — propagation is the primary goal, logging is secondary.
- Add `direction: 'outgoing'` field — distinguishes from inbound in Loki queries (`| json | direction = "outgoing"`).
- Never log request/response bodies — may contain PII or large payloads. Log URL, method, status only.
- Import `HttpLoggingModule` instead of `HttpModule` in any feature module that makes outbound HTTP calls.

---

<a id="log-envelope"></a>
## 3. Log Envelope

Every log line emitted to stdout must be valid JSON containing these fields. `nestjs-pino` + `pino-http` emit most automatically; services add domain-specific `context`.

```json
{
  "timestamp": "2026-09-02T12:34:56.789Z",
  "level": "info",
  "service": "order-service",
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
| `service` | Yes | `SERVICE_NAME` env var via `customProps` |
| `module` | Yes | NestJS `Logger(ClassName)` auto |
| `correlationId` | Yes | From `X-Correlation-ID` header or generated at request boundary |
| `requestId` | Yes | Same as `correlationId` for HTTP-initiated flows |
| `userId` | No | Set after JWT decode; `null` for unauthenticated |
| `traceId` / `spanId` | No | Reserved for OpenTelemetry Phase 2 |
| `message` | Yes | Log call |
| `context` | No | Domain-specific structured data |

**Monetary values in logs:** same rule as API — strings, never numbers.

---

<a id="correlation-id"></a>
## 4. Correlation ID Propagation

`correlationId` is the primary key for tracing a user action end-to-end across HTTP, Kafka events, async jobs, and logs.

### HTTP flow

```
Client request
  → sends header: X-Correlation-ID: <uuidv7>   (generated by client if absent)
  → NestJS middleware reads or generates correlationId
  → stored in AsyncLocalStorage (correlation context)
  → pino-http attaches to all log lines for this request
  → response includes X-Correlation-ID header back to client

NestJS → downstream service
  → Axios interceptor reads correlationId from AsyncLocalStorage
  → forwards as X-Correlation-ID on the outbound request
  → downstream service continues the chain identically
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

`correlationId` is a mandatory field in the Kafka event envelope (see [kafka-events.md](./kafka-events.md)). Consumers that write their own logs must propagate this field from the consumed event.

### Async context

Use `AsyncLocalStorage` to carry `correlationId` through non-HTTP async code (scheduled jobs, queue processors) so every log line in that execution context includes it without explicit passing.

---

<a id="alloy-config"></a>
## 5. Grafana Alloy Config

`config/alloy/config.alloy` — minimal V1 config (logs only; metrics and traces added incrementally).

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
    source_labels = ["__meta_docker_compose_service"]
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

<a id="docker-compose"></a>
## 6. docker-compose

```yaml
# observability services — add to docker-compose.yml

  alloy:
    image: grafana/alloy:v1.x
    container_name: aliceut-alloy
    ports:
      - "12345:12345"   # Alloy UI (dev only)
    volumes:
      - ./config/alloy/config.alloy:/etc/alloy/config.alloy:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock
    command: run --server.http.listen-addr=0.0.0.0:12345 /etc/alloy/config.alloy
    depends_on:
      - loki

  loki:
    image: grafana/loki:3.x
    container_name: aliceut-loki
    ports:
      - "3100:3100"
    volumes:
      - loki_data:/loki
    command: -config.file=/etc/loki/local-config.yaml

  prometheus:
    image: prom/prometheus:latest
    container_name: aliceut-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus

  grafana:
    image: grafana/grafana:11.x
    container_name: aliceut-grafana
    ports:
      - "3000:3000"
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true        # dev only — remove in any deployed env
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin      # dev only
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning:ro
    depends_on:
      - loki
      - prometheus

volumes:
  loki_data:
  prometheus_data:
  grafana_data:
```

**Provisioning:** Pre-configure Loki and Prometheus as Grafana datasources in `config/grafana/provisioning/datasources/` so Grafana is query-ready on first boot.

---

<a id="e2e-testing"></a>
## 7. E2E Testing — Playwright CI/CD Correlation

Goal: assert UI state ↔ API response ↔ DB state in a single test with full observability trace.

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
logcli query '{service="order-service"} | json | correlationId="<uuid>"' \
  --from="2026-09-02T10:00:00Z" --to="2026-09-02T10:01:00Z"
```

Or in Grafana Explore:
```logql
{service="order-service"} | json | correlationId = "<uuid>"
```

### CI/CD environment notes

- Run against **local docker-compose** (`NODE_ENV=test`) or a **staging deploy** — same strategy works for both.
- `TEST_DATABASE_URL` and `BASE_URL` set per environment in CI secrets.
- DB assertions are optional per test — use them for critical write paths (orders, payments, KYC) where eventual consistency makes API polling unreliable.
- For Kafka-driven side effects (e.g. email triggered by order event), poll the read-model API or check a test email inbox (Mailpit) rather than asserting DB directly.
