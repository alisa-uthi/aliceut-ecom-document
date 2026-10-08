# Architecture Decision Records

The technical design under `phase-1/technical-design/` and the conventions under
`conventions/` are **canonical**. Code follows them. When code and spec
disagree, that is a defect in the code until a decision says otherwise — and a
decision means an ADR in this directory.

## The rule

> Never change the code to diverge from the spec, and never change the spec to
> describe whatever the code happens to do. Change both in the same pass, and
> record why in an ADR.

Concretely, when you find code that does not match the design:

1. **Default: fix the code.** No ADR needed — the spec already said what to do.
   Reference the spec section in the commit message.
2. **If the spec is wrong or no longer the better choice:** write an ADR,
   update the spec to match the decision, and change the code in the same pass.
   All three land together, and the ADR is linked from the spec section it
   changes.
3. **If you cannot decide yet:** record it in
   [`phase-1/technical-design/spec-compliance.md`](../phase-1/technical-design/spec-compliance.md)
   as an open divergence. Never leave a silent mismatch.

A spec edit that is purely editorial — fixing a typo, clarifying wording that
changes no behaviour — needs no ADR.

## Numbering and status

Files are `NNNN-kebab-case-title.md`, numbered sequentially and never renumbered.
Status is one of:

| Status | Meaning |
|---|---|
| `Proposed` | Written, not yet agreed |
| `Accepted` | Agreed and in force; the spec and code reflect it |
| `Superseded by ADR-NNNN` | Replaced; kept for the record, never deleted |

Supersede rather than edit an accepted ADR: the history of why something changed
is the point of keeping these.

Copy [`0000-adr-template.md`](0000-adr-template.md) to start one.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-auth-session-responses-are-not-data-wrapped.md) | Auth session responses are not data-wrapped | Accepted |
