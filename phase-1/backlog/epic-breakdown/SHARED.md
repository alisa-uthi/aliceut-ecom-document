# EPIC: SHARED — Shared Libraries

**Sprint:** 1–2  
**Total Tasks:** 10  

Cross-cutting utilities consumed by every module: money value objects, UUIDv7 generation, pagination DTOs, outbox integration helpers, base exception classes, storage service, and OpenAPI configuration. Must be completed before any feature module starts.

---

## SHARED-001 — Money Value Object (`MoneyVO`)

- **US Ref:** FR-P-04
- **Estimate:** M (1d)
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/shared/src/domain/money.value-object.ts`
- Wraps `decimal.js` `Decimal`; never exposes raw JS `number`. Method set (add/subtract/multiply/equals/isGreaterThan/toDbDecimal/fromDb) per `conventions/backend-coding-standards.md` §3.1 `Money` class — see spec for exact signatures.
- `toJSON(scale: number): string` — scale-aware, caller passes `scale` from `CurrencyScaleCache.get(currency)` (SHARED-001b). **Never hardcode a 4dp constant for display** — 4dp is storage-only, via `toDbDecimal()`. See §3.2-3.3 for the DB↔app↔JSON mapping.
- Throw `InvalidMoneyException` on currency mismatch or invalid input
- Lint rule note: document that `*price`, `*amount`, `*tax`, `*fee` TypeORM column types must be `NUMERIC(19,4)`, never `float`/`integer`

**Done Criteria**

- `new MoneyVO("10.5", "USD").add(new MoneyVO("0.50", "USD")).toDbDecimal()` returns `"11.0000"`
- `new MoneyVO("1000", "JPY").toJSON(0)` returns `"1000"`; `new MoneyVO("9.99", "USD").toJSON(2)` returns `"9.99"`
- Adding USD + THB throws `InvalidMoneyException`
- Unit tests cover: add, subtract, multiply, equals, currency mismatch, invalid amount, scale-aware `toJSON` for JPY (0dp) vs USD (2dp)
- `toDbDecimal()` always produces 4 decimal places (storage precision); `toJSON(scale)` never hardcodes 4dp for display

---

## SHARED-001b — Currency Scale Cache (`CurrencyScaleCache`)

- **US Ref:** FR-P-04
- **Estimate:** S (½d)
- **Dependencies:** SHARED-001, INFRA-004
- **Spec References:** `conventions/backend-coding-standards.md` §3.2, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/shared/src/money/currency-scale.cache.ts`
- Implement per `conventions/backend-coding-standards.md` §3.2 exactly (class shape, 24h refresh interval, `get(code)` default) — see spec for the full implementation.
- **Authoritative source is DB `pricing.currency.minor_unit_scale` — never hardcode a `CURRENCY_SCALE` constant.**
- Register + export from `SharedModule`; services formatting money for JSON inject this and pass the result into `MoneyVO.toJSON(scale)`

**Done Criteria**

- Cache loads `USD=2, THB=2, SGD=2, JPY=0, BHD=3` from seeded `pricing.currency` rows on boot
- `get('JPY')` returns `0`, `get('USD')` returns `2`, `get('XXX')` (unseeded) returns `2` (default)
- Adding a new `pricing.currency` row and waiting for refresh (or manually invoking refresh in test) updates `get()` without app restart
- No `CURRENCY_SCALE` constant exists anywhere in the codebase (grep-able convention check)

---

## SHARED-002 — UUIDv7 Generator Utility

- **US Ref:** —
- **Estimate:** S (½d)
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/shared/src/utils/uuid.util.ts`
- Install `uuidv7` npm package (pure TS implementation)
- Export `generateId(): string` — returns a UUIDv7 string
- TypeORM entities: set `@PrimaryColumn('uuid')` with `default: () => 'uuidv7()'` (uses DB function from INFRA-004) AND call `generateId()` in entity constructor to pre-populate `id` field so entity can be used before being persisted
  ```ts
  @PrimaryColumn('uuid')
  id: string = generateId();
  ```
- All entity primary keys MUST use this pattern; document in `conventions/backend-module-architecture.md` reference
- No UUID v4 allowed for entity IDs (UUIDv7 required for time-ordering per NFR-16)

**Done Criteria**

- `generateId()` returns string matching UUID format regex `^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`
- 1000 generated IDs sort lexicographically in creation order (monotonically increasing)
- Unit test confirms format and time-ordering

---

## SHARED-003 — Pagination DTO + Cursor Helpers

- **US Ref:** —
- **Estimate:** S (½d)
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/shared/src/dto/pagination.dto.ts`
- `PaginationQueryDto`:
  ```ts
  class PaginationQueryDto {
    @IsOptional() @IsInt() @Min(1) @Max(100) @Type(() => Number)
    limit?: number = 20;
    
    @IsOptional() @IsString()
    cursor?: string;  // opaque base64url-encoded cursor
  }
  ```
- `PaginatedResponseDto<T>`:
  ```ts
  class PaginatedResponseDto<T> {
    data: T[];
    meta: {
      limit: number;
      hasMore: boolean;
      nextCursor?: string;    // base64url-encoded last item's id + createdAt
      totalCount?: number;    // only populated when cheap to count
    };
  }
  ```
- Cursor encoding: `Buffer.from(JSON.stringify({ id, createdAt })).toString('base64url')`
- Cursor decoding: `JSON.parse(Buffer.from(cursor, 'base64url').toString())`
- Default pagination: `limit=20`, max `limit=100`; all list endpoints must use cursor pagination (no offset/page)
- Helper function `buildPaginatedResponse<T>(items: T[], limit: number): PaginatedResponseDto<T>` — fetches `limit+1` items, sets `hasMore` based on whether `items.length > limit`, slices result

**Done Criteria**

- `PaginationQueryDto` rejects `limit > 100` with 400 validation error
- Cursor round-trips correctly: encode then decode returns original `{ id, createdAt }`
- `buildPaginatedResponse` correctly sets `hasMore: true` when extra item exists

---

## SHARED-004 — Base Domain Exception Classes

- **US Ref:** —
- **Estimate:** S (½d)
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `libs/shared/src/exceptions/`
- Base hierarchy:
  ```
  DomainException (extends Error)
  ├── NotFoundException (404) — entity not found by ID
  ├── ConflictException (409) — unique constraint, duplicate state
  ├── ValidationException (422) — domain rule violation (not input format)
  ├── ForbiddenException (403) — authorization failure
  ├── UnauthorizedException (401) — authentication failure
  └── InvalidMoneyException (400) — money operation failure
  ```
- Each exception carries: `code: string` (machine-readable, e.g. `PRODUCT_NOT_FOUND`), `message: string`, optional `details: unknown`
- Global NestJS exception filter in `apps/api/src/filters/domain-exception.filter.ts`:
  ```ts
  @Catch(DomainException)
  class DomainExceptionFilter implements ExceptionFilter {
    catch(exception: DomainException, host: ArgumentsHost) {
      // map DomainException subclasses to HTTP status codes
      // return { error: exception.code, message: exception.message, details }
    }
  }
  ```
- Apply filter globally in `main.ts`

**Done Criteria**

- Throwing `NotFoundException('PRODUCT_NOT_FOUND', 'Product not found')` from a service results in HTTP 404 response: `{ "error": "PRODUCT_NOT_FOUND", "message": "Product not found" }`
- All exception subclasses testable in isolation
- No raw `throw new Error(...)` in domain/application layer code (ESLint rule or convention note)

---

## SHARED-005 — Outbox Event Writer Helper (consumes PLATFORM's `OutboxEvent`)

- **US Ref:** FR-P-09
- **Estimate:** S (½d)
- **Dependencies:** PLATFORM-002, SHARED-002
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`, `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/kafka-events.md`

**Implementation Notes**

- **Ownership note:** the `OutboxEvent` TypeORM entity, `platform.outbox_event` table migration, and `OutboxRepository` interface are owned by **PLATFORM-002**, not this task. SHARED-005 only provides a thin, module-agnostic helper that any feature module (Product, Order, etc.) calls from inside its own transaction — it re-exports/wraps what PLATFORM-002 provides rather than redefining the entity.
- File: `libs/shared/src/outbox/outbox-event-writer.service.ts`
- `OutboxEventWriterService.write(entityManager: EntityManager, event: OutboxEventDto): Promise<void>` — inserts an outbox row (using PLATFORM-002's `OutboxEvent` entity) via the provided `EntityManager` (same transaction as domain write)
- `OutboxEventDto`: `{ aggregateType, aggregateId, eventType, eventVersion, payload, correlationId? }`
- Envelope fields added automatically: `event_id = generateId()` (SHARED-002), `occurred_at = new Date()`
- Usage pattern in application services:
  ```ts
  await this.dataSource.transaction(async (em) => {
    await em.save(ProductEntity, product);
    await this.outboxWriter.write(em, {
      aggregateType: 'Product',
      aggregateId: product.id,
      eventType: 'product.changed',
      eventVersion: 1,
      payload: { ... },
    });
  });
  ```

**Done Criteria**

- Calling `write()` outside a transaction throws (or logs clear error)
- Within a transaction: if domain save succeeds but outbox insert fails, entire transaction rolls back
- If domain save fails, outbox row is NOT written (atomicity test)
- Integration test confirms both rows appear/disappear together
- No duplicate `OutboxEvent` entity/migration defined in `libs/shared/` — single source of truth stays in PLATFORM-002's `platform.outbox_event` table

---

## SHARED-006 — Storage Service (MinIO Wrapper)

- **US Ref:** —
- **Estimate:** M (1d)
- **Dependencies:** INFRA-010, INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`, `phase-1/technical-design/docker-compose-topology.md`

**Implementation Notes**

- File: `libs/shared/src/storage/storage.service.ts`
- Wraps `@aws-sdk/client-s3` and `@aws-sdk/s3-request-presigner`
- Bucket constants: `BUCKET_PRODUCT_IMAGES = 'product-images'`, `BUCKET_KYC = 'kyc-documents'`, `BUCKET_USER_ASSETS = 'user-assets'`
- Methods:
  ```ts
  upload(bucket: string, key: string, body: Buffer | Readable, contentType: string): Promise<string>
  // Returns public URL for product-images bucket, key path for others
  
  getPresignedUploadUrl(bucket: string, key: string, expiresIn: number): Promise<string>
  // Client-side direct upload (for large files)
  
  getPresignedDownloadUrl(bucket: string, key: string, expiresIn: number): Promise<string>
  // Private bucket read access
  
  delete(bucket: string, key: string): Promise<void>
  ```
- Key naming convention: `{entityType}/{entityId}/{timestamp}-{filename}` (e.g. `products/uuid/1234567890-front.webp`)
- `StorageModule` in `libs/shared/` exports `StorageService`; config from `ConfigService`
- Never store full URLs in DB for `kyc-documents` or `user-assets` — store key only; generate presigned URL on demand
- For `product-images`: store full public URL (public bucket, URL is stable)

**Done Criteria**

- `upload('product-images', key, buf, 'image/webp')` returns accessible public URL
- `getPresignedDownloadUrl('kyc-documents', key, 900)` returns URL that expires in 900s
- Integration test: upload file, download via presigned URL, confirm content matches

---

## SHARED-007 — Redis Module + Rate Limit Guard

- **US Ref:** —
- **Estimate:** M (1d)
- **Dependencies:** INFRA-006, INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`, `phase-1/technical-design/api-design/auth.md`

**Implementation Notes**

- File: `libs/shared/src/redis/redis.module.ts`
- Exports `REDIS_CLIENT` injection token (type: `ioredis.Redis`)
- `EmailResendRateLimitGuard`: `@Injectable() implements CanActivate` — checks `auth:resend_count:{email}` in Redis; allows max 3 resends per hour; increments counter + sets TTL 3600s on first call
  ```ts
  const count = await redis.incr(`auth:resend_count:${email}`);
  if (count === 1) await redis.expire(`auth:resend_count:${email}`, 3600);
  if (count > 3) throw new TooManyRequestsException();
  ```
- `JwtRevocationService`: checks/sets `auth:revoke_before:{userId}` (TTL = remaining access token TTL)
  ```ts
  async isRevoked(userId: string, tokenIat: number): Promise<boolean> {
    const ts = await redis.get(`auth:revoke_before:${userId}`);
    return ts ? tokenIat < parseInt(ts, 10) : false;
  }
  async revokeAllForUser(userId: string): Promise<void> {
    const exp = Math.floor(Date.now() / 1000) + 960; // 16 minutes
    await redis.set(`auth:revoke_before:${userId}`, String(Date.now()), 'EX', 960);
  }
  ```

**Done Criteria**

- 3 resend attempts succeed; 4th returns 429
- After `revokeAllForUser(id)`: tokens with `iat < revoke_before timestamp` are considered invalid
- Redis key expires automatically after TTL (no leaked keys)

---

## SHARED-008 — OpenAPI / Swagger Setup

- **US Ref:** —
- **Estimate:** S (½d)
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`, `phase-1/technical-design/api-design.md`

**Implementation Notes**

- File: `apps/api/src/main.ts`
- Package: `@nestjs/swagger`
- Setup in `main.ts`:
  ```ts
  const config = new DocumentBuilder()
    .setTitle('AliceUT API')
    .setVersion('1.0.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api/docs', app, document);
  ```
- Enable in all envs (no prod-only guard in V1; protected via internal network in docker-compose)
- All DTOs use `@ApiProperty()` decorators for documentation
- Response classes use `@ApiResponse()` decorators on controllers
- `@ApiBearerAuth()` on all protected endpoints

**Done Criteria**

- `GET /api/docs` serves Swagger UI in browser
- Auth endpoints appear in the `Authentication` group
- Bearer auth flow works in Swagger UI (can paste JWT and make authenticated requests)

---

## SHARED-009 — Global Validation Pipe + Transform Config

- **US Ref:** —
- **Estimate:** S (½d)
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `apps/api/src/main.ts`
- Global validation pipe:
  ```ts
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,          // strip unknown fields
    forbidNonWhitelisted: true, // throw on unknown fields instead of silently stripping
    transform: true,          // auto-transform query param strings to correct types
    transformOptions: { enableImplicitConversion: true },
  }));
  ```
- `whitelist: true` prevents extra fields being passed to handlers — security defense-in-depth
- `forbidNonWhitelisted: true` returns 400 for unknown fields (useful for API contract enforcement)
- `transform: true` with `enableImplicitConversion` allows `@IsInt()` on query params to coerce `"20"` → `20` automatically
- Global interceptor for response serialization: `ClassSerializerInterceptor` (excludes `@Exclude()`-marked fields like passwords)

**Done Criteria**

- POST with extra unknown field `{ unknownField: "x" }` returns HTTP 400
- Query param `?limit=20` is received as `number` 20 in handler (not string)
- Response DTOs with `@Exclude()` fields (e.g. `passwordHash`) don't appear in API responses
