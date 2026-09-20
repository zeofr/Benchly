# Worker Service

## Overview

The worker is a **separate Node.js process** that consumes jobs from the BullMQ `load-tests` queue, executes k6 as a child process, parses the JSON output, persists results to PostgreSQL, and calls the Analytics service for AI-powered diagnosis.

It shares the same Docker image as the backend but is started with `node src/worker.js` instead of `node src/index.js`.

## Why a separate worker?

Running k6 inside the API process would block the Node.js event loop for the full test duration (10 s – 2 min). Separating it means:
- The API stays responsive while tests run
- Up to 3 tests can run concurrently (configurable)
- The worker can be scaled independently
- Failures in k6 don't crash the API

## Entry point: `backend/src/worker.js`

```
Startup
  │
  ├── require('./tracing')          # OpenTelemetry init
  ├── require('dotenv').config()
  ├── db.connect()                  # Postgres pool
  └── new Worker('load-tests', processJob, { concurrency: 3 })

processJob({ testId, apiUrl, vus, duration, headers, method })
  │
  ├── db.updateBenchmarkStatus(testId, 'running')
  ├── execFile('k6', [...args], env, callback)
  │     ├── success → parseK6Output(outputPath)
  │     │             db.saveBenchmark({ status: 'completed', ...metrics })
  │     │             callAnalyticsService(testId, metrics) [async, non-blocking]
  │     │             notifyClients(testId, result)   # SSE push
  │     └── error   → db.saveBenchmark({ status: 'failed', error_rate: 100 })
  └── fs.unlinkSync(outputPath)     # cleanup tmp file
```

## k6 execution

The worker calls k6 with:

```bash
k6 run \
  --out json=/tmp/k6-result-<testId>.json \
  --env TARGET_URL=<apiUrl> \
  --env VUS=<vus> \
  --env DURATION=<duration> \
  --env CUSTOM_HEADERS=<json> \
  --env HTTP_METHOD=<method> \
  backend/k6/load-test.js
```

- `execFile` is used (not `exec`) to avoid shell injection
- A 5-minute hard timeout is set on the child process
- Custom headers and HTTP method are passed via env vars to the k6 script

## Output parsing (`parseK6Output`)

k6 with `--out json` writes one JSON object per line (NDJSON). The parser:
1. Reads the file, splits on `\n`
2. Collects `Point` entries grouped by metric name
3. Computes avg / max / min from `http_req_duration` data points
4. Counts total requests from `http_reqs` points
5. Counts failed requests from `http_req_failed` points (value = 1 means failed)
6. Derives `requests_per_sec` as `total / durationSeconds`
7. Derives `error_rate` as `(failed / total) * 100`

Returns a flat metrics object:

```js
{
  avg_response_time: 142.5,   // ms
  max_response_time: 890.1,
  min_response_time: 12.3,
  requests_per_sec:  18.4,
  total_requests:    184,
  failed_requests:   3,
  error_rate:        1.63      // percent
}
```

## Analytics service call (`callAnalyticsService`)

After saving numeric results, the worker fires an HTTP POST to `http://analytics:8001/analyse` with the metrics. This is **non-blocking** — a failure just logs a warning and the benchmark result is still saved without the NL analysis field.

If the analytics service responds, the worker calls `db.saveBenchmark` again with `nl_analysis: JSON.stringify(response)` to persist the diagnosis alongside the metrics.

## SSE notification (`notifyClients`)

Imported from `routes/events.js`. Pushes the result JSON to any open SSE connections for `testId`, which immediately updates the frontend without polling.

## BullMQ configuration

```js
new Worker('load-tests', handler, {
  connection: redisConnection,
  concurrency: 3,   // process up to 3 k6 runs simultaneously
})
```

Job options (set on the queue in `queue.js`):
- `attempts: 2` — retried once on failure with 5 s delay
- `removeOnComplete: 100` — keeps last 100 job records in Redis
- `removeOnFail: 50` — keeps last 50 failed records

## Event handlers

```js
worker.on('completed', (job) => { logger.info('Job completed', ...) })
worker.on('failed',    (job, err) => { logger.error('Job failed', ...) })
worker.on('error',     (err) => { logger.error('Worker error', ...) })
```

## Graceful shutdown

On `SIGTERM` or `SIGINT`:
1. `worker.close()` — drains in-flight jobs (waits for running handlers)
2. `db.pool.end()` — releases Postgres connections
3. `process.exit(0)`

## Environment variables

Same as the backend plus:

| Variable | Default | Description |
|----------|---------|-------------|
| `ANALYTICS_URL` | `http://analytics:8001` | FastAPI analytics base URL |

All other variables (`DB_*`, `REDIS_*`, `OTEL_*`, `LOG_LEVEL`) are shared with the backend.

## Running locally

```bash
cd backend
npm run start:worker      # production
npm run dev:worker        # nodemon watch mode
```

k6 must be installed and on PATH. In the Docker image it is installed during build:

```dockerfile
ARG INSTALL_K6=false
RUN if [ "$INSTALL_K6" = "true" ]; then \
    curl -L https://github.com/grafana/k6/releases/download/v0.49.0/k6-v0.49.0-linux-amd64.tar.gz \
    | tar xz --strip-components 1 -C /usr/local/bin k6-v0.49.0-linux-amd64/k6; \
  fi
```
