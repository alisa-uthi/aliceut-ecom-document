# Epic: INFRA — Infrastructure

**Epic ID:** INFRA  
**Sprint(s):** 1  
**Status:** Now  
**Total Tasks:** 12  

## Epic Goal

Stand up the complete local development environment. All 16 Docker services running via a single `docker-compose up`. NestJS and Angular Nx monorepos initialized. Environment validation fails fast on missing vars. Health checks confirm all critical services reachable.

---

## Tasks

### INFRA-001 — Bootstrap Nx backend monorepo

**Estimate:** M (4h)  
**User Story:** —  
**Dependencies:** —  

**Implementation Notes:**
- `npx create-nx-workspace@latest aliceut-backend --preset=ts`
- Apps: `apps/api` (NestJS), `apps/workers` (NestJS)
- Libs: `libs/catalog/`, `libs/pricing/`, `libs/inventory/`, `libs/cart/`, `libs/orders/`, `libs/identity/`, `libs/seller/`, `libs/admin/`, `libs/search/`, `libs/notifications/`, `libs/platform/`, `libs/shared/`, `libs/contracts/`
- Set `paths` in `tsconfig.base.json` for each lib (`@aliceut/shared`, `@aliceut/contracts`, etc.)
- NestJS generator: `nx g @nx/nest:application api`
- Add `@nestjs/config`, `class-validator`, `class-transformer` to root deps

**Done Criteria:**
- `nx build api` succeeds (empty app)
- `nx build workers` succeeds (empty app)
- All lib paths resolvable via tsconfig aliases
- No monorepo lint errors

---

### INFRA-002 — Bootstrap Nx frontend monorepo

**Estimate:** M (4h)  
**User Story:** —  
**Dependencies:** —  

**Implementation Notes:**
- `npx create-nx-workspace@latest aliceut-frontend --preset=angular`
- Apps: `apps/buyer-app`, `apps/seller-app`, `apps/admin-app`
- Shared lib: `libs/shared/` (components, pipes, interceptors, auth state)
- `libs/api-client/` (OpenAPI-generated; do-not-edit)
- Angular Material 3 peer deps; import `provideAnimationsAsync()` in all app providers
- Set strict mode TypeScript; no implicit any

**Done Criteria:**
- `nx build buyer-app` succeeds
- `nx build seller-app` succeeds
- `nx build admin-app` succeeds
- Angular Material component renders in dev server

---

### INFRA-003 — Write docker-compose.yml (all 16 services per topology doc)

**Estimate:** L (8h)  
**User Story:** —  
**Dependencies:** INFRA-001  

**Implementation Notes:**
- Services: `nginx-buyer`, `nginx-seller`, `nginx-admin` (3 nginx reverse proxies), `api` (port 3000), `workers` (port 3001), `postgres`, `mongodb`, `elasticsearch`, `kafka`, `schema-registry`, `kafka-ui`, `minio`, `minio-init`, `redis`
- Networks: `aliceut_frontend` (nginx ↔ api), `aliceut_backend` (api ↔ all data services)
- Named volumes: `postgres_data`, `mongodb_data`, `elasticsearch_data`, `kafka_data`, `minio_data`
- Use `depends_on: condition: service_healthy` for postgres, kafka, elasticsearch — healthcheck blocks
- kafka: `KAFKA_PROCESS_ROLES=broker,controller` (KRaft mode; no ZooKeeper)
- elasticsearch: single-node, `discovery.type=single-node`, `xpack.security.enabled=false`
- All credentials from environment vars; no hardcoded passwords

**Done Criteria:**
- `docker-compose up -d` brings all 16 services without manual intervention
- `docker-compose ps` shows all services `healthy` or `running`
- `curl localhost:3000/health` returns 200
- Kafka UI accessible at `localhost:8080`

---

### INFRA-004 — PostgreSQL 16 setup + uuidv7 extension SQL function

**Estimate:** M (4h)  
**User Story:** —  
**Dependencies:** INFRA-003  

**Implementation Notes:**
- PostgreSQL 16 image; create database `aliceut`
- uuidv7 is not a native PG extension — implement as a pure SQL function:
  ```sql
  CREATE OR REPLACE FUNCTION uuidv7() RETURNS uuid AS $$
  DECLARE
    unix_ts_ms bigint;
    uuid_bytes bytea;
  BEGIN
    unix_ts_ms := (extract(epoch FROM clock_timestamp()) * 1000)::bigint;
    uuid_bytes := decode(lpad(to_hex(unix_ts_ms), 12, '0'), 'hex')
               || gen_random_bytes(10);
    -- set version bits (0111 = 7) and variant (10xx)
    uuid_bytes := set_byte(uuid_bytes, 6, (get_byte(uuid_bytes, 6) & 15) | 112);
    uuid_bytes := set_byte(uuid_bytes, 8, (get_byte(uuid_bytes, 8) & 63) | 128);
    RETURN encode(uuid_bytes, 'hex')::uuid;
  END;
  $$ LANGUAGE plpgsql;
  ```
- Run this as the very first migration (000_uuidv7.sql)
- TypeORM data source config: `host`, `port`, `username`, `password`, `database` from env vars
- Enable `pgcrypto` extension for `gen_random_bytes`

**Done Criteria:**
- `SELECT uuidv7()` returns a valid UUID with version nibble `7`
- Two consecutive calls return monotonically increasing UUID strings when sorted lexicographically
- TypeORM connects successfully; `typeorm migration:run` executes without error

---

### INFRA-005 — MongoDB 7 setup + connection config (NestJS)

**Estimate:** S (2h)  
**User Story:** —  
**Dependencies:** INFRA-003  

**Implementation Notes:**
- MongoDB 7 image; database `aliceut_logs`
- NestJS: `@nestjs/mongoose`, `mongoose` packages
- Connection string from env var `MONGODB_URI`
- `MongooseModule.forRootAsync` with `useFactory` reading config service
- Used for: activity logs, audit trail, high-write append data

**Done Criteria:**
- NestJS connects to MongoDB at startup; no connection error in logs
- `mongoose.connection.readyState === 1` in health check

---

### INFRA-006 — Redis 7 setup + connection config (ioredis)

**Estimate:** S (2h)  
**User Story:** —  
**Dependencies:** INFRA-003  

**Implementation Notes:**
- Redis 7 image with `--appendonly yes`
- `ioredis` package; connection from `REDIS_URL` env var
- Inject via custom provider `REDIS_CLIENT`
- Used for: refresh token blacklist, rate limiting, session cache

**Done Criteria:**
- Redis client connects at startup
- `redis.ping()` returns `PONG` in health check

---

### INFRA-007 — Elasticsearch 8 setup + index template placeholder

**Estimate:** M (4h)  
**User Story:** —  
**Dependencies:** INFRA-003  

**Implementation Notes:**
- Elasticsearch 8 image; `discovery.type=single-node`; `xpack.security.enabled=false` (dev only)
- `@elastic/elasticsearch` npm client
- Create `products` index with placeholder mapping on startup (ILM not needed for V1)
- ES client injected via custom provider; connection from `ELASTICSEARCH_URL` env var
- Actual index mapping created in SEARCH-001

**Done Criteria:**
- ES accessible at `localhost:9200`; `/_cluster/health` returns `green` or `yellow`
- NestJS ES client can ping cluster at startup

---

### INFRA-008 — Kafka (KRaft) + Confluent Schema Registry setup

**Estimate:** L (8h)  
**User Story:** —  
**Dependencies:** INFRA-003  

**Implementation Notes:**
- Kafka image: `confluentinc/cp-kafka:7.x` with KRaft (no ZooKeeper)
- Required env: `KAFKA_NODE_ID=1`, `KAFKA_PROCESS_ROLES=broker,controller`, `KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:29093`
- Pre-create all 24 topics at startup via `KAFKA_CREATE_TOPICS` env or init script
- Schema Registry: `confluentinc/cp-schema-registry`; `SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS=kafka:29092`
- All schemas use BACKWARD compatibility (default registry setting)
- Advertised listeners: `PLAINTEXT://kafka:29092` (internal), `PLAINTEXT_HOST://localhost:9092` (host)

**Done Criteria:**
- `kafka-topics.sh --list` shows all 24 topic names
- Schema Registry accessible at `localhost:8081`; `GET /subjects` returns `[]`
- Can produce and consume a plain string message via Kafka UI

---

### INFRA-009 — Kafka UI (provectus) setup + network config

**Estimate:** S (2h)  
**User Story:** —  
**Dependencies:** INFRA-008  

**Implementation Notes:**
- `provectus/kafka-ui` image
- Point at kafka:29092 and schema-registry:8081
- Expose on port 8080
- Mount on `aliceut_backend` network only

**Done Criteria:**
- Kafka UI loads at `localhost:8080`
- All 24 pre-created topics visible
- Schema Registry shown as connected

---

### INFRA-010 — MinIO setup + minio-init container (3 buckets)

**Estimate:** M (4h)  
**User Story:** —  
**Dependencies:** INFRA-003  

**Implementation Notes:**
- MinIO latest image; console port 9001, API port 9000
- `minio-init` service: `mc alias set minio http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD && mc mb minio/product-images && mc mb minio/kyc-documents && mc mb minio/user-assets`
- `kyc-documents` bucket: private (no public policy); pre-signed URLs only
- `product-images` bucket: public read (products visible without auth)
- `user-assets` bucket: private
- NestJS: `@aws-sdk/client-s3` (MinIO is S3-compatible)

**Done Criteria:**
- MinIO console at `localhost:9001`; 3 buckets exist
- Public product-images URL returns content without auth
- KYC document presigned URL expires in configurable TTL

---

### INFRA-011 — .env.example + Joi schema validation (fail-fast on missing vars)

**Estimate:** M (4h)  
**User Story:** US-P-08  
**Dependencies:** INFRA-001  

**Implementation Notes:**
- `.env.example` lists every required variable with placeholder values and inline comments
- NestJS `ConfigModule.forRoot({ validationSchema: Joi.object({...}), validationOptions: { abortEarly: false } })`
- Joi schema covers: DB credentials, JWT secrets, Redis URL, Kafka brokers, Schema Registry URL, MinIO credentials, OAuth client IDs/secrets, SMTP settings, FX API key
- All secrets typed as `Joi.string().required()`; no defaults for secrets
- Non-secret settings (e.g., port numbers) have sensible defaults

**Done Criteria:**
- Server exits with clear error listing ALL missing vars (not just first)
- Removing any required secret from `.env` → startup fails with variable name in error
- `.env.example` reviewed: no real credentials present

---

### INFRA-012 — Health check endpoints

**Estimate:** S (2h)  
**User Story:** —  
**Dependencies:** INFRA-001  

**Implementation Notes:**
- `GET /health` on api (port 3000): check PostgreSQL, MongoDB, Redis, Elasticsearch, Kafka connectivity
- `GET /health` on workers (port 3001): check PostgreSQL, Kafka
- `@nestjs/terminus` for health indicators
- Return `{ status: "ok" | "error", details: { ... } }` per indicator
- Docker healthcheck: `CMD curl -f http://localhost:3000/health || exit 1`

**Done Criteria:**
- `GET /health` returns `{ status: "ok" }` when all dependencies up
- If PostgreSQL is stopped: returns `{ status: "error" }` with postgres detail
- `docker-compose ps` shows api container `healthy`
