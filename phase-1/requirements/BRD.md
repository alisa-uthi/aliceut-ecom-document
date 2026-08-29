# Business Requirements Document (BRD)
## AliceUT — Global Multi-Vendor Marketplace

**Document version:** 1.1
**Date:** 2026-08-19
**Author:** Business Analyst (working with product owner)
**Status:** Signed off — ready for design phase

---

## 1. Executive Summary

A global multi-vendor e-commerce marketplace inspired by Amazon.com. Serves as a **learning/portfolio project** while implementing production-grade patterns. Supports four user types: end consumers (B2C), business buyers (B2B), third-party sellers, and platform admins. V1 delivers the core buy/sell/moderate loop with fake payment and shipping; later phases add real payment gateways and shipping providers.

---

## 2. Business Objectives

| # | Objective | Success indicator |
|---|-----------|-------------------|
| BO-1 | Demonstrate full-stack marketplace competency for portfolio | Deployable demo with all four personas usable end-to-end |
| BO-2 | Learn production patterns (auth, search, microservice-ready structure) | Codebase passes security + performance NFRs in Section 8 |
| BO-3 | Support 10k+ products with sub-2s page loads | Load test on seeded catalog meets NFR targets |
| BO-4 | Provide realistic marketplace behavior for demo | Buyer can search → cart → checkout; seller can list → fulfill; admin can moderate |

---

## 3. Scope

### 3.1 In Scope (V1)

**Buyer**
- Product search with filters (category, price, rating, sort)
- Cart (persistent for logged-in, session for guest)
- Checkout with fake payment gateway

**Seller**
- Product listing CRUD (create, read, update, delete) with images + variants
- Order fulfillment dashboard (view orders, mark shipped, refund)
- Inventory management (stock levels, low-stock alerts, bulk update)

**Admin**
- Seller onboarding + KYC (approve applications, verify docs, tax IDs)
- Catalog moderation (review listings, remove prohibited items)

**Platform**
- Authentication: email/password + OAuth (Google, Facebook)
- Per-offer multi-currency pricing (seller sets price + currency per offer); order-time price snapshot preserves historical amounts
- Global product catalog seeded from a Kaggle-style Amazon dataset
- Docker + docker-compose local deployment

### 3.2 Out of Scope (V1 — deferred)

- Real payment gateway (Stripe, PayPal, crypto)
- Real shipping integration (EasyPost, Shippo, carrier APIs)
- Reviews + ratings
- Wishlist + personalized recommendations
- Sales analytics dashboard for sellers
- Dispute / refund mediation workflow
- Commission + payout configuration
- Multi-language i18n
- Native mobile apps
- Kubernetes + Istio deployment (phase 2)

### 3.3 Assumptions

- Product owner is also the developer; single-person team
- No hard deadline — quality > speed
- Legal / tax compliance out of scope (learning project, not real commerce)
- Fake shipping generates mock tracking numbers; no carrier API calls

---

## 4. Stakeholders + Personas

| Persona | Role | Primary needs |
|---------|------|---------------|
| **Consumer (B2C)** | Individual shopper | Find product fast, trust seller, easy checkout |
| **Business buyer (B2B)** | Company procurement | Bulk view, invoice-friendly checkout, account management |
| **Third-party seller** | Vendor listing products | Simple onboarding, clear order queue, inventory control |
| **Platform admin** | Internal ops | Vet sellers, remove bad listings, keep marketplace clean |

*Note:* B2B in V1 = same UX as B2C but under a business account type. Bulk pricing/invoicing deferred.

---

## 5. Functional Requirements

### 5.1 Buyer Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-B-01 | User can register with email/password OR OAuth (Google, Facebook) | Must |
| FR-B-02 | User can search products by keyword | Must |
| FR-B-03 | User can filter results by category, price range, rating, in-stock | Must |
| FR-B-04 | User can sort results by relevance, price (asc/desc), newest | Must |
| FR-B-05 | User can view product detail page with images, variants, seller info | Must |
| FR-B-06 | User can add product (with selected variant + quantity) to cart | Must |
| FR-B-07 | Cart persists across sessions for logged-in users | Must |
| FR-B-08 | Guest cart persists in browser session | Should |
| FR-B-09 | User can proceed to checkout: enter shipping address, select fake payment, place order | Must |
| FR-B-10 | Order confirmation shows mock tracking number + estimated delivery | Must |
| FR-B-11 | User can view order history + status | Must |

### 5.2 Seller Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-S-01 | Seller applies via onboarding form (business name, tax ID, docs upload) | Must |
| FR-S-02 | Seller cannot list products until admin approves KYC | Must |
| FR-S-03 | Approved seller can create product with title, description, price, category, images, variants | Must |
| FR-S-04 | Seller can edit + delete own products | Must |
| FR-S-05 | Seller sees dashboard of pending, shipped, delivered orders | Must |
| FR-S-06 | Seller can mark order as shipped (generates mock tracking) | Must |
| FR-S-07 | Seller can issue refund (fake payment reversed) | Must |
| FR-S-08 | Seller sees inventory count per SKU, receives low-stock alert (email or in-app) | Must |
| FR-S-09 | Seller can bulk update inventory via CSV import | Should |

### 5.3 Admin Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-A-01 | Admin sees queue of pending seller applications | Must |
| FR-A-02 | Admin can view uploaded KYC docs + approve or reject with reason | Must |
| FR-A-03 | Admin sees flagged / reported listings queue | Must |
| FR-A-04 | Admin can remove listing + notify seller with reason | Must |
| FR-A-05 | Admin can suspend seller account | Should |

### 5.4 Platform / Cross-cutting

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-P-01 | A `Product` may have one or more `Offer`s (one per seller). Each `Offer` has one or more `Price`s (one per currency). Sellers set price + currency per offer; no forced canonical currency | Must |
| FR-P-02 | Optional display conversion: if buyer's preferred currency is not on the offer, system converts using FX rate table for **display only** (with visible "estimated" label) | Should |
| FR-P-03 | At checkout, system creates a **price snapshot** on `OrderItem` (unit_price_minor, currency, tax, fx_rate_used_at_capture). Historical orders never re-derive amounts from live FX or current offer prices | Must |
| FR-P-04 | All monetary amounts stored as **Decimal** (Postgres `NUMERIC(19,4)` — 19 total digits, 4 fractional). Currency code stored as ISO 4217 alongside. Precision covers major currencies including 3-decimal (BHD, KWD, OMR) and 4-decimal accounting rounding | Must |
| FR-P-04a | JS/TS boundary: TypeORM/Prisma maps `NUMERIC` to string; app code uses `decimal.js` or `Big.js` for arithmetic. **Never use JS `number` for monetary math** | Must |
| FR-P-04b | API responses serialize amounts as string (`"99.99"`), not float, to preserve precision across JSON boundary | Must |
| FR-P-05 | Buyer sees offer selection when multiple sellers offer the same product; default = lowest price in buyer's currency (or converted) | Should |
| FR-P-06 | Product catalog seeded from **Kaggle "Amazon Product Data"** dataset, **100 products** curated across major categories (electronics, books, home, apparel) | Must |
| FR-P-06a | Allowed pricing currencies for sellers in V1: **USD, THB, JPY, SGD** | Must |
| FR-P-06b | Every `Offer` supports multiple `Price` rows keyed by `price_type`: **LIST** (default), **SALE** (time-bounded discount, `starts_at`/`ends_at`), **B2B_TIER** (quantity break, `min_qty`). PDP resolves effective price by user account type + time + quantity | Must |
| FR-P-06c | Prohibited categories admin must block: **weapons, drugs, adult content**. Moderation queue flags on category taxonomy + keyword blocklist at listing time | Must |
| FR-P-06d | B2B account uses identical buyer UX to B2C. Differentiation is **branding only** (business account badge, optional business logo on invoice, "Business" tag in header) | Must |
| FR-P-07 | All secrets in env vars; no credentials in code | Must |
| FR-P-08 | Input validation on all API endpoints (DTO + class-validator) | Must |
| FR-P-09 | Domain state changes (product, offer, inventory, order, KYC, moderation) publish events to Kafka via transactional outbox | Must |
| FR-P-10 | Search index (Elasticsearch) updated **asynchronously** from Kafka events, not from synchronous API writes | Must |
| FR-P-11 | Email + in-app notifications driven by Kafka consumers, not inline from request handlers | Must |
| FR-P-12 | Every event carries `event_id`, `correlation_id`, `occurred_at`; consumers are idempotent | Must |
| FR-P-13 | Poison-message dead-letter topic per consumer group with alerting | Should |

---

## 6. User Journeys (V1)

**Buyer happy path:** Land on home → search "laptop" → filter price $500–1500 → open product → add to cart → checkout → fake pay → see confirmation.

**Seller happy path:** Register as seller → submit KYC → wait for admin approval → list first product → receive order → mark shipped → refund one order.

**Admin happy path:** Log in → review 3 pending seller apps → approve 2, reject 1 → moderate catalog → remove one prohibited listing.

---

## 7. Non-Functional Requirements

| ID | Category | Requirement | Target |
|----|----------|-------------|--------|
| NFR-01 | Performance | Product listing page load | ≤ 2s p95 (100-product seed, cold cache) |
| NFR-02 | Performance | Search response time | ≤ 500ms p95 |
| NFR-03 | Scalability | Catalog headroom (architecture supports without redesign) | ≥ 10,000 products, indexed. V1 seed = 100 |
| NFR-04 | Scalability | Concurrent users (dev target) | 100 concurrent buyers |
| NFR-05 | Security | Password storage | bcrypt / argon2, never plaintext |
| NFR-06 | Security | Auth tokens | JWT with short expiry + refresh rotation |
| NFR-07 | Security | Input validation | class-validator on every DTO |
| NFR-08 | Security | SQL injection | Parameterized queries only (TypeORM / Prisma) |
| NFR-09 | Security | PII handling | KYC docs encrypted at rest, access-logged |
| NFR-10 | Security | OWASP | Top 10 covered (CSRF, XSS, SSRF, etc.) |
| NFR-11 | Reliability | DB backup | Docker volume snapshot before schema migration |
| NFR-12 | Observability | Structured logs | JSON logs, correlation IDs on every request AND Kafka event |
| NFR-13 | Consistency | Search index freshness (Elasticsearch lag from write) | ≤ 5s p95 |
| NFR-14 | Reliability | Event delivery | At-least-once via Kafka + transactional outbox; consumers idempotent |
| NFR-15 | Reliability | Poison message handling | DLQ per consumer group, no infinite retry loops |
| NFR-16 | Testability | Backend unit test coverage | ≥ 70% line coverage (Jest, per NestJS module) |
| NFR-17 | Testability | E2E test coverage | Playwright suite covers 3 happy paths in §6 + auth flows |
| NFR-18 | Portability | Language/framework migration cost | Schema migrations written as **raw SQL** (portable); repository layer isolates all TypeORM calls behind interfaces so future language swap = reimplement repos only, not schema |

---

## 8. Constraints + Dependencies

- Solo developer; time-boxed learning task list per feature
- No budget for paid services in V1 (all self-hosted or free tier)
- Kaggle dataset licensing must permit derivative use (verify before import)
- OAuth apps must be registered with Google + Facebook dev consoles

---

## 9. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope creep (adding reviews / recs) delays V1 | High | Strict V1 checklist; defer to phase 2 |
| Elasticsearch operational complexity for solo dev | Medium | Use single-node dev cluster; managed service if pain grows |
| Kafka + Zookeeper resource footprint on dev laptop | Medium | Use `bitnami/kafka` KRaft mode (no Zookeeper) if resources tight; else standard confluentinc images. Tune heap to `-Xmx512m` per broker |
| Event schema drift breaking consumers | Medium | Schema registry (Confluent-compatible); event_version field; consumers tolerate unknown fields (BC forward-compat) |
| Duplicate event side-effects (at-least-once) | Medium | Idempotent consumers keyed on `event_id`; write dedupe table with TTL |
| Outbox relay falls behind, search stale | Low | NFR-13 monitors lag; alert when > 30s |
| KYC doc storage feels contrived without real compliance | Low | Simulate flow; document what real system would add (bucket encryption, retention policy) |
| Multi-currency FX rate staleness affects **display** conversion | Low | Order amounts snapshotted at checkout (immune). Display uses cached FX table refreshed via cron from public API (exchangerate.host) with "estimated" label |
| Offer with no price in buyer's currency | Medium | Fallback: convert cheapest available `Price` for display; block checkout if seller has zero prices |
| Rounding drift from JS float in monetary math | High | Enforce `NUMERIC(19,4)` in DB + `decimal.js`/`Big.js` in app code. Lint rule: forbid `number` type on any field named `*price*`, `*amount*`, `*tax*`, `*fee*`. Round at display boundary only |
| Precision loss over JSON boundary | Medium | Serialize amounts as strings (`"99.99"`), not JSON numbers. Angular reads string + parses with `decimal.js` for arithmetic, formats via `Intl.NumberFormat` |
| Currency-specific decimal scale (JPY = 0, BHD = 3) | Medium | Metadata table `Currency(code, minor_unit_scale)` drives display formatting; storage keeps 4 fractional digits for headroom |
| Faker/Kaggle catalog quality (bad images, missing categories) | Medium | Clean import pipeline; drop rows missing key fields |

---

## 10. Phasing

| Phase | Deliverable | Milestone |
|-------|-------------|-----------|
| **Phase 1 (V1)** | Buyer + Seller + Admin core loops, fake pay/ship, Docker compose | This BRD |
| **Phase 2** | Reviews, ratings, wishlist, seller analytics, dispute flow | Post-V1 |
| **Phase 3** | Real Stripe payment, real shipping (EasyPost), commission engine | Post-V2 |
| **Phase 4** | K8s + Istio, multi-region, observability stack, i18n | Post-V3 |

---

## 11. Acceptance Criteria (V1 done = all true)

- [ ] All FR-B, FR-S, FR-A, FR-P items marked "Must" pass end-to-end manual test
- [ ] All NFR targets met on seeded 100-product catalog
- [ ] Unit test coverage ≥ 70% on backend services, e2e Playwright covers all 3 happy paths in §6
- [ ] `docker-compose up` brings full stack live; README explains seed + first login
- [ ] Four demo accounts pre-seeded: consumer, business buyer, seller, admin
- [ ] Security checklist (NFR-05..NFR-10) reviewed and passing
- [ ] Portfolio README with architecture diagram + deployed demo link (or recording)

---

## 12. Resolved Decisions (product owner sign-off 2026-08-19)

| # | Question | Decision |
|---|----------|----------|
| 0 | Seed catalog size | **100 products** (architecture still supports 10k per NFR-03) |
| 1 | Kaggle dataset | **Amazon Product Data** |
| 2 | B2B differentiator | Same UX as B2C; brand-only diff (business badge, business logo on invoice) |
| 3 | ORM | **TypeORM** with raw-SQL migrations + repository pattern (language-portable schema) |
| 4 | Elasticsearch hosting | Self-hosted, single-node, docker-compose |
| 5 | FX source | `exchangerate.host` public API, cron refresh; display-only |
| 5a | Allowed currencies V1 | USD, THB, JPY, SGD |
| 5b | Price types | LIST + SALE + B2B_TIER (all three) |
| 6 | Test coverage in DoD | Yes — ≥ 70% unit, Playwright e2e for §6 happy paths |
| 7 | Prohibited categories | Weapons, drugs, adult content |
| 8 | Kafka vs Redpanda | **Kafka** in docker-compose (KRaft mode acceptable if resources tight) |
| 9 | Schema registry | Confluent Schema Registry, Avro, BACKWARD compatibility |
| 10 | Kafka UI tool | Yes — `provectus/kafka-ui` in docker-compose |

All prior open questions resolved. Ready for detailed design + backlog decomposition.

---

*End of BRD v1.1. All decisions signed off — proceed to design phase.*
