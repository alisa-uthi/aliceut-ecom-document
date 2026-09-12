# Health API

**Module:** `Platform`  
**Parent:** [API Design Index](../api-design.md)

---

## Summary

- [Endpoint Index](#endpoint-index)
- [DB Mapping](#db-mapping)
- [Endpoints](#endpoints)

<a id="endpoint-index"></a>
## Endpoint Index

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | [`/health`](#health-check) | PUBLIC | Liveness + readiness probe — checks all 5 datastores in parallel |

---

<a id="db-mapping"></a>
## DB Mapping

| Endpoint | Datastores checked |
|----------|--------------------|
| `GET /health` | Postgres, MongoDB, Elasticsearch, Kafka, MinIO |

---

<a id="endpoints"></a>
## Endpoints

### Health check

```
GET /health
Tag: Platform
Auth: PUBLIC
```
**Response 200**
```json
{
  "status": "ok",
  "checks": {
    "postgres": "up",
    "mongodb": "up",
    "elasticsearch": "up",
    "kafka": "up",
    "minio": "up"
  }
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant API as API (NestJS)
    participant HS as HealthService
    participant PG as Postgres
    participant MDB as MongoDB
    participant ES as Elasticsearch
    participant KF as Kafka
    participant MN as MinIO

    C->>API: GET /health
    API->>HS: checkAll()
    par probe Postgres
        HS->>PG: SELECT 1
        PG-->>HS: ok
    and probe MongoDB
        HS->>MDB: db.runCommand({ ping: 1 })
        MDB-->>HS: ok
    and probe Elasticsearch
        HS->>ES: GET /_cluster/health
        ES-->>HS: status green | yellow
    and probe Kafka
        HS->>KF: admin.listTopics()
        KF-->>HS: ok
    and probe MinIO
        HS->>MN: GET /minio/health/live
        MN-->>HS: 200 ok
    end
    HS-->>API: { postgres, mongodb, elasticsearch, kafka, minio }
    API-->>C: 200 { status: ok, checks: { postgres: up, mongodb: up, elasticsearch: up, kafka: up, minio: up } }
```
