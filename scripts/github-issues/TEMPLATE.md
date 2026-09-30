# Task template — decomposing a phase into GitHub Issues

The contract every `phase-N/tasks.csv` follows, and the procedure that produced Phase 1's. Follow it
and the next phase's issues come out shaped like this one's.

- **Seed file:** `phase-N/tasks.csv` — one per phase, beside that phase's requirements and design.
- **Importer:** `scripts/github-issues/import-issues.sh` — phase-agnostic, `--phase N`.
- **Starter:** copy `scripts/github-issues/tasks.template.csv` to `phase-N/tasks.csv`.
- **Validator:** `scripts/github-issues/validate-tasks.sh --phase N` — run it before every import.

The script is the **executable** definition of the issue body, the per-layer Definition of Done and
the baseline spec references. This document describes them; if the two ever disagree, the script is
right and this file needs fixing.

## Not a backlog

`tasks.csv` has no status, assignee, estimate or progress column, and never gets one. Status lives in
GitHub Issues and on the Project board. A status column here recreates `phase-1/backlog/`, which was
deleted on 2026-09-19 (c805aed) for exactly that reason.

## Procedure for a new phase

1. **Read the phase's sources of truth first** — `phase-N/requirements/BRD.md` (or its equivalent),
   `phase-N/requirements/user-stories/README.md`, the technical-design module inventory, the
   ui-design screen lists, the ERD schema map. The decomposition is a *projection* of those
   documents, so it cannot be written without them.
2. **Take the story list as the spine.** Every `US-*` story becomes one row per layer it touches.
   Do not invent new units of work where a story already exists.
3. **Add the work that is not a story.** Scaffolding, CI, migrations, brokers, buckets, indexes,
   seeds, test harness, design-system setup. These become `infra` and `migration` rows. Phase 1 had
   18 infra and 13 migration rows against 60 stories.
4. **Split each story by layer**, emitting a row only for layers that story actually needs. A
   consumer-only story has no `frontend` row; a pure screen has no `migration` row.
5. **Assign sprints** from the phase's own sequencing section (Phase 1: `user-stories/README.md`
   § Story Sequencing). Do not invent a different order.
6. **Wire dependencies** — the minimum that expresses real blocking, not every transitive edge.
7. **Validate**: `./validate-tasks.sh --phase N`. It must report zero problems.
8. **Dry run**: `./import-issues.sh --repo … --phase N --dry-run`.
9. **Import one sprint**, check the rendered bodies and board fields, then import the rest.

## Row contract

12 comma-separated fields. **No embedded commas. No quoted fields.** Lists use `;`. Lines starting
with `#` are comments. The importer's preflight rejects the file and names the offending line.

```
task_id,layer,module,sprint,priority,title,goal,story_ids,fr_ids,spec_refs,depends_on,dod_extra
```

| Field | Rule |
|---|---|
| `task_id` | `BE-` backend, `FE-` frontend, `DB-` migration, `IN-` infra. Prefer `<PREFIX>-<STORY-ID>` (`BE-US-B-02`); use a descriptive slug only when no single story owns the work (`BE-BLOCKLIST-01`, `DB-07`). **Stable forever** — it is the idempotency marker, so renaming one orphans its issue. |
| `layer` | `backend` \| `frontend` \| `migration` \| `infra`. Selects the DoD block and the baseline refs. |
| `module` | The owning backend module lib, or the frontend app (`buyer-app`, `seller-app`, `admin-app`), or `infra`. One owner per row — if two modules are involved, the row belongs to whichever one the route or screen lives in. |
| `sprint` | Integer, from the phase's sequencing section. |
| `priority` | `must` \| `should`, copied from the requirement — not re-judged here. |
| `title` | `[BE]` / `[FE]` / `[DB]` / `[IN]` then a short imperative phrase. No commas. |
| `goal` | One sentence, no trailing period, no commas. What the task delivers, not how. |
| `story_ids` | `US-*` ids this row implements, `;` separated. Empty for pure infra. |
| `fr_ids` | `FR-*` / `NFR-*` ids, `;` separated. |
| `spec_refs` | The refs **specific to this row**, `;` separated, using the aliases below. Deep-link to the section, not just the file. |
| `depends_on` | `task_id`s that must land first, `;` separated. Direct blockers only. |
| `dod_extra` | Acceptance points beyond the layer defaults, `;` separated. Written as fragments; the script capitalizes each and adds a period. |

### spec_refs aliases

| Alias | Expands to |
|---|---|
| `brd` | `phase-1/requirements/BRD.md` |
| `us/<f>` | `phase-1/requirements/user-stories/<f>` |
| `td/<f>` | `phase-1/technical-design/<f>` |
| `api/<f>` | `phase-1/technical-design/api-design/<f>` |
| `ui/<f>` | `phase-1/ui-design/<f>` |
| `cv/<f>` | `conventions/<f>` |
| `gl/<f>` | `guidelines/<f>` |
| `dg/<f>` | `phase-1/diagrams/<f>` |

Anchors are preserved and expected: `api/seller.md#create-offer`, `td/data-model-erd.md#schema-catalog`,
`us/buyer.md#us-b-02--search-products-by-keyword`. Note GitHub's slug rules — ` — ` collapses to
`--`, and `/`, `+` and backticks are dropped, so `## Screen 6 — Create / Edit Product` is
`#screen-6--create--edit-product`. The validator checks every anchor against the real heading, so a
guess that is wrong gets caught before import.

**Aliases are currently phase-1-rooted.** A second phase needs the `expand_ref` case block in
`import-issues.sh` taught its own prefixes (or made `--phase`-aware). That is the one change a new
phase demands in the script.

### Refs you must NOT list

The importer appends these itself; repeating them in the CSV is noise:

- every row: `BRD.md`, `guidelines/testing-guidelines.md`
- `backend`: `conventions/backend-coding-standards.md`, `conventions/backend-module-architecture.md`, `conventions/api-conventions.md`, `phase-1/technical-design/backend-module-architecture.md`
- `frontend`: `conventions/frontend-coding-standards.md`, `conventions/design-system.md`, `phase-1/ui-design/shared-components.md`, `phase-1/ui-design/navigation-routing.md`
- `migration`: `conventions/database-migrations.md`, `phase-1/technical-design/data-model-erd.md`
- `infra`: `guidelines/development-flow.md`

## Issue body anatomy

What the importer emits, in order. Inspect any row's output with
`./import-issues.sh --repo … --print-body <task_id>`.

```
<!-- aliceut-task-id: <task_id> -->      marker the importer matches on - never edit by hand
**Goal:** <goal>.
`<layer>` · module `<module>` · Sprint <n> · <priority>

## Read first                            spec_refs + baseline refs, as absolute blob links
## Traces                                story ids, requirement ids
## Depends on                            resolved to real #numbers
## Definition of Done                    layer block, then dod_extra
```

**No requirement text is ever copied into a body.** That is the whole point: a spec edit cannot
strand an issue, because the issue only ever held a link. Change a task by editing the CSV and
re-running the importer — not by editing the issue.

## Definition of Done blocks

Emitted verbatim per layer. First and last lines are common to every layer.

```
- [ ] Behaviour matches the linked specs. Any divergence amends the spec in the same PR.
```

**backend**
```
- [ ] Routes and handlers match the linked api-design section exactly: path, status codes, error envelope.
- [ ] DTO validation via class-validator on every input (FR-P-08).
- [ ] Module writes only its own Postgres schema. Cross-module work goes through the owner's exported ApplicationService.
- [ ] Every domain state change writes its outbox row in the same transaction (FR-P-09).
- [ ] Monetary values are Decimal end to end, serialized as strings. No JS `number` (FR-P-04).
- [ ] Unit and integration tests per guidelines/testing-guidelines.md.
```

**frontend**
```
- [ ] Screen matches the linked ui-design section: layout, states, mobile breakpoints, accessibility notes.
- [ ] Consumes the generated API client. No hand-written request or response types.
- [ ] Angular Material plus design-system tokens only. No hardcoded colour or spacing.
- [ ] Loading, empty and error states implemented.
- [ ] Money rendered from string amounts. No float arithmetic.
- [ ] Component and accessibility tests per guidelines/testing-guidelines.md.
```

**migration**
```
- [ ] Raw SQL up and down. No decorator schema sync.
- [ ] Column types match the ERD exactly: NUMERIC(19,4) amounts, NUMERIC(19,8) FX rates.
- [ ] Indexes, unique constraints and enum types from the ERD are present.
- [ ] Applies and reverts cleanly on a fresh database.
```

**infra**
```
- [ ] Configuration comes from env vars only. No secret in tracked source (FR-P-07).
- [ ] Verified by running it locally per guidelines/development-flow.md.
- [ ] The spec is amended in the same PR if reality had to diverge from it.
```

```
- [ ] Pre-merge checklist green (guidelines/development-flow.md, Pre-merge checklist).
```

## Labels and milestones

Created by the importer if absent, so nothing to prepare by hand:

- `phase:<N>`, `layer:<layer>`, `module:<module>`, `priority:<must|should>`, `sprint:<n>`
- milestones `Sprint 0` … `Sprint N`, or `<prefix>Sprint n` with `--milestone-prefix`. **Use a prefix
  for phase 2** (`--milestone-prefix "P2 "`), or its sprints collide with Phase 1's.

## Project board

Four single-select fields, matched case-insensitively. A missing field or option is reported by name,
skipped, and the run exits `3`.

| Field | Options |
|---|---|
| `Status` | the importer writes the first of `Todo`, `To do`, `Backlog`, `Ready` that exists |
| `Layer` | `backend`, `frontend`, `migration`, `infra` |
| `Module` | every `module` value used in the CSV |
| `Priority` | `must`, `should` |

## Worked rows

```csv
BE-US-B-02,backend,search,1,must,[BE] Product search endpoint,Implement keyword search over the products index with the documented response shape,US-B-02,FR-B-02;NFR-02,us/buyer.md#us-b-02--search-products-by-keyword;api/search.md#product-search,IN-12,Relevance and pagination match the contract;suspended and flagged offers are absent
FE-US-B-05,frontend,buyer-app,1,must,[FE] Product detail page,Build the PDP with gallery and variant selector and effective price and seller block,US-B-05,FR-B-05;FR-P-01,ui/buyer-portal.md#screen-3--product-detail-page-pdp,FE-BUYER-SHELL;BE-US-B-05,Variant derivation and effective price rules match the spec;out-of-stock state handled
DB-04,migration,pricing,1,must,[DB] pricing schema,Create currency and offer_price and fx_rate with the currency reference rows,US-P-01;US-P-04,FR-P-01;FR-P-04,td/data-model-erd.md#schema-pricing;td/data-model-erd.md#table-pricing-fx-rate,DB-01,Amounts are NUMERIC(19 4) and FX rates NUMERIC(19 8);currency rows carry minor_unit_scale
IN-03,infra,platform,0,must,[IN] Compose topology in aliceut-ecom-infra,Stand up docker-compose with every service and healthcheck and bind mount described in the topology spec,,NFR-16,td/docker-compose-topology.md;gl/development-flow.md,,Every container reports healthy;bind mounts resolve from the infra repo root
```

Note `NUMERIC(19 4)` — the space is deliberate, because a comma would break the row. Write values
that way rather than reaching for quoting, which the parser rejects.

## Phase 1 shape, for calibration

136 rows from 60 stories: 61 backend, 44 frontend, 13 migration, 18 infra. Sprint 0: 21, 1: 23,
2: 19, 3: 19, 4: 28, 5: 26. Migration rows are one per Postgres schema, plus enum types, plus
cross-schema constraints, plus retention indexes.
