# Jaeger (Distributed Tracing)

## Overview

Jaeger v1.52 provides **distributed tracing** for the Benchly stack. The backend and worker automatically emit OpenTelemetry spans for every incoming HTTP request, outbound DB query, Redis operation, and HTTP client call. These traces are collected in Jaeger and visualised in its UI, making it easy to find slow or failing operations.

## Access

- Jaeger UI: `http://localhost:16686`
- OTLP HTTP receiver: `http://localhost:4318`
- OTLP gRPC receiver: `localhost:4317`

## OpenTelemetry instrumentation (`backend/src/tracing.js`)

```js
require('./tracing');   // MUST be the very first require in index.js and worker.js
```

The tracing module initialises the OTel Node SDK:

```js
const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'benchmark-backend',
  }),
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://jaeger:4318/v1/traces',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```

**Auto-instrumented libraries:**
- `express` — span per incoming request (route, method, status code)
- `pg` — span per SQL query (statement, db name)
- `ioredis` — span per Redis command
- `http` / `https` — span per outbound HTTP call
- `dns` — span per DNS resolution

## Span attributes

Each request span includes:
- `http.method`, `http.route`, `http.status_code`
- `http.url`, `net.peer.name`
- `db.system`, `db.statement` (for DB queries)
- `messaging.system`, `messaging.destination` (for Redis)

## Service names

| Process | Service name in Jaeger |
|---------|----------------------|
| Backend API | `benchmark-backend` |
| Worker | `benchmark-worker` |

Set via `OTEL_SERVICE_NAME` environment variable.

## Trace example

A `POST /api/benchmark/run` trace looks like:

```
POST /api/benchmark/run (12ms)
  ├── authenticate middleware (1ms)
  ├── express-validator (0.5ms)
  ├── pg.query — INSERT INTO benchmark_results ... (3ms)
  └── redis.lpush — bull:load-tests:waiting (2ms)
```

A worker job trace:

```
processJob (15s total)
  ├── pg.query — UPDATE benchmark_results SET status='running' (2ms)
  ├── child_process.execFile k6 (14.8s)
  ├── pg.query — INSERT/UPDATE benchmark_results (5ms)
  └── http.request — POST analytics:8001/analyse (120ms)
```

## Docker Compose config

```yaml
jaeger:
  image: jaegertracing/all-in-one:1.52
  environment:
    COLLECTOR_OTLP_ENABLED: "true"
  ports:
    - "16686:16686"   # Jaeger UI
    - "4317:4317"     # OTLP gRPC
    - "4318:4318"     # OTLP HTTP  ← used by backend / worker
```

`all-in-one` bundles the agent, collector, query, and UI in a single process. For production use the separate `jaeger-collector` + `jaeger-query` components with a persistent backend (Elasticsearch or Cassandra).

## Kubernetes

`k8s/jaeger.yaml` deploys Jaeger `all-in-one` as a `Deployment` + `ClusterIP` service. Access via:

```bash
kubectl port-forward -n benchmark svc/jaeger 16686:16686
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OTEL_ENABLED` | `"true"` | Set to `"false"` to disable tracing |
| `OTEL_SERVICE_NAME` | `benchmark-backend` | Service name shown in Jaeger |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://jaeger:4318/v1/traces` | OTLP HTTP collector URL |

## Disabling tracing in tests

The CI pipeline sets `OTEL_ENABLED=false` to avoid connection errors to Jaeger when running unit tests:

```yaml
env:
  OTEL_ENABLED: "false"
```

The `tracing.js` module checks this flag and skips SDK initialisation when false.
