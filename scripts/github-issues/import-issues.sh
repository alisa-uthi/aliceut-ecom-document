#!/usr/bin/env bash
# Import a phase's tasks.csv into GitHub Issues and link them to a GitHub Project (v2).
#
# The CSV is an import seed only. Status lives in GitHub, never in the CSV.
# Re-runnable: issues are matched by the hidden marker "aliceut-task-id: <task_id>" in the body
# and updated in place, so a second run never creates duplicates.
#
# Usage:
#   ./import-issues.sh --repo OWNER/REPO --project-owner OWNER --project-number N [options]
#
# Options:
#   --phase N           which phase to import (default: 1) - reads phase-N/tasks.csv
#   --csv PATH          explicit task CSV, overriding --phase
#   --milestone-prefix S  prepended to the milestone title (default: empty, so "Sprint 3")
#   --ref BRANCH        branch spec links point at (default: main)
#   --only-sprint N     import a single sprint
#   --only-layer L      import a single layer (backend|frontend|migration|infra)
#   --limit N           stop after N rows
#   --no-project        create/update issues only, skip all Project v2 calls
#   --dry-run           print what would happen, call no mutating API
#   --print-body ID     render one task's issue body to stdout and exit
#   -h | --help
#
# Requires: gh (authenticated, with the `project` scope for Project v2 writes), jq.

set -euo pipefail

# ---------------------------------------------------------------------------
# args
# ---------------------------------------------------------------------------
REPO=""
PROJECT_OWNER=""
PROJECT_NUMBER=""
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE="1"
CSV=""
MILESTONE_PREFIX=""
REF="main"
ONLY_SPRINT=""
ONLY_LAYER=""
LIMIT=0
NO_PROJECT=0
DRY_RUN=0
PRINT_BODY=""

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }

usage() { sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --project-owner) PROJECT_OWNER="${2:-}"; shift 2 ;;
    --project-number) PROJECT_NUMBER="${2:-}"; shift 2 ;;
    --phase) PHASE="${2:-}"; shift 2 ;;
    --csv) CSV="${2:-}"; shift 2 ;;
    --milestone-prefix) MILESTONE_PREFIX="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --only-sprint) ONLY_SPRINT="${2:-}"; shift 2 ;;
    --only-layer) ONLY_LAYER="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --no-project) NO_PROJECT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --print-body) PRINT_BODY="${2:-}"; NO_PROJECT=1; DRY_RUN=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[[ "$PHASE" =~ ^[0-9]+$ ]] || die "--phase must be a number"
[[ -n "$CSV" ]] || CSV="$REPO_ROOT/phase-$PHASE/tasks.csv"

[[ -n "$REPO" ]] || die "--repo OWNER/REPO is required"
[[ "$REPO" == */* ]] || die "--repo must be OWNER/REPO"
[[ -f "$CSV" ]] || die "csv not found: $CSV"
if [[ $NO_PROJECT -eq 0 ]]; then
  [[ -n "$PROJECT_OWNER" && -n "$PROJECT_NUMBER" ]] || \
    die "--project-owner and --project-number are required (or pass --no-project)"
fi

REPO_OWNER="${REPO%%/*}"
BLOB_BASE="https://github.com/${REPO}/blob/${REF}"

TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
command -v gh >/dev/null 2>&1 || die "gh CLI not found"
command -v jq >/dev/null 2>&1 || die "jq not found"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
gh repo view "$REPO" --json name >/dev/null 2>&1 || die "cannot see repo $REPO"

if [[ $NO_PROJECT -eq 0 ]] && ! gh auth status 2>&1 | grep -q "project"; then
  warn "gh token may lack the 'project' scope. If pass 3 fails, run: gh auth refresh -s project,read:project"
fi

FIELD_COUNT=12

# Windows builds of gh and jq emit CRLF, and a stray CR inside an id makes the API
# reject it with a misleading error. Strip it in bash, not with an external tool.
CR=$''
nocr() { local v="$1"; printf '%s' "${v//$CR/}"; }

# CSV shape check: no quoted fields, no embedded commas, exactly FIELD_COUNT fields.
lineno=0
bad=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  lineno=$((lineno + 1))
  [[ -z "${raw//[[:space:]]/}" ]] && continue
  [[ "${raw:0:1}" == "#" ]] && continue
  case "$raw" in task_id,*) continue ;; esac
  if [[ "$raw" == *'"'* ]]; then
    warn "line $lineno: quoted fields are not supported"; bad=1; continue
  fi
  n=$(( $(printf '%s' "$raw" | tr -cd ',' | wc -c) + 1 ))
  if [[ "$n" -ne "$FIELD_COUNT" ]]; then
    warn "line $lineno: $n fields, expected $FIELD_COUNT (commas inside a field? use ';' for lists)"
    bad=1
  fi
done < "$CSV"
[[ $bad -eq 0 ]] || die "csv shape check failed"

# ---------------------------------------------------------------------------
# spec-ref alias expansion
# ---------------------------------------------------------------------------
expand_ref() {
  local r="$1"
  case "$r" in
    brd|brd#*)  printf 'phase-1/requirements/BRD.md%s' "${r#brd}" ;;
    us/*)       printf 'phase-1/requirements/user-stories/%s' "${r#us/}" ;;
    td/*)       printf 'phase-1/technical-design/%s' "${r#td/}" ;;
    api/*)      printf 'phase-1/technical-design/api-design/%s' "${r#api/}" ;;
    ui/*)       printf 'phase-1/ui-design/%s' "${r#ui/}" ;;
    cv/*)       printf 'conventions/%s' "${r#cv/}" ;;
    gl/*)       printf 'guidelines/%s' "${r#gl/}" ;;
    dg/*)       printf 'phase-1/diagrams/%s' "${r#dg/}" ;;
    *)          printf '%s' "$r" ;;
  esac
}

ref_link() {           # ref_link <alias> -> markdown bullet with an absolute blob URL
  local path; path="$(expand_ref "$1")"
  printf -- '- [%s](%s/%s)\n' "$path" "$BLOB_BASE" "$path"
}

baseline_refs() {      # layer -> the refs every issue of that layer carries
  case "$1" in
    backend)   printf '%s\n' cv/backend-coding-standards.md cv/backend-module-architecture.md \
                              cv/api-conventions.md td/backend-module-architecture.md ;;
    frontend)  printf '%s\n' cv/frontend-coding-standards.md cv/design-system.md \
                              ui/shared-components.md ui/navigation-routing.md ;;
    migration) printf '%s\n' cv/database-migrations.md td/data-model-erd.md ;;
    infra)     printf '%s\n' gl/development-flow.md ;;
  esac
}

dod_for_layer() {
  cat <<'EOF'
- [ ] Behaviour matches the linked specs. Any divergence amends the spec in the same PR.
EOF
  case "$1" in
    backend) cat <<'EOF'
- [ ] Routes and handlers match the linked api-design section exactly: path, status codes, error envelope.
- [ ] DTO validation via class-validator on every input (FR-P-08).
- [ ] Module writes only its own Postgres schema. Cross-module work goes through the owner's exported ApplicationService.
- [ ] Every domain state change writes its outbox row in the same transaction (FR-P-09).
- [ ] Monetary values are Decimal end to end, serialized as strings. No JS `number` (FR-P-04).
- [ ] Unit and integration tests per guidelines/testing-guidelines.md.
EOF
;;
    frontend) cat <<'EOF'
- [ ] Screen matches the linked ui-design section: layout, states, mobile breakpoints, accessibility notes.
- [ ] Consumes the generated API client. No hand-written request or response types.
- [ ] Angular Material plus design-system tokens only. No hardcoded colour or spacing.
- [ ] Loading, empty and error states implemented.
- [ ] Money rendered from string amounts. No float arithmetic.
- [ ] Component and accessibility tests per guidelines/testing-guidelines.md.
EOF
;;
    migration) cat <<'EOF'
- [ ] Raw SQL up and down. No decorator schema sync.
- [ ] Column types match the ERD exactly: NUMERIC(19,4) amounts, NUMERIC(19,8) FX rates.
- [ ] Indexes, unique constraints and enum types from the ERD are present.
- [ ] Applies and reverts cleanly on a fresh database.
EOF
;;
    infra) cat <<'EOF'
- [ ] Configuration comes from env vars only. No secret in tracked source (FR-P-07).
- [ ] Verified by running it locally per guidelines/development-flow.md.
- [ ] The spec is amended in the same PR if reality had to diverge from it.
EOF
;;
  esac
  printf -- '- [ ] Pre-merge checklist green (guidelines/development-flow.md, Pre-merge checklist).\n'
}

# ---------------------------------------------------------------------------
# labels
# ---------------------------------------------------------------------------
ensure_label() {
  local name="$1" color="$2" desc="$3"
  grep -Fxq "$name" "$TMPDIR_RUN/labels" && return 0
  if [[ $DRY_RUN -eq 1 ]]; then info "  would create label: $name"; else
    gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" >/dev/null 2>&1 \
      || warn "could not create label $name"
  fi
  printf '%s\n' "$name" >> "$TMPDIR_RUN/labels"
}

gh label list --repo "$REPO" --limit 300 --json name -q '.[].name' 2>/dev/null > "$TMPDIR_RUN/labels" || : > "$TMPDIR_RUN/labels"

# ---------------------------------------------------------------------------
# milestones
# ---------------------------------------------------------------------------
declare -A MILESTONE_SEEN=()
while IFS= read -r t; do [[ -n "$t" ]] && MILESTONE_SEEN["$t"]=1; done < <(
  gh api "repos/$REPO/milestones?state=all&per_page=100" -q '.[].title' 2>/dev/null || true
)

ensure_milestone() {
  local title="$1"
  [[ -n "${MILESTONE_SEEN[$title]:-}" ]] && return 0
  if [[ $DRY_RUN -eq 1 ]]; then
    info "  would create milestone: $title"
  else
    gh api --method POST "repos/$REPO/milestones" \
      -f title="$title" \
      -f description="Phase 1 sequencing per phase-1/requirements/user-stories/README.md" \
      >/dev/null 2>&1 || warn "could not create milestone $title"
  fi
  MILESTONE_SEEN["$title"]=1
}

# ---------------------------------------------------------------------------
# existing issues -> task_id map
# ---------------------------------------------------------------------------
declare -A ISSUE_OF=()
while IFS=$'\t' read -r num tid; do
  [[ -n "$tid" ]] && ISSUE_OF["$tid"]="$num"
done < <(
  gh issue list --repo "$REPO" --state all --limit 1000 --json number,body \
    -q '.[] | select(.body != null) | [.number, (.body | capture("aliceut-task-id: (?<t>[A-Za-z0-9_.-]+)").t // empty)] | @tsv' \
    2>/dev/null || true
)
info "found ${#ISSUE_OF[@]} existing imported issue(s) in $REPO"

# ---------------------------------------------------------------------------
# project v2 resolution
# ---------------------------------------------------------------------------
PROJECT_ID=""
declare -A FIELD_ID=()        # field name (lowercase) -> field node id
declare -A OPTION_ID=()       # "<field lc>|<option lc>" -> option id
PROJECT_WARN=0

resolve_project() {
  local q='query($login:String!,$number:Int!){
    user(login:$login){ projectV2(number:$number){ id title
      fields(first:50){ nodes{
        __typename
        ... on ProjectV2FieldCommon { id name }
        ... on ProjectV2SingleSelectField { id name options { id name } } } } } }
    organization(login:$login){ projectV2(number:$number){ id title
      fields(first:50){ nodes{
        __typename
        ... on ProjectV2FieldCommon { id name }
        ... on ProjectV2SingleSelectField { id name options { id name } } } } } } }'
  local out
  out="$(gh api graphql -f query="$q" -f login="$PROJECT_OWNER" -F number="$PROJECT_NUMBER" 2>/dev/null || true)"
  [[ -n "$out" ]] || die "GraphQL call failed. Check the 'project' scope: gh auth refresh -s project,read:project"
  local node
  node="$(jq -c '.data.user.projectV2 // .data.organization.projectV2 // empty' <<<"$out")"
  [[ -n "$node" && "$node" != "null" ]] || die "project #$PROJECT_NUMBER not found for owner $PROJECT_OWNER (create it first, then re-run)"

  PROJECT_ID="$(nocr "$(jq -r '.id' <<<"$node")")"
  info "project: $(jq -r '.title' <<<"$node") ($PROJECT_ID)"

  while IFS=$'\t' read -r fname fid; do
    FIELD_ID["$(nocr "$(tr '[:upper:]' '[:lower:]' <<<"$fname")")"]="$(nocr "$fid")"
  done < <(jq -r '.fields.nodes[] | select(.name != null) | [.name, .id] | @tsv' <<<"$node")

  while IFS=$'\t' read -r fname oname oid; do
    OPTION_ID["$(nocr "$(tr '[:upper:]' '[:lower:]' <<<"$fname")")|$(nocr "$(tr '[:upper:]' '[:lower:]' <<<"$oname")")"]="$(nocr "$oid")"
  done < <(jq -r '.fields.nodes[] | select(.options != null) | .name as $f | .options[] | [$f, .name, .id] | @tsv' <<<"$node")

  for f in status layer module priority; do
    [[ -n "${FIELD_ID[$f]:-}" ]] || { warn "project has no field named '$f' - values for it will be skipped"; PROJECT_WARN=1; }
  done
}

project_add_item() {   # project_add_item <issue node id> -> item id
  nocr "$(gh api graphql -f query='mutation($p:ID!,$c:ID!){ addProjectV2ItemById(input:{projectId:$p,contentId:$c}){ item { id } } }' \
    -f p="$PROJECT_ID" -f c="$1" -q '.data.addProjectV2ItemById.item.id' 2>/dev/null || true)"
}

project_set_status() {  # first Status option that exists among the usual "not started" names
  local item="$1" candidate
  for candidate in Todo "To do" Backlog Ready; do
    if [[ -n "${OPTION_ID[status|$(nocr "$(tr '[:upper:]' '[:lower:]' <<<"$candidate")")]:-}" ]]; then
      project_set_select "$item" Status "$candidate"
      return 0
    fi
  done
  warn "Status field has none of: Todo / To do / Backlog / Ready - leaving it unset"
  PROJECT_WARN=1
}

project_set_select() { # project_set_select <item id> <field name> <option name>
  local item="$1" field="$2" value="$3"
  local fkey; fkey="$(tr '[:upper:]' '[:lower:]' <<<"$field")"
  fkey="${fkey//[^a-z0-9_-]/}"
  local fid="${FIELD_ID[$fkey]:-}"
  [[ -n "$fid" ]] || return 0
  local vkey; vkey="$(tr '[:upper:]' '[:lower:]' <<<"$value")"
  vkey="${vkey//[^a-z0-9_ -]/}"
  local oid="${OPTION_ID[$fkey|$vkey]:-}"
  if [[ -z "$oid" ]]; then
    warn "field '$field' has no option '$value' - add it on the board, then re-run"
    PROJECT_WARN=1
    return 0
  fi
  # gh and jq on Windows emit CRLF; a stray CR in an id makes the API reject it with a
  # misleading "option Id does not belong to the field". These ids are [A-Za-z0-9_-] only.
  item="${item//[^A-Za-z0-9_-]/}"
  fid="${fid//[^A-Za-z0-9_-]/}"
  oid="${oid//[^A-Za-z0-9_-]/}"
  local pid="${PROJECT_ID//[^A-Za-z0-9_-]/}"
  local err attempt
  [[ -n "${DEBUG_FIELDS:-}" ]] && \
    printf 'DBG %s=%s fid=[%s] oid=[%s] item=[%s]\n' "$field" "$value" "$fid" "$oid" "$item" >&2
  # A just-added project item rejects field writes for a moment, and reports it as
  # "The single select option Id does not belong to the field". Retry through that window.
  for attempt in 1 2 3; do
    if err="$(gh api graphql -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){
        updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){ projectV2Item { id } } }'       -f p="$pid" -f i="$item" -f f="$fid" -f o="$oid" 2>&1 >/dev/null)"; then
      return 0
    fi
    sleep "$attempt"
  done
  warn "could not set $field=$value on item $item: ${err:-unknown error}"
  PROJECT_WARN=1
}

if [[ $NO_PROJECT -eq 0 && $DRY_RUN -eq 0 ]]; then
  resolve_project
elif [[ $NO_PROJECT -eq 0 ]]; then
  info "dry run: skipping project resolution"
fi

# ---------------------------------------------------------------------------
# body rendering
# ---------------------------------------------------------------------------
render_deps() {         # render_deps <depends_on> ; sets DEPS_UNRESOLVED
  local deps="$1"
  DEPS_UNRESOLVED=0
  [[ -z "$deps" ]] && { printf '_None._\n'; return; }
  local d
  IFS=';' read -ra arr <<<"$deps"
  for d in "${arr[@]}"; do
    [[ -z "$d" ]] && continue
    if [[ -n "${ISSUE_OF[$d]:-}" ]]; then
      printf -- '- #%s (`%s`)\n' "${ISSUE_OF[$d]}" "$d"
    else
      printf -- '- `%s` (issue not created yet)\n' "$d"
      DEPS_UNRESOLVED=1
    fi
  done
}

render_body() {         # render_body <all 12 fields...> -> body on stdout
  local task_id="$1" layer="$2" module="$3" sprint="$4" priority="$5" title="$6" goal="$7" \
        story_ids="$8" fr_ids="$9" spec_refs="${10}" depends_on="${11}" dod_extra="${12}"

  printf '<!-- aliceut-task-id: %s -->\n' "$task_id"
  printf '<!-- generated by scripts/github-issues/import-issues.sh from scripts/github-issues/tasks.csv - edit the CSV, not this block -->\n\n'
  printf '**Goal:** %s.\n\n' "$goal"
  printf '`%s` · module `%s` · Sprint %s · %s\n\n' "$layer" "$module" "$sprint" "$priority"

  printf '## Read first\n\n'
  printf 'The linked documents are the source of truth. This issue deliberately does not restate them; if they change, they win.\n\n'
  local r
  if [[ -n "$spec_refs" ]]; then
    IFS=';' read -ra refs <<<"$spec_refs"
    for r in "${refs[@]}"; do [[ -n "$r" ]] && ref_link "$r"; done
  fi
  while IFS= read -r r; do [[ -n "$r" ]] && ref_link "$r"; done < <(baseline_refs "$layer")
  ref_link "brd"
  ref_link "gl/testing-guidelines.md"
  printf '\n'

  printf '## Traces\n\n'
  printf 'Stories: %s\n' "${story_ids//;/, }"
  printf 'Requirements: %s\n\n' "${fr_ids//;/, }"

  printf '## Depends on\n\n'
  render_deps "$depends_on"
  printf '\n'

  printf '## Definition of Done\n\n'
  dod_for_layer "$layer"
  if [[ -n "$dod_extra" ]]; then
    IFS=';' read -ra extra <<<"$dod_extra"
    for r in "${extra[@]}"; do
      [[ -n "$r" ]] || continue
      printf -- '- [ ] %s%s.\n' "$(tr '[:lower:]' '[:upper:]' <<<"${r:0:1}")" "${r:1}"
    done
  fi
}

# ---------------------------------------------------------------------------
# pass 1 - create or update
# ---------------------------------------------------------------------------
declare -a ROWS=()
while IFS= read -r raw || [[ -n "$raw" ]]; do
  [[ -z "${raw//[[:space:]]/}" ]] && continue
  [[ "${raw:0:1}" == "#" ]] && continue
  case "$raw" in task_id,*) continue ;; esac
  ROWS+=("$raw")
done < "$CSV"

if [[ -n "$PRINT_BODY" ]]; then
  for raw in "${ROWS[@]}"; do
    IFS=',' read -r task_id layer module sprint priority title goal story_ids fr_ids spec_refs depends_on dod_extra <<<"$raw"
    [[ "$task_id" == "$PRINT_BODY" ]] || continue
    printf 'TITLE: %s\n' "$title"
    printf 'LABELS: layer:%s module:%s priority:%s sprint:%s\n' "$layer" "$module" "$priority" "$sprint"
    printf 'MILESTONE: Sprint %s\n\n' "$sprint"
    render_body "$task_id" "$layer" "$module" "$sprint" "$priority" "$title" "$goal" \
                "$story_ids" "$fr_ids" "$spec_refs" "$depends_on" "$dod_extra"
    exit 0
  done
  die "task_id not found in csv: $PRINT_BODY"
fi

CREATED=0; UPDATED=0; SKIPPED=0; PROCESSED=0
declare -a REPASS=()

info ""
info "pass 1 - issues"
for raw in "${ROWS[@]}"; do
  IFS=',' read -r task_id layer module sprint priority title goal story_ids fr_ids spec_refs depends_on dod_extra <<<"$raw"

  [[ -n "$ONLY_SPRINT" && "$sprint" != "$ONLY_SPRINT" ]] && { SKIPPED=$((SKIPPED+1)); continue; }
  [[ -n "$ONLY_LAYER"  && "$layer"  != "$ONLY_LAYER"  ]] && { SKIPPED=$((SKIPPED+1)); continue; }
  [[ "$LIMIT" -gt 0 && "$PROCESSED" -ge "$LIMIT" ]] && break
  PROCESSED=$((PROCESSED+1))

  milestone="${MILESTONE_PREFIX}Sprint $sprint"
  ensure_milestone "$milestone"
  ensure_label "phase:$PHASE"       "0e8a16" "Delivery phase"
  ensure_label "layer:$layer"       "1d76db" "Delivery layer"
  ensure_label "module:$module"     "c5def5" "Owning module or app"
  ensure_label "priority:$priority" "$([[ "$priority" == "must" ]] && echo d73a4a || echo fbca04)" "BRD priority"
  ensure_label "sprint:$sprint"     "5319e7" "Phase 1 sprint"

  body_file="$TMPDIR_RUN/$task_id.md"
  render_body "$task_id" "$layer" "$module" "$sprint" "$priority" "$title" "$goal" \
              "$story_ids" "$fr_ids" "$spec_refs" "$depends_on" "$dod_extra" > "$body_file"
  [[ "$DEPS_UNRESOLVED" -eq 1 ]] && REPASS+=("$raw")

  labels=(--label "phase:$PHASE" --label "layer:$layer" --label "module:$module" --label "priority:$priority" --label "sprint:$sprint")

  if [[ -n "${ISSUE_OF[$task_id]:-}" ]]; then
    num="${ISSUE_OF[$task_id]}"
    if [[ $DRY_RUN -eq 1 ]]; then
      info "  [update] #$num $task_id"
    else
      gh issue edit "$num" --repo "$REPO" --title "$title" --body-file "$body_file" \
        --milestone "$milestone" "${labels[@]/--label/--add-label}" >/dev/null \
        || warn "could not update #$num ($task_id)"
      info "  [update] #$num $task_id"
    fi
    UPDATED=$((UPDATED+1))
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      info "  [create] $task_id  $title"
      ISSUE_OF["$task_id"]="?"
    else
      url="$(gh issue create --repo "$REPO" --title "$title" --body-file "$body_file" \
              --milestone "$milestone" "${labels[@]}")" \
        || die "could not create issue for $task_id"
      num="$(tr -cd '0-9' <<<"${url##*/}")"
      ISSUE_OF["$task_id"]="$num"
      info "  [create] #$num $task_id"
    fi
    CREATED=$((CREATED+1))
  fi
done

# ---------------------------------------------------------------------------
# pass 2 - resolve dependency references that were unknown during pass 1
# ---------------------------------------------------------------------------
if [[ ${#REPASS[@]} -gt 0 ]]; then
  info ""
  info "pass 2 - resolving ${#REPASS[@]} dependency reference(s)"
  for raw in "${REPASS[@]}"; do
    IFS=',' read -r task_id layer module sprint priority title goal story_ids fr_ids spec_refs depends_on dod_extra <<<"$raw"
    num="${ISSUE_OF[$task_id]:-}"
    [[ -n "$num" && "$num" != "?" ]] || continue
    body_file="$TMPDIR_RUN/$task_id.md"
    render_body "$task_id" "$layer" "$module" "$sprint" "$priority" "$title" "$goal" \
                "$story_ids" "$fr_ids" "$spec_refs" "$depends_on" "$dod_extra" > "$body_file"
    if [[ $DRY_RUN -eq 1 ]]; then
      info "  [deps] #$num $task_id"
    else
      gh issue edit "$num" --repo "$REPO" --body-file "$body_file" >/dev/null \
        || warn "could not rewrite deps on #$num ($task_id)"
      info "  [deps] #$num $task_id"
    fi
  done
fi

# ---------------------------------------------------------------------------
# pass 3 - project board
# ---------------------------------------------------------------------------
if [[ $NO_PROJECT -eq 1 ]]; then
  info ""
  info "pass 3 - skipped (--no-project)"
elif [[ $DRY_RUN -eq 1 ]]; then
  info ""
  info "pass 3 - skipped (dry run)"
else
  info ""
  info "pass 3 - project board"
  boarded=0
  for raw in "${ROWS[@]}"; do
    IFS=',' read -r task_id layer module sprint priority title goal story_ids fr_ids spec_refs depends_on dod_extra <<<"$raw"
    num="${ISSUE_OF[$task_id]:-}"
    [[ -n "$num" && "$num" != "?" ]] || continue
    [[ -n "$ONLY_SPRINT" && "$sprint" != "$ONLY_SPRINT" ]] && continue
    [[ -n "$ONLY_LAYER"  && "$layer"  != "$ONLY_LAYER"  ]] && continue
    [[ "$LIMIT" -gt 0 && "$boarded" -ge "$LIMIT" ]] && break
    boarded=$((boarded+1))

    node_id="$(nocr "$(gh issue view "$num" --repo "$REPO" --json id -q '.id' 2>/dev/null || true)")"
    [[ -n "$node_id" ]] || { warn "no node id for #$num"; continue; }
    item_id="$(project_add_item "$node_id")"
    [[ -n "$item_id" ]] || { warn "could not add #$num to the project"; PROJECT_WARN=1; continue; }

    project_set_status "$item_id"
    project_set_select "$item_id" Layer    "$layer"
    project_set_select "$item_id" Module   "$module"
    project_set_select "$item_id" Priority "$priority"
    info "  [board] #$num $task_id"
  done
fi

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
info ""
info "created: $CREATED   updated: $UPDATED   filtered out: $SKIPPED"
[[ $DRY_RUN -eq 1 ]] && info "dry run - nothing was written"
if [[ $PROJECT_WARN -eq 1 ]]; then
  info ""
  info "Project fields were incomplete. See README.md, 'Project board setup', for the exact"
  info "field names and option values to create, then re-run to backfill them."
  exit 3
fi
