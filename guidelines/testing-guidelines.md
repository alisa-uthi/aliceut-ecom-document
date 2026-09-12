# Testing Guidelines

**Status:** Draft  
**Source of truth:** [BRD v1.2](../phase-1/requirements/BRD.md), [module-architecture](../conventions/module-architecture.md)

---

## Summary

| # | Section | Description |
|---|---------|-------------|
| 1 | [Testing pyramid](#testing-pyramid) | Layer ratios and what belongs at each level |
| 2 | [Coverage thresholds](#coverage-thresholds) | Per-tier minimums and CI enforcement |
| 3 | [NestJS unit tests](#nestjs-unit-tests) | Domain entities, application services, money math |
| 4 | [NestJS integration tests](#nestjs-integration-tests) | Supertest, testcontainers, outbox assertions |
| 5 | [Kafka consumer tests](#kafka-consumer-tests) | Handler isolation, idempotency, DLQ |
| 6 | [Angular unit tests](#angular-unit-tests) | Components, services, guards, forms, pipes |
| 7 | [Angular integration tests](#angular-integration-tests) | Template interaction, CDK harnesses |
| 8 | [E2E tests with Playwright](#e2e-tests) | Critical flows, page objects, seeding |
| 9 | [Test data and fixtures](#test-data) | Factories, seeding strategy, Kaggle exclusion |
| 10 | [What not to test](#what-not-to-test) | Generated code, framework internals, trivial accessors |
| 11 | [CI test gates](#ci-test-gates) | PR vs merge gates, coverage upload |

---

<a id="testing-pyramid"></a>
## 1. Testing pyramid

Target ratio: **70% unit / 20% integration / 10% E2E**.

| Layer | Ratio | What belongs here |
|-------|-------|-------------------|
| Unit | 70% | Domain entities and value objects (pure logic, zero deps). Application service command/query handlers (mock repositories via injection tokens). Angular components in isolation. Money math precision. Pipes. Guards/interceptors without HTTP. |
| Integration | 20% | NestJS modules wired against a real Postgres testcontainer. Outbox writes verified alongside domain changes. Kafka consumer idempotency against embedded or mock broker. Angular component + template interaction against a real `TestBed`. |
| E2E | 10% | Critical happy-path user flows only: buyer checkout, seller listing creation, admin KYC approval. Run against the full local docker-compose stack. |

**Rule of thumb:** if a test needs a database connection or a running server, it is an integration or E2E test. Keep units cheap; do not add testcontainers to a unit test.

---

<a id="coverage-thresholds"></a>
## 2. Coverage thresholds

Coverage is measured per module tier (see [module-architecture ยง2](../conventions/module-architecture.md)). Tier 1 modules contain the richest invariants and receive the highest bar.

| Tier | Modules | Branch | Statement | Line |
|------|---------|--------|-----------|------|
| 1 — Full hexagonal | `catalog`, `orders`, `pricing`, `inventory`, `cart` | 80% | 85% | 85% |
| 2 — Simplified service | `identity`, `seller`, `admin` | 70% | 75% | 75% |
| 3 — Thin / infra | `search`, `notifications`, `workers` | 60% | 65% | 65% |
| Frontend (Angular) | all Angular libs / apps | 70% | 75% | 75% |

**How to measure:**

```bash
# Backend (per lib, from monorepo root)
npx jest --coverage --collectCoverageFrom="libs/catalog/src/**/*.ts"

# Frontend (run per portal)
npx jest --coverage --projects=apps/buyer-portal
npx jest --coverage --projects=apps/seller-portal
npx jest --coverage --projects=apps/admin-portal
```

**CI enforcement:** Jest `coverageThreshold` in each project's `jest.config.ts` enforces the threshold. A PR that drops any metric below its tier floor fails the build. Coverage reports upload to Codecov (or equivalent) on every push. See [ยง11 CI test gates](#ci-test-gates).

---

<a id="nestjs-unit-tests"></a>
## 3. NestJS unit tests

### 3.1 Naming convention

```
describe('ClassName')
  describe('methodName')
    it('should <expected behavior> when <condition>')
```

Example: `describe('Offer') > describe('effectivePrice') > it('should return SALE price when active sale exists and account is B2C')`

### 3.2 Domain entities and value objects

Domain entities in Tier 1 modules are plain TypeScript classes with no framework imports. Test them directly โ€” no mocks needed.

```typescript
// libs/pricing/src/domain/entities/offer.entity.spec.ts
import { Offer } from './offer.entity';
import { Money } from '../value-objects/money.vo';
import Decimal from 'decimal.js';

describe('Offer', () => {
  describe('effectivePrice', () => {
    it('should return SALE price when an active sale exists', () => {
      const salePrice = Money.of(new Decimal('79.99'), 'USD');
      const listPrice = Money.of(new Decimal('99.99'), 'USD');
      const offer = Offer.create({
        listPrice,
        salePrice,
        saleStartsAt: new Date('2026-01-01'),
        saleEndsAt: new Date('2099-12-31'),
      });

      const result = offer.effectivePrice(new Date('2026-06-15'));

      expect(result.amount.toFixed(2)).toBe('79.99');
      expect(result.currency).toBe('USD');
    });

    it('should return LIST price when no active sale exists', () => {
      const offer = Offer.create({ listPrice: Money.of(new Decimal('99.99'), 'USD') });

      const result = offer.effectivePrice(new Date());

      expect(result.amount.toFixed(2)).toBe('99.99');
    });
  });
});
```

### 3.3 Application service handlers

Mock repository interfaces via NestJS injection tokens. Never import the TypeORM adapter in a unit test.

```typescript
// libs/catalog/src/application/commands/publish-product.handler.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { PublishProductHandler } from './publish-product.handler';
import { PRODUCT_REPOSITORY } from '../../domain/repositories/product.repository.interface';

describe('PublishProductHandler', () => {
  let handler: PublishProductHandler;
  const mockProductRepo = {
    findById: jest.fn(),
    save: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PublishProductHandler,
        { provide: PRODUCT_REPOSITORY, useValue: mockProductRepo },
      ],
    }).compile();

    handler = module.get(PublishProductHandler);
    jest.clearAllMocks();
  });

  describe('execute', () => {
    it('should publish the product and persist it', async () => {
      const product = buildProduct({ status: 'DRAFT' });
      mockProductRepo.findById.mockResolvedValue(product);
      mockProductRepo.save.mockResolvedValue(undefined);

      await handler.execute({ productId: product.id });

      expect(mockProductRepo.save).toHaveBeenCalledWith(
        expect.objectContaining({ status: 'PUBLISHED' }),
      );
    });

    it('should throw when product is not found', async () => {
      mockProductRepo.findById.mockResolvedValue(null);

      await expect(handler.execute({ productId: 'nonexistent' })).rejects.toThrow(
        'ProductNotFoundError',
      );
    });
  });
});
```

### 3.4 Money math precision

Every monetary calculation must be tested for precision. Floating-point edge cases are not edge cases here โ€” they are expected inputs.

```typescript
// libs/shared/src/money/money.spec.ts
import Decimal from 'decimal.js';
import { Money } from './money.vo';

describe('Money', () => {
  describe('add', () => {
    it('should not lose precision on repeated fractional addition', () => {
      // 0.1 + 0.2 = 0.30000000000000004 in JS float โ€” must not happen
      const a = Money.of(new Decimal('0.10'), 'USD');
      const b = Money.of(new Decimal('0.20'), 'USD');

      expect(a.add(b).amount.toFixed(2)).toBe('0.30');
    });
  });

  describe('applyFxRate', () => {
    it('should apply FX rate at full 8-decimal precision', () => {
      const usd = Money.of(new Decimal('100.00'), 'USD');
      const rate = new Decimal('33.12345678'); // THB/USD

      expect(usd.applyFxRate(rate, 'THB').amount.toFixed(4)).toBe('3312.3457');
    });
  });

  describe('scale', () => {
    it('should round JPY to 0 decimal places', () => {
      const jpy = Money.of(new Decimal('1500.7'), 'JPY');

      expect(jpy.toDisplayString()).toBe('ยฅ1501');
    });

    it('should round BHD to 3 decimal places', () => {
      const bhd = Money.of(new Decimal('9.9999'), 'BHD');

      expect(bhd.toDisplayString()).toBe('BHD 10.000');
    });
  });
});
```

---

<a id="nestjs-integration-tests"></a>
## 4. NestJS integration tests

### 4.1 Module setup

Use `@nestjs/testing` with `supertest`. Wire only the module under test plus its infrastructure adapters. Never import the full `AppModule`.

```typescript
// libs/catalog/src/catalog.integration.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import * as request from 'supertest';
import { INestApplication } from '@nestjs/common';
import { CatalogModule } from './catalog.module';

let app: INestApplication;

beforeAll(async () => {
  const module: TestingModule = await Test.createTestingModule({
    imports: [CatalogModule],
  }).compile();

  app = module.createNestApplication();
  await app.init();
});

afterAll(async () => {
  await app.close();
});
```

### 4.2 Real Postgres via testcontainers

Use `testcontainers-node` to spin up a real Postgres instance per test suite. Run migrations with `golang-migrate` before the suite starts.

```typescript
import { PostgreSqlContainer, StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import { execSync } from 'child_process';

let pg: StartedPostgreSqlContainer;

beforeAll(async () => {
  pg = await new PostgreSqlContainer('postgres:16-alpine').start();

  // Apply all migrations before tests run
  execSync(
    `migrate -path ./migrations -database "${pg.getConnectionUri()}" up`,
    { stdio: 'inherit' },
  );
});

afterAll(async () => {
  await pg.stop();
});
```

### 4.3 Test isolation โ€” transaction rollback

Wrap each test in a transaction that rolls back. This is faster than truncating tables and guarantees a clean state.

```typescript
import { DataSource, QueryRunner } from 'typeorm';

let queryRunner: QueryRunner;

beforeEach(async () => {
  queryRunner = dataSource.createQueryRunner();
  await queryRunner.startTransaction();
  // Override the module's dataSource connection to use this runner
});

afterEach(async () => {
  await queryRunner.rollbackTransaction();
  await queryRunner.release();
});
```

### 4.4 Outbox assertions

For every command that changes domain state, assert that the corresponding `outbox_event` row was written in the same transaction.

```typescript
it('should write outbox_event when product is published', async () => {
  await request(app.getHttpServer())
    .patch(`/catalog/products/${productId}/publish`)
    .expect(200);

  const outboxRows = await queryRunner.query(
    `SELECT event_type, payload FROM outbox_event WHERE aggregate_id = $1`,
    [productId],
  );

  expect(outboxRows).toHaveLength(1);
  expect(outboxRows[0].event_type).toBe('catalog.product.published.v1');
  expect(JSON.parse(outboxRows[0].payload).productId).toBe(productId);
});
```

---

<a id="kafka-consumer-tests"></a>
## 5. Kafka consumer tests

### 5.1 Unit test handler logic in isolation

Consumer handlers are plain classes that receive a typed message and produce side effects. Unit-test the handler logic with mocked side effects.

```typescript
// libs/workers/src/consumers/order-placed.consumer.spec.ts
import { OrderPlacedConsumer } from './order-placed.consumer';

describe('OrderPlacedConsumer', () => {
  describe('handle', () => {
    it('should send confirmation email on order placed', async () => {
      const mockEmailService = { sendOrderConfirmation: jest.fn() };
      const consumer = new OrderPlacedConsumer(mockEmailService);
      const message = buildOrderPlacedEvent({ orderId: 'ord-1' });

      await consumer.handle(message);

      expect(mockEmailService.sendOrderConfirmation).toHaveBeenCalledWith(
        expect.objectContaining({ orderId: 'ord-1' }),
      );
    });
  });
});
```

### 5.2 Idempotency test

Every consumer must dedupe on `event_id`. Test this explicitly by replaying the same event twice and asserting only one side effect occurs.

```typescript
it('should not send duplicate email when the same event_id is replayed', async () => {
  const mockEmailService = { sendOrderConfirmation: jest.fn() };
  const mockDedupeStore = new InMemoryDedupeStore();
  const consumer = new OrderPlacedConsumer(mockEmailService, mockDedupeStore);
  const message = buildOrderPlacedEvent({ eventId: 'evt-123', orderId: 'ord-1' });

  await consumer.handle(message);
  await consumer.handle(message); // replay

  expect(mockEmailService.sendOrderConfirmation).toHaveBeenCalledTimes(1);
});
```

### 5.3 Integration test with Kafka (optional)

When full broker behavior is needed (offset commit, DLQ routing), use the `kafkajs` `createMockFromSchema` pattern or spin up a Redpanda testcontainer. Keep this to the DLQ routing path; don't duplicate unit test logic.

```typescript
it('should route to DLQ when handler throws a non-retryable error', async () => {
  // Publish a malformed event to the topic, then assert the DLQ topic receives it
  await producer.send({ topic: 'order.placed', messages: [malformedMessage] });

  const dlqMessages = await consumeFromDlq('order.placed.dlq', { timeout: 5000 });
  expect(dlqMessages).toHaveLength(1);
});
```

---

<a id="angular-unit-tests"></a>
## 6. Angular unit tests

Use `jest-preset-angular`. All tests run in jsdom โ€” no real browser.

### 6.1 Components

Shallow-test presentational components. Use `NO_ERRORS_SCHEMA` only for integration-tested components; prefer importing real child components or stubs in unit tests.

```typescript
// apps/buyer-portal/src/app/features/product/product-card.component.spec.ts
import { TestBed } from '@angular/core/testing';
import { ProductCardComponent } from './product-card.component';
import { MoneyPipe } from '../../shared/pipes/money.pipe';

describe('ProductCardComponent', () => {
  describe('display', () => {
    it('should show SALE badge when offer has active sale price', async () => {
      await TestBed.configureTestingModule({
        imports: [ProductCardComponent, MoneyPipe],
      }).compileComponents();

      const fixture = TestBed.createComponent(ProductCardComponent);
      fixture.componentRef.setInput('offer', buildOffer({ hasSalePrice: true }));
      fixture.detectChanges();

      const badge = fixture.nativeElement.querySelector('[data-testid="sale-badge"]');
      expect(badge).not.toBeNull();
    });
  });
});
```

### 6.2 Services using the generated API client

Use `HttpClientTestingModule` and `HttpTestingController` to intercept HTTP calls made by the OpenAPI-generated client.

```typescript
import { HttpClientTestingModule, HttpTestingController } from '@angular/common/http/testing';

describe('CartService', () => {
  describe('addItem', () => {
    it('should POST to /cart/items and return the updated cart', () => {
      TestBed.configureTestingModule({
        imports: [HttpClientTestingModule],
        providers: [CartService],
      });
      const service = TestBed.inject(CartService);
      const http = TestBed.inject(HttpTestingController);

      service.addItem({ offerId: 'offer-1', qty: 2 }).subscribe((cart) => {
        expect(cart.items).toHaveLength(1);
      });

      const req = http.expectOne('/api/cart/items');
      expect(req.request.method).toBe('POST');
      req.flush({ data: { items: [{ offerId: 'offer-1', qty: 2 }] } });
      http.verify();
    });
  });
});
```

### 6.3 Guards and interceptors

Test `CanActivate` guards by calling `canActivate()` directly against a mock `ActivatedRouteSnapshot`.

```typescript
describe('AuthGuard', () => {
  describe('canActivate', () => {
    it('should return false and redirect to /login when user is not authenticated', () => {
      const mockAuthService = { isAuthenticated: jest.fn().mockReturnValue(false) };
      const mockRouter = { navigate: jest.fn() };
      const guard = new AuthGuard(mockAuthService as any, mockRouter as any);

      const result = guard.canActivate({} as any, {} as any);

      expect(result).toBe(false);
      expect(mockRouter.navigate).toHaveBeenCalledWith(['/login']);
    });
  });
});
```

### 6.4 Reactive forms

Test that validators fire and error state is correct. Never test Angular's built-in validators โ€” only your custom validators and the form wiring.

```typescript
describe('ListingFormComponent', () => {
  describe('priceField', () => {
    it('should be invalid when a non-numeric string is entered', () => {
      const form = new ListingFormComponent().form;
      form.get('price')!.setValue('abc');
      expect(form.get('price')!.hasError('invalidDecimal')).toBe(true);
    });
  });
});
```

### 6.5 Money formatting pipe

The `MoneyPipe` transforms string amounts using `decimal.js`. Cover currency-specific scale, including JPY (0 decimals) and THB (2 decimals).

```typescript
describe('MoneyPipe', () => {
  const pipe = new MoneyPipe();

  it('should format USD to 2 decimal places', () => {
    expect(pipe.transform('99.9', 'USD')).toBe('$99.90');
  });

  it('should format JPY with no decimal places', () => {
    expect(pipe.transform('1500', 'JPY')).toBe('ยฅ1,500');
  });

  it('should format THB with symbol and 2 decimal places', () => {
    expect(pipe.transform('350.50', 'THB')).toBe('เธฟ350.50');
  });
});
```

---

<a id="angular-integration-tests"></a>
## 7. Angular integration tests

Integration tests wire a real `TestBed` with child components, real services (backed by `HttpClientTestingModule`), and real Angular Material modules. They test component + template interaction.

### 7.1 Angular CDK harnesses for Material components

Use `MatButtonHarness`, `MatInputHarness`, etc. from `@angular/material/testing`. These are stable, accessible, and theme-agnostic.

```typescript
import { HarnessLoader } from '@angular/cdk/testing';
import { TestbedHarnessEnvironment } from '@angular/cdk/testing/testbed';
import { MatButtonHarness } from '@angular/material/button/testing';
import { MatInputHarness } from '@angular/material/input/testing';

describe('CheckoutFormComponent (integration)', () => {
  let loader: HarnessLoader;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [CheckoutFormComponent, ReactiveFormsModule, MatFormFieldModule, MatInputModule, MatButtonModule],
    }).compileComponents();

    const fixture = TestBed.createComponent(CheckoutFormComponent);
    loader = TestbedHarnessEnvironment.loader(fixture);
    fixture.detectChanges();
  });

  it('should disable the submit button until the form is valid', async () => {
    const submitBtn = await loader.getHarness(MatButtonHarness.with({ text: /place order/i }));
    expect(await submitBtn.isDisabled()).toBe(true);

    const addressInput = await loader.getHarness(MatInputHarness.with({ placeholder: /shipping address/i }));
    await addressInput.setValue('123 Test Street');

    expect(await submitBtn.isDisabled()).toBe(false);
  });
});
```

---

<a id="e2e-tests"></a>
## 8. E2E tests with Playwright

### 8.1 Critical user flows

E2E tests cover the golden path only. Exhaustive validation belongs in unit and integration tests.

| Flow | Actor | Coverage |
|------|-------|----------|
| Buyer checkout | Buyer | Browse โ’ add to cart โ’ checkout โ’ order confirmation |
| Seller listing creation | Seller | Login โ’ new listing โ’ submit for review |
| Admin KYC approval | Admin | View pending KYC โ’ approve โ’ seller status updated |

### 8.2 Page object model

Each page or significant UI region gets a dedicated page object class. Do not write raw `page.click(selector)` calls inside tests.

```typescript
// e2e/page-objects/checkout.page.ts
import { Page } from '@playwright/test';

export class CheckoutPage {
  constructor(private readonly page: Page) {}

  async goto() {
    await this.page.goto('/checkout');
  }

  async fillShippingAddress(address: string) {
    await this.page.getByLabel('Shipping address').fill(address);
  }

  async placeOrder() {
    await this.page.getByRole('button', { name: /place order/i }).click();
    await this.page.waitForURL(/\/orders\/.+\/confirmation/);
  }

  async getConfirmationOrderId() {
    return this.page.getByTestId('order-id').textContent();
  }
}
```

```typescript
// e2e/tests/buyer-checkout.spec.ts
import { test, expect } from '@playwright/test';
import { CheckoutPage } from '../page-objects/checkout.page';

test('buyer can complete checkout', async ({ page }) => {
  const checkout = new CheckoutPage(page);
  // Seed: use API to add an item to the cart before the test starts
  await seedCart(page, { offerId: fixtures.offer.id, qty: 1 });

  await checkout.goto();
  await checkout.fillShippingAddress('123 Test Street, Bangkok, 10110');
  await checkout.placeOrder();

  const orderId = await checkout.getConfirmationOrderId();
  expect(orderId).toMatch(/^ord-/);
});
```

### 8.3 Test data seeding strategy

E2E tests must not rely on existing database state. Seed via the backend API using a dedicated test-token header (only active when `NODE_ENV=test`). Never seed by writing directly to the database from Playwright.

```typescript
// e2e/helpers/seed.ts
import { request } from '@playwright/test';

export async function seedCart(page: Page, item: { offerId: string; qty: number }) {
  const api = await request.newContext({ baseURL: process.env.API_BASE_URL });
  await api.post('/internal/test/cart', {
    headers: { 'X-Test-Token': process.env.E2E_TEST_TOKEN! },
    data: item,
  });
}
```

### 8.4 Running against docker-compose

```bash
# Start the full stack
docker compose -f docker-compose.yml -f docker-compose.test.yml up -d

# Wait for health checks, then run Playwright
npx playwright test --project=chromium
```

The `docker-compose.test.yml` override sets `NODE_ENV=test` and enables the `X-Test-Token` seeding endpoint.

---

<a id="test-data"></a>
## 9. Test data and fixtures

### 9.1 Factory pattern for domain entities

Use builder/factory functions โ€” not class constructors โ€” to create test objects. Factories always provide valid defaults; tests override only what they care about.

```typescript
// tests/factories/offer.factory.ts
import Decimal from 'decimal.js';
import { Offer, OfferProps } from '../../libs/pricing/src/domain/entities/offer.entity';
import { Money } from '../../libs/pricing/src/domain/value-objects/money.vo';

export function buildOffer(overrides: Partial<OfferProps> = {}): Offer {
  return Offer.create({
    sellerId: 'seller-default',
    productId: 'product-default',
    listPrice: Money.of(new Decimal('99.99'), 'USD'),
    ...overrides,
  });
}
```

### 9.2 Seeding for integration tests

Each integration test suite maintains its own seed file. Seeds are thin โ€” only the rows required by the suite, not a full snapshot.

```
tests/
└── fixtures/
    ├── catalog-integration.seed.sql   Products and offers for catalog suite
    ├── orders-integration.seed.sql    Orders + fulfillment items for orders suite
    └── identity-integration.seed.sql  Users and roles for identity suite
```

Run fixtures after `migrate up` in the `beforeAll` hook. Roll them back as part of each test's transaction rollback or via `afterAll` truncate.

### 9.3 Kaggle data exclusion

The 100-product Kaggle seed in `phase-1/seed/` is for local developer setup only. It must never be imported into test fixtures, nor referenced in any `*.spec.ts` or Playwright spec file. Tests that need product data build it with factories or minimal SQL seeds.

---

<a id="what-not-to-test"></a>
## 10. What not to test

| Category | Examples | Reason |
|----------|----------|--------|
| Generated code | TypeORM entities with `@Column` decorators, OpenAPI Angular client (`libs/contracts/src/generated/`) | Generated; changes are tracked in the generator config, not test assertions |
| Framework internals | Angular's `ChangeDetectorRef`, NestJS dependency injection graph, TypeORM connection pooling | Tested upstream by the framework maintainers |
| Trivial accessors | `getTitle()` returning `this.title`, read-only DTO fields | Zero logic to break; adds noise without safety |
| Third-party library behavior | `decimal.js` arithmetic correctness, Passport.js strategy invocation | Not our code; trust the library's own test suite |
| Configuration wiring | Whether `AppModule` imports `CatalogModule` | Structural โ€” caught by startup, not assertions |

Do not add tests just to hit coverage thresholds. A test that asserts `expect(obj.id).toBe(obj.id)` is worse than no test.

---

<a id="ci-test-gates"></a>
## 11. CI test gates

### 11.1 On every PR

| Suite | Command | Failure action |
|-------|---------|----------------|
| Backend unit tests | `jest --projects=libs --testPathPattern=".spec.ts$" --passWithNoTests` | Block merge |
| Angular unit tests | `jest --projects=apps/buyer-portal,apps/seller-portal,apps/admin-portal --passWithNoTests` | Block merge |
| Coverage check | `jest --coverage` (thresholds enforced by config) | Block merge |
| TypeScript compile | `tsc --noEmit` (both `api` and `buyer-portal`) | Block merge |
| Lint | `eslint` with money-field lint rule | Block merge |

### 11.2 On merge to main

| Suite | Command | Failure action |
|-------|---------|----------------|
| Integration tests | `jest --testPathPattern=".integration.spec.ts$"` (with testcontainers) | Block deploy |
| E2E (Playwright) | `playwright test --project=chromium` against docker-compose | Block deploy |
| Consumer idempotency tests | `jest --testPathPattern=".consumer.spec.ts$"` | Block deploy |

### 11.3 Coverage report upload

Upload `coverage/lcov.info` to Codecov (or a self-hosted equivalent) on every push. Annotate PRs with the coverage delta. Do not gate on the absolute upload succeeding โ€” network flakiness in coverage upload must not block a passing build.

```yaml
# ci fragment โ€” upload step
- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: coverage/lcov.info
  continue-on-error: true
```
