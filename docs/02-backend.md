# Backend Service

## Overview

The backend is an **Express.js REST API** (Node.js) that handles authentication, benchmark job submission, result retrieval, real-time event streaming, and Prometheus metrics exposure. It intentionally does **not** execute k6 directly — that is delegated to the Worker process via a BullMQ queue so the API stays non-blocking.

## Tech stack

| Layer | Library |
|-------|---------|
| HTTP framework | Express 4 |
| Auth | JWT (`jsonwebtoken`) + API key header |
| Queue | BullMQ (backed by Redis) |
| Database | PostgreSQL via `pg` |
| Metrics | `prom-client` |
| Tracing | OpenTelemetry → Jaeger (OTLP HTTP) |
| Logging | Winston |
| Validation | `express-validator` |
| Rate limiting | `express-rate-limit` |

## Source layout

```
backend/src/
├── index.js              # Express app setup and entry point
├── db.js                 # PostgreSQL connection pool + schema init
├── queue.js              # BullMQ queue definition and enqueueLoadTest()
├── worker.js             # Worker process (separate from API — see 03-worker.md)
├── logger.js             # Winston logger (JSON in prod, pretty in dev)
├── tracing.js            # OpenTelemetry SDK init — MUST be required first
├── middleware/
│   ├── auth.js           # JWT verify + API key verify middleware
│   ├── appMetrics.js     # Prometheus middleware — request count, latency histogram
│   └── rateLimiter.js    # Three rate limiters: general, auth, load-test
└── routes/
    ├── auth.js           # POST /auth/login, GET /auth/me
    ├── benchmark.js      # POST /api/benchmark/run, GET /api/benchmark, GET /api/benchmark/:id
    ├── events.js         # GET /api/events/:testId — Server-Sent Events
    └── metrics.js        # GET /metrics — Prometheus text exposition
```

## API routes

### Auth — `/auth`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/login` | None | Accepts `{ username, password }`. Returns JWT + user info. |
| GET | `/auth/me` | Bearer JWT | Returns current user from token. |

Demo credentials (override via env):

| Username | Password | Role |
|----------|----------|------|
| `admin` | `admin123` | admin |
| `demo` | `demo123` | user |

### Benchmark — `/api/benchmark`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/benchmark/run` | Bearer JWT or `X-API-Key` | Submits a load test job. Returns `{ testId, status: 'pending' }`. |
| GET | `/api/benchmark` | Bearer JWT or `X-API-Key` | Lists up to 200 results. |
| GET | `/api/benchmark/:id` | Bearer JWT or `X-API-Key` | Fetches one result by UUID. |

#### POST `/api/benchmark/run` — request body

```json
{
  "apiUrl":   "https://example.com/endpoint",
  "vus":      10,
  "duration": "10s",
  "method":   "GET",
  "headers":  { "Authorization": "Bearer token" }
}
```

Validation rules:
- `apiUrl` — required, valid `http/https` URL, max 2048 chars
- `vus` — optional integer 1–100 (default 10)
- `duration` — optional string matching `/^\d+[smh]$/` (default `"10s"`)
- `headers` — optional JSON object
- `method` — optional, one of `GET POST PUT PATCH DELETE` (default `GET`)

### Events — `/api/events/:testId`

Server-Sent Events endpoint. The client connects and receives `data: {...}` messages when the worker completes a job or updates its status. Connection is cleaned up on client disconnect.

### Metrics — `/metrics`

Prometheus text format scraped by Prometheus every 10 s. Exposes:
- Default Node.js metrics (heap, GC, event loop lag, active handles)
- `http_requests_total{method, route, status_code}` — counter
- `http_request_duration_ms{method, route, status_code}` — histogram (buckets: 50, 100, 200, 400, 800, 1600, 3200 ms)
- `load_tests_total{status}` — counter incremented on queue submission

### Health — `GET /health`

No auth required. Returns:
```json
{ "status": "ok", "timestamp": "...", "version": "2.0.0" }
```
Used by Docker healthcheck, Kubernetes readiness/liveness probes, and the frontend sidebar.

## Middleware order

```
Request
  │
  ├── res.setTimeout(30 000)       # global 30s timeout
  ├── cors()                       # allow frontend origin
  ├── express.json({ limit:'10kb'})# body parsing + size cap
  ├── HTTP request logger (Winston)
  ├── appMetrics.metricsMiddleware # Prometheus histogram start
  ├── generalLimiter               # 100 req/15 min per IP
  │
  ├── /health                      # public
  ├── /auth   → authLimiter (5/15 min)
  ├── /api/benchmark/run → loadTestLimiter (10/hour)
  ├── /api/benchmark → authenticate
  ├── /api/events → open SSE
  └── /metrics → Prometheus scrape
```

## Authentication middleware (`middleware/auth.js`)

Checks in order:
1. `Authorization: Bearer <jwt>` header — verifies with `JWT_SECRET`
2. `X-API-Key: <key>` header — checks against comma-separated `API_KEYS` env var

If neither passes, returns `401`. The decoded JWT payload is attached to `req.user`.

## Rate limiters (`middleware/rateLimiter.js`)

| Limiter | Limit | Applied to |
|---------|-------|-----------|
| `generalLimiter` | 100 req / 15 min | All routes |
| `authLimiter` | 5 req / 15 min | `/auth/login` |
| `loadTestLimiter` | 10 req / hour | `POST /api/benchmark/run` |

## Queue (`queue.js`)

```js
const loadTestQueue = new Queue('load-tests', {
  connection: redisConnection,
  defaultJobOptions: {
    attempts: 2,
    backoff: { type: 'fixed', delay: 5000 },
    removeOnComplete: 100,
    removeOnFail: 50,
  },
});
```

`enqueueLoadTest({ testId, apiUrl, vus, duration, headers, method })` adds a `'run-k6'` job with `jobId = testId` so jobs are deduplicatable.

## Tracing (`tracing.js`)

Initialises the OpenTelemetry Node SDK before any other module. Auto-instruments `express`, `pg`, `ioredis`, and `http`. Spans are exported to Jaeger over OTLP HTTP (`http://jaeger:4318/v1/traces`). Controlled by:

| Env var | Default |
|---------|---------|
| `OTEL_ENABLED` | `"true"` |
| `OTEL_SERVICE_NAME` | `"benchmark-backend"` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `"http://jaeger:4318/v1/traces"` |

## Database (`db.js`)

Connection pool (`pg.Pool`) — 10 max connections. On startup calls `initSchema()` which creates the `benchmark_results` table if it doesn't exist:

```sql
CREATE TABLE IF NOT EXISTS benchmark_results (
  id               SERIAL PRIMARY KEY,
  test_id          UUID UNIQUE NOT NULL,
  api_url          TEXT NOT NULL,
  avg_response_time FLOAT,
  max_response_time FLOAT,
  min_response_time FLOAT,
  requests_per_sec  FLOAT,
  total_requests    INTEGER,
  failed_requests   INTEGER,
  error_rate        FLOAT,
  nl_analysis       TEXT,
  status            TEXT DEFAULT 'pending',
  created_at        TIMESTAMP DEFAULT NOW()
);
```

Key functions:
- `createPendingBenchmark(testId, apiUrl)` — inserts status `'pending'`
- `updateBenchmarkStatus(testId, status)` — sets `'running'`
- `saveBenchmark(data)` — upserts full result row
- `getBenchmark(testId)` — fetch one by UUID
- `getAllBenchmarks(limit)` — fetch latest N

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `4000` | HTTP listen port |
| `NODE_ENV` | `development` | Controls logging format |
| `DB_HOST` | `localhost` | Postgres host |
| `DB_PORT` | `5432` | Postgres port |
| `DB_NAME` | `benchmarkdb` | Database name |
| `DB_USER` | `postgres` | Database user |
| `DB_PASSWORD` | — | Database password |
| `REDIS_HOST` | `localhost` | Redis host |
| `REDIS_PORT` | `6379` | Redis port |
| `JWT_SECRET` | — | Secret for JWT signing |
| `API_KEYS` | `demo-key-12345` | Comma-separated valid API keys |
| `CORS_ORIGIN` | `*` | Allowed CORS origin |
| `LOG_LEVEL` | `info` | Winston log level |
| `OTEL_ENABLED` | `true` | Enable OpenTelemetry |

## Running locally

```bash
cd backend
npm install
cp .env.example .env   # edit as needed

npm run dev            # nodemon — auto-restart on change
npm run test           # Jest unit tests
npm run lint           # ESLint
```
