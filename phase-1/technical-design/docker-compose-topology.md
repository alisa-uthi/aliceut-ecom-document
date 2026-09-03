# Docker Compose Topology — Phase 1

**Status:** Draft  
**Source of truth:** [BRD v1.1 §12](../requirements/BRD.md), [architecture-overview §8](../../architecture-overview.md)

---

## Summary

- [1. Service inventory](#service-inventory)
- [2. Networks](#networks)
- [3. Volumes](#volumes)
- [4. `.env.example`](#env-example)
- [5. `docker-compose.yml`](#docker-compose-yml)
- [6. Backend Dockerfile (multi-stage, multi-target)](#backend-dockerfile)
- [7. nginx proxy configuration (buyer.conf example)](#nginx-proxy-configuration)
- [8. Startup order and dependency graph](#startup-order)
- [9. Development workflow](#development-workflow)
- [10. Port summary](#port-summary)
- [11. Design Decisions](#design-decisions)

<a id="service-inventory"></a>
## 1. Service inventory

| Service | Image / Build | Host port | Purpose |
|---------|--------------|-----------|---------|
| `buyer-nginx` | `nginx:1.27-alpine` (+ built Angular dist) | `4200:80` | Serves buyer Angular app |
| `seller-nginx` | `nginx:1.27-alpine` (+ built Angular dist) | `4201:80` | Serves seller Angular app |
| `admin-nginx` | `nginx:1.27-alpine` (+ built Angular dist) | `4202:80` | Serves admin Angular app |
| `api` | `./backend` (Dockerfile) | `3000:3000` | NestJS HTTP API |
| `workers` | `./backend` (Dockerfile, worker entrypoint) | — | Outbox relay + Kafka consumers |
| `postgres` | `postgres:16-alpine` | `5432:5432` | Primary PostgreSQL database |
| `mongodb` | `mongo:7` | `27017:27017` | Audit and activity log store |
| `elasticsearch` | `docker.elastic.co/elasticsearch/elasticsearch:8.14.0` | `9200:9200` | Search index |
| `kafka` | `apache/kafka:3.8.0` | `9092:9092` | Kafka broker (KRaft mode) |
| `schema-registry` | `confluentinc/cp-schema-registry:7.7.0` | `8081:8081` | Confluent Schema Registry (Community) |
| `kafka-ui` | `provectus/kafka-ui:latest` | `8080:8080` | Kafka management UI |
| `minio` | `minio/minio:RELEASE.2024-11-07T00-52-20Z` | `9000:9000`, `9001:9001` | S3-compatible object storage (product images, KYC docs, user assets) |
| `minio-init` | `minio/mc:latest` | — | One-shot bucket creation init container |

---

<a id="networks"></a>
## 2. Networks

```
aliceut_frontend   buyer-nginx, seller-nginx, admin-nginx (no backend access)
aliceut_backend    api, workers, postgres, mongodb, elasticsearch, kafka, schema-registry, kafka-ui
```

nginx containers are on **both** networks; they proxy `/api/*` to `api:3000`.  
`api` and `workers` are on `aliceut_backend` only.  
`kafka-ui` is on `aliceut_backend` only (not exposed to browser directly in production, but exposed via host port for development).

---

<a id="volumes"></a>
## 3. Volumes

| Volume | Used by | Purpose |
|--------|---------|---------|
| `postgres_data` | postgres | Persistent PostgreSQL data |
| `mongodb_data` | mongodb | Persistent MongoDB data |
| `elasticsearch_data` | elasticsearch | Persistent search index |
| `kafka_data` | kafka | Persistent Kafka log segments |
| `minio_data` | minio | Persistent object storage data |

---

<a id="env-example"></a>
## 4. `.env.example`

```dotenv
# ── Application ──────────────────────────────────────────
NODE_ENV=development
API_PORT=3000

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

# ── MongoDB ──────────────────────────────────────────────
MONGODB_URI=mongodb://root:change_me_mongodb@mongodb:27017/aliceut_audit?authSource=admin
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD=change_me_mongodb

# ── Elasticsearch ────────────────────────────────────────
ELASTICSEARCH_NODE=http://elasticsearch:9200

# ── Kafka ────────────────────────────────────────────────
KAFKA_BROKERS=kafka:9092
KAFKA_SCHEMA_REGISTRY_URL=http://schema-registry:8081
KAFKA_CLIENT_ID=aliceut-api
KAFKA_WORKER_CLIENT_ID=aliceut-workers

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

# ── FX rates ─────────────────────────────────────────────
FX_PROVIDER_URL=https://api.exchangerate.host/latest
FX_STALENESS_THRESHOLD_HOURS=4

# ── Email (SMTP) ──────────────────────────────────────────
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=noreply@aliceut.example.com

# ── App URLs (for email links + CORS) ────────────────────
BUYER_APP_URL=http://localhost:4200
SELLER_APP_URL=http://localhost:4201
ADMIN_APP_URL=http://localhost:4202

# ── Inventory ────────────────────────────────────────────
LOW_STOCK_THRESHOLD_DEFAULT=5
INVENTORY_RESERVATION_TTL_MINUTES=15

# ── Seed ─────────────────────────────────────────────────
SEED_ADMIN_EMAIL=admin@aliceut.example.com
SEED_ADMIN_PASSWORD=change_me_seed_admin
```

---

<a id="docker-compose-yml"></a>
## 5. `docker-compose.yml`

```yaml
version: "3.9"

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
      context: ./backend
      dockerfile: Dockerfile
      target: api
    container_name: aliceut_api
    restart: unless-stopped
    ports:
      - "3000:3000"
    env_file: .env
    environment:
      NODE_ENV: ${NODE_ENV:-development}
      POSTGRES_HOST: postgres
      MONGODB_URI: mongodb://${MONGO_INITDB_ROOT_USERNAME:-root}:${MONGO_INITDB_ROOT_PASSWORD}@mongodb:27017/aliceut_audit?authSource=admin
      ELASTICSEARCH_NODE: http://elasticsearch:9200
      KAFKA_BROKERS: kafka:9092
      KAFKA_SCHEMA_REGISTRY_URL: http://schema-registry:8081
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
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # ── NestJS Workers ───────────────────────────────────────

  workers:
    build:
      context: ./backend
      dockerfile: Dockerfile
      target: workers
    container_name: aliceut_workers
    restart: unless-stopped
    env_file: .env
    environment:
      NODE_ENV: ${NODE_ENV:-development}
      POSTGRES_HOST: postgres
      MONGODB_URI: mongodb://${MONGO_INITDB_ROOT_USERNAME:-root}:${MONGO_INITDB_ROOT_PASSWORD}@mongodb:27017/aliceut_audit?authSource=admin
      ELASTICSEARCH_NODE: http://elasticsearch:9200
      KAFKA_BROKERS: kafka:9092
      KAFKA_SCHEMA_REGISTRY_URL: http://schema-registry:8081
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
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:3001/health', r => process.exit(r.statusCode === 200 ? 0 : 1))"]
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
      - ../aliceut-ecom-utility-pipeline/database/init:/docker-entrypoint-initdb.d:ro
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
      test: ["CMD-SHELL", "mongosh --username root --password \"$MONGO_INITDB_ROOT_PASSWORD\" --authenticationDatabase admin --eval \"db.adminCommand('ping')\""]
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
      - "9092:9092"
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_NUM_PARTITIONS: 3
      KAFKA_DEFAULT_REPLICATION_FACTOR: 1
      KAFKA_LOG_DIRS: /var/lib/kafka/data
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
      test: ["CMD", "mc", "ready", "local"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 20s

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
      /bin/sh -c "
        mc alias set local http://minio:9000 $${MINIO_ROOT_USER} $${MINIO_ROOT_PASSWORD} &&
        mc mb --ignore-existing local/product-images &&
        mc mb --ignore-existing local/kyc-documents &&
        mc mb --ignore-existing local/user-assets &&
        mc anonymous set download local/product-images &&
        echo 'Buckets ready.'
      "
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minio_admin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}

  # ── Kafka UI ─────────────────────────────────────────────

  kafka-ui:
    image: provectus/kafka-ui:latest
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
```

---

<a id="backend-dockerfile"></a>
## 6. Backend Dockerfile (multi-stage, multi-target)

```dockerfile
# syntax=docker/dockerfile:1

FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./
RUN npm ci --frozen-lockfile

FROM base AS build
COPY . .
RUN npm run build

# ── API target ───────────────────────────────────────────
FROM node:20-alpine AS api
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/dist/apps/api ./dist/apps/api
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json .
EXPOSE 3000
CMD ["node", "dist/apps/api/main.js"]

# ── Workers target ───────────────────────────────────────
FROM node:20-alpine AS workers
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/dist/apps/workers ./dist/apps/workers
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json .
CMD ["node", "dist/apps/workers/main.js"]
```

---

<a id="nginx-proxy-configuration"></a>
## 7. nginx proxy configuration (buyer.conf example)

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
## 8. Startup order and dependency graph

```
postgres ─────────────────────┐
mongodb ──────────────────────┤
elasticsearch ────────────────┤──► api ──► buyer-nginx
kafka ────────────────────────┤         ├─ seller-nginx
kafka ──► schema-registry ────┤         └─ admin-nginx
kafka ──► kafka-ui            │
                              ├──► workers
                              │
schema-registry ──────────────┘
```

`api` and `workers` both wait for all four data stores plus schema-registry (`condition: service_healthy`) before starting. nginx containers wait for `api` to be healthy.

---

<a id="development-workflow"></a>
## 9. Development workflow

```bash
# Copy and edit environment
cp .env.example .env

# Start infrastructure only (no app containers)
docker compose up postgres mongodb elasticsearch kafka schema-registry kafka-ui -d

# Run migrations
npm run migration:run

# Seed database
npm run seed

# Start API and workers in development mode (hot reload)
npm run start:dev

# Build frontend and start nginx
nx run-many -t build
docker compose up buyer-nginx seller-nginx admin-nginx -d

# Start everything
docker compose up -d
```

---

<a id="port-summary"></a>
## 10. Port summary

| Service | Host port | Access URL |
|---------|-----------|------------|
| buyer-nginx | 4200 | http://localhost:4200 |
| seller-nginx | 4201 | http://localhost:4201 |
| admin-nginx | 4202 | http://localhost:4202 |
| api | 3000 | http://localhost:3000/api/v1 |
| postgres | 5432 | `psql -h localhost -U aliceut_app aliceut` |
| mongodb | 27017 | `mongosh mongodb://localhost:27017/aliceut_audit` |
| elasticsearch | 9200 | http://localhost:9200 |
| kafka | 9092 | `kafka:9092` (internal) |
| schema-registry | 8081 | http://localhost:8081/subjects |
| kafka-ui | 8080 | http://localhost:8080 |
| minio (S3 API) | 9000 | http://localhost:9000 |
| minio (console) | 9001 | http://localhost:9001 |

---

<a id="design-decisions"></a>
## 11. [DESIGN DECISIONS]

- **[DESIGN DECISION]** Kafka uses KRaft mode (no ZooKeeper). `apache/kafka:3.8.0` ships with KRaft; a `CLUSTER_ID` is pre-generated. This removes ZooKeeper as a dependency, reducing the compose service count.
- **[DESIGN DECISION]** Elasticsearch `xpack.security.enabled=false` for development simplicity. Production deployment must enable TLS and authentication.
- **[DESIGN DECISION]** Workers expose a minimal health endpoint on port 3001 for the compose health check. This is a lightweight HTTP server in the worker process checking Kafka consumer lag and outbox relay status.
- **[DESIGN DECISION]** Object storage uses MinIO (`minio/minio:RELEASE.2024-11-07T00-52-20Z`). Three buckets: `product-images` (public read, served via presigned URLs or direct path), `kyc-documents` (private; NestJS generates short-lived presigned GET URLs on demand), `user-assets` (business logos; private). `minio-init` is a one-shot service that creates buckets on first compose-up. Production must use a dedicated service-account access key, not the root credentials.
- **[DESIGN DECISION]** Schema Registry uses Community License (`confluentinc/cp-schema-registry:7.7.0`). No commercial license key required. Does not use Schema Linking, exporters, or RBAC security plugin.
