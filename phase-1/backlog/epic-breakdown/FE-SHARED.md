# Epic: FE-SHARED — Frontend Shared Libraries

**Epic ID:** FE-SHARED  
**Sprint(s):** 16  
**Total Tasks:** 12

## Epic Goal

Shared Angular libraries used by all three portals (buyer-app :4200, seller-app :4201, admin-app :4202): Nx workspace, Angular Material theme, HTTP client + interceptors, decimal display pipe, auth state + guards, shared UI component library, nginx build, OpenAPI client generation. Must be in place before any portal-specific feature work begins.

---

### FE-SHARED-001 — Nx Frontend Workspace Setup

- **US Ref:** —
- **Estimate:** L
- **Dependencies:** INFRA-002
- **Spec References:** `conventions/frontend-coding-standards.md`

**Implementation Notes:**
- Angular 22+ Nx workspace; apps: `buyer-app` (:4200), `seller-app` (:4201), `admin-app` (:4202); libs: `shared`, `api-client`
- Workspace/lib boundaries and naming: per `conventions/frontend-coding-standards.md`

**Done Criteria:**
- `nx serve buyer-app`, `nx serve seller-app`, `nx serve admin-app` each start on their designated port

---

### FE-SHARED-002 — Angular Material Theme Setup

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** FE-SHARED-001
- **Spec References:** `conventions/design-system.md`, Figma file `F69ukaWjsqx4adgo26vDFQ` (`aliceut-design-system` skill)

**Implementation Notes:**
- Design tokens, typography, color palette: per `conventions/design-system.md`
- Shared `theme.scss` imported by all three portals

**Done Criteria:**
- Material components render with the AliceUT theme in all three portals

---

### FE-SHARED-003 — HTTP Client Config

- **US Ref:** —
- **Estimate:** S
- **Dependencies:** FE-SHARED-001
- **Spec References:** `conventions/api-conventions.md`

**Implementation Notes:**
- Per-portal `environment.ts` with API base URL; `withCredentials: true` so the refresh-token cookie is sent (per `conventions/auth-jwt-design.md`)

**Done Criteria:**
- Requests from each portal reach the backend with the refresh cookie attached

---

### FE-SHARED-004 — Auth Interceptor

- **US Ref:** US-B-00
- **Estimate:** L
- **Dependencies:** FE-SHARED-001
- **Spec References:** `conventions/auth-jwt-design.md`

**Implementation Notes:**
- Attaches JWT access token to outgoing requests; on `401`, calls refresh (`POST /auth/refresh`) and retries once; on repeat failure, redirects to the appropriate portal login
- Token rotation/refresh contract: per `conventions/auth-jwt-design.md`

**Done Criteria:**
- Expired access token → transparent refresh + retry; refresh failure → redirect to login

---

### FE-SHARED-005 — Error Interceptor

- **US Ref:** US-P-09
- **Estimate:** M
- **Dependencies:** FE-SHARED-001
- **Spec References:** `conventions/api-conventions.md` (RFC 7807 error shape)

**Implementation Notes:**
- Maps RFC 7807 API error responses to user-friendly messages; structured error display via shared UI (see FE-SHARED-010)

**Done Criteria:**
- A 4xx/5xx API error renders a readable message, not a raw stack/JSON dump

---

### FE-SHARED-006 — Correlation ID Header Interceptor

- **US Ref:** NFR-12
- **Estimate:** S
- **Dependencies:** FE-SHARED-001
- **Spec References:** `conventions/observability.md`

**Implementation Notes:**
- Adds `X-Correlation-ID` (UUID, generated per request or reused per user session per spec) to every outgoing HTTP request

**Done Criteria:**
- Every request in DevTools Network tab carries an `X-Correlation-ID` header

---

### FE-SHARED-007 — Decimal Display Pipe

- **US Ref:** US-P-04
- **Estimate:** M
- **Dependencies:** FE-SHARED-001
- **Spec References:** `phase-1/ui-design/shared-components.md` § 8 Pipes (`currencyDisplay`)

**Implementation Notes:**
- Implements the `currencyDisplay` pipe per `shared-components.md`: `Intl.NumberFormat` + currency-aware decimal places (`Currency.minor_unit_scale`; JPY=0, others=2 in V1); input `amount` is always a string, converted to `Number` for formatting only — never for arithmetic
- Used by `PriceDisplayComponent` (FE-SHARED-010) and `DataTableComponent`'s `pipe: 'currencyDisplay'` column option

**Done Criteria:**
- Per `shared-components.md`'s `currencyDisplay` examples: `"99.99" | currencyDisplay:"THB"` renders with correct symbol/decimals; JPY amounts show 0 decimals

---

### FE-SHARED-008 — Auth State Service

- **US Ref:** US-B-00
- **Estimate:** M
- **Dependencies:** FE-SHARED-001
- **Spec References:** `conventions/auth-jwt-design.md`

**Implementation Notes:**
- Signals-based store: `currentUser`, `isAuthenticated`, `roles`; consumed by FE-SHARED-004 (auth interceptor) and FE-SHARED-009 (route guards)
- Token storage per `conventions/auth-jwt-design.md`

**Done Criteria:**
- Login populates `currentUser`/`roles`; logout clears state; `isAuthenticated` reflects current session

---

### FE-SHARED-009 — Route Guards

- **US Ref:** US-A-00b
- **Estimate:** M
- **Dependencies:** FE-SHARED-008
- **Spec References:** `conventions/auth-jwt-design.md`

**Implementation Notes:**
- `AuthGuard`: redirects unauthenticated users to the correct portal login
- `RoleGuard`: buyer/seller/admin role check; redirects to `/unauthorized` on mismatch

**Done Criteria:**
- Unauthenticated access to a guarded route → redirected to login
- Wrong-role access to a guarded route → redirected to `/unauthorized`

---

### FE-SHARED-010 — Shared UI Components Lib

- **US Ref:** —
- **Estimate:** L
- **Dependencies:** FE-SHARED-002
- **Spec References:** `phase-1/ui-design/shared-components.md` (full component/pipe contract)

**Implementation Notes:**
- `libs/ui/` (`LibsUiModule`), standalone components, per `shared-components.md`:
  - `NotificationBellComponent` — `<aliceut-notification-bell>`
  - `StatusBadgeComponent` — `<aliceut-status-badge>`
  - `PriceDisplayComponent` — `<aliceut-price-display>` (uses `currencyDisplay` pipe from FE-SHARED-007)
  - `EmptyStateComponent` — `<aliceut-empty-state>`
  - `DataTableComponent` — `<aliceut-data-table>` (wraps `MatTable` + `MatPaginator` + `MatSort`)
  - `FileUploadComponent` — `<aliceut-file-upload>`
  - `ConfirmDialogComponent` (opened via `MatDialog.open`)
  - Pipes: `timeAgo`, `truncate` (both alongside `currencyDisplay` from FE-SHARED-007)
- Do not re-embed each component's full input/output contract here — see `shared-components.md` §§1–8 for exact APIs

**Done Criteria:**
- All components/pipes listed above implemented per `shared-components.md`'s contracts and usable from all three portals

---

### FE-SHARED-011 — nginx Dockerfile for Angular Apps

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** INFRA-003
- **Spec References:** `phase-1/technical-design/docker-compose-topology.md`

**Implementation Notes:**
- Multi-stage build (Angular build → nginx serve) for each of the three apps; nginx proxies `/api/*` to `api:3000`

**Done Criteria:**
- `docker-compose up` serves all three portals via nginx; `/api/*` requests reach the backend container

---

### FE-SHARED-012 — OpenAPI Client Generation

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** SHARED-007
- **Spec References:** `conventions/api-conventions.md`

**Implementation Notes:**
- `openapi-generator-cli` (`typescript-angular` generator) against the backend's Swagger/OpenAPI JSON (SHARED-007); npm script; generated `libs/api-client/` carries a do-not-edit banner

**Done Criteria:**
- `npm run api:generate` produces Angular-injectable API services with no manual edits required to consume them
