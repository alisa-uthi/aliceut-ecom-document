# Module Architecture

**Status:** Draft  
**Source of truth:** [architecture-overview §10](../architecture-overview.md), [BRD v1.2](../phase-1/requirements/BRD.md)

---

## Summary

| Section | Description |
|---------|-------------|
| [1. Repository structure](#1-repository-structure) | Monorepo layout: `apps/api`, `apps/workers`, `libs/` |
| [2. Module tiers](#2-module-tiers) | Three-tier classification by domain complexity |
| [2.1. Tier 1 — Full hexagonal](#21-tier-1-full-hexagonal) | Rich domain modules: catalog, orders, pricing, inventory, cart |
| [2.2. Tier 2 — Simplified service layer](#22-tier-2-simplified-service-layer) | DB-backed modules with thin domain logic |
| [2.3. Tier 3 — Thin / infrastructure](#23-tier-3-thin-infrastructure) | Pure infrastructure modules, no owned domain state |
| [3. Layer dependency rules](#3-layer-dependency-rules) | Allowed and forbidden import directions |
| [4. CQRS-lite pattern](#4-cqrs-lite-pattern) | Command/query handlers without `@nestjs/cqrs` |
| [5. Repository interface pattern](#5-repository-interface-pattern) | Port/adapter split with injection tokens |
| [6. Outbox integration pattern](#6-outbox-integration-pattern) | Transactional outbox writes in same DB transaction |
| [7. Module dependency rules](#7-module-dependency-rules) | Cross-module access patterns and exceptions |
| [8. OpenAPI contract generation](#8-openapi-contract-generation) | Swagger generation pipeline to Angular client |
| [8.1. API versioning](#81-api-versioning) | URI versioning with `VersioningType.URI` |
| [9. Module wiring in the API composition root](#9-module-wiring-in-the-api-composition-root) | `AppModule` imports and global bootstrap configuration |
| [10. Workers composition root](#10-workers-composition-root) | `WorkersModule`: outbox relay and Kafka consumers |
| [11. Shared library (`libs/shared`)](#11-shared-library-libsshared) | Technical primitives: money, errors, logger, guards |
| [12. Elasticsearch index design](#12-elasticsearch-index-design) | `products` index mapping and query strategy |
| [13. \[DESIGN DECISIONS\]](#13-design-decisions) | Locked architectural choices with rationale |

<a id="1-repository-structure"></a>
## 1. Repository structure

```
aliceut-ecom-backend/
├── apps/
│   ├── api/                          NestJS HTTP composition root
│   │   ├── src/
│   │   │   ├── app.module.ts         Wires all feature modules
│   │   │   └── main.ts               Bootstrap: global pipes, guards, Swagger
│   │   └── Dockerfile (target: api)
│   └── workers/
│       ├── src/
│       │   ├── workers.module.ts     Wires outbox relay + all consumers
│       │   └── main.ts               Bootstrap: no HTTP, only Kafka consumers
│       └── Dockerfile (target: workers)
├── libs/
│   ├── <domain-module>/              One directory per domain (see phase module inventory)
│   ├── contracts/                    OpenAPI DTOs, Avro schemas, generated types
│   └── shared/                       Technical primitives (logging, money, errors)
```

---

<a id="2-module-tiers"></a>
## 2. Module tiers

Not every module warrants the full hexagonal layout. Three tiers apply based on domain complexity.

| Tier | When to use | Example Modules                                     |
|------|-------------|-----------------------------------------------------|
| **1 — Full hexagonal** | Rich domain rules, money, state machines, swap-ORM requirement (NFR-18) | `catalog`, `orders`, `pricing`, `inventory`, `cart` |
| **2 — Simplified service** | Has DB state but no complex invariants; auth libraries do the heavy lifting | `identity`, `seller`, `admin`                       |
| **3 — Thin / infrastructure** | No domain entities; pure read models, event fan-out, or infra wiring | `search`, `notifications`, `platform`, `workers`    |

Tier 1 modules use the full structure in §2.1. Tier 2 and 3 use the simplified structures in §2.2 and §2.3.

---

<a id="21-tier-1-full-hexagonal"></a>
## 2.1. Tier 1 — Full hexagonal

Rich domain, state machines, money handling. Using `catalog` as the canonical example:

```
libs/catalog/
├── src/
│   ├── domain/                        Pure business logic — no framework imports
│   │   ├── entities/
│   │   │   ├── product.entity.ts      Domain entity (plain class, no TypeORM decorators)
│   │   │   └── offer.entity.ts
│   │   ├── value-objects/
│   │   │   └── money.vo.ts
│   │   ├── events/
│   │   │   └── product-published.domain-event.ts
│   │   ├── repositories/
│   │   │   └── product.repository.interface.ts    Port (interface only)
│   │   └── services/
│   │       └── moderation.service.ts
│   │
│   ├── application/                   Use cases — depends only on domain
│   │   ├── commands/
│   │   │   ├── publish-product.command.ts
│   │   │   └── publish-product.handler.ts
│   │   ├── queries/
│   │   │   ├── get-product.query.ts
│   │   │   └── get-product.handler.ts
│   │   └── catalog.application-service.ts
│   │
│   ├── infrastructure/                Adapters — TypeORM, Kafka, HTTP clients
│   │   ├── persistence/
│   │   │   └── typeorm/
│   │   │       ├── product.typeorm-entity.ts
│   │   │       └── product.typeorm-repository.ts
│   │   └── outbox/
│   │       └── catalog.outbox.service.ts
│   │
│   ├── http/
│   │   ├── dto/
│   │   ├── products.controller.ts
│   │   └── categories.controller.ts
│   │
│   └── catalog.module.ts
│
├── index.ts                           Public API: exports ApplicationService + interfaces only
└── package.json
```

---

<a id="22-tier-2-simplified-service-layer"></a>
## 2.2. Tier 2 — Simplified service layer

Has DB state, but domain logic is thin or delegated to libraries (e.g. Passport, argon2, KYC state flags). No domain/persistence split, no CQRS handler split, no repository interface. Single service class.

```
libs/identity/
├── src/
│   ├── entities/
│   │   ├── user.entity.ts             TypeORM @Entity — decorators inline, no split class
│   │   └── refresh-session.entity.ts
│   ├── services/
│   │   └── identity.service.ts        Single service: register, login, refresh, profile
│   ├── http/
│   │   ├── dto/
│   │   │   ├── register-user.dto.ts
│   │   │   └── login.dto.ts
│   │   ├── auth.controller.ts
│   │   └── profile.controller.ts
│   └── identity.module.ts
├── index.ts                           Exports IdentityService (the public facade)
└── package.json
```

Tier 2 rules:
- TypeORM decorators live directly on the entity — no separate `typeorm-entity` file.
- No repository interface; inject TypeORM's `Repository<T>` directly inside the service.
- No `commands/` or `queries/` subdirectory; the service methods are the use cases.
- Outbox writes still go through `OutboxService` (from `platform`) inside a transaction.
- `index.ts` exports only the service class, not internal entities.

---

<a id="23-tier-3-thin-infrastructure"></a>
## 2.3. Tier 3 — Thin / infrastructure

No mutable domain state owned by this module. Purely reads from other modules via Kafka events or serves ES queries. No TypeORM entities, no repository pattern.

```
libs/search/
├── src/
│   ├── search.service.ts              ES client calls — query + index update methods
│   ├── consumers/
│   │   ├── product-changed.consumer.ts
│   │   └── offer-changed.consumer.ts
│   ├── dto/
│   │   └── search-products.dto.ts
│   ├── http/
│   │   └── search.controller.ts
│   └── search.module.ts
├── index.ts
└── package.json
```

```
libs/notifications/
├── src/
│   ├── notifications.service.ts       Sends email/in-app via provider client
│   ├── consumers/
│   │   ├── order-finalized.consumer.ts
│   │   └── kyc-decided.consumer.ts
│   ├── templates/                     Email template identifiers (no HTML here)
│   └── notifications.module.ts
├── index.ts
└── package.json
```

Tier 3 rules:
- No TypeORM entities. If notification preferences need a DB table, treat it as a config row via a single TypeORM repo injected directly — no entity class split.
- No ApplicationService facade. Consumers call the service directly.
- No outbox (these modules react to events; they don't own domain state that must be replicated).

---

<a id="3-layer-dependency-rules"></a>
## 3. Layer dependency rules

```
http ────────► application ────────► domain
                    │                   ▲
              infrastructure ───────────┘
                    │
              platform.outbox (write only)
```

Allowed imports:
- `http` → `application` (via ApplicationService facade)
- `application` → `domain` (entities, repository interfaces, domain services)
- `infrastructure` → `domain` (implements repository interfaces), `application` (registered as providers)
- `http` → `contracts/dto` (shared transport types)

Forbidden imports:
- `domain` → anything outside `domain/` (no NestJS, no TypeORM, no Kafka)
- Module A's `infrastructure` → Module B's `infrastructure` (no cross-schema DB reads)
- Module A's `domain` → Module B's `domain` (no direct domain coupling)
- `application` → `http` (no upward dependency)

Cross-module communication:
- **Sync:** Module A calls Module B's `ApplicationService` via NestJS DI (injected as an interface/token, not a concrete class).
- **Async:** Module A writes to `platform.outbox_event` in its transaction; Module B consumer reads from Kafka.

---

<a id="4-cqrs-lite-pattern"></a>
## 4. CQRS-lite pattern

Commands mutate state; queries read state. Handlers are plain classes registered as NestJS providers.

### Command example
```typescript
// application/commands/register-user.command.ts
export class RegisterUserCommand {
  constructor(
    public readonly email: string,
    public readonly password: string,
    public readonly fullName: string,
    public readonly accountType: AccountType,
  ) {}
}

// application/commands/register-user.handler.ts
@Injectable()
export class RegisterUserHandler {
  constructor(
    private readonly userRepo: USER_REPOSITORY,  // injected by token
    private readonly outbox: OutboxService,
    private readonly passwordService: PasswordService,
  ) {}

  async execute(cmd: RegisterUserCommand): Promise<User> {
    const hash = await this.passwordService.hash(cmd.password);
    const user = User.create({ email: cmd.email, passwordHash: hash, ... });
    await this.userRepo.save(user);                    // same tx
    await this.outbox.append(UserRegisteredEvent.from(user)); // same tx
    return user;
  }
}
```

No CQRS library dependency (e.g. `@nestjs/cqrs`) in V1. The ApplicationService facade dispatches to handlers directly. This keeps the architecture simple while the handler pattern remains extractable later.

### Query example
```typescript
// application/queries/get-user-by-id.handler.ts
@Injectable()
export class GetUserByIdHandler {
  constructor(private readonly userRepo: USER_REPOSITORY) {}

  async execute(userId: string): Promise<UserDto> {
    const user = await this.userRepo.findById(userId);
    if (!user) throw new UserNotFoundError(userId);
    return UserDto.from(user);
  }
}
```

---

<a id="5-repository-interface-pattern"></a>
## 5. Repository interface pattern

The domain layer defines a repository interface (port). The infrastructure layer provides the TypeORM implementation (adapter). The NestJS module wires them via an injection token.

```typescript
// domain/repositories/user.repository.interface.ts
export interface IUserRepository {
  findById(id: string): Promise<User | null>;
  findByEmail(email: string): Promise<User | null>;
  save(user: User): Promise<void>;
  saveAll(users: User[]): Promise<void>;
}

export const USER_REPOSITORY = Symbol('IUserRepository');

// infrastructure/persistence/typeorm/user.typeorm-repository.ts
@Injectable()
export class UserTypeOrmRepository implements IUserRepository {
  constructor(
    @InjectRepository(UserTypeOrmEntity)
    private readonly ormRepo: Repository<UserTypeOrmEntity>,
  ) {}

  async findById(id: string): Promise<User | null> {
    const row = await this.ormRepo.findOne({ where: { id } });
    return row ? UserMapper.toDomain(row) : null;
  }
  // ...
}

// identity.module.ts
@Module({
  imports: [TypeOrmModule.forFeature([UserTypeOrmEntity])],
  providers: [
    { provide: USER_REPOSITORY, useClass: UserTypeOrmRepository },
    RegisterUserHandler,
    GetUserByIdHandler,
    IdentityApplicationService,
  ],
  exports: [IdentityApplicationService],
})
export class IdentityModule {}
```

The domain entity (`User`) and the TypeORM entity (`UserTypeOrmEntity`) are **separate classes** mapped by `UserMapper`. This prevents TypeORM decorators and persistence concerns from leaking into domain logic.

---

<a id="6-outbox-integration-pattern"></a>
## 6. Outbox integration pattern

Every domain state change that must propagate externally writes to `platform.outbox_event` inside the **same PostgreSQL transaction** as the domain change.

```typescript
// platform/outbox/outbox.service.ts (in libs/platform)
@Injectable()
export class OutboxService {
  constructor(
    @InjectRepository(OutboxEventTypeOrmEntity)
    private readonly outboxRepo: Repository<OutboxEventTypeOrmEntity>,
  ) {}

  async append(
    event: DomainEvent,
    entityManager?: EntityManager,  // when called inside a tx
  ): Promise<void> {
    const repo = entityManager
      ? entityManager.getRepository(OutboxEventTypeOrmEntity)
      : this.outboxRepo;

    await repo.save({
      id: uuidv7(),
      aggregate_type: event.aggregateType,
      aggregate_id: event.aggregateId,
      topic: event.topic,
      event_type: event.eventType,
      event_version: event.eventVersion,
      payload: event.payload,
      correlation_id: event.correlationId,
      occurred_at: event.occurredAt,
      publication_status: 'PENDING',
    });
  }
}
```

Usage inside a handler with an explicit transaction:
```typescript
await this.dataSource.transaction(async (em) => {
  await em.save(UserTypeOrmEntity, userRow);
  await this.outbox.append(new UserRegisteredEvent(user), em);
});
```

The outbox relay (in `apps/workers`) polls `platform.outbox_event WHERE publication_status = 'PENDING'`, serializes to Avro using the Schema Registry client, publishes to Kafka, and marks `publication_status = 'PUBLISHED'`. It never retries a row already marked PUBLISHED.

---

<a id="7-module-dependency-rules"></a>
## 7. Module dependency rules

No module may directly import another module's:
- TypeORM entities or repositories
- Database schema or table names
- Internal services (only the exported `ApplicationService` is accessible)

Cross-module allowed patterns:

| Need | Allowed approach |
|------|----------------|
| Module A needs user info from Identity | Call `IdentityApplicationService.getUserById()` |
| Module A needs offer price from Pricing | Call `PricingApplicationService.getEffectivePrice()` |
| Module A needs to react to Module B's state change | Subscribe to Module B's Kafka topic |
| Checkout needs inventory from Inventory | Call `InventoryApplicationService.reserveStock()` in the checkout transaction (in-process) |
| Search needs product data | Consume `product.changed` and `offer.changed` Kafka events |

Checkout is an exception: it calls Inventory's application service **synchronously in the same process** because the inventory reservation is part of the atomic checkout transaction. This is the controlled transactional composition flow described in `architecture-overview.md §10`.

---

<a id="8-openapi-contract-generation"></a>
## 8. OpenAPI contract generation

```
NestJS controllers (with @ApiOperation, @ApiResponse, @ApiTags, @ApiBearerAuth)
    +
Transport DTOs (with @ApiProperty decorators)
    │
    ▼
SwaggerModule.createDocument()  (in apps/api/main.ts)
    │
    ▼
libs/contracts/openapi/aliceut-v1.json   (committed, CI-verified)
    │
    ▼
openapi-generator-cli (typescript-angular)
    │
    ▼
aliceut-ecom-frontend/libs/api-client/   (generated, do not edit manually)
```

### OpenAPI tagging conventions
Every controller method is tagged by its module:
```typescript
@ApiTags('Identity')
@Controller('auth')
export class AuthController { ... }
```

### OperationId conventions
Format: `<Module>_<verb><Resource>` → `Identity_register`, `Orders_placeOrder`, `Seller_createOffer`  
These become generated Angular service method names: `identityService.register(...)`, `ordersService.placeOrder(...)`.

### CI enforcement
A CI step runs `SwaggerModule.createDocument()` in a test environment and diffs against the committed `aliceut-v1.json`. A diff → build failure. This prevents undocumented API drift.

A second CI step runs `openapi-generator-cli` and diffs the generated Angular client against `libs/api-client/` in `aliceut-ecom-frontend/`. A diff → build failure.

---

<a id="81-api-versioning"></a>
## 8.1. API versioning

URI versioning via NestJS built-in `VersioningType.URI`. All routes served under `/api/v{N}/...`.

### Bootstrap setup

```typescript
// main.ts
import { VersioningType } from '@nestjs/common';

app.setGlobalPrefix('api');
app.enableVersioning({
  type: VersioningType.URI,
  defaultVersion: '1',   // controllers without @Version() are treated as v1
});
```

`defaultVersion: '1'` means existing controllers need no annotation for V1 — add `@Version('2')` only when introducing a breaking change.

### Controller convention

Version at the controller class level (not per-method) unless surgically bumping one endpoint:

```typescript
// Tier 1 / Tier 2 controllers — no annotation needed for v1
@ApiTags('Identity')
@Controller('auth')                         // served at /api/v1/auth/*
export class AuthController { ... }

// When introducing a breaking v2 variant, add a new controller file:
@ApiTags('Identity')
@Controller({ path: 'auth', version: '2' }) // served at /api/v2/auth/*
export class AuthV2Controller { ... }
```

Wire both controllers in the same NestJS module. Old `AuthController` continues unchanged.

### OpenAPI impact

`SwaggerModule.createDocument()` picks up the version segment automatically — `/api/v1/auth/login` appears in the generated spec. As long as only V1 exists, `aliceut-v1.json` is the committed spec. When V2 endpoints are introduced, generate a combined spec (all versions in one document) and rename the file to `aliceut-api.json`.

Swagger UI endpoint: `api/docs` (no version prefix — serves all versions).

### Rules
- Never bake a version into `setGlobalPrefix` (the old `api/v1` approach makes all routes always v1 and version bumping requires renaming the prefix).
- Do not use Header or Media-Type versioning — URI versioning is visible in logs, CDN rules, and client code.
- A new controller version requires a new DTO file (e.g. `register-user-v2.dto.ts`) — never mutate a v1 DTO shape.

---

<a id="9-module-wiring-in-the-api-composition-root"></a>
## 9. Module wiring in the API composition root

`apps/api/src/app.module.ts` imports all feature modules and configures shared infrastructure:

```typescript
@Module({
  imports: [
    // Shared infrastructure
    ConfigModule.forRoot({ isGlobal: true, envFilePath: '.env' }),
    TypeOrmModule.forRootAsync({
      useFactory: (cfg: ConfigService) => ({
        type: 'postgres',
        host: cfg.get('POSTGRES_HOST'),
        port: cfg.get<number>('POSTGRES_PORT'),
        username: cfg.get('POSTGRES_USER'),
        password: cfg.get('POSTGRES_PASSWORD'),
        database: cfg.get('POSTGRES_DB'),
        entities: [
          // All TypeORM entities from all modules
          ...IdentityEntities, ...CatalogEntities, ...PricingEntities,
          ...InventoryEntities, ...CartEntities, ...OrdersEntities,
          ...SellerEntities, ...AdminEntities, ...NotificationsEntities,
          ...PlatformEntities,
        ],
        synchronize: false,  // migrations only
      }),
      inject: [ConfigService],
    }),
    ThrottlerModule.forRootAsync({ ... }),

    // Feature modules (see phase module inventory for the active set)
    IdentityModule,
    CatalogModule,
    // ... phase-specific modules
  ],
})
export class AppModule {}
```

### Global bootstrap (`main.ts`)
```typescript
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix('api');
  app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  }));
  app.useGlobalFilters(new GlobalExceptionFilter());
  app.enableCors({ origin: [...allowedOrigins], credentials: true });
  useContainer(app.select(AppModule), { fallbackOnErrors: true });

  const swagger = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, swagger);

  await app.listen(process.env.API_PORT ?? 3000);
}
```

---

<a id="10-workers-composition-root"></a>
## 10. Workers composition root

`apps/workers/src/workers.module.ts` wires only infrastructure + consumer services.

Workers process bootstraps a minimal HTTP server on `PORT_WORKERS` (default: `3001`) exposing a single `GET /health` endpoint that returns HTTP 200 when the outbox relay and all registered consumer groups are running. This is required by the docker-compose healthcheck: `curl -f http://localhost:3001/health`. A NestJS standalone app or a minimal Express server is acceptable for this purpose.

```typescript
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync({ ... }),  // same config as API
    ClientsModule.registerAsync([
      { name: 'KAFKA_CLIENT', useFactory: ... }
    ]),
    ScheduleModule.forRoot(),  // @nestjs/schedule — enables @Cron() decorators
    PlatformModule,            // outbox relay
    // Phase-specific consumer modules wired here
  ],
})
export class WorkersModule {}
```

Consumers are NestJS `@Injectable()` classes decorated with `@EventPattern()` or implemented as KafkaJS consumer groups managed by the Platform module's consumer factory.

Scheduled tasks use `@Cron()` from `@nestjs/schedule` and live under `apps/workers/src/schedulers/`. Each scheduler is a plain `@Injectable()` registered as a provider in `WorkersModule`. Schedulers may inject exported services from feature modules — they never access DB tables directly.  

---

<a id="11-shared-library-libsshared"></a>
## 11. Shared library (`libs/shared`)

`shared` contains **only technical primitives** — no domain entities or business rules.

| Sub-package | Contents |
|-------------|----------|
| `shared/money` | `Money` value object, `decimal.js` wrapper, currency scale lookup |
| `shared/errors` | `AppError` base, `NotFoundError`, `ForbiddenError`, domain error hierarchy |
| `shared/logger` | `StructuredLogger` — JSON output with `correlation_id`, `trace_id` |
| `shared/pagination` | `CursorPage<T>`, `OffsetPage<T>`, cursor encode/decode |
| `shared/uuidv7` | `uuidv7()` generator (wraps `uuid` library) |
| `shared/guards` | `JwtAuthGuard`, `RolesGuard`, `EmailVerifiedGuard`, `SellerApprovedGuard` |
| `shared/decorators` | `@CurrentUser()`, `@Roles()`, `@ApiMoney()` |

Domain modules may import from `shared`. `shared` must never import from any domain module.

---

<a id="12-elasticsearch-index-design"></a>
## 12. Elasticsearch index design

The search module owns one index: `products`.

### Index mapping (simplified)
```json
{
  "mappings": {
    "properties": {
      "productId":    { "type": "keyword" },
      "title":        { "type": "text", "analyzer": "standard" },
      "brand":        { "type": "keyword" },
      "categoryId":   { "type": "keyword" },
      "categoryPath": { "type": "keyword" },
      "status":       { "type": "keyword" },
      "offers": {
        "type": "nested",
        "properties": {
          "offerId":     { "type": "keyword" },
          "sellerId":    { "type": "keyword" },
          "status":      { "type": "keyword" },
          "availableQty":{ "type": "integer" },
          "prices": {
            "type": "nested",
            "properties": {
              "currencyCode": { "type": "keyword" },
              "amount":       { "type": "keyword" },
              // Price amounts stored as keyword strings (e.g. "99.9900") to preserve NUMERIC(19,4)
              // precision and ensure API serialization always returns a string per FR-P-04b.
              // Range filters use the `display_prices` numeric sub-field.
              // Do NOT change to a numeric type — float imprecision corrupts monetary values.
              "priceType":    { "type": "keyword" }
            }
          }
        }
      },
      "inStock":      { "type": "boolean" },
      "createdAt":    { "type": "date" },
      "images":       { "type": "keyword", "index": false }
    }
  }
}
```

**Search query strategy:** Full-text on `title` (boosted), `brand`, `categoryPath`. Facets via aggregations on `categoryId` and nested `prices.amount` (with FX conversion applied at query time using cached FX rates). `inStock` filter applied as a top-level bool filter.

---

<a id="13-design-decisions"></a>
## 13. [DESIGN DECISIONS]

- **[DESIGN DECISION]** URI versioning via `VersioningType.URI` with `defaultVersion: '1'`. `setGlobalPrefix` carries only `'api'` — version segment is injected by NestJS. Reason: baking version into the prefix locks all routes to one version forever; URI versioning lets individual controllers bump independently without touching bootstrap.
- **[DESIGN DECISION]** No `@nestjs/cqrs` dependency in V1. Commands and queries are plain handler classes dispatched by the ApplicationService facade. Removes a framework dependency while retaining the pattern's clarity.
- **[DESIGN DECISION]** TypeORM `synchronize: false` always. Raw SQL migrations are the only schema change mechanism — stored in `alice-ut-utility-pipeline/database/phase-N/` and applied via golang-migrate CLI through GitHub Actions (`workflow_dispatch`). See [conventions/database-migrations.md](database-migrations.md).
- **[DESIGN DECISION]** The Checkout module calls Inventory's ApplicationService synchronously (in-process) rather than via Kafka for the reservation step. This is the only deliberate cross-module synchronous call; it is documented as a composition flow seam. When Inventory is extracted to a separate service, this call is replaced with a two-phase reservation API + saga.
- **[DESIGN DECISION]** `libs/contracts/` holds Avro schemas (`.avsc` files), generated Avro TypeScript types, and the OpenAPI JSON. It is the boundary module — never depends on any domain module. Both `api` and `workers` may import from `contracts`.
