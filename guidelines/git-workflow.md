# Git Workflow

**Status:** Draft
**Source of truth:** [BRD v1.2](../phase-1/requirements/BRD.md)

This document establishes Git conventions for AliceUT to ensure a clean, auditable history suitable for a learning/portfolio project while maintaining production discipline. Solo developer context: self-review gates and CI enforcement replace team oversight.

---

## Summary

- [1. Branching Strategy](#branching-strategy)
- [2. Commit Conventions](#commit-conventions)
- [3. Pull Request Process](#pull-request-process)
- [4. GitHub Projects Integration](#github-projects-integration)
- [5. Release Tagging and Versioning](#release-tagging-and-versioning)
- [6. Hotfix Flow](#hotfix-flow)
- [7. CI Enforcement Hooks](#ci-enforcement-hooks)
- [8. `.gitignore` Guidance](#gitignore-guidance)
- [9. Workflow Examples](#workflow-examples)
- [10. Quick Reference](#quick-reference)
- [11. Related Documents](#related-documents)

<a id="branching-strategy"></a>
## 1. Branching Strategy

### 1.1 Branch Names and Lifetime

All feature work branches from `main`. Use kebab-case prefixes:

| Prefix | Use case | Example | Lifetime |
|--------|----------|---------|----------|
| `feature/` | New feature or user story | `feature/ET-21-seller-kyc` | Delete after merge |
| `fix/` | Bug fix (not infrastructure) | `fix/ET-42-cart-total-rounding` | Delete after merge |
| `refactor/` | Code reorganization (no behavior change) | `refactor/catalog-repository-tests` | Delete after merge |
| `docs/` | Documentation, diagrams, examples | `docs/phase-1-technical-design` | Delete after merge |
| `chore/` | Dependency updates, CI config, tooling | `chore/upgrade-nestjs-to-v10` | Delete after merge |
| `hotfix/` | Production emergency (see §6) | `hotfix/v1.0.1-payment-race-condition` | Delete after merge; tag release |

**Branch naming tie-in:** If work is tracked in GitHub Issues or Projects, include the issue/ticket number: `feature/ET-21-...`. This enables automated linking.

### 1.2 Branch Lifecycle

1. Create from `main` (unless part of a multi-PR feature, then branch from parent feature branch if agreed explicitly).
2. Commit atomically and push regularly.
3. Open a pull request **before** merging—no direct pushes to `main`.
4. CI checks must pass; self-review checklist completed.
5. Squash-merge to `main` to keep history clean.
6. **Delete the branch immediately after merge** (GitHub can auto-delete; enable in repo settings).

### 1.3 Long-Lived Branch Protection

`main` is the only long-lived branch. No `develop`, `staging`, or `release` branches in V1 (phase-1 CI deploys from `main` via docker-compose).

---

<a id="commit-conventions"></a>
## 2. Commit Conventions

### 2.1 Conventional Commits Format

Follow [Conventional Commits](https://www.conventionalcommits.org/) v1.0.0:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type:** One of:
- `feat` — New feature or capability
- `fix` — Bug fix
- `refactor` — Code reorganization (no behavior change, no new features)
- `test` — Test additions or fixes (no source change)
- `docs` — Documentation, comments, diagrams
- `style` — Formatting, linting (no logic change)
- `chore` — Dependency updates, CI config, build tooling
- `ci` — CI/CD configuration and scripts
- `perf` — Performance optimization

**Scope:** Module or domain (e.g., `catalog`, `order`, `auth`, `api`, `database`). Optional but strongly encouraged for clarity.

**Subject:** Imperative mood, lowercase first letter, no period. Max 50 characters.
- ✅ `feat(auth): add Google OAuth provider`
- ❌ `feat(auth): added Google OAuth`
- ❌ `feat(auth): Add Google OAuth provider.`

### 2.2 Body and Footers

**Body** (optional unless breaking change): Explain *why* the change exists. Wrap at 72 characters. Separate from subject by blank line.

**Footer** (optional): Link to issues or document breaking changes.

Breaking change: Start line with `BREAKING CHANGE:` followed by description.

```
fix(order): prevent order total from going negative on refund

Apply tax cumulatively in deduction order to avoid intermediate
rounding errors. Fixes edge case where multi-currency FX conversion
caused total to dip below zero cents.

Closes #ET-42
BREAKING CHANGE: calculateTotal() now returns Promise<Decimal> instead of Decimal; callers must await.
```

### 2.3 Commit Size and Atomicity

Each commit should:
- Represent one logical change (feature, fix, test group, etc.)
- Compile and pass tests in isolation (no "WIP" commits in `main`)
- Be understandable by reading the commit message and diff

Bad: `git commit -am "lots of changes"` bundling unrelated fixes and refactors.
Good: Separate commits for catalog bugfix, auth refactor, and docs update.

### 2.4 Commit Message Linting

Repository enforces Conventional Commits syntax via **commitlint** (see §7).

---

<a id="pull-request-process"></a>
## 3. Pull Request Process

### 3.1 PR Title and Description

**Title:** Must match Conventional Commits format. GitHub Actions auto-generates from squash-merged PR title, so precision matters.

```
feat(order): implement order status cancellation flow
fix(cart): prevent duplicate items on fast add-to-cart clicks
docs(phase-1): add technical ERD and API specs
```

**Description template** (save as `.github/pull_request_template.md`):

```markdown
## Summary
Brief 2-3 sentence description of what this PR does and why.

## Changes
- Specific change 1
- Specific change 2

## Testing
- [ ] Unit tests added/updated
- [ ] E2E scenarios validated in browser (for UI changes)
- [ ] No regressions in related features (list them)
- [ ] Performance impact assessed (if relevant)

## Breaking Changes
None (or list incompatibilities with prior API/behavior).

## Screenshots (UI changes only)
Attach before/after or relevant screens.

## Related Issues
Closes #ET-42, references #ET-99
```

### 3.2 Self-Review Checklist (Solo Development)

Before opening PR, complete locally:

- [ ] Code compiles and all tests pass
- [ ] Commit messages follow Conventional Commits format
- [ ] No hardcoded secrets (API keys, passwords, tokens)
- [ ] `.gitignore` excludes generated/local files
- [ ] Changes align with the [conventions](../conventions/) and technical design of each phase
- [ ] Type-safe: no `any` types without justification
- [ ] No console.log left in; debug output removed or logged via logger
- [ ] Monetary calculations use `Decimal` (never `number`), amounts in JSON as strings
- [ ] Event-driven writes use transactional outbox pattern (if applicable)
- [ ] Error handling present for external calls (API, database, Kafka)
- [ ] No direct DB connection outside repository pattern
- [ ] Async code has proper cancellation/timeout handling

When you open the PR on GitHub, GitHub Actions runs CI checks. Wait for them to pass before merging.

### 3.3 Merge Strategy

**Squash-merge only.** This collapses all commits on the branch into a single commit on `main`, keeping history linear and readable.

```bash
# GitHub UI: Select "Squash and merge" when merging PR
# Title: Use the PR title (already Conventional Commits format)
# Delete branch after merge: Enable in repo settings
```

Rationale:
- Clean main branch history for portfolio/learning value
- Each merge = one logical feature/fix
- Easier to bisect and blame
- Tag a single commit per release

### 3.4 Stacked PRs

PR stacking splits a large feature into a chain of dependent, reviewable PRs instead of one giant branch. Each PR targets its parent branch rather than `main`, so each diff is one logical layer.

#### When to stack

Stack when a feature has a clear build order that would create an unwieldy single diff. Examples:

- Domain module: entities → repository → use-case handlers → controller → tests
- Migration + API endpoint + frontend screen

Do **not** stack when work can be split into independent features with no dependency order.

#### Branch chain pattern

```
main
 └─ feature/ET-21-kyc-entity        ← stack base (PR 1 targets main)
     └─ feature/ET-21-kyc-usecase   ← PR 2 targets ET-21-kyc-entity
         └─ feature/ET-21-kyc-api   ← PR 3 targets ET-21-kyc-usecase
```

Branch naming: keep the same ticket prefix on all levels so they sort together.

#### Opening stacked PRs on GitHub

1. Push all branches to remote.
2. Open PRs bottom-up. **Set each PR's base to its parent feature branch**, not `main`.
3. Label all PRs with the same `stack/ET-21` label.
4. GitHub shows each PR's diff relative to its base, so each layer is a clean delta.

```bash
git checkout main
git checkout -b feature/ET-21-kyc-entity
# ... implement entity changes ...
git push -u origin feature/ET-21-kyc-entity

git checkout -b feature/ET-21-kyc-usecase
# ... implement use-case ...
git push -u origin feature/ET-21-kyc-usecase

git checkout -b feature/ET-21-kyc-api
# ... implement controller ...
git push -u origin feature/ET-21-kyc-api

# Open PRs:
# PR 1: feature/ET-21-kyc-entity → main
# PR 2: feature/ET-21-kyc-usecase → feature/ET-21-kyc-entity
# PR 3: feature/ET-21-kyc-api → feature/ET-21-kyc-usecase
```

#### Keeping a stack in sync

When `main` changes, rebase the entire stack bottom-up:

```bash
git fetch origin

git checkout feature/ET-21-kyc-entity
git rebase origin/main

git checkout feature/ET-21-kyc-usecase
git rebase feature/ET-21-kyc-entity

git checkout feature/ET-21-kyc-api
git rebase feature/ET-21-kyc-usecase

git push --force-with-lease origin \
  feature/ET-21-kyc-entity \
  feature/ET-21-kyc-usecase \
  feature/ET-21-kyc-api
```

`--force-with-lease` rejects a push if the remote has commits you haven't fetched, preventing accidental overwrites.

#### Merging a stack

Merge bottom-up, squash-merging each PR in order. After PR 1 merges to `main`:

1. GitHub automatically retargets PR 2's base from `feature/ET-21-kyc-entity` to `main`.
2. Verify the diff looks right (no phantom diff from the now-gone parent).
3. Merge PR 2 to `main` (squash). Repeat for PR 3.

#### Tooling: `gh stack` extension

Install the `gh stack` GitHub CLI extension to automate stack management:

```bash
gh extension install nickvdyck/gh-stack
```

Key commands:

```bash
gh stack list                     # show stack state for current branch
gh stack sync                     # rebase entire stack from main
```

The manual `git rebase` workflow above works without it; `gh stack` is optional but saves time on deep stacks.

---

<a id="github-projects-integration"></a>
## 4. GitHub Projects Integration

### 4.1 Linking PRs to Issues

Mention the issue in the PR description or commit footers:

```
Closes #ET-21
Refs #ET-22
```

GitHub auto-links and auto-closes issues when PR merges.

### 4.2 Branch Naming Ties to Issues

If using GitHub Issues or Projects for task tracking:

- `feature/ET-21-seller-kyc` corresponds to issue/card ET-21
- Include the ticket number for automated linking

### 4.3 Project Cards

Use GitHub Projects to visualize progress across phases. Link PRs to project cards:
- Each PR description includes "Closes #ET-N" to auto-move cards to "Done" on merge
- Cards stay in "In Progress" while PR is open

---

<a id="release-tagging-and-versioning"></a>
## 5. Release Tagging and Versioning

### 5.1 Semantic Versioning

Tags follow [Semantic Versioning](https://semver.org/) format: `vMAJOR.MINOR.PATCH`

- `v1.0.0` — Initial phase-1 release
- `v1.1.0` — New features added (backward-compatible)
- `v1.1.1` — Bug fix, no API changes
- `v2.0.0` — Phase-2 (breaking changes allowed)

### 5.2 Tagging Process

After PR is merged to `main` (via squash-merge):

```bash
# Pull latest main
git checkout main
git pull origin main

# Create annotated tag
git tag -a v1.0.0 -m "Release: Phase 1 MVP"

# Push tag
git push origin v1.0.0
```

Annotated tags (not lightweight) are recommended for releases; they include tagger name, date, and message.

### 5.3 CHANGELOG

Maintain `CHANGELOG.md` at repo root. Update when releasing:

```markdown
# Changelog

All notable changes to AliceUT are documented here.

## [1.0.0] - 2026-09-15

### Added
- Seller KYC flow (ET-21)
- Cart management with tax calculation (ET-15)
- Product catalog with Elasticsearch indexing (ET-10)

### Fixed
- Race condition in order totals (ET-42)

### Changed
- API now returns monetary amounts as strings, not numbers (BREAKING)

## [0.1.0] - 2026-08-01

### Added
- Project initialization and documentation
```

Update `CHANGELOG.md` from squash-merged PR titles (Conventional Commits makes this mechanical).

---

<a id="hotfix-flow"></a>
## 6. Hotfix Flow

When production is broken:

1. **Branch from the release tag**, not `main`:
   ```bash
   git checkout -b hotfix/v1.0.1-payment-race-condition v1.0.0
   ```

2. **Fix and commit** as normal (Conventional Commits).

3. **Test thoroughly** (this is production, not a learning exercise).

4. **Merge back to `main` via PR** (squash-merge as usual).

5. **Tag the patch release** on the merge commit:
   ```bash
   git tag -a v1.0.1 -m "Hotfix: Payment race condition"
   git push origin v1.0.1
   ```

6. **Deploy from the tag** (CI/CD pipeline pulls `v1.0.1`).

---

<a id="ci-enforcement-hooks"></a>
## 7. CI Enforcement Hooks

### 7.1 Branch Protection Rules

Configure on `main` in GitHub settings:

- [x] Require a pull request before merging
- [x] Require status checks to pass before merging
  - `build` (compile, type-check)
  - `test` (unit + integration tests)
  - `lint` (code style, formatting)
  - `security` (dependency scanning, SAST if available)
- [x] Require branches to be up to date before merging
- [x] Require commit message to follow Conventional Commits (via commitlint in CI)
- [x] Automatically delete head branches

### 7.2 Commitlint Configuration

File: `.commitlintrc.js` (or `.commitlintrc.json`)

```javascript
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', ['feat', 'fix', 'refactor', 'test', 'docs', 'style', 'chore', 'ci', 'perf']],
    'scope-enum': [1, 'always', ['auth', 'catalog', 'order', 'cart', 'pricing', 'inventory', 'identity', 'seller', 'admin', 'notifications', 'search', 'workers', 'api', 'database', 'infra', 'docs']],
    // 'payment' is excluded — real payment gateway is out of V1 scope (BRD §3.2)
    'subject-case': [2, 'never', ['start-case', 'pascal-case', 'upper-case']],
    'subject-max-length': [2, 'always', 100],
  },
};
```

Enforce in GitHub Actions CI:

```yaml
# .github/workflows/lint.yml
- name: Validate commit messages
  uses: wagoid/commitlint-github-action@v5
```

### 7.3 CI Pipeline

Full `.github/workflows/ci.yml` for `aliceut-ecom-backend`:

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - uses: pnpm/action-setup@v4
        with:
          version: 10
      - run: pnpm install --frozen-lockfile
      - run: pnpm run build
      - run: pnpm run test
      - run: pnpm run lint

  claude-design-review:
    runs-on: ubuntu-latest
    needs: build-and-test
    if: github.event_name == 'pull_request'
    permissions:
      contents: read
      pull-requests: write
    steps:
      - name: Checkout backend
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Checkout design docs
        uses: actions/checkout@v4
        with:
          repository: alisa-uthi/aliceut-ecom-document
          path: aliceut-ecom-document

      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code

      - name: Get PR diff
        id: diff
        run: |
          git diff origin/main...HEAD -- '*.ts' > pr_diff.txt
          echo "diff_size=$(wc -l < pr_diff.txt)" >> $GITHUB_OUTPUT

      - name: Run Claude design review
        if: steps.diff.outputs.diff_size != '0'
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          claude --print -p "
          You are a senior backend architect reviewing a pull request for the AliceUT e-commerce platform.

          Design spec and conventions live in aliceut-ecom-document/:
          - Architecture: aliceut-ecom-document/architecture-overview.md
          - Module architecture: aliceut-ecom-document/conventions/backend-module-architecture.md
          - Backend coding standards: aliceut-ecom-document/conventions/backend-coding-standards.md
          - API conventions: aliceut-ecom-document/conventions/api-conventions.md
          - Kafka events: aliceut-ecom-document/conventions/kafka-events.md
          - Auth/JWT design: aliceut-ecom-document/conventions/auth-jwt-design.md
          - Database migrations: aliceut-ecom-document/conventions/database-migrations.md
          - Phase-1 implementation spec: aliceut-ecom-document/phase-1/technical-design

          PR diff:
          \$(cat pr_diff.txt)

          Focus ONLY on the changed lines in the diff above. Do not review unchanged code.
          For each changed file and line, check only the rules that the diff actually touches:

          - Money handling: if the diff touches monetary fields or arithmetic — Decimal only, no JS number, amounts as strings in JSON
          - Event-driven writes: if the diff touches domain state changes — transactional outbox pattern required
          - Module boundaries: if the diff touches cross-module calls or DB queries — no cross-module DB joins, repository pattern enforced
          - Order immutability: if the diff touches FulfillmentItem or checkout — snapshots must not be re-derived
          - Security: if the diff adds env vars, error responses, or external calls — no hardcoded secrets, no raw stack traces to clients
          - TypeScript: if the diff introduces new types or function signatures — no untyped \`any\`, strict mode compliance
          - Tests: if the diff adds a new endpoint or Tier-1 handler — check that a corresponding test exists in the diff

          Skip any rule whose subject is not present in the diff.
          Output as a Markdown list. Each finding: severity (BLOCKER/WARNING/INFO), file:line, explanation, fix.
          Skip praise. Skip findings with no actionable fix. If the diff is clean, output only: \`All changed lines look good.\`
          " > claude_review.md

      - name: Post review as PR comment
        if: steps.diff.outputs.diff_size != '0'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const review = fs.readFileSync('claude_review.md', 'utf8');
            if (review.trim().length === 0) return;
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `## Claude Design Review\n\n${review}\n\n---\n*Reviewed against [aliceut-ecom-document](https://github.com/alisa-uthi/aliceut-ecom-document)*`
            });
```

**Setup required:**
- Add `ANTHROPIC_API_KEY` to GitHub repository secrets.
- The `claude-design-review` job runs only on PRs, never on direct pushes to `main`.
- The design-review job is non-blocking by default (does not gate merge). To make it a hard gate, add it to the branch protection required status checks.

---

<a id="gitignore-guidance"></a>
## 8. `.gitignore` Guidance

### 8.1 What to Ignore

File: `.gitignore` (checked in)

```gitignore
# Dependencies
node_modules/
# Do NOT add lock files here — package-lock.json / yarn.lock / pnpm-lock.yaml must be committed
# for reproducible installs across dev, CI, and production.

# Build and dist
dist/
build/
*.tsbuildinfo

# Environment variables (never commit secrets)
.env
.env.local
.env.*.local

# IDE and editor
.vscode/
.idea/
*.swp
*.swo
*.sublime-workspace
.DS_Store

# Runtime and logs
logs/
*.log
npm-debug.log*

# Test coverage
coverage/
.nyc_output/

# Docker volumes and local data
docker/volumes/
postgres_data/
mongo_data/

# Database migrations temp files
*.migration.tmp

# OS
Thumbs.db
```

### 8.2 What to Check In

- All source code (`.ts`, `.html`, `.css`)
- Configuration files (`.eslintrc`, `tsconfig.json`, `nest-cli.json`)
- Package manifest (`package.json`, though not lock files)
- CI workflows (`.github/workflows/`)
- Documentation and diagrams (`*.md`, `*.drawio`)
- Docker Compose files (`docker-compose.yml`)
- Database migration scripts (`migrations/phase-1/`, `migrations/phase-2/`)

### 8.3 Secrets Management

Never commit:
- `.env` files (gitignore)
- API keys, OAuth secrets, database passwords
- Private keys (SSL certs, SSH keys)

Use GitHub Secrets for CI/CD; document expected env vars in `README.md` without values.

---

<a id="workflow-examples"></a>
## 9. Workflow Examples

### Example 1: Feature Branch Lifecycle

```bash
# Create issue ET-21 in GitHub Projects (Seller KYC)
# Create and switch to feature branch
git checkout -b feature/ET-21-seller-kyc

# Make atomic commits
git add src/kyc/kyc.service.ts
git commit -m "feat(kyc): implement document verification logic"

git add src/kyc/kyc.controller.ts
git commit -m "feat(kyc): add endpoint POST /sellers/:id/kyc"

git add test/kyc.spec.ts
git commit -m "test(kyc): add verification edge cases"

# Push to remote
git push -u origin feature/ET-21-seller-kyc

# Open PR on GitHub (title auto-filled from commit: "feat(kyc)...")
# GitHub Actions runs CI
# Self-review checklist completed locally and in PR description
# Squash-merge via GitHub UI
# Branch auto-deleted
```

### Example 2: Hotfix for Production Bug

```bash
# Bug found in v1.0.0: race condition in order total
git checkout -b hotfix/v1.0.1-payment-race-condition v1.0.0

# Fix the bug
git add src/order/order.service.ts
git commit -m "fix(order): prevent negative total from race condition"

# Push and open PR
git push -u origin hotfix/v1.0.1-payment-race-condition

# PR merged, squash-merge to main
# Tag the patch
git checkout main
git pull origin main
git tag -a v1.0.1 -m "Hotfix: Payment race condition"
git push origin v1.0.1

# CI/CD detects tag, builds and deploys v1.0.1
```

### Example 3: Commit Message with Breaking Change

```
git commit -am "refactor(auth): replace JWT strategy with refresh rotation

Move refresh tokens to secure HTTP-only cookies. Access tokens remain
in Authorization header but now shorter-lived (15 min vs 1 hour).

Closes #ET-55
BREAKING CHANGE: Login response no longer includes refresh_token in body; clients must use cookies instead.
"
```

---

<a id="quick-reference"></a>
## 10. Quick Reference

| Task | Command |
|------|---------|
| Create feature branch | `git checkout -b feature/ET-21-name` |
| Commit with type/scope | `git commit -m "feat(catalog): add product search"` |
| Squash last 3 commits | `git rebase -i HEAD~3` |
| Update main from remote | `git fetch origin && git rebase origin/main` |
| List local branches | `git branch --list` |
| Delete merged branch | `git branch -d feature/branch-name` |
| Tag a release | `git tag -a v1.0.0 -m "Release v1.0.0"` |
| Push tags | `git push origin v1.0.0` |
| Revert a commit | `git revert <commit-hash>` |

---

<a id="related-documents"></a>
## 11. Related Documents

- [BRD v1.2 — Locked Decisions §12](../phase-1/requirements/BRD.md)
- [Architecture Overview](../architecture-overview.md)
- [API Conventions](../conventions/api-conventions.md)
- [Database Migrations](../conventions/database-migrations.md)
- [Backend Coding Standards](../conventions/backend-coding-standards.md)
- [Frontend Coding Standards](../conventions/frontend-coding-standards.md)
- [Testing Guidelines](testing-guidelines.md)
