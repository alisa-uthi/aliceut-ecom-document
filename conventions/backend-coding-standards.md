# Backend Coding Standards

**Status:** Complete  
**Source of truth:** [BRD v1.2](../phase-1/requirements/BRD.md), [module-architecture](backend-module-architecture.md)

---

## Summary

| Section | Description |
|---------|-------------|
| [1. TypeScript configuration](#1-typescript-configuration) | `tsconfig.json` key settings, path aliases, strictness flags |
| [2. ESLint rules](#2-eslint-rules) | Required rules, money lint, import ordering |
| [3. Money handling code patterns](#3-money-handling-code-patterns) | `Money` value object, `decimal.js`, currency scale cache (DB-sourced) |
| [4. DTO validation patterns](#4-dto-validation-patterns) | `class-validator`, monetary field decorators, whitelist pipe |
| [5. Error handling](#5-error-handling) | `AppError` hierarchy, `GlobalExceptionFilter`, never-throw rules |
| [6. Environment config](#6-environment-config) | `@nestjs/config`, Joi schema, required env var checklist |
| [7. Database query patterns](#7-database-query-patterns) | Repository interface usage, QueryBuilder scope, transaction pattern |
| [8. NestJS-specific patterns](#8-nestjs-specific-patterns) | Scope, globals, interceptor vs guard vs middleware, pipes |
| [9. File naming conventions](#9-file-naming-conventions) | `kebab-case.type.ts` rules, barrel files |
| [10. Code review checklist](#10-code-review-checklist) | Gate criteria before merge |

---

<a id="1-typescript-configuration"></a>
## 1. TypeScript configuration

All NestJS packages (`apps/api`, `apps/workers`, `libs/*`) extend a shared root `tsconfig.base.json`.

### 1.1 Required compiler flags

```jsonc
// tsconfig.base.json
{
  "compilerOptions": {
    "strict": true,               // enables strictNullChecks + noImplicitAny + others
    "strictNullChecks": true,
    "noImplicitAny": true,
    "exactOptionalPropertyTypes": true,  // optional props must be explicitly undefined, not absent
    "noUncheckedIndexedAccess": true,    // array[i] and Record<K,V>[k] return T | undefined
    "noImplicitOverride": true,
    "forceConsistentCasingInFileNames": true,
    "esModuleInterop": true,
    "experimentalDecorators": true,      // required for NestJS / TypeORM decorators
    "emitDecoratorMetadata": true,
    "target": "ES2022",
    "module": "CommonJS",
    "moduleResolution": "node",
    "baseUrl": ".",
    "paths": {
      "@app/*": ["apps/api/src/*"],
      "@workers/*": ["apps/workers/src/*"],
      "@lib/*": ["libs/*"]
    }
  }
}
```

`noUncheckedIndexedAccess` forces explicit `undefined` checks on array reads and object index signatures, which catches off-by-one errors on TypeORM result arrays before runtime.

`exactOptionalPropertyTypes` prevents assigning `{ key: undefined }` where `{}` (absent key) is expected — relevant for partial DTO mapping.

### 1.2 Package-level extends

```jsonc
// apps/api/tsconfig.json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src/**/*"]
}
```

Never set `"strict": false` in a package-level override. If a third-party type requires a workaround, use a `// @ts-expect-error` comment with a justification on the preceding line — not `// @ts-ignore` (the latter silences errors even when the underlying type is fixed).

---

<a id="2-eslint-rules"></a>
## 2. ESLint rules

### 2.1 Base configuration

```jsonc
// .eslintrc.json (root)
{
  "root": true,
  "parser": "@typescript-eslint/parser",
  "parserOptions": { "project": "./tsconfig.base.json" },
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:@typescript-eslint/recommended-requiring-type-checking",
    "plugin:import/recommended",
    "plugin:import/typescript"
  ],
  "plugins": ["@typescript-eslint", "import"],
  "rules": { /* see table below */ }
}
```

### 2.2 Required rules

| Rule | Setting | Reason |
|------|---------|--------|
| `@typescript-eslint/no-floating-promises` | `error` | Unhandled async paths cause silent failures in NestJS middleware chains |
| `@typescript-eslint/no-explicit-any` | `error` | `any` defeats the value of strict mode |
| `@typescript-eslint/explicit-function-return-type` | `error` (public functions) | Makes API surface visible at a glance |
| `no-console` | `error` | Use injected `Logger` / `PinoLogger`; see [observability.md](observability.md) |
| `@typescript-eslint/no-unsafe-assignment` | `error` | Part of `recommended-requiring-type-checking` |
| `no-restricted-syntax` (money lint) | `error` | See §2.3 |
| `import/order` | `error` | See §2.4 |

### 2.3 Money lint rule

Forbid `number` type on any property whose name matches a monetary field pattern. Use targeted AST selectors — the first selector below fires ONLY on monetary-named properties, not all numbers.

```jsonc
{
  "no-restricted-syntax": [
    "error",
    {
      "selector": "PropertyDefinition[key.name=/price|amount|tax|fee|rate/i] > TSTypeAnnotation > TSNumberKeyword",
      "message": "Monetary fields (price/amount/tax/fee/rate) must use 'string' or 'Decimal', not 'number'. See conventions/backend-coding-standards.md §3."
    },
    {
      "selector": "TSPropertySignature[key.name=/price|amount|tax|fee|rate/i] > TSTypeAnnotation > TSNumberKeyword",
      "message": "Monetary fields (price/amount/tax/fee/rate) must use 'string' or 'Decimal', not 'number'. See conventions/backend-coding-standards.md §3."
    }
  ]
}
```

This targets class property definitions and interface property signatures whose name contains monetary keywords. Non-monetary `number` fields are unaffected.

### 2.4 Import ordering

```jsonc
{
  "import/order": ["error", {
    "groups": ["builtin", "external", "internal", ["parent", "sibling", "index"]],
    "pathGroups": [
      { "pattern": "@app/**", "group": "internal" },
      { "pattern": "@lib/**", "group": "internal" },
      { "pattern": "@workers/**", "group": "internal" }
    ],
    "newlines-between": "always",
    "alphabetize": { "order": "asc", "caseInsensitive": true }
  }]
}
```

---

<a id="3-money-handling-code-patterns"></a>
## 3. Money handling code patterns

Money in JSON is always a string. Money in Postgres is `NUMERIC(19,4)`. Money in application code is a `Decimal` instance. Never let a JS `number` touch a monetary value.

See [api-conventions.md](api-conventions.md) §Money for the JSON wire format rule.

### 3.1 Money value object

```typescript
// libs/shared/src/money/money.vo.ts
import Decimal from 'decimal.js';

export class Money {
  readonly amount: Decimal;
  readonly currency: string;

  private constructor(amount: Decimal, currency: string) {
    this.amount = amount;
    this.currency = currency;
  }

  static of(amount: string | Decimal, currency: string): Money {
    return new Money(new Decimal(amount), currency);
  }

  add(other: Money): Money {
    this.assertSameCurrency(other);
    return new Money(this.amount.plus(other.amount), this.currency);
  }

  multiply(factor: string | Decimal): Money {
    return new Money(this.amount.mul(factor), this.currency);
  }

  toJSON(scale = 2): string {
    return this.amount.toFixed(scale);
  }

  private assertSameCurrency(other: Money): void {
    if (this.currency !== other.currency) {
      throw new Error(`Currency mismatch: ${this.currency} vs ${other.currency}`);
    }
  }
}
```

### 3.2 Currency scale cache (DB-sourced)

`minor_unit_scale` drives display rounding and `toFixed()` precision. The authoritative source is `pricing.currency.minor_unit_scale` — **do not hardcode a `CURRENCY_SCALE` constant**. Scale values are ISO 4217 standard and never change between restarts, so a startup-loaded in-memory cache is correct: no per-request DB hit, and admin can add new currencies without a code deploy.

```typescript
// libs/shared/src/money/currency-scale.cache.ts
import { Injectable, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { DataSource } from 'typeorm';

const TTL_MS = 24 * 60 * 60 * 1000; // 1 day

@Injectable()
export class CurrencyScaleCache implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly scales = new Map<string, number>();
  private refreshTimer: NodeJS.Timeout | undefined;

  constructor(private readonly dataSource: DataSource) {}

  async onApplicationBootstrap(): Promise<void> {
    await this.refresh();
    this.refreshTimer = setInterval(() => void this.refresh(), TTL_MS);
  }

  onApplicationShutdown(): void {
    clearInterval(this.refreshTimer);
  }

  get(code: string): number {
    return this.scales.get(code) ?? 2;
  }

  private async refresh(): Promise<void> {
    const rows = await this.dataSource.query<Array<{ code: string; minor_unit_scale: number }>>(
      'SELECT code, minor_unit_scale FROM pricing.currency',
    );
    for (const row of rows) {
      this.scales.set(row.code, row.minor_unit_scale);
    }
  }
}
```

Register `CurrencyScaleCache` in the `SharedModule` and export it. Any service that formats money for JSON output injects it. The cache loads on startup and refreshes every 24 hours — adding a new `pricing.currency` row takes effect within one day without a restart.

**Seed data** — the `pricing.currency` migration must insert all supported currencies (and any reference currencies) before the app starts:

| ISO 4217 | `minor_unit_scale` | `is_seller_price_allowed` |
|----------|--------------------|---------------------------|
| `USD` | 2 | `true` |
| `THB` | 2 | `true` |
| `SGD` | 2 | `true` |
| `JPY` | 0 | `true` |
| `BHD` | 3 | `false` |

V1 seller-pricing currencies are `USD`, `THB`, `JPY`, `SGD` only (BRD §12). The cache reloads at each restart; adding a new row to `pricing.currency` takes effect after the next deploy with no code change.

### 3.3 DB ↔ application ↔ JSON mapping

```typescript
// infrastructure layer: reading a TypeORM row
import Decimal from 'decimal.js';

// TypeORM returns NUMERIC columns as string when column type is 'numeric'
const money = Money.of(row.unitPrice as string, row.currency);

// arithmetic
const total = money.multiply(new Decimal(quantity));

// back to DB string (always 4dp for storage)
const storageValue: string = total.amount.toFixed(4);

// JSON response — scale-aware (inject CurrencyScaleCache; see §3.2)
const scale = this.currencyScaleCache.get(total.currency);
const jsonValue: string = total.toJSON(scale); // '1000' for JPY, '9.99' for USD
```

**Never:**
```typescript
// BAD — JS number loses precision at large values and introduces floating-point error
const total = parseFloat(row.unitPrice) * quantity;
const total = +row.unitPrice + +row.discount;
```

### 3.4 TypeORM column definition for monetary fields

```typescript
@Column({ type: 'numeric', precision: 19, scale: 4, transformer: { /* see §7.2 */ } })
unitPrice: string; // always string in the entity — never number
```

---

<a id="4-dto-validation-patterns"></a>
## 4. DTO validation patterns

The global `ValidationPipe` is registered in `apps/api/src/main.ts` with `whitelist: true` and `forbidNonWhitelisted: true`. **Do not register a second `ValidationPipe` on individual controllers or handlers** — it overrides the global settings and may silently disable `whitelist`.

### 4.1 Standard setup (already in bootstrap — reference only)

```typescript
// apps/api/src/main.ts (already set — do not re-add)
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
    transformOptions: { enableImplicitConversion: false },
  }),
);
```

### 4.2 Monetary fields — use `@IsNumberString()`, not `@IsNumber()`

```typescript
import { IsNumberString, IsIn, IsISO8601, IsInt, Min } from 'class-validator';

export class CreateOfferDto {
  @IsNumberString()        // accepts "9.99" — rejects number 9.99
  listPrice: string;

  @IsIn(['USD', 'THB', 'JPY', 'SGD'])
  currency: string;

  @IsISO8601({ strict: true })  // rejects non-UTC or missing timezone
  saleStartAt?: string;

  @IsInt()
  @Min(1)
  minQty: number;
}
```

### 4.3 Nested DTOs

```typescript
import { Type } from 'class-transformer';
import { ValidateNested } from 'class-validator';

export class CreateOrderDto {
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items: OrderItemDto[];
}
```

Always pair `@ValidateNested()` with `@Type()` from `class-transformer`. Without `@Type()`, nested objects are not instantiated as class instances and validators are not applied.

### 4.4 Optional fields

With `exactOptionalPropertyTypes: true` in tsconfig, declare optional DTO fields with `| undefined`:

```typescript
export class UpdateProductDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  title?: string | undefined;
}
```

---

<a id="5-error-handling"></a>
## 5. Error handling

### 5.1 AppError hierarchy

All domain and application errors extend `AppError`. Never throw a raw `new Error()` in domain or application layer — these reach the `GlobalExceptionFilter` uncategorised and expose stack traces to clients.

```typescript
// libs/shared/src/errors/app-error.ts
export abstract class AppError extends Error {
  abstract readonly code: string;

  constructor(message: string, readonly context?: Record<string, unknown>) {
    super(message);
    this.name = this.constructor.name;
  }
}

// Example domain errors
export class ProductNotFoundError extends AppError {
  readonly code = 'PRODUCT_NOT_FOUND';
}

export class InsufficientInventoryError extends AppError {
  readonly code = 'INSUFFICIENT_INVENTORY';
  constructor(readonly available: number, readonly requested: number) {
    super(`Requested ${requested}, only ${available} in stock`);
  }
}

export class ForbiddenOperationError extends AppError {
  readonly code = 'FORBIDDEN_OPERATION';
}
```

Define errors in `libs/<module>/src/domain/errors/` for domain-specific errors, and `libs/shared/src/errors/` for cross-cutting errors.

### 5.2 GlobalExceptionFilter mapping

```typescript
// apps/api/src/filters/global-exception.filter.ts
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    if (exception instanceof HttpException) {
      response.status(exception.getStatus()).json(exception.getResponse());
      return;
    }

    if (exception instanceof AppError) {
      const status = APP_ERROR_STATUS_MAP[exception.code] ?? 422;
      response.status(status).json({
        statusCode: status,
        error: exception.code,
        message: exception.message,  // safe — domain errors have caller-facing messages
      });
      return;
    }

    // Unknown: log full exception, return generic 500
    this.logger.error({ err: exception }, 'Unhandled exception');
    response.status(500).json({
      statusCode: 500,
      error: 'INTERNAL_SERVER_ERROR',
      message: 'An unexpected error occurred.',
    });
  }
}
```

```typescript
// libs/shared/src/errors/app-error-status-map.ts
export const APP_ERROR_STATUS_MAP: Record<string, number> = {
  PRODUCT_NOT_FOUND: 404,
  OFFER_NOT_FOUND: 404,
  INSUFFICIENT_INVENTORY: 409,
  FORBIDDEN_OPERATION: 403,
  // ... extend per module
};
```

### 5.3 Rules

- **Domain layer:** throw only `AppError` subclasses. Never import `HttpException` or any NestJS type.
- **Application layer:** throw only `AppError` subclasses; may catch domain errors and re-wrap if needed.
- **Infrastructure layer:** translate infrastructure exceptions (TypeORM `EntityNotFoundError`, `QueryFailedError`) into `AppError` before surfacing to the application layer.
- **HTTP layer (controllers):** never catch exceptions — let `GlobalExceptionFilter` handle them.
- **Never** include a stack trace, SQL query, or internal service name in a client-facing error response.

---

<a id="6-environment-config"></a>
## 6. Environment config

### 6.1 ConfigModule setup

```typescript
// apps/api/src/app.module.ts
import * as Joi from 'joi';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validationSchema: Joi.object({
        NODE_ENV: Joi.string().valid('development', 'test', 'production').required(),
        PORT: Joi.number().default(3000),
        DATABASE_URL: Joi.string().uri().required(),
        JWT_SECRET: Joi.string().min(32).required(),
        JWT_ACCESS_TTL_SECONDS: Joi.number().default(900),
        KAFKA_BROKERS: Joi.string().required(),
        // ... (see §6.2)
      }),
      validationOptions: { abortEarly: false },
    }),
  ],
})
export class AppModule {}
```

`abortEarly: false` reports all missing vars at once rather than stopping at the first failure — saves startup iteration time.

### 6.2 Required env var checklist

| Variable | `api` | `workers` | Notes |
|----------|:-----:|:---------:|-------|
| `NODE_ENV` | ✓ | ✓ | `development` \| `test` \| `production` |
| `PORT` | ✓ | — | Default 3000 |
| `DATABASE_URL` | ✓ | ✓ | Postgres connection string |
| `MONGODB_URI` | ✓ | ✓ | MongoDB connection string |
| `REDIS_URL` | ✓ | — | Redis connection string (used for `auth:revoke_before:{userId}` revocation); overrides REDIS_HOST/PORT when set |
| `REDIS_HOST` | ✓ | — | Redis host (alternative to REDIS_URL) |
| `REDIS_PORT` | ✓ | — | Redis port; default 6379 |
| `MINIO_ENDPOINT` | ✓ | — | MinIO host |
| `MINIO_ACCESS_KEY` | ✓ | — | |
| `MINIO_SECRET_KEY` | ✓ | — | |
| `AES_ENCRYPTION_KEY` | ✓ | — | 32-byte hex key for KYC document AES-256 encryption in MinIO `kyc-documents` bucket |
| `JWT_SECRET` | ✓ | — | Min 32 bytes; generated per environment |
| `JWT_ACCESS_TTL_SECONDS` | ✓ | — | Default 900 (15 min) |
| `JWT_REFRESH_TTL_SECONDS` | ✓ | — | Default 604800 (7 days) |
| `KAFKA_BROKERS` | ✓ | ✓ | Comma-separated host:port list |
| `SCHEMA_REGISTRY_URL` | ✓ | ✓ | Confluent Schema Registry |
| `ELASTICSEARCH_NODE` | ✓ | ✓ | ES/OpenSearch node URL |
| `GOOGLE_CLIENT_ID` | ✓ | — | OAuth |
| `GOOGLE_CLIENT_SECRET` | ✓ | — | OAuth |
| `FACEBOOK_APP_ID` | ✓ | — | OAuth |
| `FACEBOOK_APP_SECRET` | ✓ | — | OAuth |
| `OUTBOX_POLL_INTERVAL_MS` | — | ✓ | Default 500 |
| `PORT_WORKERS` | — | ✓ | Health check HTTP port; default 3001 |
| `LOG_SENSITIVE_KEYS` | ✓ | ✓ | Comma-separated field names to redact from logs; see [observability.md](observability.md) |
| `LOG_MAX_BODY_BYTES` | ✓ | ✓ | Max body size to log before truncation; default 4096 |

### 6.3 Accessing config

```typescript
// Inject ConfigService — never use process.env directly in application code
constructor(private readonly config: ConfigService) {}

const jwtSecret = this.config.getOrThrow<string>('JWT_SECRET');
```

Use `getOrThrow` rather than `get` when the value must be present — it throws at the call site rather than producing `undefined` silently.

---

<a id="7-database-query-patterns"></a>
## 7. Database query patterns

See [database-migrations.md](database-migrations.md) for migration authoring rules. See [backend-module-architecture.md §2](backend-module-architecture.md#2-module-tiers) for the repository interface / TypeORM adapter split.

### 7.1 When to use what

| Approach | Use when |
|----------|----------|
| Repository interface method | Default for all domain reads/writes in Tier 1 modules |
| TypeORM `QueryBuilder` | Complex joins or conditional filtering in query handlers (infrastructure layer only) |
| Raw SQL | Migrations only — never in application or domain code |

### 7.2 Numeric ↔ string transformer for monetary columns

TypeORM returns `NUMERIC` columns as strings when `type: 'numeric'` is set. Add a no-op transformer to make this explicit and prevent accidental coercion:

```typescript
// libs/shared/src/persistence/transformers/numeric-string.transformer.ts
import { ValueTransformer } from 'typeorm';

export const numericStringTransformer: ValueTransformer = {
  to: (value: string | null): string | null => value,
  from: (value: string | null): string | null => value,
};

// Usage in a TypeORM entity
@Column({
  type: 'numeric',
  precision: 19,
  scale: 4,
  transformer: numericStringTransformer,
})
unitPrice: string;
```

### 7.3 Transaction pattern

Use `DataSource.transaction()` to wrap domain change + outbox write atomically. This is the only approved transaction pattern — do not use `EntityManager` from the module's regular DI scope for cross-table operations.

```typescript
// infrastructure adapter
async publishProduct(command: PublishProductCommand): Promise<void> {
  await this.dataSource.transaction(async (em) => {
    await em.save(ProductTypeOrmEntity, productRow);
    await em.save(OutboxEventEntity, outboxRow);  // same transaction
  });
}
```

See [kafka-events.md](kafka-events.md) §Transactional outbox for the full outbox pattern.

### 7.4 N+1 prevention

Always use `leftJoinAndSelect` or a separate bulk query when loading a collection and its relations. Never query inside a loop.

```typescript
// BAD
const products = await this.repo.find();
for (const p of products) {
  p.offers = await this.offerRepo.find({ where: { productId: p.id } }); // N queries
}

// GOOD
const products = await this.repo
  .createQueryBuilder('p')
  .leftJoinAndSelect('p.offers', 'o')
  .getMany();
```

---

<a id="8-nestjs-specific-patterns"></a>
## 8. NestJS-specific patterns

### 8.1 Injection scope

Use the default **singleton** scope (`@Injectable()` with no scope option) for all providers. `Scope.REQUEST` creates a new provider instance per HTTP request, which:

- Defeats connection-pool sharing (TypeORM `DataSource`)
- Breaks Kafka consumer context (Kafka consumer instances must be long-lived)
- Increases memory pressure

Use `Scope.REQUEST` only when a provider genuinely needs per-request isolation (e.g. a request-scoped audit context) and document why.

### 8.2 @Global() modules

Use `@Global()` only for modules that every feature module needs without explicit imports. In AliceUT:

| Module | @Global? | Reason |
|--------|----------|--------|
| `ConfigModule` | Yes | `ConfigService` needed everywhere |
| `LoggerModule` (nestjs-pino) | Yes | Logger injected in every service |
| All domain feature modules | No | Explicit imports clarify dependencies |
| `TypeOrmModule` | No | Import in each module that owns entities |

### 8.3 Guard vs interceptor vs middleware

| Concern | Use |
|---------|-----|
| Authentication (who is the caller?) | `AuthGuard` (Passport) — runs before handler |
| Authorization (can this caller do X?) | Custom `@UseGuards(RolesGuard)` — reads JWT claims |
| Request/response transformation, logging | Interceptor — wraps the handler |
| Cross-cutting HTTP concerns (CORS, rate limit, body-parser) | Middleware |
| DTO shape validation | `ValidationPipe` (global) — not a guard |

Do not put authorization logic in middleware — middleware runs before guards and before NestJS resolves the route handler, so JWT claims are not yet validated.

### 8.4 Avoiding duplicate pipes and guards

The global `ValidationPipe` and `JwtAuthGuard` (when configured globally) already apply to all routes. Adding them again at controller or handler level overrides the global configuration and may silently change behavior:

```typescript
// BAD — redundant, and the locally-supplied options may differ from global
@UsePipes(new ValidationPipe({ whitelist: false }))
@Controller('products')
export class ProductsController {}

// GOOD — rely on global pipe; opt out per route only when intentional
@SkipJwtAuth()  // custom decorator to exempt a route from the global JWT guard
@Post('webhook')
handleWebhook() {}
```

### 8.5 Swagger / OpenAPI decoration

Controllers and DTOs must include decorators for OpenAPI generation:

```typescript
@ApiTags('products')
@Controller('products')
export class ProductsController {
  @ApiOperation({ summary: 'List published products' })
  @ApiOkResponse({ type: ProductListResponseDto })
  @Get()
  list(@Query() query: ListProductsDto) {}
}
```

See [api-conventions.md](api-conventions.md) for `operationId` naming convention.

---

<a id="9-file-naming-conventions"></a>
## 9. File naming conventions

### 9.1 Pattern

All backend files use `kebab-case.type.ts`:

| Type suffix | Example | Contains |
|-------------|---------|----------|
| `.entity.ts` | `product.entity.ts` | Domain entity (pure class, no framework imports) |
| `.typeorm-entity.ts` | `product.typeorm-entity.ts` | TypeORM `@Entity` with decorators (Tier 1 only) |
| `.repository.interface.ts` | `product.repository.interface.ts` | Port/interface definition (Tier 1 only) |
| `.typeorm-repository.ts` | `product.typeorm-repository.ts` | TypeORM adapter implementing the interface |
| `.command.ts` | `publish-product.command.ts` | CQRS command class (Tier 1) |
| `.handler.ts` | `publish-product.handler.ts` | Command or query handler (Tier 1) |
| `.query.ts` | `get-product.query.ts` | CQRS query class |
| `.service.ts` | `identity.service.ts` | NestJS service (Tier 2/3) |
| `.controller.ts` | `products.controller.ts` | NestJS controller |
| `.module.ts` | `catalog.module.ts` | NestJS module |
| `.dto.ts` | `create-offer.dto.ts` | Request/response DTO |
| `.guard.ts` | `roles.guard.ts` | NestJS guard |
| `.interceptor.ts` | `logging.interceptor.ts` | NestJS interceptor |
| `.consumer.ts` | `product-changed.consumer.ts` | Kafka consumer |
| `.domain-event.ts` | `product-published.domain-event.ts` | Domain event class |
| `.vo.ts` | `money.vo.ts` | Value object |
| `.spec.ts` | `publish-product.handler.spec.ts` | Unit test |
| `.e2e-spec.ts` | `orders.e2e-spec.ts` | Integration/E2E test |

### 9.2 Barrel files (index.ts)

Create `index.ts` only at module boundaries — one per `libs/<module>/` root. Do not create barrel files inside subdirectories (e.g. no `libs/catalog/src/domain/index.ts`). Deep barrel files cause circular import chains as modules grow.

```typescript
// libs/catalog/index.ts — exports only the public API surface
export { CatalogApplicationService } from './src/application/catalog.application-service';
export type { IProductRepository } from './src/domain/repositories/product.repository.interface';
export { ProductNotFoundError } from './src/domain/errors/product-not-found.error';
// Do NOT export TypeORM entities, internal command/query classes, or infrastructure adapters
```

---

<a id="10-code-review-checklist"></a>
## 10. Code review checklist

Gate these before approving any backend PR:

### Domain layer
- [ ] Domain entity has zero framework imports (`@nestjs/*`, `typeorm`, `class-validator`)
- [ ] Repository interface defines contracts only (no TypeORM types leak through as parameters or return types)
- [ ] Domain errors extend `AppError`, not `Error` or `HttpException`
- [ ] No monetary value is typed as `number`

### Money correctness
- [ ] All monetary arithmetic uses `decimal.js` / `Money.multiply()` / `Money.add()` — no JS `+`, `*`, `/` operators on monetary values
- [ ] TypeORM monetary columns declared as `string` with `numericStringTransformer`
- [ ] JSON response monetary fields are strings, not numbers
- [ ] Currency scale resolved via injected `CurrencyScaleCache`, not a hardcoded `CURRENCY_SCALE` constant

### Event-driven integrity
- [ ] Outbox event written in the same `DataSource.transaction()` as the domain state change
- [ ] Event payload includes `event_id`, `event_type`, `event_version`, `occurred_at`, `correlation_id`
- [ ] Consumer is idempotent (dedupes on `event_id`)

### Cross-module boundaries
- [ ] No cross-module DB joins (each module queries only its own tables)
- [ ] No cross-module service injection (communicate via Kafka events or the module's public `index.ts` API)

### Validation and security
- [ ] No `ValidationPipe` re-registered at controller/handler level
- [ ] No `@IsNumber()` on a monetary DTO field (must be `@IsNumberString()`)
- [ ] No secret or internal error detail exposed in a client-facing response

### Testing
- [ ] Command/query handlers for Tier 1 modules have unit tests covering the happy path and at least one error path
- [ ] Integration tests (or E2E) exist for any new API endpoint
- [ ] Tests do not call `process.env` directly — use a stubbed `ConfigService`
