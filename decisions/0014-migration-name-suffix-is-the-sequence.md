# ADR-0014: A migration's `name` ends in a 13-digit form of its sequence, and every CREATE TABLE is guarded

**Status:** Accepted
**Date:** 2026-10-16
**Affects:** `conventions/database-migrations.md` (§2, §5 Naming, §5 SQL rules)
**Implemented by:** aliceut-ecom-backend#67

## Context

`database-migrations.md` §2 and §5 said TypeORM orders migrations by the
trailing digits of the class name, so a `CreateUsers0002` class would run in
sequence order. The convention flagged that claim as unverified.

It was wrong for TypeORM 0.3.31. `MigrationExecutor` reads
`migration.name || migration.constructor.name`, takes its **last 13
characters** as a JavaScript timestamp, and throws when they do not parse.
A class name like `CreateUsers0002` fails that check, so the backend gave
every migration a `name` property ending in a timestamp. Those timestamps were
chosen by hand and did not follow the sequence: 0001–0005 and 0003b carried
`1790927180000`–`1790927192001`, 0006–0018 carried `1728031200000`–
`1728720000018`. On an empty database `migration:run` applied 0006 first and
failed on the missing `inventory` schema (spec-compliance.md, former entry 7).

Two more faults were behind the same failure. 0003b and 0008 both created
`identity."user"`, with different columns; 0008's unguarded `CREATE TABLE`
failed whenever 0003b had run. And 0007 (seller) referenced `identity."user"`,
which only 0008 created, so the file order was wrong even with correct names.

No deployed database needed carrying over: on 2026-10-16 the owner decided
that every existing database is dropped and rebuilt, so the names recorded in
`schema_migrations_phase1` could change freely.

## Decision

Every migration class sets `name = '{seq}_{description}_179000000{seq}'`
(`0019_add_foo` → `'0019_add_foo_1790000000019'`), so the 13 digits TypeORM
reads grow with the 4-digit file sequence and execution order is file order.
The sequence has no letter suffixes; 0003b is deleted, `0007_identity_schema`
owns `identity."user"`, and seller moves to `0008_seller_schema` so it runs
after the table it references. Every `CREATE TABLE` is written
`CREATE TABLE IF NOT EXISTS`. CI applies the whole sequence to an empty
Postgres, reverts all of it and applies it again on every push.
`database-migrations.md` §2 and §5 now say this.

## Consequences

- A fresh `migration:run` works, and CI fails a pull request that breaks it.
- Every existing local or dev database must be rebuilt
  (`docker compose down -v`); its recorded names no longer match.
- `IF NOT EXISTS` makes a duplicate create pass silently: a second migration
  that creates an existing table with different columns is now a no-op rather
  than an error. The empty-database CI job does not catch that; review must.
- References to `0007_seller_schema` in ADR-0006, ADR-0007 and seller.md now
  read `0008_seller_schema`.

## Alternatives considered

- **Rename and ship a one-off SQL that rewrites `schema_migrations_phase1`.**
  Keeps existing databases, but there were none worth keeping.
- **Squash 0001–0018 into one baseline.** Fixes the order at the cost of the
  history and of every per-migration revert; more change than the fault needs.
- **Keep 0003b and turn 0008 into `ALTER TABLE`.** Leaves the `b` suffix and
  splits one table's definition across two migrations.
- **Rename 0008 to 0005b instead of swapping.** Fewer document edits, but keeps
  letter suffixes and a gap in the sequence.
