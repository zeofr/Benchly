# PostgreSQL Service

## Overview

PostgreSQL 15 is the primary persistent data store. It holds all benchmark run records — configuration, status, numeric results, and the analytics diagnosis text. It is also the source of truth for the results history and comparison views.

## Connection details

| Setting | Docker Compose | Kubernetes |
|---------|---------------|------------|
| Host | `postgres` | `postgres` (ClusterIP service) |
| Port | `5432` | `5432` |
| Database | `benchmarkdb` | `benchmarkdb` (from Secret) |
| User | `postgres` | `postgres` (from Secret) |
| Password | `$POSTGRES_PASSWORD` (env) | Kubernetes Secret `db-secret` |

## Schema

The backend auto-creates the schema on startup via `db.initSchema()`.

```sql
CREATE TABLE IF NOT EXISTS benchmark_results (
  id                SERIAL PRIMARY KEY,
  test_id           UUID    UNIQUE NOT NULL,
  api_url           TEXT    NOT NULL,
  avg_response_time FLOAT,
  max_response_time FLOAT,
  min_response_time FLOAT,
  requests_per_sec  FLOAT,
  total_requests    INTEGER,
  failed_requests   INTEGER,
  error_rate        FLOAT,
  nl_analysis       TEXT,         -- JSON string from analytics service
  status            TEXT    DEFAULT 'pending',   -- pending | running | completed | failed
  created_at        TIMESTAMP DEFAULT NOW()
);
```

### Status lifecycle

```
pending  →  running  →  completed
                     ↘  failed
```

`pending` is set by the API on job submission. `running` is set by the Worker when k6 starts. `completed` or `failed` is set when k6 finishes.

## Queries (from `backend/src/db.js`)

| Function | SQL |
|----------|-----|
| `createPendingBenchmark(testId, apiUrl)` | `INSERT INTO benchmark_results (test_id, api_url, status) VALUES ($1, $2, 'pending')` |
| `updateBenchmarkStatus(testId, status)` | `UPDATE benchmark_results SET status=$2 WHERE test_id=$1` |
| `saveBenchmark(data)` | `INSERT ... ON CONFLICT (test_id) DO UPDATE SET ...` — full upsert |
| `getBenchmark(testId)` | `SELECT * FROM benchmark_results WHERE test_id=$1` |
| `getAllBenchmarks(limit)` | `SELECT * FROM benchmark_results ORDER BY created_at DESC LIMIT $1` |

## Connection pool

Configured via `pg.Pool`:

```js
const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     process.env.DB_PORT     || 5432,
  database: process.env.DB_NAME     || 'benchmarkdb',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD,
  max: 10,                         // max simultaneous connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

## Docker Compose config

```yaml
postgres:
  image: postgres:15-alpine
  environment:
    POSTGRES_DB:       benchmarkdb
    POSTGRES_USER:     postgres
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-demo123}
  volumes:
    - postgres_data:/var/lib/postgresql/data    # persistent across restarts
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U postgres"]
    interval: 10s
    retries: 5
```

Data is persisted in the `postgres_data` named volume. Remove it with `docker volume rm benchly_postgres_data` to reset.

## Kubernetes

Deployed as a single-replica `Deployment` + `ClusterIP` service. Credentials are injected from the `db-secret` Secret.

In the Terraform config, a `kubernetes_secret` resource creates `db-secret` with `DB_USER`, `DB_PASSWORD`, and `DB_NAME` from variables. For production use a managed database (AWS RDS, Cloud SQL, etc.) instead.

## Backup / restore

```bash
# Backup
docker exec benchmark-postgres pg_dump -U postgres benchmarkdb > backup.sql

# Restore
docker exec -i benchmark-postgres psql -U postgres benchmarkdb < backup.sql
```

## Connecting manually

```bash
docker exec -it benchmark-postgres psql -U postgres -d benchmarkdb

# Useful queries
SELECT test_id, api_url, status, avg_response_time, created_at
FROM benchmark_results
ORDER BY created_at DESC
LIMIT 20;
```
