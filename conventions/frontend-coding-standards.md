# Frontend Coding Standards

**Status:** Complete  
**Source of truth:** [BRD v1.2](../phase-1/requirements/BRD.md), [design-system](design-system.md)

---

## Summary

| Section | Description |
|---------|-------------|
| [1. Project structure](#1-project-structure) | Angular workspace layout and lib boundaries |
| [2. Component architecture](#2-component-architecture) | Standalone, smart/dumb split, OnPush |
| [3. State management](#3-state-management) | Services + signals/BehaviorSubject, no NgRx |
| [4. HTTP and API client](#4-http-and-api-client) | Generated client, interceptors, error handling |
| [5. Money display patterns](#5-money-display-patterns) | MoneyPipe, Intl.NumberFormat, no JS number |
| [6. Form patterns](#6-form-patterns) | Reactive forms, typed FormGroup, mat-error |
| [7. Routing and guards](#7-routing-and-guards) | Route structure, CanActivateFn, lazy loading |
| [8. Angular Material usage rules](#8-angular-material-usage-rules) | Component choices, import strategy |
| [9. TypeScript and ESLint](#9-typescript-and-eslint) | Strict mode, naming, lint rules |
| [10. Accessibility](#10-accessibility) | aria-label, matLabel, keyboard nav |
| [11. Performance](#11-performance) | Lazy routes, trackBy, async pipe |

---

<a id="1-project-structure"></a>
## 1. Project structure

Angular workspace root is `aliceut-ecom-frontend/`. All apps and shared libraries live under it.

```
aliceut-ecom-frontend/
├── angular.json
├── tsconfig.base.json
├── apps/
│   ├── buyer-app/       # mobile-first; public catalog + auth flows
│   ├── seller-app/      # desktop-first; listing, inventory, order management
│   └── admin-app/       # desktop-first; KYC, moderation, platform ops
└── libs/
    ├── api-client/         # generated TypeScript client (openapi-generator-cli)
    ├── ui/                 # presentational components, pipes, directives (no domain logic)
    └── shared-util/        # pure functions: money formatting, date helpers, validators
```

### What belongs where

| Code | Location |
|------|----------|
| Generated API services and models | `libs/api-client/` — never hand-edit |
| `ProductCardComponent`, `StatusBadgeComponent`, all shared UI | `libs/ui/` |
| `CurrencyDisplayPipe`, `TimeAgoPipe`, `TruncatePipe` | `libs/ui/src/lib/pipes/` |
| `formatMoney()`, `parseCurrencyScale()` pure utils | `libs/shared-util/` |
| `CartService`, `AuthService`, `NotificationService` | App-level (`apps/<portal>/src/app/core/`) — not shared-ui |
| Feature modules (product listing, checkout, KYC flow) | `apps/<portal>/src/app/features/<name>/` |
| Portal shell, routing, guards | `apps/<portal>/src/app/` |

**Import boundary:** `shared-ui` and `shared-util` must not import from any app or from each other circularly. Apps import from libs; libs never import from apps.

Path aliases in `tsconfig.base.json`:

```json
{
  "paths": {
    "@aliceut/api-client": ["libs/api-client/src/index.ts"],
    "@aliceut/shared-ui": ["libs/ui/src/index.ts"],
    "@aliceut/shared-util": ["libs/shared-util/src/index.ts"]
  }
}
```

---

<a id="2-component-architecture"></a>
## 2. Component architecture

### Standalone components

Prefer standalone components (Angular 22+ default). Use `NgModule` only when third-party libraries require it as a host.

```typescript
@Component({
  selector: 'aliceut-product-card',
  standalone: true,
  imports: [MatCardModule, MatButtonModule, CurrencyDisplayPipe, RouterLink],
  templateUrl: './product-card.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ProductCardComponent { ... }
```

### Smart vs dumb split

| Type | Responsibilities | Rule |
|------|-----------------|------|
| **Smart (container)** | Injects services, fetches data, handles routing, dispatches actions | One per feature route; named `<Feature>PageComponent` |
| **Dumb (presentational)** | Renders inputs, emits output events, no service injection | All shared-ui components; no `inject()` for domain services |

Pass data down via `@Input()`. Communicate up via `@Output()` events. Never inject `CartService` or `AuthService` inside a component in `shared-ui/`.

### Change detection

`ChangeDetectionStrategy.OnPush` is the default for every component. Exceptions require a comment explaining why.

The only acceptable patterns for triggering CD in OnPush components:

- `async` pipe in template (preferred)
- Signal reads (`mySignal()`) in template
- Explicit `markForCheck()` after an imperative push (last resort)

Avoid mutating arrays or objects in place — always produce new references so OnPush detects the change.

### Loading / empty / error states

Every data-fetching component must define all three states. Use a discriminated union:

```typescript
type ViewState<T> =
  | { status: 'loading' }
  | { status: 'empty' }
  | { status: 'error'; message: string }
  | { status: 'loaded'; data: T };
```

Template pattern:

```html
@switch (viewState.status) {
  @case ('loading') { <aliceut-skeleton-list /> }
  @case ('empty')   { <aliceut-empty-state icon="receipt_long" title="No orders yet" /> }
  @case ('error')   { <aliceut-error-banner [message]="viewState.message" /> }
  @case ('loaded')  { <!-- actual content --> }
}
```

Do not use `*ngIf="data && !loading && !error"` chains — they produce invisible error states.

---

<a id="3-state-management"></a>
## 3. State management

No NgRx in V1. Angular services with `BehaviorSubject` or `signal()` cover all V1 needs.

### Singleton stores (app-level, provided in root)

| Service | State held | Tech |
|---------|-----------|------|
| `AuthService` | `currentUser`, access token in memory, logout | `BehaviorSubject<User \| null>` |
| `CartService` | cart items, item count, total (display only) | `signal<CartItem[]>` |
| `NotificationService` | unread notifications, toast queue | `BehaviorSubject<Notification[]>` |

### When to use `signal()` vs `BehaviorSubject`

| Scenario | Use |
|----------|-----|
| Simple local component state (toggle, counter, selected tab) | `signal()` |
| Cross-component shared state that multiple services or components subscribe to | `BehaviorSubject<T>` |
| Derived/computed values from other state | `computed()` (from signals) |
| Stream of async events (HTTP, polling) | `Observable` piped into a `BehaviorSubject` via `subscribe` in service |

Expose `BehaviorSubject` values as `asObservable()` from services — components must not call `.next()` directly.

```typescript
@Injectable({ providedIn: 'root' })
export class CartService {
  private _items = signal<CartItem[]>([]);

  readonly items = this._items.asReadonly();
  readonly itemCount = computed(() => this._items().reduce((n, i) => n + i.quantity, 0));

  addItem(item: CartItem): void {
    this._items.update(current => [...current, item]);
  }
}
```

---

<a id="4-http-and-api-client"></a>
## 4. HTTP and API client

### Use only the generated client

Never call `HttpClient` directly for API endpoints. Always use the generated services from `@aliceut/api-client`.

```typescript
// Wrong
this.http.get<Order[]>('/api/orders')

// Correct
this.ordersApi.ordersList({ limit: 20 })
```

The generated client is at `libs/api-client/` and produced by `openapi-generator-cli typescript-angular` from the backend OpenAPI spec. Re-generate after any API spec change.

### JWT auth: access token storage

Access token is stored **in memory only** (a private variable in `AuthService`). It is never written to `localStorage` or `sessionStorage`.

Refresh token is stored in an **httpOnly cookie** set by the server — the frontend never reads it directly. On app load, `AuthService` calls `POST /auth/refresh` to silently restore a session if the cookie is present.

### HTTP interceptors

Register interceptors in `app.config.ts` via `provideHttpClient(withInterceptors([...]))`.

```typescript
// auth.interceptor.ts
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const token = authService.accessToken();
  const authed = token
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req;
  return next(authed);
};
```

Required interceptors (in order):

| Interceptor | Responsibility |
|-------------|---------------|
| `authInterceptor` | Attaches `Authorization: Bearer <token>` when token is present |
| `refreshInterceptor` | On 401, calls `POST /auth/refresh` once, replays original request; on second 401, redirects to login |
| `correlationIdInterceptor` | Attaches `X-Correlation-Id: <uuid>` header on every outbound request |

### Error handling

Map API error shape (`{ statusCode, message, errors }` — see [api-conventions.md](api-conventions.md)) to user-facing feedback in a shared `ApiErrorHandler` service:

```typescript
@Injectable({ providedIn: 'root' })
export class ApiErrorHandler {
  private snackBar = inject(MatSnackBar);

  handle(err: HttpErrorResponse): void {
    const msg = err.error?.message ?? 'An unexpected error occurred.';
    this.snackBar.open(msg, 'Dismiss', { duration: 5000, panelClass: 'snack-error' });
  }
}
```

Smart components call `apiErrorHandler.handle(err)` in their `catchError`. Never show raw HTTP status codes to the user.

---

<a id="5-money-display-patterns"></a>
## 5. Money display patterns

All monetary values arrive from the API as **strings** (e.g. `"99.9900"`). See [api-conventions.md § Money](api-conventions.md).

### Rule

Never convert a monetary string to a JS `number` for arithmetic or display. Use `decimal.js` or `Big.js` for any calculation; use `Intl.NumberFormat` only at the final render boundary.

### CurrencyDisplayPipe

Lives at `libs/ui/src/lib/pipes/currency-display.pipe.ts`. Exported from `@aliceut/shared-ui`.

```typescript
@Pipe({ name: 'currencyDisplay', standalone: true, pure: true })
export class CurrencyDisplayPipe implements PipeTransform {
  transform(amount: string, currencyCode: string): string {
    const scale = CURRENCY_SCALE[currencyCode] ?? 2;
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency: currencyCode,
      minimumFractionDigits: scale,
      maximumFractionDigits: scale,
    }).format(Number(amount)); // Number() only at Intl boundary — no arithmetic
  }
}
```

Currency scale lookup (add to `libs/shared-util/src/lib/currency.ts`):

```typescript
export const CURRENCY_SCALE: Record<string, number> = {
  JPY: 0,
  BHD: 3, KWD: 3,
  USD: 2, THB: 2, SGD: 2,
};
```

Template usage:

```html
<span>{{ offer.price.amount | currencyDisplay:offer.price.currency }}</span>
```

### Buyer display-currency conversion

The buyer's display currency preference is a **display-only conversion**. It does not affect which `Price` row the server selects. The frontend:

1. Reads the buyer's preferred currency from `AuthService` (or a `PreferencesService`).
2. Fetches cached FX rates from `GET /fx-rates` (cached in `FxRateService` for the session).
3. Applies multiplication via `Decimal` from `decimal.js` — never via JS `*` on numbers — then formats with `CurrencyDisplayPipe`.

```typescript
// FX estimate — decimal.js multiplication only
const rate = new Decimal(fxRates[fromCurrency][toCurrency]);
const converted = new Decimal(amount).mul(rate).toFixed(scale);
```

Mark FX-estimated amounts visually: prefix with `≈` and show an info tooltip (see `PriceDisplay` component in [design-system.md § 8.3](design-system.md)).

---

<a id="6-form-patterns"></a>
## 6. Form patterns

Reactive forms only — no template-driven forms. Use typed `FormGroup<T>` (Angular 14+).

```typescript
interface LoginForm {
  email: FormControl<string>;
  password: FormControl<string>;
}

form = new FormGroup<LoginForm>({
  email:    new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.email] }),
  password: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.minLength(8)] }),
});
```

### Validation error display

Show `mat-error` only after a field is touched or the form has been submitted. Never show errors on pristine fields.

```html
<mat-form-field appearance="outline" subscriptSizing="dynamic">
  <mat-label>Email</mat-label>
  <input matInput formControlName="email" type="email" />
  <mat-error *ngIf="form.controls.email.hasError('required')">Email is required</mat-error>
  <mat-error *ngIf="form.controls.email.hasError('email')">Enter a valid email address</mat-error>
  <mat-error *ngIf="form.controls.email.hasError('emailTaken')">This email is already registered</mat-error>
</mat-form-field>
```

`subscriptSizing="dynamic"` prevents layout shift when validation messages appear.

### Async validators

Async validators (e.g. email uniqueness) show a `mat-spinner` in the suffix slot during the pending state. Debounce with `debounceTime(400)` in the validator to avoid firing on every keystroke.

```html
<mat-form-field appearance="outline">
  <mat-label>Email</mat-label>
  <input matInput formControlName="email" />
  <mat-spinner *ngIf="form.controls.email.pending" matSuffix diameter="18" />
</mat-form-field>
```

### Submit button

Disable the submit button while the form is invalid or any control is pending:

```html
<button
  mat-flat-button
  color="primary"
  type="submit"
  [disabled]="form.invalid || form.pending"
>
  Submit
</button>
```

### Monetary inputs

Always use the `CurrencyInputComponent` from `@aliceut/shared-ui`. Never use `<input type="number">` for monetary fields — it converts strings to JS floats.

### Multi-step forms

Use `mat-stepper` in linear mode. Each step validates before proceeding; invalid steps block the next step navigation.

---

<a id="7-routing-and-guards"></a>
## 7. Routing and guards

All feature routes are **lazily loaded**. No eager imports of feature components in `AppComponent`.

### Route structure per portal

**Buyer portal:**

```typescript
export const routes: Routes = [
  { path: '', loadComponent: () => import('./features/home/home-page.component') },
  { path: 'search', loadComponent: () => import('./features/catalog/search-page.component') },
  { path: 'product/:id', loadComponent: () => import('./features/catalog/product-detail-page.component') },
  { path: 'cart', loadComponent: () => import('./features/cart/cart-page.component'), canActivate: [authGuard] },
  { path: 'checkout', loadChildren: () => import('./features/checkout/checkout.routes'), canActivate: [authGuard, emailVerifiedGuard] },
  { path: 'orders', loadChildren: () => import('./features/orders/orders.routes'), canActivate: [authGuard] },
  { path: 'account', loadChildren: () => import('./features/account/account.routes'), canActivate: [authGuard] },
  { path: 'auth', loadChildren: () => import('./features/auth/auth.routes') },
];
```

**Seller portal:** all routes require `sellerApprovedGuard` except the KYC submission flow.

**Admin portal:** all routes require `roleGuard` with `role: 'ADMIN'`.

### Guard matrix

| Guard | Condition | Failure redirect |
|-------|-----------|-----------------|
| `authGuard` | Valid access token present in `AuthService` | `/auth/login?returnUrl=<current>` |
| `emailVerifiedGuard` | `currentUser.emailVerified === true` | `/account/verify-email` |
| `sellerApprovedGuard` | `currentUser.sellerKycStatus === 'APPROVED'` | `/seller/kyc` |
| `roleGuard` | `currentUser.roles` contains required role | `/403` |

All guards are `CanActivateFn` (functional guards — no class-based guards).

```typescript
export const authGuard: CanActivateFn = (route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (auth.isAuthenticated()) return true;
  return router.createUrlTree(['/auth/login'], { queryParams: { returnUrl: state.url } });
};
```

### Post-login redirect

After a successful login, read `?returnUrl=` from `ActivatedRoute.snapshot.queryParams` and navigate there. Default to `/` if absent. Validate the `returnUrl` is a relative path (starts with `/`) before using it — reject absolute URLs to prevent open redirects.

---

<a id="8-angular-material-usage-rules"></a>
## 8. Angular Material usage rules

Follow [design-system.md](design-system.md) for palette, typography, spacing, and shared components. This section covers import and usage rules.

### No custom component if Material has one

Before writing a custom component, check whether an Angular Material component fulfils the need. Exceptions require a comment.

### Component choices for common patterns

| Need | Use |
|------|-----|
| Toast / brief feedback | `MatSnackBar` — 3s duration, bottom-center |
| Confirmation dialogs | `ConfirmDialogComponent` from `@aliceut/shared-ui` |
| Data tables | `MatTable` + `MatPaginator` + `MatSort` (wrapped by `DataTableComponent` from `@aliceut/shared-ui`) |
| Multi-step forms | `MatStepper` linear mode |
| Navigation drawers (seller/admin) | `MatSidenav` |
| Selection chips / tags | `MatChipListbox` |
| Loading indicators | `MatProgressBar` (page-level) / `MatProgressSpinner` (inline) |
| Tooltips | `MatTooltip` directive |
| Date inputs | `MatDatepicker` with Angular Material datepicker module |

### Import strategy

Feature components must import individual Angular Material modules, not a catch-all `MatModule` barrel. This keeps tree-shaking effective.

```typescript
// Correct — named imports
@Component({
  standalone: true,
  imports: [MatCardModule, MatButtonModule, MatIconModule],
})

// Wrong — barrel that defeats tree-shaking
imports: [MatModule]
```

Components in `shared-ui` re-export the AM modules they use. Feature components that use a `shared-ui` wrapper do not re-import the underlying AM module.

### Snackbar conventions

```typescript
// Success
this.snackBar.open('Order placed successfully', undefined, {
  duration: 3000,
  panelClass: 'snack-success',
});

// Error (persistent until dismissed)
this.snackBar.open(errorMessage, 'Dismiss', {
  panelClass: 'snack-error',
});
```

Define `snack-success` and `snack-error` panel classes in the global stylesheet using semantic color tokens from [design-system.md § 2](design-system.md).

---

<a id="9-typescript-and-eslint"></a>
## 9. TypeScript and ESLint

### TypeScript config

`strict: true` in `tsconfig.base.json`. Additional flags required:

```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictTemplates": true,
    "strictInjectionParameters": true,
    "noUncheckedIndexedAccess": true
  }
}
```

`strictTemplates: true` catches binding type errors in HTML — do not disable it to avoid fixing template issues.

### Forbidden patterns on money fields

ESLint rule (custom or via `@typescript-eslint/no-explicit-any` with type-pattern overrides) must flag `number` type on any identifier matching `*price*`, `*amount*`, `*tax*`, `*fee*`, `*total*`, `*subtotal*`. These fields must be `string` at API boundaries and `Decimal` when involved in arithmetic.

```typescript
// Wrong
interface CartItem {
  unitPrice: number; // ESLint error
}

// Correct
interface CartItem {
  unitPrice: string;
  currency: string;
}
```

### File naming

| Artifact | Convention | Example |
|----------|-----------|---------|
| Component | `kebab-case.component.ts` | `product-card.component.ts` |
| Service | `kebab-case.service.ts` | `cart.service.ts` |
| Pipe | `kebab-case.pipe.ts` | `currency-display.pipe.ts` |
| Guard | `kebab-case.guard.ts` | `auth.guard.ts` |
| Interceptor | `kebab-case.interceptor.ts` | `auth.interceptor.ts` |
| Route file | `kebab-case.routes.ts` | `checkout.routes.ts` |
| Model/DTO | `kebab-case.model.ts` | `order.model.ts` |

### Barrel files

`index.ts` barrels are allowed at lib root boundaries only (`libs/ui/src/index.ts`). Do not create barrels inside feature folders — they cause circular dependency issues.

### ESLint config baseline

```json
{
  "extends": [
    "plugin:@angular-eslint/recommended",
    "plugin:@typescript-eslint/recommended-type-checked"
  ],
  "rules": {
    "@typescript-eslint/no-explicit-any": "error",
    "@angular-eslint/prefer-standalone": "warn",
    "no-console": ["warn", { "allow": ["warn", "error"] }]
  }
}
```

---

<a id="10-accessibility"></a>
## 10. Accessibility

Angular Material handles baseline accessibility for its components. The rules below cover gaps and AliceUT-specific requirements.

### Icon-only buttons

Every `mat-icon-button` without visible text must have `aria-label`:

```html
<button mat-icon-button aria-label="Remove item from cart" (click)="remove(item)">
  <mat-icon>close</mat-icon>
</button>
```

### Form labels

Every `mat-form-field` must contain a `mat-label`. Never rely on `placeholder` as the only label — it disappears on focus and is not reliably announced by screen readers.

```html
<!-- Correct -->
<mat-form-field>
  <mat-label>Search products</mat-label>
  <input matInput [(ngModel)]="query" />
</mat-form-field>

<!-- Wrong — placeholder only -->
<mat-form-field>
  <input matInput placeholder="Search products" />
</mat-form-field>
```

### Color is never the only state indicator

All status badges combine color and text (or color and icon). Never use color alone. See [design-system.md § 8.2](design-system.md) for `StatusBadgeComponent`.

### Images

All `<img>` elements must have `alt`. Product images use the product title. Decorative images use `alt=""`.

### Keyboard navigation

Custom interactive elements that are not native `<button>` or `<a>` must have `role`, `tabindex="0"`, and keydown handlers for `Enter` / `Space`. Prefer native elements over custom interactive divs.

### Screen reader supplements

Use `.cdk-visually-hidden` for supplemental text not visible on screen (e.g. "3 items in cart" after a badge showing "3"):

```html
<mat-icon matBadge="3">shopping_cart</mat-icon>
<span class="cdk-visually-hidden">3 items in cart</span>
```

### Skip link

Each portal shell includes a skip-to-main-content link as the first focusable element in the DOM:

```html
<a class="skip-link" href="#main-content">Skip to main content</a>
```

---

<a id="11-performance"></a>
## 11. Performance

### Lazy loading (required)

Every feature route must be lazily loaded with `loadComponent` or `loadChildren`. Eager loading a feature route is a build-time error (enforced by `@angular-eslint` rule `no-forward-ref` + code review).

### trackBy on ngFor

Use `trackBy` on every `*ngFor` over a list that can change:

```typescript
trackByOrderId(_index: number, order: Order): string {
  return order.id;
}
```

```html
<mat-list-item *ngFor="let order of orders; trackBy: trackByOrderId">
```

For static lists (e.g. enum labels), `trackBy` is optional.

### OnPush everywhere

Every component defaults to `ChangeDetectionStrategy.OnPush`. This is a lint-enforced rule via `@angular-eslint/prefer-on-push-component-change-detection`.

### async pipe over manual subscriptions

Use the `async` pipe in templates to subscribe to observables. It auto-unsubscribes on component destroy.

```html
<!-- Correct -->
<mat-list-item *ngFor="let n of notifications$ | async">

<!-- Wrong — requires manual ngOnDestroy unsubscribe -->
notifications: Notification[] = [];
ngOnInit() { this.notifService.list$.subscribe(n => this.notifications = n); }
```

When subscribing imperatively (unavoidable in smart components handling user events), use `takeUntilDestroyed(this.destroyRef)`.

### Image lazy loading

All product images not in the initial viewport use `loading="lazy"`:

```html
<img [src]="product.imageUrl" [alt]="product.title" loading="lazy" />
```

Above-the-fold hero images use `loading="eager"` (or omit the attribute) to avoid LCP penalty.

### Bundle size

- Import only the operators you use from `rxjs` — `import { map, filter } from 'rxjs/operators'`.
- Import Material modules individually (see §8) to enable tree-shaking.
- Run `ng build --stats-json && npx webpack-bundle-analyzer dist/stats.json` to audit bundle size before releasing a feature.
