# Admin Stories (US-A-*)

Maps to BRD FR-A-* functional requirements. See [README](README.md) for format legend and cross-role index.

---

## US-A-00 — Admin dashboard overview
**As an** admin, **I want** to see a summary of pending work when I log in, **so that** I can triage without navigating to every queue manually.
Priority: Must — trace: FR-A-01, FR-A-03, FR-A-05

**Acceptance criteria**
- Dashboard shows live counts: KYC applications pending, flagged listings pending review, currently suspended sellers, SLA breaches (KYC pending > 3 days).
- Each count is a link to the corresponding queue.
- Counts update on page load (no real-time push required in V1).

---

## US-A-01 — Pending seller applications queue
**As an** admin, **I want** to see pending KYC applications sorted by submission time, **so that** I can process oldest first.
Priority: Must — trace: FR-A-01

**Acceptance criteria**
- List paginated, filterable by country, sortable by `submitted_at`.
- Row: business name, country, submitted_at, days pending (SLA badge red if > 3 days).
- Resubmissions show a "Resubmit" badge; hovering/expanding reveals the previous rejection reason and date.

---

## US-A-02 — Review KYC docs and decide
**As an** admin, **I want** to view uploaded docs and approve or reject with a reason, **so that** I control who sells.
Priority: Must — trace: FR-A-02, NFR-09

**Acceptance criteria**
- Doc viewer supports PDF/image inline.
- All document views are logged for audit purposes (NFR-09).
- Actions: `Approve`, `Reject with reason` (mandatory ≤ 500 chars).
- Approve → seller account activated; seller can start listing products. (→ ET-06)
- Reject → seller receives email with reason and can resubmit. (→ ET-07)

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
- Action: `Remove` on one or more flagged listings (single listing or multi-select from the queue).
- Mandatory reason per listing: dropdown (prohibited category / IP violation / misleading / other) + free text. When multi-selecting, admin may apply the same reason to all or set individually.
- Selected listings removed from catalog and search; product removed if all its offers are removed.
- Sellers notified by daily digest email — one email per seller per day aggregating all that day's removals. (→ ET-09)
- Action is auditable (one audit record per removed listing).
- Pending unshipped orders for removed listings remain active; sellers are still responsible for fulfillment. No new orders can be placed on removed listings.

---

## US-A-04b — Clear false-positive flagged listing
**As an** admin, **I want** to dismiss a flag on a listing I've reviewed and found compliant, **so that** false positives don't accumulate and legitimate listings stay live.
Priority: Must — trace: FR-A-03, FR-A-04

**Acceptance criteria**
- Action: `Clear / Approve` on a flagged listing; optional note (≤ 500 chars).
- Listing remains live in catalog and search; flag resolved.
- Action is auditable (admin, timestamp, note).
- Cleared listings do not re-trigger the same auto-flag rule unless the listing content changes.

---

## US-A-05 — Suspend seller account
**As an** admin, **I want** to suspend a seller account, **so that** repeat offenders can be stopped.
Priority: Should — trace: FR-A-05

**Acceptance criteria**
- Action requires reason + duration (7 / 30 / 90 days / permanent). Permanent requires explicit confirmation dialog.
- All listings deactivated on suspension.
- Seller cannot list new products or log into seller dashboard (buyer role still active if same account).
- Seller notified by email (→ ET-10); all listings removed from search; action is auditable.
- Pending unshipped orders at suspension time remain active; seller retains obligation to fulfill them. If seller remains suspended and an order is not shipped within its expected window, buyer is notified and a refund is issued. (→ ET-13)
- Suspension expiry: timed suspensions (7/30/90 days) auto-lift at `suspended_until`; listings are reactivated automatically and seller is notified by email (→ ET-11).

---

## US-A-05b — Reinstate suspended seller
**As an** admin, **I want** to lift a suspension early, **so that** I can act on a seller's successful appeal or correct a mistaken suspension.
Priority: Should — trace: FR-A-05

**Acceptance criteria**
- Suspended sellers list accessible from admin dashboard (US-A-00) and seller search (US-A-06).
- Action: `Lift suspension` with mandatory reason (≤ 500 chars).
- Seller account reactivated; all previously active listings restored to catalog and search.
- Seller notified by email with reinstatement reason. (→ ET-12)
- Action is auditable (supersedes prior suspension record, not replaces it).

---

## US-A-06 — Seller search and profile lookup
**As an** admin, **I want** to search for a seller by name or email and view their full profile, **so that** I can investigate complaints and review history without relying solely on queues.
Priority: Should — trace: FR-A-01, FR-A-02, FR-A-05

**Acceptance criteria**
- Search by business name, email, or tax ID; returns paginated results.
- Seller profile view shows: KYC status, account status (active / suspended), registration date, all active listings, count of removed listings, full moderation action history (removals, suspensions, clearances) with timestamps and admin actors.
- Profile provides direct links to KYC review (US-A-02) and suspension action (US-A-05).
