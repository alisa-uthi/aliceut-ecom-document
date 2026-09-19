# Database Migrations Convention

**Status:** Complete  
**Source of truth:** [BRD v1.2](../phase-1/requirements/BRD.md), [module-architecture](backend-module-architecture.md)

Migration scripts live in the backend repository — **`aliceut-ecom-backend`** — under `migrations/`. The backend never runs migrations automatically; all migrations are intentional, operator-triggered actions.

---

## Summary

- [1. Backend repo layout](#backend-repo-layout)
- [2. Execution engine](#execution-engine)
- [3. GitHub Actions workflows](#github-actions-workflows)
- [4. GitHub Environments and secrets](#github-environments-and-secrets)
- [5. Migration file conventions](#migration-file-conventions)

<a id="backend-repo-layout"></a>
## 1. Backend repo layout

```
aliceut-ecom-backend/
├── .github/
│   └── workflows/
│       ├── db-migrate.yml          # apply / revert migrations in an environment
│       └── db-status.yml           # show applied and pending migrations per environment
├── migrations/
│   ├── init/                       # empty in V1 — .gitkeep only, no .sql files
│   ├── phase-1/
│   │   ├── datasource.ts           # TypeORM DataSource for the phase-1 sequence
│   │   ├── 0001_create_extensions.ts
│   │   ├── 0001_create_extensions.up.sql
│   │   ├── 0001_create_extensions.down.sql
│   │   ├── 0002_create_users.ts
│   │   ├── 0002_create_users.up.sql
│   │   ├── 0002_create_users.down.sql
│   │   └── ...
│   └── phase-2/
│       ├── datasource.ts
│       ├── 0001_add_k8s_config.ts
│       ├── 0001_add_k8s_config.up.sql
│       ├── 0001_add_k8s_config.down.sql
│       └── ...
└── ...
```

Each phase directory is an independent migration sequence starting at `0001`. Keeping migrations in the backend repo means integration tests, local setup, and production deployments all reference the same source.

`migrations/init/` is mounted into the Postgres container's `docker-entrypoint-initdb.d`. **In V1 it ships empty** — a `.gitkeep` and no `.sql` files at all. It is not part of any migration sequence.

It exists as a guard rather than as a container. Postgres runs that directory exactly once, as the superuser, on the first boot of an empty data volume, and never again. Anything placed there is invisible to `migration:run`, unversioned, unrepeatable, and absent from every environment whose volume already exists: it bypasses the migration state table, so on a pre-existing volume it silently never runs and the database diverges from what the state table claims. The only category that legitimately needs superuser-at-first-boot semantics is roles and grants — naming that category and then shipping zero files in it is what makes the three rules below enforceable instead of preferences.

- **No schema.** Tables, columns, indexes and constraints come exclusively from the numbered migrations below.
- **No extensions.** `CREATE EXTENSION` belongs in migration `0001` (see §2).
- **No roles or grants either, in V1.** The platform has exactly one database principal — the owner named by `POSTGRES_USER` in [docker-compose-topology.md § 5](../phase-1/technical-design/docker-compose-topology.md#env-example), which is also the credential in every `DATABASE_URL`. There is no read-only role, no separate application role and no per-schema grant, so there is nothing for this directory to hold.

The directory name invites a newcomer to put schema there. It is the wrong place, and this paragraph exists to say so. The first file that legitimately lands here would be a read-only reporting role, and it arrives in the commit that names that role.

---

<a id="execution-engine"></a>
## 2. Execution engine

**TypeORM migrations carrying raw SQL** (BRD §12 decision 25, NFR-18). The engine is the TypeORM CLI, already a backend dependency — no extra binary to install in CI or on a developer machine.

Two rules define the shape:

- **`synchronize` is `false` in every environment, without exception.** Schema never derives from entity decorators. TypeORM is the sequencer and the state tracker; it is not the schema author.
- **Every migration's body is raw SQL held in a `.sql` file.** The `.ts` class is a thin shell that reads its sibling `.up.sql` / `.down.sql` and executes it. Nothing in a migration is expressed as a TypeORM schema-builder call, so the SQL stays reviewable, portable and diffable (NFR-18).

```typescript
// migrations/phase-1/0002_create_users.ts
import { MigrationInterface, QueryRunner } from 'typeorm';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const sql = (file: string) => readFileSync(join(__dirname, file), 'utf8');

export class CreateUsers0002 implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(sql('0002_create_users.up.sql'));
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(sql('0002_create_users.down.sql'));
  }
}
```

The class name ends in the same 4-digit sequence as its files. TypeORM orders migrations by the trailing number in the class name, so the sequence in §5 is also the execution order. **That ordering rule is asserted from TypeORM's documented behaviour, not from anything in this repository** — verify it against the installed version when the first migration is written, because a mismatch would reorder the whole sequence silently rather than fail.

### State table per phase

Each phase has its own `DataSource`, and each names its own state table, so the two sequences cannot interfere:

| Phase | DataSource | Tracking table |
|-------|-----------|----------------|
| phase-1 | `migrations/phase-1/datasource.ts` | `schema_migrations_phase1` |
| phase-2 | `migrations/phase-2/datasource.ts` | `schema_migrations_phase2` |

```typescript
// migrations/phase-1/datasource.ts
import { DataSource } from 'typeorm';

export default new DataSource({
  type: 'postgres',
  url: process.env.DATABASE_URL,
  synchronize: false,
  migrationsTableName: 'schema_migrations_phase1',
  migrations: [`${__dirname}/0*.ts`],
  entities: [],          // migrations never load entities
});
```

### Commands

```bash
# Apply all pending migrations in phase-1
npm run migration:run

# Revert the most recently applied migration (one per invocation)
npm run migration:revert

# List applied and pending migrations
npm run migration:show
```

`package.json` scripts wrap the CLI with the phase-1 DataSource, which is the sequence in play for the whole of Phase 1:

```json
"migration:run":    "typeorm-ts-node-commonjs migration:run    -d migrations/phase-1/datasource.ts",
"migration:revert": "typeorm-ts-node-commonjs migration:revert -d migrations/phase-1/datasource.ts",
"migration:show":   "typeorm-ts-node-commonjs migration:show   -d migrations/phase-1/datasource.ts"
```

**There is no "go to version N".** TypeORM reverts one migration per invocation and offers no jump-to-target. Walking back several steps means invoking `migration:revert` that many times, newest first. Nothing in the workflow below pretends otherwise.

**The backend never runs migrations on start.** No container entrypoint calls `migration:run`; `migrationsRun` is not set on any runtime DataSource. Applying a migration is always a deliberate act — a developer running the script, or the workflow in §3.

### Extensions

`CREATE EXTENSION` statements live in migration `0001_create_extensions`, never in `migrations/init/`. Phase 1 needs exactly one:

```sql
-- migrations/phase-1/0001_create_extensions.up.sql
CREATE EXTENSION IF NOT EXISTS btree_gist;
```

`pricing.offer_price` carries `EXCLUDE USING gist (offer_id WITH =, tstzrange(starts_at, ends_at) WITH &&)`. The `tstzrange … WITH &&` operand is core, but `offer_id WITH =` is not: `offer_id` is `uuid`, core PostgreSQL 16 ships no GiST operator class for that type, and `gist_uuid_ops` arrives only with `btree_gist`. Without the extension, the `pricing` migration fails outright with `data type uuid has no default operator class for access method "gist"`.

`btree_gist` is a bundled contrib module, present in the official `postgres:16-alpine` image and trusted from PostgreSQL 13 onwards, so it needs no custom image and no superuser. **NFR-18 portability caveat:** a managed PostgreSQL that forbids contrib extensions also forbids this constraint. That is the one place where the portability claim carries an asterisk — every other object in the schema is plain ANSI-adjacent PostgreSQL DDL.

---

<a id="github-actions-workflows"></a>
## 3. GitHub Actions workflows

### `db-migrate.yml` — apply / revert

Trigger: `workflow_dispatch` (manual).

```yaml
name: DB Migrate

on:
  workflow_dispatch:
    inputs:
      phase:
        description: "Phase"
        required: true
        type: choice
        options: [phase-1, phase-2]
      direction:
        description: "Direction"
        required: true
        type: choice
        options: [up, down]
      steps:
        description: "Migrations to revert, newest first (ignored for 'up')"
        required: false
        default: "1"
      environment:
        description: "Target environment"
        required: true
        type: choice
        options: [dev, staging, prod]

jobs:
  migrate:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - run: npm ci

      - name: Run migration
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
          DS: migrations/${{ inputs.phase }}/datasource.ts
        run: |
          case "${{ inputs.direction }}" in
            up)
              npx typeorm-ts-node-commonjs migration:run -d "$DS"
              ;;
            down)
              for _ in $(seq 1 ${{ inputs.steps }}); do
                npx typeorm-ts-node-commonjs migration:revert -d "$DS"
              done
              ;;
          esac

      - name: Print migration state
        if: always()
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
          DS: migrations/${{ inputs.phase }}/datasource.ts
        run: npx typeorm-ts-node-commonjs migration:show -d "$DS"
```

The revert loop is not decoration — `migration:revert` undoes exactly one migration per invocation (§2), so reverting three means calling it three times. The loop stops on the first non-zero exit, leaving the database at a known migration rather than half-walked.

### `db-status.yml` — current state

```yaml
name: DB Status

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, staging, prod]
        required: true

jobs:
  status:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'
      - run: npm ci
      - name: phase-1 state
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: npx typeorm-ts-node-commonjs migration:show -d migrations/phase-1/datasource.ts
      - name: phase-2 state
        if: hashFiles('migrations/phase-2/datasource.ts') != ''
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: npx typeorm-ts-node-commonjs migration:show -d migrations/phase-2/datasource.ts
```

---

<a id="github-environments-and-secrets"></a>
## 4. GitHub Environments and secrets

Each environment (`dev`, `staging`, `prod`) is configured as a [GitHub Environment](https://docs.github.com/en/actions/deployment/targeting-different-deployment-environments-with-environment-variables). Each holds one secret:

| Secret | Value shape |
|--------|-------------|
| `DATABASE_URL` | `postgres://user:pass@host:5432/aliceut?sslmode=require` |

**`prod` environment must require manual reviewer approval** before the job executes (Settings → Environments → prod → Required reviewers). This is the primary guard against accidental production migrations.

---

<a id="migration-file-conventions"></a>
## 5. Migration file conventions

### Naming

Three files per migration, sharing one stem:

```
{seq}_{description}.ts        # MigrationInterface shell — reads the two files below
{seq}_{description}.up.sql
{seq}_{description}.down.sql
```

- `seq` — zero-padded 4-digit integer, unique and sequential within the phase directory.
- `description` — snake_case, describes what this migration does.
- Class name — PascalCase of `description`, suffixed with `seq` (`0002_create_users.ts` → `CreateUsers0002`). TypeORM reads the trailing digits as the ordering key, so the class suffix and the filename prefix must agree. As in §2, the ordering key is asserted TypeORM behaviour and is worth confirming once against the installed version; the filename order is what a reader trusts, and the two must not be allowed to disagree.

### SQL rules

| Rule | Rationale |
|------|-----------|
| `CREATE INDEX CONCURRENTLY` on existing tables | Avoids write lock |
| `DROP TABLE / DROP INDEX` always with `IF EXISTS` | Makes `down.sql` idempotent |
| New columns must be nullable or have a `DEFAULT` | `NOT NULL` without default rewrites all rows |
| Schema changes and data backfills in separate numbered migrations | Shorter transactions, independent rollback |
| Never edit a file already applied to staging or prod | Use a new numbered migration instead |
| An index a documented query depends on ships in the migration that creates its table | A deferred index is a plan regression that appears in production and in no review |
| `CREATE TYPE` precedes the first table whose column uses it, in the same migration | Postgres resolves the column type at `CREATE TABLE` time; a type created afterwards fails the apply |

**Two phase-1 migrations those last two rules decide, because both are easy to write in the wrong order.** The `identity` migration creates `identity.portal_type` as an enum of `BUYER`, `SELLER`, `ADMIN` before the `identity.password_reset_token` table, whose `portal` column is required with no default — the token is only redeemable on the portal that issued it ([data-model-erd.md](../phase-1/technical-design/data-model-erd.md#table-identity-password-reset-token)). The `notifications` migration creates the partial index `(recipient_user_id, read_at) WHERE read_at IS NULL` on `notifications.in_app_notification` in the same migration as the table ([data-model-erd.md](../phase-1/technical-design/data-model-erd.md#table-notifications-in-app-notification)). That index is not an optimisation to add later: the unread badge is a `COUNT(*)` served entirely by it, and the predicate is the point — a plain composite index on the same two columns would index every notification ever created and grow without bound.

**`CREATE INDEX CONCURRENTLY` needs its own untransacted migration.** TypeORM wraps each migration in a transaction by default, and PostgreSQL rejects `CREATE INDEX CONCURRENTLY` inside a transaction block. A migration that uses it holds nothing else, and is applied with `migration:run --transaction none`; state that requirement in a comment at the top of its `.up.sql`. Index creation in the initial phase-1 sequence runs against empty tables, so plain `CREATE INDEX` is correct there and this only applies to indexes added to populated tables later.

### Example pair

```sql
-- migrations/phase-1/0005_create_offers.up.sql
CREATE TABLE offers (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  UUID        NOT NULL REFERENCES products(id),
  seller_id   UUID        NOT NULL REFERENCES users(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_offers_product_id ON offers (product_id);
CREATE INDEX idx_offers_seller_id  ON offers (seller_id);
```

```sql
-- migrations/phase-1/0005_create_offers.down.sql
DROP INDEX IF EXISTS idx_offers_seller_id;
DROP INDEX IF EXISTS idx_offers_product_id;
DROP TABLE IF EXISTS offers;
```
