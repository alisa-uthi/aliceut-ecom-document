# Project Progress — AliceUT E-Commerce

Daily log of work on this project. Newest entry on top. One entry per active day.

**How to update**
- At session end, or when a milestone lands, add a new dated section at the top (below this header).
- Keep each subsection to bullets. If a subsection is empty, omit it. Keep the update direct and concise. Covering the key themes rather than every individual change.
- Use ISO date `YYYY-MM-DD`.
- Each day gets an explicit `<a id="YYYY-MM-DD"></a>` anchor immediately above its heading so external links resolve reliably (GitHub also auto-anchors the heading, but the explicit id survives renderer differences). Add the new date to the **Index** below.

**Entry template**
```
<a id="YYYY-MM-DD"></a>
## YYYY-MM-DD
**Focus:** one-line theme of the day.

**Done:**
- shipped or completed items

**Decisions:**
- locked choices (link to BRD § when relevant)

**Blockers:**
- what is stuck and why

**Next:**
- immediate next steps for the following session
```
---

> **Note on `phase-1/audits/` paths below.** That directory is gone: its two files — `2026-09-22-wave0-decisions.md` (decision records D-01…D-14) and `2026-09-22-alignment-audit-fix-plan.md` — were committed on 2026-09-22 and deleted again on 2026-09-24 by commit `c5767b8`. A `phase-1/audits/README.md` was never committed at any point, so entries below that describe creating one describe work that did not land. Every `phase-1/audits/…` path in the dated entries records what was worked from at the time; none of them resolve today. The decisions themselves are recorded inline in the documents they bind — `BRD.md` §12 and its amendment list, and `CLAUDE.md` Core Rules — and in the git history of commits `4f24166`, `61bbda4`, `f0db299` and `c5767b8`.

**Index**
- [2026-09-30](#2026-09-30) — Dead `D-NN` pointer scrub finished; the five open audit contradictions resolved (BRD v1.4); `conventions/` pass closed.
- [2026-09-24](#2026-09-24) — Alignment-audit Waves 2/3/4/5/6 fixes; all ten Wave 7 hygiene items.
- [2026-09-22](#2026-09-22) — Alignment-audit Wave 0 decision gate (BRD v1.3) and Wave 1 event-contract fixes.
- [2026-09-19](#2026-09-19) — Cross-document alignment audit; static backlog deleted in favour of GitHub Issues.
- [2026-09-13](#2026-09-13) — Backlog decomposition + GitHub Issues script (**superseded 2026-09-19** — both deleted).
- [2026-09-13 (earlier)](#2026-09-13-tooling) — Claude Code subagent routing guideline + CLAUDE.md templates.
- [2026-09-12](#2026-09-12) — Phase 1 documentation complete: full developer-readiness audit, cross-doc alignment (multi-pass), Mermaid rendering fixes, interactive architecture diagrams.
- [2026-09-03](#2026-09-03) — Developer guidelines, repo restructure, GitHub PR Stack, CI Claude review, TOC pass.
- [2026-09-02](#2026-09-02) — API/data-lifecycle conventions, UI cross-validation, response-envelope migration, observability stack.
- [2026-08-30](#2026-08-30) — 116-finding consistency fix pass, MinIO decision, all 81 sequence diagrams, Mermaid validation.
- [2026-08-29 (session 3)](#2026-08-29c) — Revalidation fixes across 7 design docs.
- [2026-08-29 (session 2)](#2026-08-29b) — Phase 1 technical design + UI design produced by parallel agent team.
- [2026-08-29](#2026-08-29) — Requirements deep-dive: order lifecycle, buyer stories, auth portals, BA revalidation.
- [2026-08-22](#2026-08-22) — Phase 1 technical-design kickoff; architecture overview + ERD.
- [2026-08-19](#2026-08-19) — Requirements freeze (BRD v1.2 signed off) + repo scaffolding.

<a id="2026-09-30"></a>
## 2026-09-30
**Focus:** finish the 2026-09-24 cleanup pass — scrub the dead decision pointers, then rule on the five contradictions it surfaced.

**Done:**
- Scrubbed all 59 dead `D-NN` decision citations left behind when `phase-1/audits/` was deleted (commit `c5767b8`), across 20 files. Each one had its decision's substance inlined at the citation site before the pointer came out, so nothing now points at an unopenable record. `docker-compose-topology.md` § `btree_gist` was rewritten rather than tag-stripped: it cited a decision record that turned out to be about the sole-writer rule and said nothing about `pg_cron`, so the bundled-contrib-versus-third-party argument is now stated in place.
- Applied the five contradictions the alignment audit raised and deliberately left for a ruling. BRD to v1.4; version citation bumped in the 33 documents that name it.
- Confirmed the `@aliceut/shared-ui` versus `libs/ui/` split in `frontend-coding-standards.md` is **not** a defect — one is the tsconfig path alias for the other's barrel file, and every site uses the right one.
- Closed the `conventions/` pass the killed agent team left mid-run. Audited all 10 documents (4,671 lines) for dead links, cross-file duplication and stale scope claims: **0** dead links or anchors, and the only lines repeated across files are `**Source of truth:**` header boilerplate, which is supposed to repeat. No `72 hours`, `BUSINESS_BUYER` or `B2B_TIER` survives in `conventions/`. Delegation between overlapping documents is already one-directional — `api-conventions.md § Money` defers to `backend-coding-standards.md § 3`, `§ Correlation ID` to `observability.md`, and `conventions/kafka-events.md` (envelope, registry, idempotency, DLQ) to `phase-1/technical-design/kafka-events.md` (topic catalogue) — so nothing needed merging or deleting.
- Header shape is now uniform: every one of the 10 carries `**Status:**` and `**Source of truth:**`. `data-lifecycle.md` had neither and `design-system.md` had no source line — it now names the Figma file as authority for visual design and the BRD for stack. `data-lifecycle.md` deliberately keeps no `## Summary` block: it is 19 lines with no sections to index.
- Scoped `auth-jwt-design.md § 3`'s password-reset line to admins. It read "No password reset UI in V1" under a heading that limits it to the admin portal, which is correct in place but wrong when quoted — buyer and seller self-service reset exists (US-B-13, US-S-12) and is specified in § 9 of the same document.
- Fixed a residue of the roles ruling that the first sweep missed: `user-stories/admin.md` still seeded the admin with a singular `role: ADMIN`. Now `roles = ['ADMIN']`, matching the `TEXT[]` column.

**Decisions:**
- FR-S-03 no longer lists price as a product attribute (BRD § Amendments 2026-09-30). Price lives on `Offer`; `POST /seller/products` and `POST /seller/offers` are separate writes.
- FX rates are `NUMERIC(19,8)`, now stated at FR-P-04. The 4-digit rule binds monetary amounts; a rate is not one, and an inverse rate against a zero-decimal currency loses material precision at 4 digits.
- Roles and `account_type` are orthogonal, ERD wins: `roles TEXT[]` ∈ {BUYER, SELLER, ADMIN}, `account_type` ∈ {B2C, B2B}. `BUSINESS_BUYER` and `B2B_BUYER` are gone from the stories, including the seed demo-account list. A seller who also buys adds the `BUYER` role to the same account — not a second account.
- ET-08 has three trigger sources, not two. A `FLAG`-tier match at offer create **does** create the listing as `FLAGGED` and fires ET-08; only a prohibited node or a `BLOCK`-tier term is the 422-with-no-event path (FR-P-06c).
- KYC review SLA is **3 business days** (BRD §12 #14), persisted once at submit as `seller.kyc_application.review_due_at`. Mon–Fri `Asia/Bangkok`, 17:00 cutoff, holiday set configurable and empty in V1. The four independent `submitted_at + INTERVAL '72 hours'` recomputations were the actual defect; every badge, count and email now reads the column.

**Next:**
- `phase-1/ui-design/` has no audit report — that partition stays unverified. (`conventions/` is now done.)
- Smaller items still open: `README.md` Story Sequencing holds task state that belongs in GitHub Issues, near-duplicate password-reset stories US-B-13 / US-S-12, six NFRs defined and referenced nowhere (NFR-01, 04, 08, 12, 16, 17), and whether `api-design/seller.md` (2117 lines) should be split.
- Backlog decomposition straight into GitHub Issues remains the pre-implementation gate.

---

<a id="2026-09-24"></a>
## 2026-09-24
**Focus:** Alignment-audit fix waves 2/3/4/5/6 + all ten Wave 7 hygiene items.

**Done:**
- Waves 2 (money correctness), 3 (missing contracts), 5 (convention consistency) and 6 (UI design documents) of `phase-1/audits/2026-09-22-alignment-audit-fix-plan.md` applied across 13 files — `conventions/backend-coding-standards.md`, `backend-module-architecture.md`, `design-system.md`, `phase-1/technical-design/api-design/{cart,catalog,pricing,search,seller}.md`, `consumer-field-matrix.md`, `phase-1/ui-design/{buyer-portal,seller-portal,shared-components}.md`, `.gitignore`
- Money errors: `CurrencyScaleUnavailableError` now carries operator-only `context` and maps to `500` in `APP_ERROR_STATUS_MAP`; every `AppError` code must be registered there, since the `?? 422` default mislabels a server fault as bad input
- FX disclosure: `PriceDisplay` FX props bound on cart and checkout line totals and per-seller subtotals; cross-group `itemSubtotal` / `grandTotal` disclose FR-P-02 through a summary caption instead, because they have no single native currency to put in `estimatedFrom`
- `converted` fixed as a template-derived expression, not a response field — no API returns it
- Three broken `PriceDisplay` anchors repaired (`#priceDisplay` → `#83-pricedisplay`); portal docs now reference the canonical prop surface instead of restating it
- Wave 7 hygiene: `CLAUDE.md` restated as design-complete with GitHub Issues as the status source, repo layout corrected (added `diagrams/`, `screens/`, `audits/`, `guidelines/templates/`, sibling `aliceut-ecom-infra`), `phase-2/` marked planned-not-on-disk, out-of-scope list synced to BRD §3.2 (buyer email change), five-week-stale Prior-Session Context deleted; this log's index completed and its stale claims corrected

**Decisions:**
- `fxRate` appears only in `lowestOffer` (search results). `effectivePrice`, `lineTotal` and `group` carry `currency` / `fxAsOf` / `fxStale` only
- `grandTotal.fxAsOf` is the oldest constituent rate, so the caption says "rates as of" rather than implying one rate governed the whole total

**Wave 4 + Wave 7 (later in the same session):**
- Wave 4 (propagate the BRD/CLAUDE.md amendments) applied after a verification grep pass. Item 5 reported inapplicable: it asks for a story-vs-FR capability audit that no enumerated list in the repo supports, and its four known concrete instances were already Wave 1 items 7–10 (Postgres search fallback, admin manual flagging, CSV bulk-inventory dry-run, zero-stock auto-hide). A mechanical traceability check confirmed every `FR-*` / `NFR-*` id cited in the story files exists in the BRD tables
- All ten Wave 7 items applied: dead `scripts/create-github-issues.ps1` deleted and its two `CLAUDE.md` references removed; `phase-1/audits/README.md` created as the audit index; five `email-templates.md` anchors corrected (GitHub strips the em dash, so `## ET-01 — …` slugs to two hyphens, not four); compose build contexts `./backend` → `../aliceut-ecom-backend`; `LOG_SENSITIVE_KEYS` added to `.env.example` and `LOG_MAX_BODY_BYTES` unified at `4096`; `registeredJobs` reconciled to **14** across `api-design/health.md`, `phase-1/technical-design/backend-module-architecture.md` and `cleanup-jobs.md`; `authGuard` route, testing-guidelines seed scope, `CHANGELOG.md` ownership and the repo-wide `BRD v1.2` → `v1.3` sweep (30 files) done

**Decisions (Wave 7):**
- `registeredJobs: 14`, derived rather than asserted: `@nestjs/schedule` counts decorated *methods*, and `cleanup.scheduler.ts` holds eight of them, so six single-job schedulers + 8 = 14, cross-checked against cleanup-jobs' ten rows + the four non-retention jobs (digest, FX refresh, delivery mock, auto-refund). The derivation is written into all three documents so the number stays auditable
- `CHANGELOG.md` belongs to `aliceut-ecom-backend` and `aliceut-ecom-frontend`, neither of which exists yet. This documentation repo is never tagged and keeps no changelog — its running record is this file
- ~~`phase-1/audits/README.md` indexes the nine inline audits by commit with dates and diffstats rather than reconstructing their finding lists, which would be a guess and not a record. `architecture-overview.md` §14's row narrowed to match~~ — **corrected 2026-09-24:** no such index was ever committed. The audit trail is the git history and this log; `architecture-overview.md` §14 no longer carries a row for it

**Also:**
- Hardcoded cross-document counts removed: no document now asserts “thirty-nine consumer groups”, “twenty-nine topics”, “forty DLQ topics” or `registeredJobs: 14`. Each statement now names the list that owns the items — the module summary table for consumer groups, `kafka-events.md § 1` for topics, the scheduled-task table for jobs — and keeps the counting *rule* (a DLQ is per consumer group, not per topic; the scheduler registry counts decorated methods, not files) without the tally. Touched `kafka-events.md`, `backend-module-architecture.md`, `consumer-field-matrix.md`, `docker-compose-topology.md`, `api-design/health.md`, `cleanup-jobs.md`. `consumer-field-matrix.md § 7` keeps its figures but is now labelled a dated audit record that nothing else should cite
- Lock framing dropped across the living documents: no document now claims a BRD decision is locked, signed off, non-negotiable or not revisable. §12 is described as the decisions currently in force, changed by amending the BRD. Renames: `CLAUDE.md` “Locked Stack” → “Current Stack” and “Non-Negotiable Rules” → “Core Rules”; `development-flow.md` §10 “Cross-cutting non-negotiables” → “Cross-cutting rules” (anchor renamed with it, single inbound link updated); both `guidelines/templates/*-CLAUDE.md` “Locked stack” / “Non-negotiables” retitled. BRD status line, §12 heading and closing line reworded to “agreed” / “current baseline”. Dated entries in this log and in `phase-1/audits/` left as-is — they record what was decided at the time

**Next:**
- Redo backlog decomposition **directly into GitHub Issues** (no checked-in backlog file), then Sprint 1 implementation kickoff

<a id="2026-09-22"></a>
## 2026-09-22
**Focus:** Alignment-audit Wave 0 decision gate and Wave 1 event-contract fixes.

**Done:**
- `phase-1/audits/2026-09-22-alignment-audit-fix-plan.md` — 8-wave fix plan with findings index and sequencing
- `phase-1/audits/2026-09-22-wave0-decisions.md` — decision records D-01…D-14 closing the gate every later wave depends on; BRD amended to v1.3
- Wave 1 (18 files): event-contract alignment across `kafka-events.md`, `consumer-field-matrix.md` (new), `api-design/{admin,auth,orders,search,seller}.md`, `cleanup-jobs.md`, `docker-compose-topology.md`, `data-model-erd.md`, `data-model-mongodb.md`
- N11 follow-up: D-05's superseded Trigger cells marked inline

**Decisions:**
- Prohibited-content tier comes from the matched blocklist term's stored `enforcement` (`BLOCK` | `FLAG`), not from match precision; `match_type` is an independent column and both tiers support every matching mode (D-14)
- Redis added to the locked stack: `noeviction` on the instance holding single-use tokens (60s OAuth authorization code), separate eviction-enabled cache instance
- `B2B_TIER` removed from V1 in the BRD FR table itself, not only in an appendix

<a id="2026-09-19"></a>
## 2026-09-19
**Focus:** Cross-document alignment audit (74 files, +8128/−9662).

**Done:**
- Full cross-document alignment audit pass across requirements, technical design, UI design and conventions
- **Deleted `phase-1/backlog/`** — `backlog.md`, `sprint-plan.md` and all 20 `epic-breakdown/` files (22 files, ~5900 lines). A checked-in backlog duplicates task state that belongs in GitHub Issues and drifts from the specs it cites

**Decisions:**
- Implementation status lives in GitHub Issues + Milestones + Project board only; this repo holds specs
- `scripts/create-github-issues.ps1` is left in the tree but is now dead — its `$epicDir` points at the deleted `epic-breakdown/`. Slated for deletion in Wave 7

<a id="2026-09-13"></a>
## 2026-09-13
**Focus:** Phase 1 backlog decomposition + GitHub Issues automation.

> **Superseded 2026-09-19.** Every artifact below was deleted in `c805aed`: the 22 backlog files, and the issue-creation script's only input. No GitHub Issues were ever created from them. Kept as a record of what the decomposition covered, not as a pointer to living files.

**Done:**
- `phase-1/backlog/backlog.md`: master backlog, 20 epics, 211 tasks prioritized by implementation order
- `phase-1/backlog/sprint-plan.md`: 11 detailed sprints + 7 directional, solo dev 40h/sprint, risk register
- `phase-1/backlog/epic-breakdown/` — 20 epic files (INFRA → FE-ADMIN); each task has ID, estimate, US ref, dependencies, spec references, implementation notes, done criteria
- Epic breakdown format: metadata as bullet list (renders correctly in GitHub), `**Spec References:**` per task pointing to `phase-1/technical-design/` docs, `**Status:**` removed (GitHub Issues is status source)
- `scripts/create-github-issues.ps1`: creates 211 GitHub Issues from epic breakdown files — milestones (Sprint N), labels (epic:name), optional GitHub Project linking; `-DryRun` flag for preview

**Decisions:**
- GitHub Issues + Milestones + Project board = live status; epic breakdown files = static specs only
- Money invariants, outbox pattern, async search enforced in every relevant task description
- Script dry-run reported 211 issues clean across all 20 epics **as of this date only** — not reproducible since 2026-09-19, when its input directory was deleted

**Next (as recorded on 2026-09-13; both steps are void — see [2026-09-19](#2026-09-19)):**
- ~~Create GitHub Project manually, then run `.\scripts\create-github-issues.ps1 -ProjectNumber <N>`~~ — script has no input; decomposition must be redone directly into GitHub Issues
- Implementation kickoff: Sprint 1 — INFRA → SHARED → ORDERS → FE bootstrap

---

<a id="2026-09-13-tooling"></a>
## 2026-09-13 (earlier)
**Focus:** Developer tooling — Claude Code subagent routing guideline.

**Done:**
- Created `guidelines/claude-code-subagents.md`: install instructions for `voltagent/awesome-claude-code-subagents`, routing map (backend/frontend/docker/CI-CD/review/tests), usage examples with project-specific context, pre-push hook reminder pattern
- Added subagents entry to `development-flow.md §4` conventions map
- Created `guidelines/templates/backend-CLAUDE.md` and `frontend-CLAUDE.md`: embed locked stack, module tiers, layer rules, money/events/auth non-negotiables, subagent routing, full conventions reference, compact pre-merge checklist
- Added `cp` commands to `development-flow.md §2 Step 1` so new developers copy CLAUDE.md templates on first clone

**Decisions:**
- Pre-push hook is advisory (echo only), not blocking — keeps the policy in process rather than brittle shell enforcement

**Next:**
- Implementation kickoff: technical design phase or backlog decomposition (per BRD §12)

<a id="2026-09-12"></a>
## 2026-09-12
**Focus:** Phase 1 documentation — developer-readiness audit, cross-doc alignment passes, Mermaid fixes, architecture diagrams.

**Done:**
- **Developer-readiness audit** (71 findings: 14 BLOCKING, 29 HIGH fixed) across all 37 phase-1 docs: wrong HTTP codes, missing ES-sync outbox events, docker-compose build context + volume + healthcheck fixes, Angular version bumps to 22+, missing shared-components.md spec (new file), 15 user story ACs added/tightened
- **Kafka ↔ email ↔ API alignment**: fixed all mismatched Kafka trigger names in email-templates.md; added missing payload fields to seller.reinstated + fulfillment.cancelled events; added listing.flagged topic; added LISTING_FLAGGED/FULFILLMENT_CANCELLED/SUSPENSION_EXPIRED in-app notification types
- **Cross-doc alignment (28 findings)**: guard names (KycApprovedGuard → SellerApprovedGuard); notification mark-all-read POST → PATCH; KYC_APPROVED/REJECTED → KYC_DECIDED; FULFILLMENT_SHIPPED/DELIVERED → SHIPMENT_UPDATE/DELIVERY_UPDATE; JWT_REFRESH_TTL 30d → 7d; Grafana port 3000 → 3200; design-system @aliceut/ui → @aliceut/shared-ui
- **Cross-doc alignment (13 findings)**: refresh token delivery corrected to HttpOnly cookie only; invalid PROCESSING fulfillment status removed; listing.soft_deleted ES delete fixed to unconditional; businessLogoUrl removed from PATCH /profile/me; Redis service added to docker-compose (`redis:7-alpine`, JWT revocation); `expire_reservations()` rewrote to LOOP pattern (stock release + outbox event atomic per row, race condition eliminated); search module consumers completed (inventory.reservation_expired, seller.suspension_expired, listing.soft_deleted, fx_rate.updated); app/lib naming aligned (buyer-app/seller-app/admin-app, libs/ui/)
- **Mermaid rendering**: all sequence diagrams capped at alt/loop/opt nesting depth ≤ 2 (4 files fixed: admin, orders, cart, pricing)
- **Interactive diagrams**: two standalone HTML files at repo root — `architecture-overview.html` (system architecture) and `event-dataflow.html` (event-driven outbox dataflow), each 9/9 on showcase validation. A third, buyer-journey workflow, was built the same day but is not in the tree. Mermaid diagram *sources* live in `phase-1/diagrams/` (01–06) and are a separate set

**Decisions:**
- Suspension-expiry: pg_cron canonical; NestJS `suspension-expiry.scheduler.ts` removed
- Reservation-expiry: pg_cron `expire_reservations()` owns stock release + outbox event; NestJS `reservation-expiry.scheduler.ts` removed
- SLA: 72h calendar time (not business days)
- Redis: ephemeral (no volume), `maxmemory 256mb allkeys-lru`; only `api` depends on it

**Next:**
- Implementation: scaffold `aliceut-ecom-backend` + `aliceut-ecom-frontend` repos per backend-module-architecture.md and guidelines/

---

<a id="2026-09-03"></a>
## 2026-09-03
**Focus:** Developer guidelines, repo restructure, GitHub PR Stack, CI Claude review, TOC pass.

**Done:**

_Developer guidelines (new files under `guidelines/`)_
- `git-workflow.md` — branching strategy, Conventional Commits, PR process (incl. §3.4 Stacked PRs with `gh stack`), GitHub Projects, SemVer releases, hotfix flow, commitlint CI; §7.3 `ci.yml` with `claude-design-review` job
- `testing-guidelines.md` — testing pyramid (70/20/10), coverage thresholds by module tier (Tier 1: 80% branch), NestJS unit/integration, Kafka consumer idempotency, Angular CDK harness, Playwright E2E + page objects, factory pattern, CI gates
- `development-flow.md` — local dev setup, daily workflow diagram (incl. Claude review step), conventions map, MongoDB/MinIO rules, API client regen, full pre-merge checklist
- Tech lead review applied 6 cross-doc fixes (lock files in `.gitignore`, money lint AST selector scope, app portal naming, env var checklist additions)

_Also moved from `conventions/` to `guidelines/`_: `git-workflow.md`, `testing-guidelines.md`, `development-flow.md`

_Repo restructure_
- All `backend/` refs → `aliceut-ecom-backend/`, `frontend/` refs → `aliceut-ecom-frontend/` across 8 files each
- Local workspace layout updated: four sibling repos under `aliceut-ecom/` parent (document, backend, frontend, utility-pipeline)
- `docker-compose-topology.md` nginx volume paths updated to sibling-repo relative paths (`../aliceut-ecom-frontend/`)

_Stack version bumps_
- Node.js 22 LTS, pnpm 10+, Angular CLI 20+, Angular 20+, NestJS 11+ — applied in `development-flow.md`, `architecture-overview.md`, `CLAUDE.md`. **Angular and the CLI were raised again to 22+ on [2026-09-12](#2026-09-12); 22+ is the locked floor** (BRD §12)

_GitHub PR Stack + CI Claude review_
- `git-workflow.md` §3.4: stacked PR pattern with `gh stack` extension (branch chain, open/sync/merge workflow)
- `git-workflow.md` §7.3: `claude-design-review` CI job — diffs PR against main (`.ts` files), runs `claude --print` with design spec context, posts findings as PR comment; prompt scoped to diff-touched lines only

_TOC pass (all 36 docs)_
- Added `## Summary` anchor-link table and `<a id="">` anchors before every `##` section across entire repo: all conventions, guidelines, phase-1 technical-design (API specs, ERD, kafka, docker-compose, module-arch, implementation-specs), phase-1 ui-design (buyer/seller/admin portals, navigation-routing), architecture-overview

<a id="2026-09-02"></a>
## 2026-09-02
**Focus:** Conventions + design doc day — API/data lifecycle conventions, full UI cross-validation, API response migration, Kafka consumer patterns, observability stack.

**Done:**

_Product owner decisions (carry-forward from 2026-08-29b)_
- Search: suppress offers from suspended sellers — **yes**.
- Max saved addresses per buyer: **10** (matches US-B-14).
- Buyer currency param at checkout: **display only** — affects price display, not `Price` row selection.

_`conventions/api-conventions.md`_
- Added `## Datetime` section: ISO 8601 UTC strings (`Z` required, ms precision), `*At`/`*Date` field naming, `TIMESTAMPTZ` storage, client-side TZ conversion, ISO 8601 duration strings.
- Added `## Success Response Shape` section: always-envelope `{ data, meta }` for single resource + collection; HTTP 204 for empty success.

_`conventions/data-lifecycle.md` (new file)_
- Documented all `pg_cron` cleanup jobs: `refresh_session`, `email_verification_token`, `password_reset_token`, `idempotency_key`, `outbox_event`, `processed_event`, `fx_rate` — plus `inventory.expire_reservations()` and `seller.lift_expired_suspensions()` PG functions.
- Phase 1 job catalog moved to `phase-1/technical-design/cleanup-jobs.md`; conventions file holds cross-phase rule + pointer only.

_`phase-1/technical-design/api-design/` — response envelope migration_
- All 11 files updated: every non-204 success response wrapped `{ "data": { ... } }`.
- Applied to JSON blocks and Mermaid sequence diagram inline responses.
- Files: `auth.md`, `profile.md`, `catalog.md`, `pricing.md`, `cart.md`, `orders.md`, `admin.md`, `notifications.md`, `seller.md` (search + health already correct).

_UI design cross-validation — 15 fixes across 2 passes_
- `seller-portal.md`: `[ORD-xxx]` → `[FUL-xxx]`; B2B_TIER `min_qty` `≥ 1` → `≥ 2`; no-enumeration pattern on forgot-password (removed `notFoundError` banner); `KYC_APPROVED` → `APPROVED` (5 occurrences); `validFrom`/`validUntil` → `startsAt`/`endsAt`; anti-enumeration success copy; removed non-existent pre-validation spinner.
- `navigation-routing.md`: `NotSuspendedGuard` source → `seller_suspension_status` JWT claim; removed undefined `AdminGuard` on notifications child route.
- `buyer-portal.md`: email-verified warning text scoped to checkout only; `accountType === 'B2B'` → `isBusinessAccount`; `?next=` → `?returnUrl=` throughout; removed non-existent `validate-reset-token` endpoint; resend-verification body removed (JWT-authenticated).
- `admin-portal.md`: `KYC_PENDING` → `PENDING_KYC`; `registeredAt` → `createdAt` (table + detail panel).

_`conventions/kafka-events.md` — consumer processing patterns_
- Added §4.1 Mermaid flowchart: generic consumer loop (poll → dedupe → side effect → `processed_event` INSERT → offset commit → DLQ).
- Added §4.2 consumer family patterns: processing bodies for all 5 families (`notification.*`, `search.*`, `audit`, `inventory.*`, `orders.*`).
- Added `Pattern` column to all 24 event consumer group tables in `phase-1/technical-design/kafka-events.md`.

_`conventions/observability.md` (new file)_
- Stack: Grafana Alloy (unified collector) → Loki + Prometheus + Tempo → Grafana.
- NestJS logger: `nestjs-pino` via `LoggerModule.forRootAsync`; structured JSON; `pino-pretty` for dev.
- Log envelope: mandatory fields (`correlationId`, `service`, `module`, `userId`, `traceId`/`spanId` reserved).
- Sensitive field masking: pino `redact` for headers; `buildSanitizer()` factory (recursive JSON replacer, case-insensitive, size-guarded) for request + response bodies. Keys + `maxBodyLogBytes` driven by `LOG_SENSITIVE_KEYS` / `LOG_MAX_BODY_BYTES` env vars — add keys by updating `.env` + `docker compose up -d --no-build`, no rebuild.
- `X-Correlation-ID` propagation: inbound middleware → `AsyncLocalStorage` → Axios interceptor forwards on all outbound calls.
- `LoggingInterceptor`: captures response body via RxJS `tap`; sanitizes before logging.
- Alloy `config.alloy`: Docker discovery, JSON parsing, low-cardinality labels (`level`, `service`), `correlationId` as structured metadata (not label).
- docker-compose snippets for Alloy, Loki, Prometheus, Grafana with provisioning.
- Playwright E2E correlation strategy: inject `X-Correlation-ID` per test → assert UI + `waitForResponse` + direct DB fixture → post-failure Loki query by `correlationId`.

_Currency field clarity pass_
- Root problem: every `currency`/`currency_code` field in API responses and Kafka schemas was unlabeled — ambiguous whether it was seller's native pricing currency or buyer's display/preference currency.
- `search.md`: added `displayAmount`, `displayCurrency`, `fxRate` to `lowestOffer`; added `displayMin`, `displayMax`, `displayCurrency` to `facets.priceRange`; updated ES query note to reference `display_prices[currency]`; added notes block explaining buyer vs seller fields.
- `pricing.md`: renamed `displayInCurrency` → `displayCurrency` (naming consistency); labeled `currency` param as buyer's requested display currency; added field semantics block.
- `catalog.md`: `GET /catalog/products/:id/offers` — added `displayAmount`/`displayCurrency`/`fxRate` to `effectivePrice`; fixed incorrect sequence query that filtered `AND currency_code = :currency` (would miss offers priced in a different native currency); added separate FX join step; added field semantics note. `GET /catalog/products/:id` — added note that it returns seller-native only, directs to `/offers?currency=` for display conversion.
- `cart.md`: added `displayAmount`/`displayCurrency` to `effectivePrice`; added field semantics (display currency from `buyer.profile.preferred_currency` in JWT); updated both sequence diagrams with explicit FX join labeling.
- `kafka-events.md`: annotated `doc` fields across `fulfillment.placed`, `fulfillment.refunded`, `fulfillment.refund_suspended_seller`, `fx_rate.updated`, `offer.changed` — every `currency_code` now states seller-native vs buyer-display. Bug fix: `RefundedItem.fx_rate_used_at_capture` was non-nullable `"string"` (structural inconsistency vs `fulfillment.placed` where same field is `["null","string"]`); corrected to `["null","string"]` with `"default": null`.
- `data-model-erd.md`: labeled `pricing.offer_price.currency_code` (seller native); `pricing.fx_rate.base_currency_code` (seller native) and `quote_currency_code` (buyer display); `orders.fulfillment` monetary columns (`shipping_cost`, `tax_total`, `total_amount`) in `currency_code` (seller native); `orders.fulfillment_item.currency_code` (seller native), `unit_price`, `tax` (seller native), `fx_rate_used_at_capture` (base=seller native → quote=buyer display, null when no conversion); `orders.payment_attempt.currency_code` + `amount` (seller native).

**Next:**
- Backlog decomposition or implementation scaffolding — direction TBD next session.

---

<a id="2026-08-30"></a>
## 2026-08-30
**Focus:** Full design documentation day — consistency review + 116-finding fix pass, repo restructure, MinIO decision, all 81 sequence diagrams, Mermaid syntax validation.

**Done:**

_Cross-artifact review & fixes_
- Read and cross-referenced all phase-1 user stories + design docs; produced 39-finding report (7 CRITICAL, 24 MAJOR, 8 MINOR).
- 3-team parallel review (technical-design, ui-design, cross-validation) surfaced 77 additional findings (10 CRITICAL, 40 MAJOR, 27 MINOR); 8 parallel fix agents applied all fixes across 11 files.
- Key fixes: 6 new Kafka events, 8 new API endpoints, 10 new ERD columns, consumer group corrections, seller/admin/buyer portal completions, design-system pipes.

_Repo restructure & architecture_
- Extracted cross-phase conventions into `conventions/`: `auth-jwt-design.md`, `design-system.md`, `backend-module-architecture.md`, `kafka-events.md`.
- Added MinIO to stack: 3 buckets (`product-images` public, `kyc-documents` + `user-assets` private); added `minio` + `minio-init` services to docker-compose; closed ERD §10 open decision #2.
- Rewrote `architecture-overview.md` as cross-phase reference (removed Phase-1-specific framing).

_Sequence diagrams — all 11 API modules (~81 diagrams total)_
- Auth (13 endpoints) + Profile (7): guard chain, outbox writes, refresh reuse-detection, OAuth callback CSRF.
- Catalog (5), Pricing (2), Search (1 endpoint + 6 ES maintenance): effective price resolution, all ES consumer groups.
- Seller (21 endpoints): full guard chain, outbox, KYC/suspension gate, bulk CSV inventory, PII access log.
- Cart (6), Orders (3), Admin (12), Notifications (3 + async section), Health (1): full coverage, all embedded inline per endpoint.

_Mermaid syntax validation_
- Identified root causes: `<br/>` in `Note over` text (converts to newline mid-parse), `;` in Note/arrow text (treated as statement separator by jison lexer).
- Fixed 6 files (cart, catalog, pricing, search, seller, auth) via parallel agents; all `<br/>` removed from Note lines, all `;` replaced.

**Decisions:**
- Diagrams embedded inline per endpoint, not in a separate `sequences/` directory.
- MongoDB audit writes modeled outside Postgres transaction boundary.
- Notification consumer idempotency via `platform.processed_event(consumer_group, event_id)`.
- `FLAGGED` added as explicit `offer_status` enum value (not derived from moderation_case).
- Auth transactional emails (ET-18/19/20) moved to Kafka outbox — no inline SMTP.
- ES price fields use `keyword` type; range filters via numeric sub-field.
- ET-09 daily digest: buffer table + 23:00 UTC cron (not Kafka Streams).
- `conventions/` classifier: "would phase-2 engineers change this, or just reference it?" — reference-only files move there.

**Next:**
- Verify diagrams render correctly in GitHub / Mermaid Live.
- Begin implementation scaffolding (NestJS monorepo init, docker-compose up).

<a id="2026-08-29c"></a>
## 2026-08-29 (session 3)
**Focus:** Revalidation fixes — applied all blocking and high-priority findings from parallel agent review across 7 design docs.

**Done:**
- `data-model-erd.md` — `seller_profile.status` split into `kyc_status` + `suspension_status`; `fulfillment.display_id` added (`FUL-<8hex>`); `low_stock_threshold` added to `inventory.stock`; 5 missing cross-schema FKs added; CHECK constraints; missing timestamps; `platform.outbox_event` partial index note.
- `kafka-events.md` — BRD version fixed; `order.completed` payload corrected (`fulfillment_ids[]` + `order_id`, partition key `order_id`); delivery-tracker consumer description fixed (queries `orders.fulfillment`); `fulfillment_id` + `display_id` added to all fulfillment event payloads; `order.finalized` `placed_orders` renamed to `placed_fulfillments`; new `seller.reinstated` event added (§2.15); §3 topic summary updated.
- `api-design.md` — BRD version fixed; guard legend updated to `kyc_status`/`suspension_status`; §9.8 DELETE offer removed (duplicate of PATCH); `orders[]` note added (each element = fulfillment); §8.3 response schema added; 409 price-changed response body added; `PATCH /seller/profile` endpoint added; `GET /admin/sellers/:sellerId` added; §10.4 response schema added; §10.6 reinstate side effects added; §10.9 ES deindex now async via Kafka; notification types `REFUND_ISSUED`, `KYC_SUBMITTED`, `ORDER_COMPLETED`, `SELLER_REINSTATED` added.
- `auth-jwt-design.md` — BRD version fixed; `seller_status` JWT claim split into `seller_kyc_status` + `seller_suspension_status`; OAuth callbacks fixed from URL fragment to query param + `HttpOnly` Set-Cookie; guard definitions updated; guard matrix extended (OAuth endpoints, resend-verification); §13 design decision updated.
- `implementation-specs.md` — `SellerProfile.status` split into `kyc_status` + `suspension_status`; `User.account_type` `CONSUMER`/`BUSINESS` → `B2C`/`B2B`.
- `backend-module-architecture.md` — BRD version fixed; inventory consumer group label clarified (`fulfillment.placed` topic vs `inventory.fulfillment-placed` group); `seller.reinstated` added to admin/search/notifications Kafka columns; Workers module row added.
- `docker-compose-topology.md` — BRD version fixed; MongoDB auth credentials added (`MONGO_INITDB_ROOT_USERNAME/PASSWORD`); healthcheck updated to authenticate; both `MONGODB_URI` values updated with auth; workers `depends_on` mongodb added; `.env.example` MongoDB section updated; FX URL fixed to `api.exchangerate.host`.

**Decisions:**
- `seller_kyc_status` and `seller_suspension_status` as separate JWT claims (independent guard composition — a KYC-approved seller can be suspended without affecting their KYC state).
- `FUL-<8hex>` as fulfillment display ID distinct from order's `ORD-<8hex>` (buyer-facing "orders" in UI are actually fulfillments).

**Next:**
- Backlog decomposition into implementation tickets, or start implementation scaffolding.

<a id="2026-08-29b"></a>
## 2026-08-29 (session 2)
**Focus:** Phase 1 technical design + UI design produced by parallel agent team.

**Done:**

_Technical design (`phase-1/technical-design/`)_
- `api-design.md` — 67 REST endpoints across all modules; auth guards, request/response shapes, cursor pagination, money as strings.
- `kafka-events.md` — 14 topics; full Avro schemas (envelope + payload); consumer groups with side effects; BACKWARD compat rules; DLQ topology.
- `auth-jwt-design.md` — JWT access token (15 min, HS256, `roles[]`, `seller_status` embedded); opaque refresh token (7 days, HttpOnly cookie, SHA-256 stored); refresh rotation + reuse-detection sequence diagrams; Google + Facebook OAuth flows; guard matrix (5 guards × all endpoint groups); argon2id params; rate limits; security headers.
- `docker-compose-topology.md` — 11 services (3 nginx, api, workers, postgres, mongo, elasticsearch, kafka KRaft, schema-registry, kafka-ui); full `docker-compose.yml` YAML; health checks; `.env.example`.
- `backend-module-architecture.md` — hexagonal 4-layer structure per module; CQRS-lite (no `@nestjs/cqrs`); repository interface pattern; outbox integration with `EntityManager` tx propagation; OpenAPI generation pipeline; module dependency table.
- `data-model-erd.md` (updated) — `role` (single) → `roles TEXT[]`; added `email_verification_token`, `password_reset_token`, `email_template` tables; `idempotency_key_id` on order; corrections log.

_UI design (`phase-1/ui-design/`)_
- `design-system.md` — Indigo/Amber AM theme; 8px grid; CDK breakpoints; Material Icons catalogue; 9 shared `libs/ui/` component specs (ProductCard, StatusBadge, PriceDisplay, CurrencyInput, ConfirmDialog, DataTable, NotificationBell, FileUpload, EmptyState).
- `buyer-portal.md` — 13 screens (Home, Search, PDP, Cart, 4-step Checkout, Confirmation, Order History, Order Detail, Login, Register, Account Settings, Email Verification Pending, Forgot Password).
- `seller-portal.md` — 10 screens (Login, Register, KYC, Dashboard, Listings, Create/Edit Product, Order Queue, Order Detail, Inventory, Notifications).
- `admin-portal.md` — 8 screens (Login, Dashboard, KYC Queue, KYC Detail, Moderation Queue, Moderation Detail, Seller Management, Seller Detail).
- `navigation-routing.md` — Route trees for all 3 apps; 9 auth guards; guard matrix; deep-link behavior; query param conventions; TitleStrategy; scroll restoration.

_Consistency check (coordinator)_
- Guards align: UI `AuthGuard`/`KycApprovedGuard`/`NotSuspendedGuard` etc. match architect's guard matrix and JWT `seller_status` claim.
- Suspended-seller allowed-endpoints match UI's `KycApprovedGuard`-only gate on `/seller/orders`.
- Route structures consistent with 06-auth-portals diagram.

**Decisions:**
- Refresh token as HttpOnly cookie (reduces XSS surface; Angular interceptor handles 401→refresh→retry).
- `seller_status` embedded in JWT (avoids per-request DB lookup; 15-min propagation lag on suspension acceptable for V1).
- No `@nestjs/cqrs` — plain handler classes sufficient for V1.
- KRaft Kafka (no ZooKeeper) in docker-compose.
- `KycApprovedGuard` and `NotSuspendedGuard` show in-route overlays rather than hard redirects.
- `PreloadAllModules` for buyer-app; `NoPreloading` for seller-app and admin-app.

**Open questions (need product owner input):**
1. Search results — suppress offers from suspended sellers? (defaulted: yes)
2. Max saved addresses per buyer? (defaulted: no limit; US-B-14 said 10)
3. Buyer's currency param at checkout — affects price row selection or display only? (defaulted: display only)

**Next:**
- Resolve 3 open questions above.
- Begin backlog decomposition into implementation tasks.
- Scaffold repo structure (`aliceut-ecom-backend/`, `aliceut-ecom-frontend/`, `aliceut-ecom-utility-pipeline/`) when ready to code.

---

<a id="2026-08-29"></a>
## 2026-08-29
**Focus:** Full requirements deep-dive across 4 sessions — order lifecycle, buyer story validation, auth portals & diagrams, BA revalidation.

**Done:**

_Order lifecycle & cross-doc consistency_
- Refined buyer stories US-B-06–US-B-12; added `email-templates.md` (ET-01–ET-04).
- Locked entity hierarchy: `Order` → `Fulfillment` (per seller) → `FulfillmentItem` (snapshotted). `OrderItem` removed everywhere.
- Defined `Order.placement_outcome` (immutable: `FULLY_PLACED` | `PARTIALLY_PLACED`) vs `Order.status` (projected read model).
- Kafka events: `order.finalized` (per Order), `fulfillment.placed/shipped/delivered/refunded` (per Fulfillment).
- Removed BRD §7 (content moved to architecture-overview + technical-design); renumbered §8–§12.

_Buyer story validation (39 → 43 → 59 stories total over the day)_
- Validated all buyer stories; fixed US-B-06 vs US-B-09 contradiction (skip-at-submit wins, not disabled CTA).
- US-B-01: email verification gates checkout (not browsing); OAuth accounts pre-verified.
- Added US-B-13 (password reset, 60-min TTL, no enumeration), US-B-14 (address book, 10-cap), US-B-15 (profile management).
- US-B-05: variant-level availability, B2B tier display, imported-rating tooltip.
- US-B-07: silent merge → toast; US-B-09: guest checkout deferred; US-B-11: no cancel in V1.

_Auth portals & diagram source files_
- Locked auth portal routes: buyer (`/login`, `/register`), seller (`/seller/login`, `/seller/register`), admin (`/admin/login` only). Seller + admin: email/password only, no OAuth.
- Dual-role confirmed: one account may hold BUYER + SELLER; ADMIN never co-held with either.
- ET-08: CC admin on every auto-flag. ET-21 added: admin KYC alert on submit/resubmit, `review_by` = submitted_at + 3 business days.
- US-A-00b: admin accounts seeded in DB (not docker-compose); hashed password in DB.
- Created `phase-1/diagrams/` — 6 Mermaid source files (01–06) with story refs + invariants; removed `flows.html`.
- Added Git conventions (one-line commits) to CLAUDE.md.

_BA revalidation (41 findings)_
- Full pass: 7 critical, 22 major, 12 minor. ERD criticals deferred to tech design.
- DIAG-01: email verification gate added to diagram 06-auth-portals (`email_verified` branch).
- README-01: added US-B-00, US-A-00b, US-P-17/18/19; total 54 → 59; sprint + dependency graph updated.
- Multi-role: `User.roles` is now an array; `SELLER_PENDING` removed in favour of `SellerProfile.kyc_status` gating.
- FX staleness: `staleness_threshold` aligned to 4 h (was 24 h) in implementation-specs.
- REAL-06 (US-B-09): second price-change rejection in plain behavior language.
- REAL-04 (US-P-17): concurrency-safety note on reservation expiry scheduler.
- REAL-09 (US-A-05): suspended-seller restriction rephrased as observable behavior; API guard spec added.

**Decisions:**
- Cart cleared only for placed fulfillments; skipped + failed items remain in cart.
- `Order.status` projected read model; `Order.placement_outcome` immutable checkout record.
- Email amounts use `fx_rate_used_at_capture`; templates stored as DB rows.
- Email verification gates checkout only — avoids hard friction at registration.
- Password reset: no-enumeration response pattern.
- OAuth-only buyer accounts must set local password (US-B-15) before accessing `/seller/register`.
- ERD structural corrections deferred to tech design phase.
- User stories stay behavior-only; implementation detail lives in implementation-specs.

**Next:**
- Begin Phase 1 technical design (`phase-1/technical-design/`).

---

<a id="2026-08-22"></a>
## 2026-08-22
**Focus:** Phase 1 technical-design kickoff.

**Done:**
- Added the project architecture overview, covering module boundaries, data ownership, event flows, deployment evolution, and Phase 1 scope boundaries.
- Marked the project architecture overview complete; detailed technical design continues within each phase.
- Aligned buyer-story UI criteria with the Buyer Portal mock without expanding the signed BRD scope.
- Added the Phase 1 ERD/data-model design for PostgreSQL module schemas, MongoDB audit/activity collections, order immutability, and outbox ownership.
- Clarified the V1 order lifecycle across buyer, seller, and platform stories: `PENDING → SHIPPED → DELIVERED`, with a full-refund transition from every post-payment status.

**Decisions:**
- V1 remains a NestJS modular monolith with PostgreSQL transaction/outbox ownership and Kafka integration seams.
- Later phases will extract domain modules into independently built and deployed Kubernetes services, moving to database-per-service incrementally.
- V1 backend will use a modular monorepo with module-owned code, contracts, schemas, migrations, and worker processes to preserve extraction seams.
- REST APIs will use a versioned OpenAPI contract generated from NestJS transport DTOs; Angular consumes an OpenAPI-generated TypeScript client.
- PostgreSQL 18+ uses native UUIDv7 identifiers for generated entities and events; audit timestamps remain explicit columns.
- Seller coupon-code promotions are deferred from Phase 1 and reserved for a future `promotion` module/schema with immutable order-redemption snapshots.
- Reusable buyer addresses are owned by Identity; Orders stores only an immutable checkout address snapshot.
- A tracking number is generated at order placement and retained at shipment; stock is restored only for a refund before shipment.

**Next:**
- Define OpenAPI endpoint contracts and Avro event/outbox details.

---

<a id="2026-08-19"></a>
## 2026-08-19
**Focus:** Requirements freeze + repo scaffolding for Phase 1.

**Done:**
- BRD v1.2 signed off (`phase-1/requirements/BRD.md`).
- User stories split by role into `phase-1/requirements/user-stories/` — 39 stories across buyer / seller / admin / platform, indexed by `README.md`.
- Linked Figma file "AliceUT" (`F69ukaWjsqx4adgo26vDFQ`) as authoritative design source; recorded in `CLAUDE.md` → *Design Reference*.
- Draft screens for "Buyer" in Figma

**Decisions:**
- Locked stack per BRD §7.1 / §13 — Angular + Angular Material, NestJS modular monolith, Postgres + Mongo, Elasticsearch, Kafka + Schema Registry, TypeORM w/ raw-SQL migrations, Passport.js + JWT, docker-compose V1 → K8s V2.
- V1 seller currencies restricted to USD / THB / JPY / SGD.
- Money storage `NUMERIC(19,4)` + ISO 4217; app-side `decimal.js`/`Big.js`; API amounts as strings.
- Pricing model: `Product → Offer → Price`; cart/order references `Offer`, never `Product`.
- Order line items snapshot `unit_price`, `currency`, `tax`, `fx_rate_used_at_capture` — never re-derive.
- All domain writes via Kafka **transactional outbox**; consumers idempotent, DLQ per group.

**Blockers:**
- None.

**Next:**
- Design UI and re-align with the user stories
- Kick off Phase 1 **technical design** in `phase-1/technical-design/` — architecture overview, ERD (Postgres + Mongo), API contracts, Kafka event schemas (Avro), outbox pattern doc.
- Backlog decomposition of the 39 user stories into implementation tasks.
- Confirm direction with user before writing any code.
