# User Stories — AliceUT V1

**Author:** Senior Business Analyst
**Source:** BRD.md v1.1 (signed off 2026-08-19)
**Format:** Connextra + INVEST + Gherkin acceptance criteria
**Scope:** V1 Must + Should items only. Out-of-scope (BRD §3.2) excluded.

---

## Files

Stories split by role. One file per role for scalability.

| File | Prefix | FR trace | Count |
|------|--------|----------|-------|
| [buyer.md](buyer.md) | US-B-* | FR-B | 15 |
| [seller.md](seller.md) | US-S-* | FR-S | 14 |
| [admin.md](admin.md) | US-A-* | FR-A | 9 |
| [platform.md](platform.md) | US-P-* | FR-P | 16 |

**Total: 54 stories.** All V1 Must + Should items covered.

---

## Legend

- **US-B-*** — Buyer stories (maps to FR-B)
- **US-S-*** — Seller stories (FR-S)
- **US-A-*** — Admin stories (FR-A)
- **US-P-*** — Platform / cross-cutting (FR-P)

Each story:
```
ID | Title
As a <persona>, I want <capability>, so that <outcome>.
Priority: Must / Should
BRD trace: FR-x-nn
Acceptance criteria: Given/When/Then
Notes: preconditions, edge cases, dependencies
```

---

## Story Index

### Buyer ([buyer.md](buyer.md))
| ID | Title | Priority | Trace |
|----|-------|----------|-------|
| US-B-01 | Register account | Must | FR-B-01 |
| US-B-02 | Search products by keyword | Must | FR-B-02 |
| US-B-03 | Filter search results | Must | FR-B-03 |
| US-B-04 | Sort search results | Must | FR-B-04 |
| US-B-05 | View product detail page (PDP) | Must | FR-B-05 |
| US-B-06 | Add to cart | Must | FR-B-06 |
| US-B-07 | Persistent logged-in cart | Must | FR-B-07 |
| US-B-08 | Guest cart persistence | Should | FR-B-08 |
| US-B-09 | Checkout with fake payment | Must | FR-B-09 |
| US-B-10 | Order confirmation with mock tracking | Must | FR-B-10 |
| US-B-11 | View order history + status | Must | FR-B-11 |
| US-B-12 | Order lifecycle email notifications | Must | FR-B-10, FR-B-11 |
| US-B-13 | Reset forgotten password | Must | FR-B-01 |
| US-B-14 | Manage delivery addresses | Should | FR-B-09 |
| US-B-15 | Manage account profile | Should | FR-B-01 |

### Seller ([seller.md](seller.md))
| ID | Title | Priority | Trace |
|----|-------|----------|-------|
| US-S-00 | Seller dashboard overview | Must | FR-S-05, FR-S-08 |
| US-S-01 | Seller onboarding application | Must | FR-S-01 |
| US-S-02 | Block listing until KYC approved | Must | FR-S-02 |
| US-S-03 | Create product listing | Must | FR-S-03 |
| US-S-04 | Edit and delete own products | Must | FR-S-04 |
| US-S-04b | Manage offer pricing | Must | FR-P-01, FR-P-06a |
| US-S-05 | Order fulfillment dashboard | Must | FR-S-05 |
| US-S-05b | Order detail view | Must | FR-S-05, FR-S-06 |
| US-S-06 | Mark order shipped | Must | FR-S-06 |
| US-S-07 | Issue refund | Must | FR-S-07 |
| US-S-08 | Inventory + low-stock alerts | Must | FR-S-08 |
| US-S-09 | Bulk inventory update via CSV | Should | FR-S-09 |
| US-S-10 | View listing moderation status | Must | FR-A-03, FR-A-04 |
| US-S-11 | Cancel unfulfillable PENDING order | Should | FR-S-05, FR-S-07 |

### Admin ([admin.md](admin.md))
| ID | Title | Priority | Trace |
|----|-------|----------|-------|
| US-A-00 | Admin dashboard overview | Must | FR-A-01, FR-A-03 |
| US-A-01 | Pending seller applications queue | Must | FR-A-01 |
| US-A-02 | Review KYC docs and decide | Must | FR-A-02 |
| US-A-03 | Flagged listings queue | Must | FR-A-03 |
| US-A-04 | Remove listing with notification | Must | FR-A-04 |
| US-A-04b | Clear false-positive flagged listing | Must | FR-A-03, FR-A-04 |
| US-A-05 | Suspend seller account | Should | FR-A-05 |
| US-A-05b | Reinstate suspended seller | Should | FR-A-05 |
| US-A-06 | Seller search and profile lookup | Should | FR-A-01, FR-A-05 |

### Platform ([platform.md](platform.md))
| ID | Title | Priority | Trace |
|----|-------|----------|-------|
| US-P-01 | Multi-currency offer model | Must | FR-P-01 |
| US-P-02 | FX display conversion | Should | FR-P-02 |
| US-P-03 | Order price snapshot immutability | Must | FR-P-03 |
| US-P-04 | Decimal money handling end-to-end | Must | FR-P-04 |
| US-P-05 | Multi-seller offer selection | Should | FR-P-05 |
| US-P-06 | Seed 100 curated products | Must | FR-P-06 |
| US-P-07 | B2B account branding differentiation | Must | FR-P-06d |
| US-P-08 | Secrets in env only | Must | FR-P-07 |
| US-P-09 | DTO validation on every endpoint | Must | FR-P-08 |
| US-P-10 | Transactional outbox for domain events | Must | FR-P-09 |
| US-P-11 | Async search index update | Must | FR-P-10 |
| US-P-12 | Notifications via Kafka consumers | Must | FR-P-11 |
| US-P-13 | Event envelope + idempotency | Must | FR-P-12 |
| US-P-14 | Dead-letter topics | Should | FR-P-13 |
| US-P-15 | Mock delivery scheduler | Must | FR-B-10, FR-S-05 |
| US-P-16 | Auto-refund monitor for suspended-seller orders | Should | FR-A-05 |

---

## Story Dependencies (top-level)

```
US-B-01 (register) ← US-B-06,07,09,11,13,14,15 (buyer core)
US-S-01 (KYC apply) ← US-A-02 (KYC decide) ← US-S-03 (list product)
US-S-03 (list) ← US-S-04, US-S-04b, US-S-10 (listing management)
US-S-05 (fulfillment dashboard) ← US-S-05b (order detail)
US-B-05 (PDP) ← US-P-01,02,04,05 (pricing correctness)
US-B-09 (checkout) ← US-P-03,10,15 (snapshot + outbox + scheduler)
US-P-13 (envelope) ← US-P-10,11,12 (event consumers)
US-P-06 (seed) ← everything demo-facing
US-A-05 (suspend) ← US-A-05b (reinstate) ← US-P-16 (auto-refund monitor)
```

---

## Story Sequencing (proposed sprints)

**Sprint 0 — Foundation (1 wk)**
US-P-08, US-P-09, US-P-10, US-P-13, US-P-04

**Sprint 1 — Catalog + Search (2 wk)**
US-P-01, US-P-06, US-B-02, US-B-03, US-B-04, US-B-05, US-P-11, US-P-05

**Sprint 2 — Auth + Cart (1 wk)**
US-B-01, US-B-13, US-B-14, US-B-15, US-B-06, US-B-07, US-B-08, US-P-07

**Sprint 3 — Checkout + Orders (2 wk)**
US-B-09, US-B-10, US-B-11, US-B-12, US-P-03, US-P-02, US-P-12, US-P-15

**Sprint 4 — Seller (2 wk)**
US-S-00, US-S-01, US-S-02, US-S-03, US-S-04, US-S-04b, US-S-05, US-S-05b,
US-S-06, US-S-07, US-S-08, US-S-09, US-S-10, US-S-11

**Sprint 5 — Admin + DLQ (1 wk)**
US-A-00, US-A-01, US-A-02, US-A-03, US-A-04, US-A-04b,
US-A-05, US-A-05b, US-A-06, US-P-14, US-P-16

Total ≈ 9–10 wk solo.
