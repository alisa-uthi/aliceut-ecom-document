# Docker Compose Topology — Phase 1

**Status:** Complete  
**Source of truth:** [BRD v1.4 §12](../requirements/BRD.md), [architecture-overview §8](../../architecture-overview.md)

---

## Summary

- [1. Repository layout](#repository-layout)
- [2. Service inventory](#service-inventory)
- [3. Networks](#networks)
- [4. Volumes](#volumes)
- [5. `.env.example`](#env-example)
- [6. `docker-compose.yml`](#docker-compose-yml)
- [7. Backend Dockerfile (multi-stage, multi-target)](#backend-dockerfile)
- [8. nginx proxy configuration (buyer.conf example)](#nginx-proxy-configuration)
- [9. Startup order and dependency graph](#startup-order)
- [10. Prerequisites and development workflow](#development-workflow)
- [11. Port summary](#port-summary)
- [12. Operations and alerting](#operations-and-alerting)
- [13. Design Decisions](#design-decisions)

<a id="repository-layout"></a>
## 1. Repository layout

The project is four sibling repositories under one parent directory. `docker-compose.yml` lives in the infrastructure repository and is always invoked with its working directory at that repository's root — that is what makes every `../` path in this document resolve.

```
D:/Github/aliceut-ecom/
├── aliceut-ecom-document/     requirements, technical design, UI design (this repository)
├── aliceut-ecom-backend/      Nx monorepo: apps/api, apps/workers, libs/<module>, migrations/
├── aliceut-ecom-frontend/     Nx monorepo: apps/{buyer,seller,admin}-app, nginx/*.conf, dist/
└── aliceut-ecom-infra/        docker-compose.yml, .env, config/
```

| Path in compose | Resolves to |
|---|---|
| `../aliceut-ecom-backend` | `api` and `workers` build context |
| `../aliceut-ecom-backend/migrations/init` | first-boot Postgres bootstrap (see §6, `postgres`) |
| `../aliceut-ecom-frontend/dist/{buyer,seller,admin}-app` | built Angular bundles served by the nginx containers |
| `../aliceut-ecom-frontend/nginx/{buyer,seller,admin}.conf` | per-portal nginx server blocks |
| `./config/alloy/config.alloy` | Alloy collector config ([observability.md §5](../../conventions/observability.md#alloy-config)) |
| `./config/prometheus/prometheus.yml` | Prometheus scrape config |
| `./config/grafana/provisioning/` | Grafana datasource and dashboard provisioning |

All four directories are created by the developer as siblings; compose does not create them. Run every `docker compose` command from `aliceut-ecom-infra/`.

The three `./config/` paths resolve inside the infra repository itself, not a sibling. They are committed there, so a clone plus `docker compose up` yields a query-ready Grafana with no manual UI setup.

---

<a id="service-inventory"></a>
## 2. Service inventory

**Twenty services.** Every one of them starts in V1; nothing in this file is staged for a later phase.

| Service | Image / Build | Host port | Purpose |
|---------|--------------|-----------|---------|
| `buyer-nginx` | `nginx:1.27-alpine` (+ built Angular dist) | `4200:80` | Serves buyer Angular app |
| `seller-nginx` | `nginx:1.27-alpine` (+ built Angular dist) | `4201:80` | Serves seller Angular app |
| `admin-nginx` | `nginx:1.27-alpine` (+ built Angular dist) | `4202:80` | Serves admin Angular app |
| `api` | `../aliceut-ecom-backend` (Dockerfile) | `3000:3000` | NestJS HTTP API |
| `workers` | `../aliceut-ecom-backend` (Dockerfile, worker entrypoint) | — | Outbox relay + Kafka consumers |
| `postgres` | `postgres:16-alpine` | `5432:5432` | Primary PostgreSQL database |
| `mongodb` | `mongo:7` | `27017:27017` | Audit and activity log store |
| `elasticsearch` | `docker.elastic.co/elasticsearch/elasticsearch:8.14.0` | `9200:9200` | Search index |
| `kafka` | `apache/kafka:3.8.0` | `29092:29092` | Kafka broker (KRaft mode); `kafka:9092` in-network, `localhost:29092` from the host |
| `kafka-init` | `apache/kafka:3.8.0` | — | One-shot topic provisioning: creates every event topic in [kafka-events.md § 1](./kafka-events.md#topic-summary), one DLQ per consumer group, and `email.outbound.dlq`, each with its documented retention, partition count and replication factor |
| `schema-registry` | `confluentinc/cp-schema-registry:7.7.0` | `8081:8081` | Confluent Schema Registry (Community) |
| `kafka-ui` | `provectus/kafka-ui:v0.7.2` | `8080:8080` | Kafka management UI |
| `minio` | `minio/minio:RELEASE.2024-11-07T00-52-20Z` | `9000:9000`, `9001:9001` | S3-compatible object storage (product images, KYC docs, user assets) |
| `minio-init` | `minio/mc:latest` | — | One-shot bucket creation init container — the one unpinned tag here, see below |
| `redis` | `redis:7-alpine` | `6379:6379` | JWT revocation key store (`auth:revoke_before:{userId}` keys, TTL 960 s) |
| `mailpit` | `axllent/mailpit:v1.41.1` | `8025:8025`, `1025:1025` | SMTP sink and web inbox — the target of every `ET-*` email the notification consumer sends |
| `alloy` | `grafana/alloy:v1.19.2` | `12345:12345` | Unified collector: tails container logs, forwards to Loki |
| `loki` | `grafana/loki:3.7.7` | `3100:3100` | Log aggregation and LogQL query API |
| `prometheus` | `prom/prometheus:v3.14.0` | `9090:9090` | Metrics scrape, including the outbox-lag gauge (§12) |
| `grafana` | `grafana/grafana:11.6.16` | `3200:3000` | Dashboards over Loki + Prometheus |

The last four are the observability stack specified by [conventions/observability.md §5-6](../../conventions/observability.md#docker-compose); that document owns their configuration and this one owns their wiring. Image tags are pinned to an exact patch release rather than a floating `latest` or `3.x` — a topology whose behaviour changes on `docker compose pull` is not reproducible.

**`minio-init` is the one exception, and it is the only image where `latest` is tolerable.** It is a one-shot container that runs `mc mb --ignore-existing` against a bucket list and exits; it serves no request, holds no state, and is not running when anything else talks to MinIO, so a newer `mc` changes the topology's behaviour only if bucket creation itself breaks — which fails loudly at start-up rather than silently at runtime. Pinning it is still the better default: replace `latest` with the `RELEASE.*` tag published alongside the `minio/minio` version above when one is confirmed against the registry. Every other service here carries an exact tag and must keep one.

---

<a id="networks"></a>
## 3. Networks

```
aliceut_frontend   buyer-nginx, seller-nginx, admin-nginx (no backend access)
aliceut_backend    api, workers, postgres, mongodb, elasticsearch, kafka, kafka-init,
                   schema-registry, kafka-ui, minio, minio-init, redis, mailpit,
                   alloy, loki, prometheus, grafana
```

nginx containers are on **both** networks; they proxy `/api/*` to `api:3000`.  
`api` and `workers` are on `aliceut_backend` only.  
`kafka-ui` is on `aliceut_backend` only (not exposed to browser directly in production, but exposed via host port for development).  
`mailpit` is on `aliceut_backend` so `api` and `workers` can reach `mailpit:1025`.  
The observability stack shares `aliceut_backend` rather than getting a network of its own: Prometheus must scrape `api:3000` and `workers:3001`, and Grafana must reach `loki:3100` and `prometheus:9090`. A separate network would need every one of those crossings declared anyway.

---

<a id="volumes"></a>
## 4. Volumes

| Volume | Used by | Purpose |
|--------|---------|---------|
| `postgres_data` | postgres | Persistent PostgreSQL data |
| `mongodb_data` | mongodb | Persistent MongoDB data |
| `elasticsearch_data` | elasticsearch | Persistent search index |
| `kafka_data` | kafka | Persistent Kafka log segments |
| `minio_data` | minio | Persistent object storage data |
| `loki_data` | loki | Persistent log chunks and index |
| `prometheus_data` | prometheus | Persistent metrics TSDB |
| `grafana_data` | grafana | Grafana's own SQLite: saved dashboards, users, preferences |

`mailpit` and `redis` are deliberately volume-less. Mailpit holds captured mail in memory, so a restart empties the inbox — that is correct for a development sink, where stale verification links are a hazard rather than an asset.

---

<a id="env-example"></a>
## 5. `.env.example`

Variable names follow the required checklist in [conventions/backend-coding-standards.md §6.2](../../conventions/backend-coding-standards.md). `POSTGRES_*` and `MONGO_INITDB_*` are consumed by the database images themselves; the application reads `DATABASE_URL` and `MONGODB_URI`.

```dotenv
# ── Application ──────────────────────────────────────────
NODE_ENV=development
PORT=3000
PORT_WORKERS=3001
SERVICE_NAME=aliceut-api
LOG_LEVEL=info
LOG_MAX_BODY_BYTES=4096
# Comma-separated, case- and separator-insensitive. Overrides the built-in
# DEFAULT_SENSITIVE_KEYS list entirely — see conventions/observability.md § 2 (config/log.config.ts)
# for the list. Any override must keep at minimum password, token, authorization,
# cookie, taxid, secret and refreshtoken.
LOG_SENSITIVE_KEYS=password,newpassword,currentpassword,passwordhash,token,accesstoken,refreshtoken,idtoken,verificationtoken,resettoken,secret,apikey,privatekey,clientsecret,authorization,cookie,ssn,cardnumber,cvv,taxid

# ── JWT ──────────────────────────────────────────────────
JWT_SECRET=change_me_to_a_32_char_random_string
JWT_ACCESS_TTL_SECONDS=900
JWT_REFRESH_TTL_SECONDS=604800

# ── PostgreSQL ───────────────────────────────────────────
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=aliceut
POSTGRES_USER=aliceut_app
POSTGRES_PASSWORD=change_me_postgres
DATABASE_URL=postgresql://aliceut_app:change_me_postgres@postgres:5432/aliceut

# ── MongoDB ──────────────────────────────────────────────
MONGODB_URI=mongodb://root:change_me_mongodb@mongodb:27017/aliceut_audit?authSource=admin
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD=change_me_mongodb

# ── Elasticsearch ────────────────────────────────────────
ELASTICSEARCH_NODE=http://elasticsearch:9200

# ── Redis ──────────────────────────────────────────────────
REDIS_URL=redis://redis:6379
REDIS_HOST=redis
REDIS_PORT=6379

# ── Kafka ────────────────────────────────────────────────
KAFKA_BROKERS=kafka:9092
SCHEMA_REGISTRY_URL=http://schema-registry:8081
KAFKA_CLIENT_ID=aliceut-api
KAFKA_WORKER_CLIENT_ID=aliceut-workers
# Topic retention applied by kafka-init at creation time (§6). 7 days for every topic,
# 24 hours for the three auth.* topics, whose payloads carry a raw single-use credential
# token. Raising the first without raising PROCESSED_EVENT_RETENTION_DAYS (14) breaks the
# dedupe ordering the DLQ replay depends on.
KAFKA_TOPIC_RETENTION_MS=604800000
KAFKA_AUTH_TOPIC_RETENTION_MS=86400000

# ── Outbox relay (workers) ───────────────────────────────
OUTBOX_POLL_INTERVAL_MS=500

# ── OAuth ────────────────────────────────────────────────
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_CALLBACK_URL=http://localhost:3000/api/v1/auth/google/callback

FACEBOOK_APP_ID=
FACEBOOK_APP_SECRET=
FACEBOOK_CALLBACK_URL=http://localhost:3000/api/v1/auth/facebook/callback

# ── MinIO (object storage) ───────────────────────────────
MINIO_ENDPOINT=http://minio:9000
MINIO_ROOT_USER=minio_admin
MINIO_ROOT_PASSWORD=change_me_minio
MINIO_ACCESS_KEY=aliceut_app
MINIO_SECRET_KEY=change_me_minio_app
MINIO_PRODUCT_IMAGES_BUCKET=product-images
MINIO_KYC_DOCS_BUCKET=kyc-documents
MINIO_USER_ASSETS_BUCKET=user-assets
AES_ENCRYPTION_KEY=change_me_to_a_32_byte_hex_key
# KYC upload limits, enforced by api on the seller upload route. Size and count only —
# no content scanning happens in V1 (§12, accepted risk).
KYC_UPLOAD_MAX_BYTES=10485760
KYC_UPLOAD_MAX_FILES=5

# ── FX rates ─────────────────────────────────────────────
FX_PROVIDER_URL=https://api.exchangerate.host/latest
# Read-time staleness bound, in whole hours. Past it the API still returns the rate,
# marked stale, and the UI shows an indicative-rate note — it is not a refusal
# (cleanup-jobs.md, "Stores with no job here"). Integer, not a "24h" duration string:
# one duration syntax per repo, and every other variable here is _MS, _DAYS or _HOURS.
FX_STALE_AFTER_HOURS=24
# Refresh schedule for the same table. Declared with the other crons below, since it
# is a workers job; the two values are independent — refreshing hourly does not stop a
# rate going stale if the provider is unreachable for a day.

# ── Email (SMTP → Mailpit) ────────────────────────────────
# Mailpit accepts unauthenticated plaintext SMTP, so user and password stay empty
# in development. Both are required against any real relay.
SMTP_HOST=mailpit
SMTP_PORT=1025
SMTP_USER=
SMTP_PASS=
SMTP_SECURE=false
SMTP_FROM=noreply@aliceut.dev
MAILPIT_WEB_URL=http://localhost:8025

# ── App URLs (for email links + CORS) ────────────────────
BUYER_APP_URL=http://localhost:4200
SELLER_APP_URL=http://localhost:4201
ADMIN_APP_URL=http://localhost:4202

# ── Inventory ────────────────────────────────────────────
LOW_STOCK_THRESHOLD_DEFAULT=5
INVENTORY_RESERVATION_TTL_MINUTES=15

# ── Moderation ───────────────────────────────────────────
KEYWORD_BLOCKLIST_CACHE_TTL=60

# ── Scheduled jobs (workers) ─────────────────────────────
# Every interval, TTL, batch size and retention window is env-driven; no schedule
# literal is hardcoded. Full per-job list with cron expression, retention window and
# advisory-lock key: cleanup-jobs.md. All cron expressions are UTC, five-field, and
# written UNQUOTED here — docker-compose's .env parser keeps quotes as literal
# characters, and @nestjs/schedule rejects '0 3 * * *' with the quotes attached.
DELIVERY_MOCK_INTERVAL_MS=60000
AUTO_REFUND_INTERVAL_MS=3600000
RESERVATION_EXPIRY_INTERVAL_MS=300000
SUSPENSION_EXPIRY_CRON=0 * * * *
# FX rate refresh from FX_PROVIDER_URL, upserting pricing.fx_rate in place. Hourly is
# a BRD §12 commitment, not a tuning choice. Pairs with FX_STALE_AFTER_HOURS above.
FX_RATE_REFRESH_CRON=0 * * * *
# ET-09 listing-removed digest. 23:00 UTC is a product choice about when a seller
# receives the mail, not a stagger — the digest is not a retention delete, which is
# why it sits outside the 03:00 sequence below rather than in it. The digest
# scheduler is the only writer and the only deleter of its table; no cleanup job
# touches it, and none may be added (cleanup-jobs.md, "Stores with no job here").
NOTIFICATION_DIGEST_CRON=0 23 * * *
# Nightly deletes are staggered five minutes apart so they never overlap on one
# connection pool. Keep the offsets if you change the hour.
CLEANUP_REFRESH_SESSIONS_CRON=0 3 * * *
CLEANUP_EMAIL_VERIFICATION_TOKENS_CRON=5 3 * * *
CLEANUP_PASSWORD_RESET_TOKENS_CRON=10 3 * * *
CLEANUP_STOCK_RESERVATIONS_CRON=15 3 * * *
CLEANUP_IDEMPOTENCY_KEYS_CRON=20 3 * * *
CLEANUP_OUTBOX_EVENTS_CRON=25 3 * * *
CLEANUP_PROCESSED_EVENTS_CRON=30 3 * * *
CLEANUP_IN_APP_NOTIFICATIONS_CRON=35 3 * * *
# One batch size shared by every cleanup job, not one per job.
CLEANUP_BATCH_SIZE=1000
# Retention windows. Three of these are coupled to other values and are not free
# to lower in isolation:
#   REFRESH_SESSION_CLEANUP_BUFFER_DAYS is ADDED to JWT_REFRESH_TTL_SECONDS above,
#     never used alone. At 0 a stolen refresh token stops being detectable as stolen
#     the moment it expires.
#   PROCESSED_EVENT_RETENTION_DAYS must be STRICTLY GREATER than Kafka log retention,
#     which the kafka service pins at KAFKA_LOG_RETENTION_HOURS=168 (7 days). 14 > 7.
#     A dedupe row exists to make a REDELIVERY idempotent, and redelivery has two
#     sources: a rebalance or uncommitted offset, which replays within minutes; and a
#     deliberate offset reset or DLQ replay, which can replay anything still in the
#     log. So the row must outlive the message. Equal values do not satisfy this —
#     they race, and the loser applies the side effect twice.
#   IN_APP_NOTIFICATION_READ_RETENTION_DAYS must stay well above
#     PROCESSED_EVENT_RETENTION_DAYS: deleting a read notification frees its
#     (recipient_user_id, source_event_id) unique pair, which is only safe once
#     redelivery is impossible.
REFRESH_SESSION_CLEANUP_BUFFER_DAYS=7
STOCK_RESERVATION_RETENTION_DAYS=30
OUTBOX_PUBLISHED_RETENTION_DAYS=7
OUTBOX_FAILED_RETENTION_DAYS=30
PROCESSED_EVENT_RETENTION_DAYS=14
IN_APP_NOTIFICATION_READ_RETENTION_DAYS=90
# Written by the checkout path on insert, honoured by the cleanup job on delete —
# so it belongs to api as well as workers, unlike everything else in this group.
IDEMPOTENCY_KEY_TTL_HOURS=24
# Staleness bound on the scheduler health signal: 3x the shortest configured job
# interval, which is DELIVERY_MOCK_INTERVAL_MS at 60 s. A dead @nestjs/schedule
# timer is invisible from outside the process; this is what makes it a probe failure.
# OUTBOX_POLL_INTERVAL_MS (500 ms) is deliberately not the floor: the relay is not a
# scheduled job (cleanup-jobs.md). Counting it would make this bound 360x the interval
# it is meant to police, which detects nothing — so the exclusion is not bookkeeping.
WORKERS_SCHEDULER_STALE_MS=180000

# ── Observability ────────────────────────────────────────
# LOG_LEVEL and SERVICE_NAME above feed the same pipeline; Alloy reads them off the
# JSON log line, not from env. METRICS_PATH is what Prometheus scrapes on api and
# workers. Label cardinality rules: observability.md §5.
METRICS_PATH=/metrics
LOKI_URL=http://loki:3100
PROMETHEUS_URL=http://prometheus:9090
GRAFANA_URL=http://localhost:3200
GF_AUTH_ANONYMOUS_ENABLED=true
# Viewer, never Admin. An anonymous Admin can edit datasources, and a Grafana
# datasource is a credentialed connection to Loki and Prometheus — so Admin here is a
# path to repointing where the platform's logs are read from, not just dashboard
# vandalism. Editing is what GF_SECURITY_ADMIN_PASSWORD is for.
GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
GF_SECURITY_ADMIN_PASSWORD=change_me_grafana

# ── Seed ─────────────────────────────────────────────────
SEED_ADMIN_EMAIL=admin@aliceut.dev
SEED_ADMIN_PASSWORD=change_me_seed_admin
```

`GF_AUTH_ANONYMOUS_ENABLED=true` is a development-only convenience carried over from [observability.md §6](../../conventions/observability.md#docker-compose) — it makes Grafana query-ready with no login. Any deployed environment must set it to `false` and rely on `GF_SECURITY_ADMIN_PASSWORD`. The anonymous role is **`Viewer`**: opening a dashboard without logging in is the point of a development stack, editing a datasource is not, and on a published port those two are the same permission if the role is `Admin`.

---

<a id="docker-compose-yml"></a>
## 6. `docker-compose.yml`

Lives at `aliceut-ecom-infra/docker-compose.yml` (§1). Compose v2 — no top-level `version:` key.

```yaml
networks:
  aliceut_frontend:
    driver: bridge
  aliceut_backend:
    driver: bridge

volumes:
  postgres_data:
  mongodb_data:
  elasticsearch_data:
  kafka_data:
  minio_data:
  loki_data:
  prometheus_data:
  grafana_data:

services:

  # ── Frontend nginx containers ────────────────────────────

  buyer-nginx:
    image: nginx:1.27-alpine
    container_name: aliceut_buyer_nginx
    restart: unless-stopped
    ports:
      - "4200:80"
    volumes:
      - ../aliceut-ecom-frontend/dist/buyer-app:/usr/share/nginx/html:ro
      - ../aliceut-ecom-frontend/nginx/buyer.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - aliceut_frontend
      - aliceut_backend
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:80/"]
      interval: 30s
      timeout: 5s
      retries: 3

  seller-nginx:
    image: nginx:1.27-alpine
    container_name: aliceut_seller_nginx
    restart: unless-stopped
    ports:
      - "4201:80"
    volumes:
      - ../aliceut-ecom-frontend/dist/seller-app:/usr/share/nginx/html:ro
      - ../aliceut-ecom-frontend/nginx/seller.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - aliceut_frontend
      - aliceut_backend
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:80/"]
      interval: 30s
      timeout: 5s
      retries: 3

  admin-nginx:
    image: nginx:1.27-alpine
    container_name: aliceut_admin_nginx
    restart: unless-stopped
    ports:
      - "4202:80"
    volumes:
      - ../aliceut-ecom-frontend/dist/admin-app:/usr/share/nginx/html:ro
      - ../aliceut-ecom-frontend/nginx/admin.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - aliceut_frontend
      - aliceut_backend
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:80/"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ── NestJS API ───────────────────────────────────────────

  api:
    build:
      context: ../aliceut-ecom-backend
      dockerfile: Dockerfile
      target: api
    container_name: aliceut_api
    restart: unless-stopped
    ports:
      - "3000:3000"
    env_file: .env
    environment:
      NODE_ENV: ${NODE_ENV:-development}
      SERVICE_NAME: aliceut-api
      DATABASE_URL: postgresql://${POSTGRES_USER:-aliceut_app}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-aliceut}
      MONGODB_URI: mongodb://${MONGO_INITDB_ROOT_USERNAME:-root}:${MONGO_INITDB_ROOT_PASSWORD}@mongodb:27017/aliceut_audit?authSource=admin
      ELASTICSEARCH_NODE: http://elasticsearch:9200
      KAFKA_BROKERS: kafka:9092
      SCHEMA_REGISTRY_URL: http://schema-registry:8081
      REDIS_URL: redis://redis:6379
      MINIO_ENDPOINT: http://minio:9000
      # Written by checkout when it inserts the idempotency row and sets expires_at;
      # the cleanup job in workers only honours the column it finds. The value has to
      # be on both services or nothing sets a TTL for the job to act on.
      IDEMPOTENCY_KEY_TTL_HOURS: ${IDEMPOTENCY_KEY_TTL_HOURS:-24}
      KYC_UPLOAD_MAX_BYTES: ${KYC_UPLOAD_MAX_BYTES:-10485760}
      KYC_UPLOAD_MAX_FILES: ${KYC_UPLOAD_MAX_FILES:-5}
      # Read-time staleness bound on pricing.fx_rate. api-only — the refresh that
      # writes the table runs in workers, which is where FX_PROVIDER_URL lives.
      FX_STALE_AFTER_HOURS: ${FX_STALE_AFTER_HOURS:-24}
      METRICS_PATH: ${METRICS_PATH:-/metrics}
    networks:
      - aliceut_backend
    depends_on:
      postgres:
        condition: service_healthy
      mongodb:
        condition: service_healthy
      elasticsearch:
        condition: service_healthy
      kafka:
        condition: service_healthy
      schema-registry:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy
      minio-init:
        condition: service_completed_successfully
      kafka-init:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # ── NestJS Workers ───────────────────────────────────────

  workers:
    build:
      context: ../aliceut-ecom-backend
      dockerfile: Dockerfile
      target: workers
    container_name: aliceut_workers
    restart: unless-stopped
    env_file: .env
    environment:
      NODE_ENV: ${NODE_ENV:-development}
      SERVICE_NAME: aliceut-workers
      PORT_WORKERS: ${PORT_WORKERS:-3001}
      DATABASE_URL: postgresql://${POSTGRES_USER:-aliceut_app}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-aliceut}
      MONGODB_URI: mongodb://${MONGO_INITDB_ROOT_USERNAME:-root}:${MONGO_INITDB_ROOT_PASSWORD}@mongodb:27017/aliceut_audit?authSource=admin
      ELASTICSEARCH_NODE: http://elasticsearch:9200
      KAFKA_BROKERS: kafka:9092
      SCHEMA_REGISTRY_URL: http://schema-registry:8081
      # Every ET-* email leaves from here: notifications are Kafka consumers, never
      # inline in an HTTP handler, so api carries no SMTP config at all.
      SMTP_HOST: ${SMTP_HOST:-mailpit}
      SMTP_PORT: ${SMTP_PORT:-1025}
      SMTP_SECURE: ${SMTP_SECURE:-false}
      SMTP_FROM: ${SMTP_FROM:-noreply@aliceut.dev}
      # Scheduled-job tuning. Every interval, cron, batch size and retention window
      # the jobs read is env-driven (§5); the defaults here are the committed ones,
      # so a missing .env still boots with the documented behaviour. Each cron value
      # is quoted: the default contains spaces and asterisks, and unquoted YAML would
      # not read it as a single scalar.
      DELIVERY_MOCK_INTERVAL_MS: ${DELIVERY_MOCK_INTERVAL_MS:-60000}
      AUTO_REFUND_INTERVAL_MS: ${AUTO_REFUND_INTERVAL_MS:-3600000}
      RESERVATION_EXPIRY_INTERVAL_MS: ${RESERVATION_EXPIRY_INTERVAL_MS:-300000}
      SUSPENSION_EXPIRY_CRON: "${SUSPENSION_EXPIRY_CRON:-0 * * * *}"
      NOTIFICATION_DIGEST_CRON: "${NOTIFICATION_DIGEST_CRON:-0 23 * * *}"
      FX_RATE_REFRESH_CRON: "${FX_RATE_REFRESH_CRON:-0 * * * *}"
      # The provider URL is workers-only: nothing on api fetches a rate. api reads
      # FX_STALE_AFTER_HOURS instead, which is the read-time half of the same table.
      FX_PROVIDER_URL: ${FX_PROVIDER_URL:-https://api.exchangerate.host/latest}
      CLEANUP_REFRESH_SESSIONS_CRON: "${CLEANUP_REFRESH_SESSIONS_CRON:-0 3 * * *}"
      CLEANUP_EMAIL_VERIFICATION_TOKENS_CRON: "${CLEANUP_EMAIL_VERIFICATION_TOKENS_CRON:-5 3 * * *}"
      CLEANUP_PASSWORD_RESET_TOKENS_CRON: "${CLEANUP_PASSWORD_RESET_TOKENS_CRON:-10 3 * * *}"
      CLEANUP_STOCK_RESERVATIONS_CRON: "${CLEANUP_STOCK_RESERVATIONS_CRON:-15 3 * * *}"
      CLEANUP_IDEMPOTENCY_KEYS_CRON: "${CLEANUP_IDEMPOTENCY_KEYS_CRON:-20 3 * * *}"
      CLEANUP_OUTBOX_EVENTS_CRON: "${CLEANUP_OUTBOX_EVENTS_CRON:-25 3 * * *}"
      CLEANUP_PROCESSED_EVENTS_CRON: "${CLEANUP_PROCESSED_EVENTS_CRON:-30 3 * * *}"
      CLEANUP_IN_APP_NOTIFICATIONS_CRON: "${CLEANUP_IN_APP_NOTIFICATIONS_CRON:-35 3 * * *}"
      CLEANUP_BATCH_SIZE: ${CLEANUP_BATCH_SIZE:-1000}
      REFRESH_SESSION_CLEANUP_BUFFER_DAYS: ${REFRESH_SESSION_CLEANUP_BUFFER_DAYS:-7}
      STOCK_RESERVATION_RETENTION_DAYS: ${STOCK_RESERVATION_RETENTION_DAYS:-30}
      IDEMPOTENCY_KEY_TTL_HOURS: ${IDEMPOTENCY_KEY_TTL_HOURS:-24}
      OUTBOX_PUBLISHED_RETENTION_DAYS: ${OUTBOX_PUBLISHED_RETENTION_DAYS:-7}
      OUTBOX_FAILED_RETENTION_DAYS: ${OUTBOX_FAILED_RETENTION_DAYS:-30}
      # 14, not 7: strictly greater than the broker's KAFKA_LOG_RETENTION_HOURS (168 h
      # = 7 days), so a DLQ replay of a week-old message still finds its dedupe row.
      PROCESSED_EVENT_RETENTION_DAYS: ${PROCESSED_EVENT_RETENTION_DAYS:-14}
      IN_APP_NOTIFICATION_READ_RETENTION_DAYS: ${IN_APP_NOTIFICATION_READ_RETENTION_DAYS:-90}
      WORKERS_SCHEDULER_STALE_MS: ${WORKERS_SCHEDULER_STALE_MS:-180000}
      METRICS_PATH: ${METRICS_PATH:-/metrics}
    networks:
      - aliceut_backend
    depends_on:
      postgres:
        condition: service_healthy
      mongodb:
        condition: service_healthy
      kafka:
        condition: service_healthy
      schema-registry:
        condition: service_healthy
      elasticsearch:
        condition: service_healthy
      mailpit:
        condition: service_healthy
      kafka-init:
        condition: service_completed_successfully
    healthcheck:
      # Path is /api/v1/health, not /health: the endpoint sits under the global
      # prefix and has no unversioned alias (api-design/health.md).
      test: ["CMD-SHELL", "node -e \"require('http').get('http://localhost:'+(process.env.PORT_WORKERS||3001)+'/api/v1/health', r => process.exit(r.statusCode === 200 ? 0 : 1))\""]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ── PostgreSQL ───────────────────────────────────────────

  postgres:
    image: postgres:16-alpine
    container_name: aliceut_postgres
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-aliceut}
      POSTGRES_USER: ${POSTGRES_USER:-aliceut_app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      # First-boot only (runs when postgres_data is empty): roles and grants, and
      # nothing else. No schema, no extensions — see §10 for what does not belong here.
      - ../aliceut-ecom-backend/migrations/init:/docker-entrypoint-initdb.d:ro
    networks:
      - aliceut_backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-aliceut_app} -d ${POSTGRES_DB:-aliceut}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

  # ── MongoDB ──────────────────────────────────────────────

  mongodb:
    image: mongo:7
    container_name: aliceut_mongodb
    restart: unless-stopped
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_DATABASE: aliceut_audit
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME:-root}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
    volumes:
      - mongodb_data:/data/db
    networks:
      - aliceut_backend
    healthcheck:
      # $$ escapes compose interpolation so the container shell expands the variable.
      test: ["CMD-SHELL", "mongosh --username \"$$MONGO_INITDB_ROOT_USERNAME\" --password \"$$MONGO_INITDB_ROOT_PASSWORD\" --authenticationDatabase admin --eval \"db.adminCommand('ping')\" --quiet"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 20s

  # ── Elasticsearch ────────────────────────────────────────

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.14.0
    container_name: aliceut_elasticsearch
    restart: unless-stopped
    ports:
      - "9200:9200"
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
      - cluster.name=aliceut-dev
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    networks:
      - aliceut_backend
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://localhost:9200/_cluster/health | grep -q '\"status\":\"green\"\\|\"status\":\"yellow\"'"]
      interval: 20s
      timeout: 10s
      retries: 10
      start_period: 60s

  # ── Kafka (KRaft mode) ───────────────────────────────────

  kafka:
    image: apache/kafka:3.8.0
    container_name: aliceut_kafka
    restart: unless-stopped
    ports:
      - "29092:29092"   # EXTERNAL listener — host tooling only
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      # Two client listeners: INTERNAL for in-network clients (api, workers, schema-registry,
      # kafka-ui), EXTERNAL for host tooling. A single listener breaks one or the other.
      KAFKA_LISTENERS: INTERNAL://0.0.0.0:9092,EXTERNAL://0.0.0.0:29092,CONTROLLER://0.0.0.0:9093
      KAFKA_ADVERTISED_LISTENERS: INTERNAL://kafka:9092,EXTERNAL://localhost:29092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      KAFKA_HEAP_OPTS: "-Xms512m -Xmx512m"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      # Off, deliberately. An auto-created topic takes the broker's defaults, and the
      # broker default retention is 7 days — which silently overrides the 24 hours the
      # auth.* topics are specified at, and those payloads carry a raw single-use
      # credential token (kafka-events.md § 3). Every topic is created explicitly by
      # kafka-init below, with its own retention, partition count and replication factor.
      # A producer publishing to a topic nobody created now fails loudly instead of
      # inventing one with the wrong settings.
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"
      # 1, matching every topic in the catalogue, so an internal topic the broker does
      # create for itself is shaped like the rest. It was 3, which contradicted
      # kafka-events.md § 3 for anything auto-created.
      KAFKA_NUM_PARTITIONS: 1
      KAFKA_DEFAULT_REPLICATION_FACTOR: 1
      KAFKA_LOG_DIRS: /var/lib/kafka/data
      # 7 days, pinned rather than inherited from the image default, because
      # PROCESSED_EVENT_RETENTION_DAYS (§5, 14) is specified as strictly greater than
      # this figure and a constraint against an unstated default is not a constraint.
      # Raising this without raising that one lets a DLQ replay of an old message find
      # no dedupe row and apply its side effect a second time. Deliberately a literal,
      # not ${...}: an .env override could break the ordering silently.
      KAFKA_LOG_RETENTION_HOURS: 168
      CLUSTER_ID: MkU3OEVBNTcwNTJENDM2Qk
    volumes:
      - kafka_data:/var/lib/kafka/data
    networks:
      - aliceut_backend
    healthcheck:
      test: ["CMD-SHELL", "/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 > /dev/null 2>&1"]
      interval: 20s
      timeout: 10s
      retries: 10
      start_period: 30s

  kafka-init:
    image: apache/kafka:3.8.0
    container_name: aliceut_kafka_init
    restart: "no"
    depends_on:
      kafka:
        condition: service_healthy
    networks:
      - aliceut_backend
    environment:
      # 7 days, matching KAFKA_LOG_RETENTION_HOURS above. Both are overridable, and the
      # dedupe window (PROCESSED_EVENT_RETENTION_DAYS, 14) must stay strictly greater.
      KAFKA_TOPIC_RETENTION_MS: ${KAFKA_TOPIC_RETENTION_MS:-604800000}
      # 24 hours. The auth.* payloads carry a raw verification_token / reset_token, whose
      # own TTL is shorter still, so nothing is lost by expiring the message early and the
      # window in which a broker-log reader could replay a live token closes with it.
      KAFKA_AUTH_TOPIC_RETENTION_MS: ${KAFKA_AUTH_TOPIC_RETENTION_MS:-86400000}
    entrypoint: >
      /bin/sh -euc "
        K=/opt/kafka/bin/kafka-topics.sh;
        B=kafka:9092;
        create() {
          $$K --bootstrap-server $$B --create --if-not-exists --topic \"$$1\" \
              --partitions 1 --replication-factor 1 --config retention.ms=\"$$2\";
        };
        STANDARD='seller.kyc.submitted seller.kyc.decided seller.suspended
          seller.suspension_expired seller.reinstated seller.profile_changed
          seller.suspension_amended
          fulfillment.placed fulfillment.shipped fulfillment.delivered
          fulfillment.refunded fulfillment.cancelled fulfillment.refund_suspended_seller
          order.finalized order.completed product.changed offer.changed
          listing.soft_deleted inventory.changed inventory.low_stock
          inventory.reservation_expired fx_rate.updated listing.flagged
          moderation.listing.removed pii.accessed keyword_blocklist.changed';
        AUTH='auth.email_verification_requested auth.password_reset_requested
          auth.password_changed';
        DLQ='notification.kyc-submitted notification.kyc-decided
          notification.seller-suspended notification.seller-reinstated
          notification.suspension-expired notification.fulfillment-placed
          notification.fulfillment-seller-alert notification.fulfillment-shipped
          notification.fulfillment-delivered notification.fulfillment-refunded
          notification.fulfillment-cancelled notification.refund-suspended-seller-buyer
          notification.refund-suspended-seller-seller notification.order-summary
          notification.order-completed notification.low-stock
          notification.listing-flagged notification.listing-removed
          search.product-changed search.offer-changed
          search.inventory-changed search.reservation-expired search.seller-suspended
          search.seller-reinstated search.suspension-expired search.listing-flagged
          search.listing-removed search.listing-soft-deleted
          search.seller-profile-changed search.fx-rate-updated
          inventory.fulfillment-placed inventory.fulfillment-shipped
          inventory.fulfillment-cancelled inventory.fulfillment-refunded
          orders.delivery-tracker platform.audit';
        AUTH_DLQ='notification.email-verification notification.password-reset
          notification.password-changed';
        for t in $$STANDARD; do create \"$$t\" \"$$KAFKA_TOPIC_RETENTION_MS\"; done;
        for t in $$AUTH; do create \"$$t\" \"$$KAFKA_AUTH_TOPIC_RETENTION_MS\"; done;
        for g in $$DLQ; do create \"$$g.dlq\" \"$$KAFKA_TOPIC_RETENTION_MS\"; done;
        for g in $$AUTH_DLQ; do create \"$$g.dlq\" \"$$KAFKA_AUTH_TOPIC_RETENTION_MS\"; done;
        create email.outbound.dlq \"$$KAFKA_TOPIC_RETENTION_MS\";
        echo 'Topics ready: event topics, one dead-letter topic per consumer group, email.outbound.dlq.'
      "

  # ── Confluent Schema Registry ────────────────────────────

  schema-registry:
    image: confluentinc/cp-schema-registry:7.7.0
    container_name: aliceut_schema_registry
    restart: unless-stopped
    ports:
      - "8081:8081"
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: PLAINTEXT://kafka:9092
      SCHEMA_REGISTRY_LISTENERS: http://0.0.0.0:8081
      SCHEMA_REGISTRY_KAFKASTORE_TOPIC: _schemas
      SCHEMA_REGISTRY_DEBUG: "false"
    networks:
      - aliceut_backend
    depends_on:
      kafka:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/subjects"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 30s

  # ── MinIO (object storage) ──────────────────────────────

  minio:
    image: minio/minio:RELEASE.2024-11-07T00-52-20Z
    container_name: aliceut_minio
    restart: unless-stopped
    ports:
      - "9000:9000"   # S3 API
      - "9001:9001"   # MinIO console
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minio_admin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes:
      - minio_data:/data
    networks:
      - aliceut_backend
    healthcheck:
      # The minio server image ships `mc`, not curl.
      test: ["CMD", "mc", "ready", "local"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  minio-init:
    image: minio/mc:latest
    container_name: aliceut_minio_init
    restart: "no"
    depends_on:
      minio:
        condition: service_healthy
    networks:
      - aliceut_backend
    entrypoint: >
      /bin/sh -euc "
        until mc alias set local http://minio:9000 $${MINIO_ROOT_USER} $${MINIO_ROOT_PASSWORD}; do
          echo 'Waiting for MinIO...'; sleep 2;
        done;
        mc mb --ignore-existing local/product-images;
        mc mb --ignore-existing local/kyc-documents;
        mc mb --ignore-existing local/user-assets;
        mc anonymous set download local/product-images;
        if ! mc admin user info local $${MINIO_ACCESS_KEY} > /dev/null 2>&1; then
          mc admin user add local $${MINIO_ACCESS_KEY} $${MINIO_SECRET_KEY};
        fi;
        mc admin policy attach local readwrite --user $${MINIO_ACCESS_KEY} > /dev/null 2>&1 || true;
        echo 'Buckets and application service account ready.'
      "
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minio_admin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      MINIO_ACCESS_KEY: ${MINIO_ACCESS_KEY:-aliceut_app}
      MINIO_SECRET_KEY: ${MINIO_SECRET_KEY}

  # ── Redis ─────────────────────────────────────────────────

  redis:
    image: redis:7-alpine
    container_name: aliceut_redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    # noeviction, not allkeys-lru: this instance also holds the 60-second single-use
    # OAuth authorization code, and an LRU eviction would drop it mid-login with no
    # error. A cache instance that may evict has to be a separate one (BRD §12 #13).
    command: redis-server --appendonly no --maxmemory 256mb --maxmemory-policy noeviction
    networks:
      - aliceut_backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  # ── Kafka UI ─────────────────────────────────────────────

  kafka-ui:
    # Pinned, like every other image in this file. On `latest` the UI's configuration
    # schema can change under a `docker compose pull` on a shared dev machine, and the
    # DLQ alert in §12 is a screen in this container.
    image: provectus/kafka-ui:v0.7.2
    container_name: aliceut_kafka_ui
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: aliceut-dev
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:9092
      KAFKA_CLUSTERS_0_SCHEMAREGISTRY: http://schema-registry:8081
      DYNAMIC_CONFIG_ENABLED: "false"
    networks:
      - aliceut_backend
    depends_on:
      kafka:
        condition: service_healthy
      schema-registry:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ── Mailpit (SMTP sink + web inbox) ──────────────────────

  mailpit:
    image: axllent/mailpit:v1.41.1
    container_name: aliceut_mailpit
    restart: unless-stopped
    ports:
      - "8025:8025"   # web inbox
      - "1025:1025"   # SMTP
    environment:
      MP_MAX_MESSAGES: 500
      MP_SMTP_AUTH_ACCEPT_ANY: 1
      MP_SMTP_AUTH_ALLOW_INSECURE: 1
    networks:
      - aliceut_backend
    healthcheck:
      # The image ships no curl; the binary carries its own readiness subcommand.
      test: ["CMD", "/mailpit", "readyz"]
      interval: 15s
      timeout: 5s
      retries: 5

  # ── Observability: Alloy → Loki / Prometheus → Grafana ───

  alloy:
    image: grafana/alloy:v1.19.2
    container_name: aliceut_alloy
    restart: unless-stopped
    ports:
      - "12345:12345"   # Alloy UI — development only
    volumes:
      - ./config/alloy/config.alloy:/etc/alloy/config.alloy:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      # Log discovery reads the Docker API. On Windows hosts this is the Docker
      # Desktop socket proxied into WSL2; the path inside the container is fixed.
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command: run --server.http.listen-addr=0.0.0.0:12345 /etc/alloy/config.alloy
    networks:
      - aliceut_backend
    depends_on:
      loki:
        condition: service_healthy
    # No healthcheck: the image ships neither wget nor curl, and the Alloy binary has
    # no readiness subcommand. A probe here would be a guess. Alloy failing is visible
    # as an empty Loki result, and its own UI on :12345 reports component health.

  loki:
    image: grafana/loki:3.7.7
    container_name: aliceut_loki
    restart: unless-stopped
    ports:
      # Published because the Playwright post-test log query runs logcli from the
      # host against this API — observability.md §7.
      - "3100:3100"
    volumes:
      - loki_data:/loki
    command: -config.file=/etc/loki/local-config.yaml
    networks:
      - aliceut_backend
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3100/ready"]
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 30s

  prometheus:
    image: prom/prometheus:v3.14.0
    container_name: aliceut_prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - aliceut_backend
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:9090/-/healthy"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 20s

  grafana:
    image: grafana/grafana:11.6.16
    container_name: aliceut_grafana
    restart: unless-stopped
    ports:
      # Host 3200 — host 3000 belongs to api. Grafana's own port stays 3000.
      - "3200:3000"
    environment:
      GF_AUTH_ANONYMOUS_ENABLED: ${GF_AUTH_ANONYMOUS_ENABLED:-true}
      # Viewer, not Admin — an anonymous Admin can rewrite the Loki and Prometheus
      # datasource credentials. See §5 and §13.
      GF_AUTH_ANONYMOUS_ORG_ROLE: ${GF_AUTH_ANONYMOUS_ORG_ROLE:-Viewer}
      GF_SECURITY_ADMIN_PASSWORD: ${GF_SECURITY_ADMIN_PASSWORD}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning:ro
    networks:
      - aliceut_backend
    depends_on:
      loki:
        condition: service_healthy
      prometheus:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
```

---

<a id="backend-dockerfile"></a>
## 7. Backend Dockerfile (multi-stage, multi-target)

Node 22 matches the stack (Angular 22, NestJS 11). The runtime targets copy from `prod-deps`, not from `build`, so devDependencies never reach an image.

```dockerfile
# syntax=docker/dockerfile:1

FROM node:22-alpine AS base
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM base AS build
COPY . .
RUN npm run build

# ── Production dependencies only ─────────────────────────
FROM node:22-alpine AS prod-deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# ── API target ───────────────────────────────────────────
FROM node:22-alpine AS api
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/dist/apps/api ./dist/apps/api
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/package.json .
EXPOSE 3000
CMD ["node", "dist/apps/api/main.js"]

# ── Workers target ───────────────────────────────────────
FROM node:22-alpine AS workers
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/dist/apps/workers ./dist/apps/workers
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/package.json .
CMD ["node", "dist/apps/workers/main.js"]
```

---

<a id="nginx-proxy-configuration"></a>
## 8. nginx proxy configuration (buyer.conf example)

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Angular router history-mode fallback
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy API calls to NestJS
    location /api/ {
        proxy_pass http://api:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
    }

    # Gzip static assets
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    gzip_min_length 1000;

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

`seller.conf` and `admin.conf` follow the same pattern with appropriate `server_name`.

---

<a id="startup-order"></a>
## 9. Startup order and dependency graph

```
postgres ─────────────────────┐
mongodb ──────────────────────┤
elasticsearch ────────────────┤──► api ──► buyer-nginx
kafka ──► kafka-init ─────────┤         ├─ seller-nginx
kafka ──► schema-registry ────┤         └─ admin-nginx
kafka ──► kafka-ui            │
redis ────────────────────────┤
minio ──► minio-init ─────────┤
mailpit ──────────────────────┤──► workers
                              │
schema-registry ──────────────┘

loki ──► alloy
loki ──┐
       ├──► grafana
prometheus ──┘
```

`api` waits for postgres, mongodb, elasticsearch, kafka, schema-registry, redis and minio to report `service_healthy`, and for `minio-init` and `kafka-init` to report `service_completed_successfully` — the application's MinIO service account and the three buckets must exist before the first upload request, and every Kafka topic must exist with its own retention before the relay publishes to one or a consumer subscribes to one. `workers` waits for postgres, mongodb, kafka, schema-registry, elasticsearch and mailpit, plus the same `kafka-init` completion. nginx containers wait for `api` to be healthy.

**`kafka-init` runs once and is idempotent.** It creates every event topic in [kafka-events.md § 1](./kafka-events.md#topic-summary) and one dead-letter topic per consumer group [§ 4](./kafka-events.md#dlq-topics), plus `email.outbound.dlq` — the one dead-letter topic that is not a consumer group's, holding emails whose SMTP delivery failed three times — with `--if-not-exists`, one partition and replication factor 1 each, at 7-day retention — except the three `auth.*` topics and the three DLQs fed only by them, which are created at 24 hours because those payloads carry a raw single-use credential token.

**The `AUTH_DLQ` list is why the DLQ loop is two loops.** A dead-lettered message carries the original envelope and payload ([conventions/kafka-events.md § DLQ](../../conventions/kafka-events.md#dlq-topology)), so a `notification.password-reset` failure parks a live `reset_token` in `notification.password-reset.dlq`. Provisioned from `KAFKA_TOPIC_RETENTION_MS` with the rest, that token would sit in the broker log for seven days — on the one path where the notification never reached the user and an operator is therefore going to open the topic and read it, which is the exposure the 24-hour `auth.*` retention exists to close. The rule is a DLQ takes the **longest** of its source topics' retentions ([kafka-events.md § 3](./kafka-events.md#topic-retention)); `notification.email-verification`, `notification.password-reset` and `notification.password-changed` each subscribe to exactly one 24-hour topic, so for them the longest is 24 hours. `platform.audit.dlq` stays at seven days because that group also consumes 7-day topics and a genuine maximum is what the rule asks for. Broker auto-creation is off (§6), so this container is the only thing that creates a topic: with auto-creation on, the first producer to reach an unprovisioned `auth.*` topic would have created it at the broker default of 7 days and held live password-reset tokens in the log for seven times the intended window, with nothing in the topology to notice. Running to completion before `api` and `workers` start also keeps it clear of the migrations.

The observability stack is a second, independent root: `alloy` and `grafana` wait on `loki`, and `grafana` additionally on `prometheus`. Nothing in the application graph waits on any of them, and that is deliberate — a collector outage must not stop the API from booting. The dependency runs the other way: Alloy discovers containers through the Docker API, so it picks up services that started before it without needing to be told about them.

### The Elasticsearch index is not a service in this graph

There is no `elasticsearch-init` container and there will not be one. The Search module creates the `products` index itself during `workers` boot — an idempotent `ensureIndex` that runs after `elasticsearch` is healthy and **before** any `search.*` consumer group begins consuming, so no consumer can index a document into a missing or unmapped index. It reads the index, creates it with the mapping if absent, warns on drift if present, and never mutates a live index.

`minio-init` looks like a precedent and is not one. Buckets must exist before *any* process starts, and several services touch them; this index has exactly one writer and exactly one moment it is needed, which is inside the process that writes it. A one-shot init container would instead race the migrations and the app, need its own image carrying an Elasticsearch client, and make the index conditional on someone remembering to include the infra profile in their `docker compose up`. `kafka-init` is not the counter-example it looks like: its work is per topic rather than per process, three services depend on its output, and one of its settings is a security control no application code could apply to a topic the broker had already created.

---

<a id="development-workflow"></a>
## 10. Prerequisites and development workflow

### Prerequisite — build the frontend before starting nginx

The three nginx services bind-mount `../aliceut-ecom-frontend/dist/<app>` from the host (§1). Compose does not build the Angular apps. **Build them first**, from `aliceut-ecom-frontend/`:

```bash
npm run build:buyer && npm run build:seller && npm run build:admin
```

Skipping this step is not a build failure — the containers start, mount an empty or missing directory, and every request returns 403 or 404. Rebuild after any frontend change; nginx serves whatever is on disk, so no container restart is needed.

### Prerequisite — the three `config/` files must exist

`alloy`, `prometheus` and `grafana` bind-mount configuration from `aliceut-ecom-infra/config/` (§1). These are committed files, not generated ones, and each fails differently when absent: Docker creates a **directory** where a missing bind-mounted file was expected, so Alloy starts and exits on a parse error, Prometheus starts with no scrape targets and reports healthy while collecting nothing, and Grafana starts with no datasource so every panel reads "No data". The Alloy config is specified in [observability.md §5](../../conventions/observability.md#alloy-config); `prometheus.yml` must scrape `api:3000` and `workers:3001` with `metrics_path: /metrics`; Grafana's provisioning directory must declare Loki and Prometheus as datasources so the stack is query-ready on first boot.

Those three values are **literals in `prometheus.yml`, not `${PORT_WORKERS}` and `${METRICS_PATH}`.** Prometheus performs no environment substitution in its config file — the only expansion it ships is `--enable-feature=expand-external-labels`, which applies to `external_labels` and nothing else — so a `${PORT_WORKERS}` in a `targets` list is a parse failure at boot, not a fallback to a default. The duplication with §5 is real and unavoidable: the two Nest processes do expand `PORT_WORKERS` and `METRICS_PATH`, so changing either variable without editing `prometheus.yml` by hand leaves Prometheus scraping the old address and reporting healthy while it collects nothing. That is the failure this paragraph exists to make findable.

### First run

```bash
# Copy and edit environment
cp .env.example .env

# Start infrastructure only (no app containers)
docker compose up postgres mongodb elasticsearch kafka schema-registry kafka-ui \
  redis minio minio-init mailpit loki prometheus grafana alloy -d

# Snapshot the Postgres volume before applying any schema change (NFR-11)
docker run --rm -v aliceut-ecom-infra_postgres_data:/data -v "$PWD/backups:/backup" \
  alpine tar czf /backup/postgres_data_$(date +%Y%m%dT%H%M%S).tar.gz -C /data .

# Apply raw-SQL migrations in filename order (operator-triggered; TypeORM never
# synchronizes schema). 0001_create_extensions runs first and must — see below.
cd ../aliceut-ecom-backend && npm run migration:run

# Seed database
npm run seed

# Start API and workers in development mode (hot reload)
npm run start:dev

# Build frontend (see prerequisite above), then start nginx
cd ../aliceut-ecom-frontend
npm run build:buyer && npm run build:seller && npm run build:admin
cd ../aliceut-ecom-infra && docker compose up buyer-nginx seller-nginx admin-nginx -d

# Start everything
docker compose up -d
```

`npm run migration:run` wraps the TypeORM migration CLI over the raw `.sql` files in `aliceut-ecom-backend/migrations/phase-1/` (BRD §12: TypeORM with raw-SQL migrations; `synchronize` is off in every environment). Migrations are never applied automatically on container start — see [conventions/database-migrations.md](../../conventions/database-migrations.md).

They run in filename order, and that order is load-bearing rather than tidy: `0001_create_extensions` must be a real named migration and must execute **before** the `pricing` schema migration, because `pricing.offer_price`'s `EXCLUDE USING gist` constraint fails at creation time without `btree_gist`. Reordering them, or folding the extension into a later file, breaks `migration:run` on a fresh database — the failure is at `CREATE TABLE` time, not at first use. The next subsection says exactly why the extension is needed.

### What the `migrations/init` mount is not for

`../aliceut-ecom-backend/migrations/init` is mounted into `docker-entrypoint-initdb.d` (§6, `postgres`) and holds **roles and grants only**. Never schema. Schema comes exclusively from the TypeORM raw-SQL migrations run above (BRD §12, NFR-18), because those are versioned and recorded in the migration state table. Anything applied through the initdb mount bypasses that table entirely: the objects exist but no migration is recorded, so the next `migration:run` tries to create them again, and a volume that already has data silently diverges from a volume created fresh. Postgres also runs that directory exactly once — when `postgres_data` is empty — so a statement added there later never executes for any existing developer. The directory name invites the mistake; this paragraph is here so the answer is written down.

### Required extension

Migration `0001_create_extensions` exists solely to run `CREATE EXTENSION IF NOT EXISTS btree_gist;`, and it is numbered `0001` so that it precedes the `pricing` migration. The `EXCLUDE USING gist (offer_id WITH =, tstzrange(starts_at, ends_at) WITH &&)` constraint on `pricing.offer_price` ([data-model-erd.md](./data-model-erd.md#table-pricing-offer-price)) splits into two operands. The range half is core — built-in `range_ops` covers `WITH &&`. The `offer_id WITH =` half is not: `offer_id` is `UUID`, core PostgreSQL 16 ships no GiST operator class for `uuid`, and `gist_uuid_ops` comes only from `btree_gist`. Without the extension the migration fails with `data type uuid has no default operator class for access method "gist"`. The ERD carries the same rationale next to the constraint.

**This does not require a custom image.** `btree_gist` is a bundled contrib module already present in the official `postgres:16-alpine` image, and it is trusted in PG13+, so the database owner creates it without superuser — **no custom Dockerfile and no privileged migration step**. The rule it has to satisfy is bundled contrib versus third-party module, not extension versus no extension: that is the same distinction that rejects `pg_cron` in the design-decision list below. NFR-18 portability carries one caveat: a managed Postgres that blocks contrib modules blocks this constraint. No other extension is required in Phase 1.

Running `api` and `workers` on the host (`npm run start:dev`) puts them outside `aliceut_backend`, so they reach each service through its published host port. Override `KAFKA_BROKERS=localhost:29092` (the EXTERNAL listener), `DATABASE_URL` on `localhost:5432` and `MINIO_ENDPOINT=http://localhost:9000` in a local `.env` for that mode; the values committed in `.env.example` are the in-network ones the containers use.

---

<a id="port-summary"></a>
## 11. Port summary

| Service | Host port | Access URL |
|---------|-----------|------------|
| buyer-nginx | 4200 | http://localhost:4200 |
| seller-nginx | 4201 | http://localhost:4201 |
| admin-nginx | 4202 | http://localhost:4202 |
| api | 3000 | http://localhost:3000/api/v1 |
| workers (health) | — | `PORT_WORKERS` (default 3001), in-container only; used by the compose healthcheck. Read it with `docker compose exec workers wget -qO- http://localhost:3001/api/v1/health` |
| postgres | 5432 | `psql -h localhost -U aliceut_app aliceut` |
| mongodb | 27017 | `mongosh mongodb://localhost:27017/aliceut_audit` |
| elasticsearch | 9200 | http://localhost:9200 |
| kafka | 29092 | `kafka:9092` (INTERNAL), `localhost:29092` (EXTERNAL, host tooling) |
| schema-registry | 8081 | http://localhost:8081/subjects |
| kafka-ui | 8080 | http://localhost:8080 |
| minio (S3 API) | 9000 | http://localhost:9000 |
| minio (console) | 9001 | http://localhost:9001 |
| redis | 6379 | `redis-cli -h localhost` |
| mailpit (web inbox) | 8025 | http://localhost:8025 |
| mailpit (SMTP) | 1025 | `mailpit:1025` from `workers`; `localhost:1025` for host-mode dev |
| grafana | 3200 | http://localhost:3200 — **not 3000**, which is `api` |
| prometheus | 9090 | http://localhost:9090 |
| loki | 3100 | `logcli --addr=http://localhost:3100` |
| alloy | 12345 | http://localhost:12345 (component health UI, development only) |

Every host port in this table is distinct, and two of them are near-collisions worth stating: Grafana's container port **is** 3000 and is published on 3200 because `api` holds host 3000; Loki's 3100 is not a Grafana port despite the adjacent number.

---

<a id="operations-and-alerting"></a>
## 12. Operations and alerting

Logging, correlation-ID propagation and the collector stack are governed by [conventions/observability.md](../../conventions/observability.md). Alloy, Loki, Prometheus and Grafana run in this compose file (§2), so every observation point below is live infrastructure a developer can open, not a future capability. Two conditions must raise an alert in V1.

| Condition | Threshold | How it is observed in V1 |
|---|---|---|
| Outbox relay lag | oldest `PENDING` row in `platform.outbox_event` older than **30 s** | The workers process computes the lag as `now() - min(created_at) WHERE publication_status = 'PENDING'` and reports it on its health endpoint (`GET :$PORT_WORKERS/api/v1/health`, §11). The same value is exposed as `aliceut_outbox_oldest_pending_age_seconds` on `workers`' `METRICS_PATH`, scraped by the `prometheus` service, so the alert is a threshold rule on that gauge and the history is queryable in Grafana (http://localhost:3200). Age is the gauge the rule fires on, not `aliceut_outbox_pending`: a steady small pending count with a climbing age is a stuck relay, while a large count with a flat age is a busy one, so alerting on depth would page on throughput. Read `aliceut_outbox_pending` beside it for the size of the backlog once the rule has fired. The health endpoint remains the container-level probe: a non-200 means the relay is stalled or lagging. |
| DLQ non-empty | **any** message on any `<consumer_group>.dlq` topic | Kafka UI (http://localhost:8080) → cluster `aliceut-dev` → Topics, filtered to `*.dlq`: any topic with a non-zero message count is a live alert. Consumer lag per group is on the same screen. DLQ naming and the alert requirement come from [conventions/kafka-events.md §5](../../conventions/kafka-events.md). This one is screen-only in V1 and deliberately so: no gauge in [api-design/health.md](./api-design/health.md#workers-health-check) reports DLQ depth, and the `consumers` check passes with an assignment held even while that group is dead-lettering every message, so a green probe is not evidence of an empty DLQ. |

The `*.dlq` filter is expected to match one topic per consumer group in [backend-module-architecture.md](./backend-module-architecture.md#module-summary-table), plus `email.outbound.dlq`, all of them created by `kafka-init` at start-up rather than on first failure. A dead-letter topic is per *consumer group*, not per event topic, and two groups subscribe to more than one topic — `platform.audit` to nearly every topic, and `inventory.fulfillment-refunded` to both `fulfillment.refunded` and `fulfillment.refund_suspended_seller` — so the DLQ count is deliberately **not** the event-topic count in [kafka-events.md §1](./kafka-events.md#topic-summary) and the two must not be reconciled against each other. `email.outbound.dlq` belongs to no group: it holds the *email* after three failed SMTP attempts, while the event that produced it was processed correctly and is not dead-lettered ([kafka-events.md § 4](./kafka-events.md#dlq-topics)). A group with no `.dlq` topic on that screen is a wiring defect, not a quiet success.

Neither condition is self-clearing. A non-empty DLQ stays non-empty until an operator replays or discards the messages, so the alert is a work queue, not a transient.

### Where the numbers come from

The outbox row reads from the `workers` health endpoint and the metrics path beside it, both now specified in [api-design/health.md § Workers health check](./api-design/health.md#workers-health-check) rather than requested by this document. What matters here is the wiring:

- **The endpoint** is `GET /api/v1/health` on `PORT_WORKERS` (default 3001), unpublished to the host, served by `WorkersHealthController` and called only by the compose healthcheck. It sits under the global prefix and has no unversioned alias, which is why the probe above targets the prefixed path — a healthcheck on `/health` would 404 forever and the container would never become healthy.
- **Healthy means more than "the port answers."** `workers` exists to relay the outbox, run consumers and fire scheduled jobs, so a running process whose consumers are all revoked, or whose `@nestjs/schedule` timer has died, must return non-200 or the healthcheck is decorative. The scheduler branch is bounded by `WORKERS_SCHEDULER_STALE_MS` (§5, default `180000` — 3× the 60 s `DELIVERY_MOCK_INTERVAL_MS`, the shortest configured job interval). `OUTBOX_POLL_INTERVAL_MS` at 500 ms is shorter but is not a job — the relay is excluded from this check by definition ([cleanup-jobs.md](./cleanup-jobs.md)) and by consequence: treat it as one and the bound becomes 360× the interval it polices, which detects nothing.
- **The gauges the alert rules evaluate** are on `METRICS_PATH` (`/metrics`) on both `api` and `workers`: `aliceut_outbox_pending`, `aliceut_outbox_oldest_pending_age_seconds`, `aliceut_outbox_failed`, `aliceut_outbox_relay_lock_held` and `aliceut_consumer_assigned_partitions` (labelled by consumer group). `aliceut_consumer_assigned_partitions` at `0` for a group is the stopped-consumer signal, which is what makes a silent consumer visible without reading a screen. Names are owned by `health.md`; the `prometheus` service in §6 is what scrapes them.

The division of labour is deliberate: the health endpoint is for the container probe, the metrics path for alert rules and dashboard history.

### Accepted V1 risk — neither Prometheus nor Loki has a retention policy

Both have named volumes (§4) and neither is given a retention flag. That is a decision, not an omission, and it has two different consequences worth knowing before a developer trusts either store:

- **Prometheus silently drops history at 15 days** — its default `--storage.tsdb.retention.time`. A query over a longer window returns a shorter series with no warning, so "the lag was fine last month" is not a question this stack can answer.
- **Loki grows without bound.** The compactor's retention is off by default, so nothing deletes old chunks and the `loki_data` volume expands until the disk fills. The failure surfaces as the whole Docker host running out of space, not as Loki reporting a problem.

Neither is fixed in V1 because a retention policy nobody will observe on a laptop is not worth the config surface, and the cheap mitigation already exists: `docker compose down -v` discards both volumes. No environment variable is introduced for either — a knob implies someone tuned it.

### Accepted V1 risk — KYC uploads are not scanned for malware

No antivirus or scanner sidecar runs in V1. A seller can upload a file that is a valid PDF or JPEG by extension, MIME sniff and size, and still carries a malicious payload; an admin who downloads it and opens it locally is exposed. This is recorded rather than fixed: a scanner is real infrastructure with real operational burden and is not in BRD scope. The mitigations that do exist narrow it to that single path:

- The `kyc-documents` bucket is private. No public URL and no anonymous download policy — contrast `product-images`, which is public-read (§6, `minio-init`).
- Read access is a short-lived presigned GET issued only to an authenticated ADMIN. No buyer, seller or unauthenticated caller can retrieve another party's document.
- Uploads are validated on extension **and** sniffed MIME type **and** size, against an allowlist of PDF, JPEG and PNG only. Extension alone is not sufficient and is not used alone. Size and count are bounded by `KYC_UPLOAD_MAX_BYTES` (10 MB) and `KYC_UPLOAD_MAX_FILES` (5), declared on `api` only (§5) — the enforcement is in the multipart request path, and nothing in `workers` reads the bytes.
- The admin portal never renders a document inline. Documents download, so there is no browser-side execution or preview path.

**V2 remedy:** a scanner sidecar (ClamAV or equivalent) between upload and the document becoming admin-visible, with the object quarantined until it returns clean.

---

<a id="design-decisions"></a>
## 13. [DESIGN DECISIONS]

- **[DESIGN DECISION]** The compose file lives in the sibling `aliceut-ecom-infra` repository, not in the backend or frontend repository, because it wires all of them together and belongs to neither. Every `../` path in it resolves against that repository's root (§1). Compose commands run from there.
- **[DESIGN DECISION]** Kafka uses KRaft mode (no ZooKeeper). `apache/kafka:3.8.0` ships with KRaft; a `CLUSTER_ID` is pre-generated. This removes ZooKeeper as a dependency, reducing the compose service count.
- **[DESIGN DECISION]** Kafka advertises two client listeners, `INTERNAL://kafka:9092` and `EXTERNAL://localhost:29092`. A broker can advertise only one address per listener, and `kafka:9092` is unresolvable from the host while `localhost:29092` is unreachable from inside the network. Publishing host port 9092 is deliberately avoided: a host client connecting there would be redirected to `kafka:9092` and fail confusingly. In-network clients (`api`, `workers`, `schema-registry`, `kafka-ui`) use `KAFKA_BROKERS=kafka:9092`; host tooling and host-mode development use `localhost:29092`.
- **[DESIGN DECISION]** Postgres stays on the stock `postgres:16-alpine` image. No custom image and no in-database scheduler: all scheduled work runs in the `workers` service via `@nestjs/schedule`. See [backend-module-architecture.md](./backend-module-architecture.md#scheduled-tasks) for the job inventory and [cleanup-jobs.md](./cleanup-jobs.md) for the per-job schedule and env var. The distinction that matters is bundled versus third-party: the official image ships the standard contrib modules, so `btree_gist` is a plain `CREATE EXTENSION` in migration `0001` (§10) and needs no Dockerfile. `pg_cron` is not a contrib module — it would require building or sourcing a different image, which is what this decision rejects.
- **[DESIGN DECISION]** `workers` runs as a single instance in V1 and every scheduled job additionally takes a `pg_advisory_lock` keyed on the job name before doing work, so a second replica is safe by construction rather than by convention. The compose file therefore sets no replica count; horizontal scaling of the consumer side needs only more partitions.
- **[DESIGN DECISION]** The three nginx services bind-mount host build output rather than baking the Angular bundles into images. Rebuilding a frontend is then a `npm run build:*` away with no image rebuild and no container restart, which is the right trade for local development. The cost is that the build is a documented prerequisite (§10) rather than something compose guarantees; a clean clone with no `dist/` serves 403/404 until the build runs. V2 (Kubernetes) bakes the bundles into images.
- **[DESIGN DECISION]** `migrations/init` is mounted into `docker-entrypoint-initdb.d` and holds **only** first-boot roles and grants. Postgres runs that directory exactly once, when `postgres_data` is empty. Neither schema nor extensions are placed there: migrations are operator-triggered and versioned, an initdb-executed statement is recorded in no migration state table, and `btree_gist` therefore belongs in migration `0001_create_extensions` (§10) where the ordering against the `pricing` migration is explicit and enforced by filename.
- **[DESIGN DECISION]** The observability stack — `alloy`, `loki`, `prometheus`, `grafana` — is part of the Phase 1 compose file, not a later phase. `conventions/observability.md` specifies structured logging, correlation-ID propagation and a Loki-backed debugging workflow throughout; every one of those is unusable without somewhere for the logs to go, and §12's two alert conditions need a real metrics store behind them. The four services are configured from committed files under `config/`, so the stack is query-ready on first boot rather than after a manual Grafana setup session.
- **[DESIGN DECISION]** Grafana publishes on host **3200**, mapped to its own container port 3000. Host 3000 belongs to `api`. Two services cannot bind the same host port — compose fails the second one at start with `port is already allocated` — so this is a correctness constraint, not a preference. Loki's 3100 and Grafana's 3200 are adjacent by coincidence and are unrelated services.
- **[DESIGN DECISION]** `alloy` carries no healthcheck. Its image ships neither `wget` nor `curl`, and the Alloy binary has no readiness subcommand, so any probe written here would be a guess that either always fails or always passes — the same class of silent bug as a healthcheck against a tool the image does not contain. Alloy's failure mode is visible instead: Loki returns no rows, and Alloy's own UI on `:12345` reports per-component health. Nothing in the graph waits on Alloy, so an unhealthy collector cannot block a boot.
- **[DESIGN DECISION]** Loki publishes 3100 to the host even though only Grafana queries it in normal use, because `observability.md` §7's post-test debugging workflow runs `logcli` from the host against that API. Alloy's 12345 is published for the same reason — component health during config work — and both are development-only exposures.
- **[DESIGN DECISION]** Mailpit (`axllent/mailpit:v1.41.1`) is the V1 SMTP sink: web inbox on 8025, SMTP on 1025. Phase 1 has 21 `ET-*` templates and the notification consumer previously had nowhere to send, which made email verification, KYC correspondence and low-stock digests untestable end to end. Mailpit accepts unauthenticated plaintext SMTP, so `SMTP_USER` and `SMTP_PASS` stay empty in development while remaining required against a real relay. Only `workers` holds SMTP configuration — notifications are Kafka consumers, never inline in an HTTP handler — so `api` has no mail path at all. The inbox is in-memory with `MP_MAX_MESSAGES: 500`: a restart clears it, which is correct when the alternative is a developer clicking a stale verification link.
- **[DESIGN DECISION]** Elasticsearch `xpack.security.enabled=false` for development simplicity. Production deployment must enable TLS and authentication.
- **[DESIGN DECISION]** Workers expose a minimal health endpoint at `GET /api/v1/health` on `PORT_WORKERS` (default 3001) for the compose health check. This is a lightweight HTTP server in the worker process, carrying that route and `METRICS_PATH` and nothing else; §12's outbox-lag condition reads from both, and its DLQ condition from neither — no gauge reports DLQ depth in V1. The port is not published to the host; the healthcheck runs inside the container. The path carries the global prefix because the endpoint has no unversioned alias ([api-design/health.md](./api-design/health.md)) — a probe on `/health` would 404 and leave the container permanently unhealthy, which is the same silent-failure class as a healthcheck invoking a binary the image does not ship.
- **[DESIGN DECISION]** The Elasticsearch `products` index is created by the Search module during `workers` boot, not by an init container (§9). There is no twentieth service. The index has one writer and one moment it is needed, so the code that writes it is the right owner; `minio-init` exists because buckets must precede every process, which is a different shape of problem.
- **[DESIGN DECISION]** Grafana's anonymous role is `Viewer`, not `Admin`. Anonymous access itself stays enabled — opening a dashboard without a login is the point of a development stack — but an anonymous `Admin` on a published port can edit datasources, and a Grafana datasource is a credentialed connection to Loki and Prometheus. That makes `Admin` a path to repointing where the platform's logs are read from, not merely dashboard vandalism. Editing is what `GF_SECURITY_ADMIN_PASSWORD` is for. Do not restore `Admin` as a convenience.
- **[DESIGN DECISION]** Object storage uses MinIO (`minio/minio:RELEASE.2024-11-07T00-52-20Z`). Three buckets: `product-images` (public read, served via presigned URLs or direct path), `kyc-documents` (private; NestJS generates short-lived presigned GET URLs on demand), `user-assets` (business logos; private). `minio-init` is a one-shot service that creates the three buckets and the `MINIO_ACCESS_KEY` service account with the `readwrite` policy; it is idempotent, so re-running compose on an existing volume is a no-op. The application authenticates with that service account, never with the root credentials — the root credentials exist only for `minio-init` and the console. `api` waits on `service_completed_successfully` so no upload can precede the account.
- **[DESIGN DECISION]** Schema Registry uses Community License (`confluentinc/cp-schema-registry:7.7.0`). No commercial license key required. Does not use Schema Linking, exporters, or RBAC security plugin.
- **[DESIGN DECISION]** Redis (`redis:7-alpine`) is ephemeral — no persistent volume. JWT revocation keys (`auth:revoke_before:{userId}`) carry a 960 s TTL (15-min JWT lifetime + 60 s buffer). If Redis restarts in development, the worst-case window for a revoked token is at most 15 minutes until the access JWT expires naturally. Persistent storage is not justified for this TTL. `maxmemory 256mb` bounds growth, with `maxmemory-policy noeviction` — this instance also holds the 60-second single-use OAuth authorization code, which must never be evicted; an eviction-enabled cache belongs on a separate instance. Only `api` depends on Redis; `workers` processes Kafka events and does not validate JWTs.
