# Admin Stories (US-A-*)

Maps to BRD FR-A-* functional requirements. See [README](README.md) for format legend and cross-role index.

---

## US-A-01 — Pending seller applications queue
**As an** admin, **I want** to see pending KYC applications sorted by submission time, **so that** I can process oldest first.
Priority: Must — trace: FR-A-01

**Acceptance criteria**
- List paginated, filterable by country, sortable by `submitted_at`.
- Row: business name, country, submitted_at, days pending (SLA badge red if > 3 days).

---

## US-A-02 — Review KYC docs and decide
**As an** admin, **I want** to view uploaded docs and approve or reject with a reason, **so that** I control who sells.
Priority: Must — trace: FR-A-02, NFR-09

**Acceptance criteria**
- Doc viewer supports PDF/image inline.
- Every doc view logs `audit.event` with admin_id, doc_id, timestamp (NFR-09).
- Actions: `Approve`, `Reject with reason` (mandatory ≤ 500 chars).
- Approve → `SellerProfile.status=APPROVED`, role upgraded, publish `seller.kyc.decided` (`decision=APPROVED`).
- Reject → same event with `decision=REJECTED`, `reason`; seller receives email + can resubmit.

---

## US-A-03 — Flagged listings queue
**As an** admin, **I want** to see flagged/auto-flagged listings, **so that** I can moderate the catalog.
Priority: Must — trace: FR-A-03, FR-P-06c

**Acceptance criteria**
- V1 flag sources: keyword blocklist hit or prohibited category attempt during listing (auto-flag). Buyer report deferred to V2.
- List sorted by `flagged_at desc`; shows product title, seller, flag reason, snippet.

---

## US-A-04 — Remove listing with notification
**As an** admin, **I want** to remove a listing and notify the seller with a reason, **so that** sellers understand the rule violated.
Priority: Must — trace: FR-A-04

**Acceptance criteria**
- Action: `Remove` on a flagged listing.
- Mandatory reason (dropdown: prohibited category / IP violation / misleading / other + free text).
- Sets `Offer.status=REMOVED`; `Product.status=REMOVED` if all offers removed.
- Publishes `moderation.listing.removed` → seller email consumer + search deindex.
- Auditable via `AuditLog` in Mongo.

---

## US-A-05 — Suspend seller account
**As an** admin, **I want** to suspend a seller account, **so that** repeat offenders can be stopped.
Priority: Should — trace: FR-A-05

**Acceptance criteria**
- Action requires reason + duration (7 / 30 / 90 days / permanent).
- Sets `SellerProfile.status=SUSPENDED`; all offers → `INACTIVE`.
- Seller cannot list new products or log into seller dashboard (buyer role still active if same account).
- Publishes `seller.suspended` → search deindex, email, audit log.
