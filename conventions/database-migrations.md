# Database Migrations Convention

**Status:** Draft  
**Source of truth:** [BRD v1.1](../phase-1/requirements/BRD.md), [module-architecture](module-architecture.md)

Migration scripts live in a separate utility pipeline repository — **`alice-ut-utility-pipeline`** — not in the application source tree. The application repo (`alice-ut`) never runs migrations automatically; all migrations are intentional, operator-triggered actions.

---

## 1. Utility pipeline repo layout

```
alice-ut-utility-pipeline/
├── .github/
│   └── workflows/
│       ├── db-migrate.yml          # apply / rollback / goto a version
│       └── db-status.yml           # show current migration state per environment
├── database/
│   ├── phase-1/
│   │   ├── 0001_create_extensions.up.sql
│   │   ├── 0001_create_extensions.down.sql
│   │   ├── 0002_create_users.up.sql
│   │   ├── 0002_create_users.down.sql
│   │   └── ...
│   └── phase-2/
│       ├── 0001_add_k8s_config.up.sql
│       ├── 0001_add_k8s_config.down.sql
│       └── ...
└── README.md
```

Each phase directory is an independent migration sequence starting at `0001`. Other utility workflows (e.g. seed data, infra scripts) live in sibling directories under the repo root — `database/` is specifically for schema migrations.

---

## 2. Execution engine

[**golang-migrate**](https://github.com/golang-migrate/migrate) CLI — single static binary, no runtime dependency. Reads raw `.sql` files natively. Tracks applied migrations in a Postgres table.

State table per phase (prevents cross-phase interference):

| Phase | Tracking table |
|-------|----------------|
| phase-1 | `schema_migrations_phase1` |
| phase-2 | `schema_migrations_phase2` |

```bash
# Apply all pending migrations in phase-1
migrate -path database/phase-1 \
        -database "$DATABASE_URL" \
        -table schema_migrations_phase1 up

# Roll back 1 migration
migrate -path database/phase-1 \
        -database "$DATABASE_URL" \
        -table schema_migrations_phase1 down 1

# Jump to a specific version
migrate -path database/phase-1 \
        -database "$DATABASE_URL" \
        -table schema_migrations_phase1 goto 5

# Show current version
migrate -path database/phase-1 \
        -database "$DATABASE_URL" \
        -table schema_migrations_phase1 version
```

---

## 3. GitHub Actions workflows

### `db-migrate.yml` — apply / rollback

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
        options: [up, down, goto]
      version:
        description: "Version (step count for 'down', target version for 'goto'; ignored for 'up')"
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

      - name: Install golang-migrate
        run: |
          curl -L https://github.com/golang-migrate/migrate/releases/download/v4.18.1/migrate.linux-amd64.tar.gz \
            | tar xvz
          sudo mv migrate /usr/local/bin/

      - name: Run migration
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: |
          TABLE="schema_migrations_$(echo '${{ inputs.phase }}' | tr '-' '_')"
          case "${{ inputs.direction }}" in
            up)
              migrate -path "database/${{ inputs.phase }}" -database "$DATABASE_URL" -table "$TABLE" up
              ;;
            down)
              migrate -path "database/${{ inputs.phase }}" -database "$DATABASE_URL" -table "$TABLE" down ${{ inputs.version }}
              ;;
            goto)
              migrate -path "database/${{ inputs.phase }}" -database "$DATABASE_URL" -table "$TABLE" goto ${{ inputs.version }}
              ;;
          esac

      - name: Print current version
        if: always()
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: |
          TABLE="schema_migrations_$(echo '${{ inputs.phase }}' | tr '-' '_')"
          migrate -path "database/${{ inputs.phase }}" -database "$DATABASE_URL" -table "$TABLE" version
```

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
      - name: Install golang-migrate
        run: |
          curl -L https://github.com/golang-migrate/migrate/releases/download/v4.18.1/migrate.linux-amd64.tar.gz \
            | tar xvz && sudo mv migrate /usr/local/bin/
      - name: phase-1 version
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: migrate -path database/phase-1 -database "$DATABASE_URL" -table schema_migrations_phase1 version
      - name: phase-2 version
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: migrate -path database/phase-2 -database "$DATABASE_URL" -table schema_migrations_phase2 version
```

---

## 4. GitHub Environments and secrets

Each environment (`dev`, `staging`, `prod`) is configured as a [GitHub Environment](https://docs.github.com/en/actions/deployment/targeting-different-deployment-environments-with-environment-variables). Each holds one secret:

| Secret | Value shape |
|--------|-------------|
| `DATABASE_URL` | `postgres://user:pass@host:5432/aliceut?sslmode=require` |

**`prod` environment must require manual reviewer approval** before the job executes (Settings → Environments → prod → Required reviewers). This is the primary guard against accidental production migrations.

---

## 5. Migration file conventions

### Naming

```
{seq}_{description}.up.sql
{seq}_{description}.down.sql
```

- `seq` — zero-padded 4-digit integer, unique and sequential within the phase directory.
- `description` — snake_case, describes what this migration does.

### SQL rules

| Rule | Rationale |
|------|-----------|
| `CREATE INDEX CONCURRENTLY` on existing tables | Avoids write lock |
| `DROP TABLE / DROP INDEX` always with `IF EXISTS` | Makes `down.sql` idempotent |
| New columns must be nullable or have a `DEFAULT` | `NOT NULL` without default rewrites all rows |
| Schema changes and data backfills in separate numbered migrations | Shorter transactions, independent rollback |
| Never edit a file already applied to staging or prod | Use a new numbered migration instead |

### Example pair

```sql
-- database/phase-1/0005_create_offers.up.sql
CREATE TABLE offers (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  UUID        NOT NULL REFERENCES products(id),
  seller_id   UUID        NOT NULL REFERENCES users(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX CONCURRENTLY idx_offers_product_id ON offers (product_id);
CREATE INDEX CONCURRENTLY idx_offers_seller_id  ON offers (seller_id);
```

```sql
-- database/phase-1/0005_create_offers.down.sql
DROP INDEX IF EXISTS idx_offers_seller_id;
DROP INDEX IF EXISTS idx_offers_product_id;
DROP TABLE IF EXISTS offers;
```
