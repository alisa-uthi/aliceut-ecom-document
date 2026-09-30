# GitHub issue import

Turns a phase's `tasks.csv` into GitHub Issues on `aliceut-ecom-document` and links every one of them
to a GitHub Project (v2) board.

| File | Role |
|---|---|
| `phase-N/tasks.csv` | the seed, one per phase, beside that phase's requirements and design |
| `import-issues.sh` | the importer. `--phase N` reads `phase-N/tasks.csv` |
| `validate-tasks.sh` | checks a seed before import. Run it every time |
| `TEMPLATE.md` | the row contract, the Definition of Done blocks, and the procedure for a new phase |
| `tasks.template.csv` | starter to copy to `phase-N/tasks.csv` |

The issues are written for an **AI agent to pick up and implement**. Each one carries a goal line,
absolute links to the spec sections that govern it, its story and requirement traces, its
dependencies as real issue references, and a layer-appropriate Definition of Done. No issue restates
requirement text: when a spec changes the issue does not go stale, because it never held a copy.

## What this is not

`tasks.csv` is an **import seed**, not a backlog. Status, assignee and progress live only in GitHub
Issues and on the Project board — that is why `phase-1/backlog/` was deleted (c805aed) and why this
file has no status column. Do not add one.

## Prerequisites

- `gh` authenticated: `gh auth login`
- The `project` scope for board writes: `gh auth refresh -s project,read:project`
- `jq`
- A working `python` (only for `validate-tasks.sh`; the importer itself needs neither)
- The Project board created by hand (see below). The script never creates a project.

## Project board setup

Create the project in the GitHub UI, then add these **single-select** fields. Field and option names
are matched case-insensitively; a missing field or option is reported by name and skipped, and the
script exits `3` so a partial run is visible.

| Field | Type | Options |
|---|---|---|
| `Status` | single select | The script writes the first of `Todo`, `To do`, `Backlog`, `Ready` that the field actually has, so GitHub's stock board works unchanged. |
| `Layer` | single select | `backend`, `frontend`, `migration`, `infra` |
| `Module` | single select | `catalog`, `pricing`, `inventory`, `cart`, `orders`, `identity`, `seller`, `admin`, `search`, `notifications`, `platform`, `buyer-app`, `seller-app`, `admin-app`, `infra` |
| `Priority` | single select | `must`, `should`. On a stock board these sit alongside the template's `P0`–`P2`; the script only writes `must` / `should`. |

Sprint is a milestone, not a field. The script creates `Sprint 0` … `Sprint 5` if they are missing.

## Usage

```bash
cd scripts/github-issues

# always validate first
./validate-tasks.sh --phase 1

# then look
./import-issues.sh --repo alisa-uthi/aliceut-ecom-document \
  --project-owner alisa-uthi --project-number 1 --dry-run

# one sprint at a time is the sane way to start
./import-issues.sh --repo alisa-uthi/aliceut-ecom-document \
  --project-owner alisa-uthi --project-number 1 --only-sprint 0

# everything
./import-issues.sh --repo alisa-uthi/aliceut-ecom-document \
  --project-owner alisa-uthi --project-number 1
```

| Option | Effect |
|---|---|
| `--phase N` | which phase to import (default `1`), reading `phase-N/tasks.csv` |
| `--csv PATH` | explicit task file, overriding `--phase` |
| `--milestone-prefix S` | prepended to milestone titles. Use `"P2 "` for phase 2 so its sprints do not collide with phase 1's |
| `--ref BRANCH` | branch the spec links point at (default `main`) |
| `--only-sprint N` | import one sprint |
| `--only-layer L` | import one layer |
| `--limit N` | stop after N rows |
| `--no-project` | issues only, no board calls |
| `--dry-run` | print the plan, write nothing |

## Re-running

Safe and idempotent. Each issue body opens with `<!-- aliceut-task-id: <task_id> -->`; the script
reads every issue in the repo, maps markers to issue numbers, and **edits** rather than creates when
a marker already exists. Re-run after editing the CSV to push the change into the issues.

Three passes:

1. **Issues** — create or update title, body, labels, milestone.
2. **Dependencies** — rewrite the `Depends on` section of any issue whose dependency was created
   later in the same run, so the references become real `#numbers`.
3. **Board** — add each issue to the project and set `Status`, `Layer`, `Module`, `Priority`.

Labels are created if missing: `phase:N`, `layer:*`, `module:*`, `priority:must|should`, `sprint:0..5`.

## Troubleshooting

**`The single select option Id does not belong to the field`** — almost never means what it says.
Windows builds of `gh` and `jq` emit CRLF, so an id captured from their output can carry a trailing
`\r`, and the API rejects it with this message. Every id is now filtered to `[A-Za-z0-9_]` before it
is sent. If you touch that code, keep the filter.

**Inspecting what the script is about to do**

```bash
./import-issues.sh --repo … --print-body BE-US-S-03   # render one issue body, write nothing
DEBUG_FIELDS=1 ./import-issues.sh …                   # print the field/option ids per board write
```

`--limit N` applies to both the issue pass and the board pass, so `--limit 1` really is one issue.

## CSV format

Full contract, worked rows and the per-layer Definition of Done: **[TEMPLATE.md](TEMPLATE.md)**.
The short version - 12 fields, in this order:

```
task_id,layer,module,sprint,priority,title,goal,story_ids,fr_ids,spec_refs,depends_on,dod_extra
```

Hard rules, enforced by a preflight check that names the offending line:

- **No commas inside a field. No quoted fields.** Use `;` for every list.
- Exactly 12 fields per row.
- Lines starting with `#` are comments.

| Field | Meaning |
|---|---|
| `task_id` | stable key and the idempotency marker. `BE-*` backend, `FE-*` frontend, `DB-*` migration, `IN-*` infra. Never reuse or renumber one — that orphans its issue. |
| `layer` | `backend` \| `frontend` \| `migration` \| `infra`. Selects the Definition of Done and the baseline refs. |
| `module` | owning backend module, or the frontend app |
| `sprint` | `0`–`5`, per `phase-1/requirements/user-stories/README.md` § Story Sequencing |
| `priority` | `must` \| `should`, from the BRD |
| `title` | issue title, already prefixed `[BE]` / `[FE]` / `[DB]` / `[IN]` |
| `goal` | one sentence, no trailing period, no commas |
| `story_ids` | `US-*` ids, `;` separated |
| `fr_ids` | `FR-*` / `NFR-*` ids, `;` separated |
| `spec_refs` | the refs specific to this task, `;` separated, using the aliases below |
| `depends_on` | `task_id`s, `;` separated |
| `dod_extra` | extra Definition of Done lines beyond the layer defaults, `;` separated |

### spec_refs aliases

Expanded by the script into absolute `https://github.com/<repo>/blob/<ref>/<path>` links, so the
links work inside an issue body (relative paths do not).

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

Anchors are kept: `api/seller.md#create-offer`.

### Refs you do not list

The script appends these per layer, so the CSV only carries what is specific to the task:

- always: `BRD.md`, `guidelines/testing-guidelines.md`
- backend: `conventions/backend-coding-standards.md`, `conventions/backend-module-architecture.md`, `conventions/api-conventions.md`, `phase-1/technical-design/backend-module-architecture.md`
- frontend: `conventions/frontend-coding-standards.md`, `conventions/design-system.md`, `phase-1/ui-design/shared-components.md`, `phase-1/ui-design/navigation-routing.md`
- migration: `conventions/database-migrations.md`, `phase-1/technical-design/data-model-erd.md`
- infra: `guidelines/development-flow.md`

## Adding or changing a task

1. Edit `phase-N/tasks.csv`. Keep `task_id` stable; a new task gets a new id.
2. `./validate-tasks.sh --phase N`, then `--dry-run`.
3. Re-run for real. Existing issues are updated in place; the new one is created.

If a task turns out to be wrong, close its issue in GitHub and delete its CSV row. Do not silently
repurpose an existing `task_id`.
