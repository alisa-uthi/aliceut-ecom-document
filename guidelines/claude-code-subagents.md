# Claude Code Subagents

**Status:** Active  
**Source:** [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)

All developers on this project use the same set of Claude Code subagents. This ensures consistent code quality, architectural alignment, and review depth across every contribution — regardless of who writes it.

---

## Summary

| # | Section | Description |
|---|---------|-------------|
| 1 | [What are subagents](#1-what-are-subagents) | Why we use them and what they do |
| 2 | [Installation](#2-installation) | One-time setup |
| 3 | [Routing map](#3-routing-map) | Which agent to use for which task |
| 4 | [Usage patterns](#4-usage-patterns) | How to invoke agents in Claude Code |
| 5 | [Workflow integration](#5-workflow-integration) | Where agents fit in the daily cycle |
| 6 | [Additional agents](#6-additional-agents) | Extra agents for specific scenarios |

---

<a id="1-what-are-subagents"></a>
## 1. What are subagents

Subagents are specialized Claude Code agents with a narrow, well-defined role: they have a scoped system prompt, a specific tool set, and a fixed output contract. Using the right agent for a task produces better output than asking a general-purpose Claude session to do everything.

**Why we enforce this:**

- Consistency — every developer's backend code is reviewed by the same agent with the same checklist.
- Depth — a dedicated `backend-developer` agent knows NestJS, TypeORM, Kafka outbox, and module tier rules better than a general-purpose session.
- Auditability — the subagent used is visible in the Claude Code session log, so any reviewer can see what checks ran.

---

<a id="2-installation"></a>
## 2. Installation

Install the VoltAgent subagent collection as a Claude Code plugin. Run this **once** per machine.

```bash
claude plugin install voltagent/awesome-claude-code-subagents
```

Verify installation:

```bash
claude plugin list
```

You should see `voltagent-core-dev`, `voltagent-infra`, `voltagent-qa-sec`, and related entries.

### Troubleshooting

If `claude plugin install` is not available, install from source:

```bash
git clone https://github.com/VoltAgent/awesome-claude-code-subagents.git ~/.claude/plugins/awesome-claude-code-subagents
```

Then restart Claude Code. The agents should appear in `/agents` or via the `Agent` tool.

---

<a id="3-routing-map"></a>
## 3. Routing map

Use the table below to pick the right agent. When in doubt, pick the narrowest match — do not use a general-purpose session when a specific agent exists.

| Task | Subagent | When to use |
|------|----------|-------------|
| Backend feature / bug fix | `voltagent-core-dev:backend-developer` | Any change in `aliceut-ecom-backend/`: NestJS modules, services, handlers, DTOs, TypeORM entities, Kafka producers, outbox patterns |
| Frontend feature / bug fix | `voltagent-core-dev:frontend-developer` | Any change in `aliceut-ecom-frontend/`: Angular components, services, routes, state, forms, generated API client usage |
| Docker / Compose | `voltagent-infra:docker-expert` | Editing `docker-compose.yml`, writing `Dockerfile`s, optimizing image builds, container networking, health checks |
| CI/CD pipelines | `voltagent-infra:devops-engineer` | GitHub Actions workflows, CI job authoring, deployment pipelines, environment secrets wiring |
| Local review before push | `voltagent-qa-sec:code-reviewer` + `voltagent-qa-sec:performance-engineer` | Run both on your diff before opening a PR. See [§5](#5-workflow-integration) for the exact steps |
| Integration tests / E2E tests | `voltagent-qa-sec:qa-expert` | Writing Supertest integration tests, Playwright E2E flows, test strategy for new features |

---

<a id="4-usage-patterns"></a>
## 4. Usage patterns

### Invoking a single agent

In a Claude Code session, prefix your request with the agent name:

```
Use voltagent-core-dev:backend-developer to implement the CreateOffer command handler in the pricing module. Follow the CQRS-lite pattern in backend-module-architecture.md.
```

```
Use voltagent-core-dev:frontend-developer to build the OfferPriceCard component for the PDP. Reference the Angular Material design system in conventions/design-system.md.
```

### Running two agents in parallel (local review)

Claude Code can run multiple agents concurrently. For the pre-push review step, invoke both review agents in one message:

```
Run voltagent-qa-sec:code-reviewer and voltagent-qa-sec:performance-engineer on my current diff.
```

Both agents receive the same diff and post independent findings. Address any BLOCKER items before pushing.

### Scoping the agent with context

Always tell the agent which conventions to apply. This project has specific constraints the agent must know about:

```
Use voltagent-core-dev:backend-developer to implement the FulfillmentItem snapshot logic.
Context:
- Unit price must be stored as NUMERIC(19,4), handled with decimal.js — never JS number
- Snapshot is immutable — do not re-derive from live Price rows
- Outbox row must be written in the same Postgres transaction as the domain change
- Follow the handler pattern in conventions/backend-module-architecture.md §4
```

The more context you give, the less the agent hallucinates or drifts from project conventions.

---

<a id="5-workflow-integration"></a>
## 5. Workflow integration

The agents map onto the daily workflow from [development-flow.md §3](development-flow.md#3-daily-development-workflow):

```
GitHub issue
  └─ Implement with backend-developer / frontend-developer / docker-expert / devops-engineer
      └─ Write tests with qa-expert
          └─ LOCAL REVIEW: code-reviewer + performance-engineer (before push)
              └─ Push → open PR
                  └─ CI: Claude design-review job (automated — backend PRs only)
                      └─ Address BLOCKER findings
                          └─ Self-review checklist (development-flow.md §11)
                              └─ Squash-merge
```

### Local review gate

Before pushing **any** non-trivial change, run the review pair:

1. Stage your changes (`git add -p` for precision).
2. In Claude Code:
   ```
   Run voltagent-qa-sec:code-reviewer and voltagent-qa-sec:performance-engineer on my staged diff.
   ```
3. Read both reports. Fix all BLOCKER / HIGH findings.
4. Push only after findings are resolved.

This gate is a developer responsibility — CI does not substitute for it.

---

<a id="6-additional-agents"></a>
## 6. Additional agents

These agents are available but situational. Invoke them when the specific concern arises.

| Task | Subagent | When to use |
|------|----------|-------------|
| Security-sensitive code | `voltagent-qa-sec:security-auditor` | Auth flows, JWT handling, KYC document access, any endpoint that touches user data or financial records |
| DB schema / migration authoring | `voltagent-infra:database-administrator` | Complex migration pairs, index strategy for high-volume tables, Postgres query tuning |
| TypeScript type system | `ecc:typescript-reviewer` | Advanced generic patterns, DTO type widening/narrowing, TypeORM transformer types |
| Accessibility | `ecc:a11y-architect` | WCAG compliance checks on Angular components, especially buyer portal flows |

### Suggested improvement over a plain routing list

A routing list alone does not prevent agents being skipped. Consider adding a pre-push Git hook that reminds (but does not block) the developer to run the review pair. Add to `aliceut-ecom-backend/.husky/pre-push` and `aliceut-ecom-frontend/.husky/pre-push`:

```bash
#!/usr/bin/env sh
echo ""
echo "────────────────────────────────────────────────"
echo " Reminder: did you run the Claude Code review?"
echo " voltagent-qa-sec:code-reviewer"
echo " voltagent-qa-sec:performance-engineer"
echo "────────────────────────────────────────────────"
echo ""
```

This surfaces the reminder without blocking the push, so the policy stays enforced by process and not brittle hooks.
