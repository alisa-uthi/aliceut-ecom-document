#!/usr/bin/env bash
# Validate a phase's tasks.csv before importing it.
#
# Checks: field count, quoting, duplicate task_id, known layer / priority values, sprint is numeric,
# every depends_on resolves to a row in the file, and every spec_refs entry resolves to a real file
# AND (when it carries one) a real heading anchor in that file.
#
# Usage: ./validate-tasks.sh [--phase N] [--csv PATH]
# Exit:  0 clean, 1 problems found (each one printed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE="1"
CSV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    --csv) CSV="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[[ -n "$CSV" ]] || CSV="$REPO_ROOT/phase-$PHASE/tasks.csv"
[[ -f "$CSV" ]] || { printf 'error: csv not found: %s\n' "$CSV" >&2; exit 1; }

# On Windows, `python3` is often a Store stub that exists on PATH but cannot run, so probe by
# actually executing each candidate rather than trusting `command -v`.
PY=""
for candidate in python python3 py; do
  if "$candidate" --version >/dev/null 2>&1; then PY="$candidate"; break; fi
done
[[ -n "$PY" ]] || { printf 'error: no working python found (tried python, python3, py)\n' >&2; exit 1; }

"$PY" - "$CSV" "$REPO_ROOT" <<'PYCODE'
import os, re, sys

csv_path, repo_root = sys.argv[1], sys.argv[2]
FIELDS = 12
LAYERS = {"backend", "frontend", "migration", "infra"}
PRIORITIES = {"must", "should"}
ALIASES = {
    "us/":  "phase-1/requirements/user-stories/",
    "td/":  "phase-1/technical-design/",
    "api/": "phase-1/technical-design/api-design/",
    "ui/":  "phase-1/ui-design/",
    "cv/":  "conventions/",
    "gl/":  "guidelines/",
    "dg/":  "phase-1/diagrams/",
}

problems = []
rows = []

with open(csv_path, encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, start=1):
        line = raw.rstrip("\n").rstrip("\r")
        if not line.strip() or line.startswith("#") or line.startswith("task_id,"):
            continue
        if '"' in line:
            problems.append(f"line {lineno}: quoted fields are not supported")
            continue
        parts = line.split(",")
        if len(parts) != FIELDS:
            problems.append(
                f"line {lineno}: {len(parts)} fields, expected {FIELDS} "
                f"(comma inside a field? use ';' for lists) -- starts with {parts[0]!r}")
            continue
        rows.append((lineno, parts))

ids = [p[0] for _, p in rows]
for tid in sorted({i for i in ids if ids.count(i) > 1}):
    problems.append(f"duplicate task_id: {tid}")

def expand(ref):
    if ref == "brd" or ref.startswith("brd#"):
        return "phase-1/requirements/BRD.md" + ref[3:]
    for alias, target in ALIASES.items():
        if ref.startswith(alias):
            return target + ref[len(alias):]
    return ref

def slug(heading):
    h = heading.strip().lower().replace("`", "")
    h = re.sub(r"[^\w\s-]", "", h)
    return re.sub(r"\s", "-", h)

anchor_cache = {}

def anchors_of(path):
    if path in anchor_cache:
        return anchor_cache[path]
    found = set()
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^#{1,6}\s+(.*)$", line)
                if m:
                    found.add(slug(m.group(1)))
                found.update(re.findall(r'<a id="([^"]+)"', line))
    anchor_cache[path] = found
    return found

for lineno, p in rows:
    tid, layer, module, sprint, priority = p[0], p[1], p[2], p[3], p[4]
    spec_refs, depends_on = p[9], p[10]

    if layer not in LAYERS:
        problems.append(f"{tid}: unknown layer {layer!r}")
    if priority not in PRIORITIES:
        problems.append(f"{tid}: unknown priority {priority!r}")
    if not sprint.isdigit():
        problems.append(f"{tid}: sprint {sprint!r} is not a number")
    if not module:
        problems.append(f"{tid}: module is empty")
    if not p[6]:
        problems.append(f"{tid}: goal is empty")
    if not spec_refs:
        problems.append(f"{tid}: no spec_refs -- an issue with no source of truth is not importable")

    for dep in filter(None, depends_on.split(";")):
        if dep not in ids:
            problems.append(f"{tid}: depends_on {dep!r} is not a task_id in this file")
        if dep == tid:
            problems.append(f"{tid}: depends on itself")

    for ref in filter(None, spec_refs.split(";")):
        expanded = expand(ref)
        path, _, anchor = expanded.partition("#")
        full = os.path.join(repo_root, path)
        if not os.path.isfile(full):
            problems.append(f"{tid}: spec_ref {ref!r} -> missing file {path}")
        elif anchor and anchor not in anchors_of(full):
            problems.append(f"{tid}: spec_ref {ref!r} -> no anchor #{anchor} in {path}")

print(f"{len(rows)} rows checked in {os.path.relpath(csv_path, repo_root)}")
if problems:
    print(f"\n{len(problems)} problem(s):")
    for problem in problems:
        print(f"  - {problem}")
    sys.exit(1)
print("clean: fields, ids, layers, sprints, dependencies, spec files and anchors all valid")
PYCODE
