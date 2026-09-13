# CLAUDE.md — aliceut-ecom-frontend

> Copy this file to the root of `aliceut-ecom-frontend/` as `CLAUDE.md` on first clone.
> Full conventions live in sibling repo `../aliceut-ecom-document/`. Read them before proposing architectural changes.

---

## Repo identity

Angular 22+ Nx monorepo. Three portals: `buyer-app` (mobile-first), `seller-app` (desktop-first), `admin-app` (desktop-first). Shared libs: `api-client` (generated), `ui`, `shared-util`.

## Locked stack (BRD §12 — treat as constraints, not suggestions)

| Layer | Technology |
|-------|-----------|
| Framework | Angular 22+ |
| UI library | Angular Material |
| HTTP client | Generated `@aliceut/api-client` (openapi-generator-cli) — never `HttpClient` directly |
| State | Services + Angular signals / `BehaviorSubject` — no NgRx |
| Money | `Intl.NumberFormat` via `MoneyPipe` — never JS `number` for monetary display |
| Deploy | docker-compose (V1) |

---

## Workspace layout

```
aliceut-ecom-frontend/
├── apps/
│   ├── buyer-app/       mobile-first; public catalog, auth, cart, checkout, orders
│   ├── seller-app/      desktop-first; listings, inventory, orders, KYC
│   └── admin-app/       desktop-first; KYC moderation, user management, platform ops
└── libs/
    ├── api-client/      generated Angular HTTP client — NEVER hand-edit
    ├── ui/              presentational components, pipes, directives (no domain logic)
    └── shared-util/     pure functions: money formatting, date helpers, validators
```

**Import boundary:** `libs/` never import from apps. Apps import from libs. `api-client`, `ui`, `shared-util` must not import from each other circularly.

Path aliases (`tsconfig.base.json`):

```json
{
  "@aliceut/api-client":   "libs/api-client/src/index.ts",
  "@aliceut/shared-ui":    "libs/ui/src/index.ts",
  "@aliceut/shared-util":  "libs/shared-util/src/index.ts"
}
```

---

## Non-negotiables — read before writing any code

### API client — never use HttpClient directly

The frontend calls the backend through the generated client only.

```typescript
// WRONG
constructor(private http: HttpClient) {}
this.http.get<Product[]>('/api/v1/products');

// RIGHT
constructor(private catalogApi: CatalogService) {}   // from @aliceut/api-client
this.catalogApi.listProducts({ page: 1, limit: 20 });
```

Regenerate after any backend OpenAPI spec change:

```bash
pnpm run generate:api-client
```

### Money display

Never render monetary values with JS number arithmetic. Use the `MoneyPipe` from `@aliceut/shared-ui`:

```html
<!-- WRONG -->
{{ product.price | number:'1.2-2' }}

<!-- RIGHT -->
{{ product.price | money:product.currency }}
```

Currency display scale: JPY=0 decimal places, BHD=3, USD/THB/SGD=2. The pipe handles this via `Currency.minor_unit_scale`.

Full patterns: `../aliceut-ecom-document/conventions/frontend-coding-standards.md §5`

### Token storage

- Access token: memory only (`AuthService` property). Never `localStorage`, never `sessionStorage`.
- Refresh token: httpOnly cookie (backend sets it). Frontend never reads it.

### Component architecture

- All components are **standalone** (Angular 22+ default). `NgModule` only when a third-party lib requires it as host.
- Smart/dumb split: feature components fetch data and hold state; presentational components in `libs/ui/` are pure input/output.
- `ChangeDetectionStrategy.OnPush` on all components. No `Default` strategy.
- Every data-fetching component handles **three states**: loading, empty, error.

### Routing

- All feature routes are **lazily loaded**. No eagerly loaded feature modules.
- Route guards use `CanActivateFn` (functional). No class-based guards.

Full patterns: `../aliceut-ecom-document/conventions/frontend-coding-standards.md`

---

## API client regeneration

When the backend OpenAPI spec changes (`libs/contracts/openapi/aliceut-v1.json` in `aliceut-ecom-backend/`), regenerate:

```bash
pnpm run generate:api-client
```

Commit the regenerated `libs/api-client/` files. CI diffs the output and fails the build if the client is stale.

---

## Design system

UI uses Angular Material with the AliceUT custom theme. Reference:
- Figma: https://www.figma.com/design/F69ukaWjsqx4adgo26vDFQ/AliceUT
- Convention: `../aliceut-ecom-document/conventions/design-system.md`

Before building any screen or component, fetch the Figma design context via the Figma MCP tool.

---

## Subagent routing

Install: `claude plugin install voltagent/awesome-claude-code-subagents` (one-time per machine).

| Task | Agent |
|------|-------|
| Implement frontend feature / fix | `voltagent-core-dev:frontend-developer` |
| Write integration tests / E2E | `voltagent-qa-sec:qa-expert` |
| Local review before push | `voltagent-qa-sec:code-reviewer` + `voltagent-qa-sec:performance-engineer` (run both in parallel) |
| Accessibility audit | `ecc:a11y-architect` |

Full guide: `../aliceut-ecom-document/guidelines/claude-code-subagents.md`

---

## Full conventions reference

All paths relative to the sibling `aliceut-ecom-document/` repo:

| Concern | File |
|---------|------|
| Angular structure, state, forms, routing, OnPush | `conventions/frontend-coding-standards.md` |
| Angular Material palette, tokens, component choices | `conventions/design-system.md` |
| Money display, MoneyPipe, currency scale | `conventions/frontend-coding-standards.md §5` |
| API client generation pipeline | `conventions/backend-module-architecture.md §8` |
| Git branching, commits, PR template | `guidelines/git-workflow.md` |
| Test pyramid, coverage thresholds, Playwright | `guidelines/testing-guidelines.md` |
| Daily dev workflow, local setup | `guidelines/development-flow.md` |

---

## Pre-merge checklist (compact)

Full checklist: `../aliceut-ecom-document/guidelines/development-flow.md §11`

**API and data**
- [ ] No raw `HttpClient` calls for API endpoints — always use generated client
- [ ] Access token never written to `localStorage` / `sessionStorage`
- [ ] Every data-fetching component handles loading, empty, and error states

**Money**
- [ ] No JS number arithmetic on monetary values
- [ ] `MoneyPipe` used for all currency display

**Architecture**
- [ ] All components are standalone
- [ ] All feature routes are lazily loaded
- [ ] `ChangeDetectionStrategy.OnPush` on every component

**Tests**
- [ ] New feature component has Angular component tests
- [ ] Critical user flows covered by Playwright E2E
