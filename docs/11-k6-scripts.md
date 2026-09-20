# k6 Load Test Scripts

## Overview

Grafana k6 is the load testing engine. The worker executes k6 as a subprocess for each benchmark run. There are also standalone scripts for different test scenarios. All scripts read configuration from environment variables so the same file can be used in development, CI, and production.

## Scripts location

```
backend/k6/
├── load-test.js       # Standard load test — used by the worker for user-submitted tests
├── smoke-test.js      # Quick sanity check (1 VU, 30s)
├── spike-test.js      # Sudden traffic burst pattern
└── ci-load-test.js    # CI pipeline test — hits the backend's own health/metrics endpoints
```

## `load-test.js` — Worker execution script

This is the script the Worker runs for every user-submitted benchmark.

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_URL` | `http://localhost:4000` | URL under test |
| `VUS` | `10` | Virtual user count |
| `DURATION` | `10s` | Test duration |
| `CUSTOM_HEADERS` | `{}` | JSON object of custom request headers |
| `HTTP_METHOD` | `GET` | HTTP method |

### Test configuration

```js
export const options = {
  vus:      __ENV.VUS      || 10,
  duration: __ENV.DURATION || '10s',
  thresholds: {
    http_req_duration: ['p(95)<2000'],  // 95% of requests under 2s
    http_req_failed:   ['rate<0.1'],    // Less than 10% error rate
  },
};
```

### Request logic

```js
export default function () {
  const headers = JSON.parse(__ENV.CUSTOM_HEADERS || '{}');
  const method  = __ENV.HTTP_METHOD || 'GET';
  const url     = __ENV.TARGET_URL;

  const res = http[method.toLowerCase()](url, null, { headers });
  check(res, { 'status 2xx': (r) => r.status >= 200 && r.status < 300 });
  sleep(1);
}
```

Custom headers (Bearer token, API key, etc.) are forwarded as-is from the user's form submission.

### Output

Worker invokes k6 with `--out json=/tmp/k6-result-<testId>.json`. The JSON output file is parsed by `parseK6Output()` in `worker.js`.

## `smoke-test.js` — Quick sanity check

Run manually to verify the stack is up:

```bash
k6 run backend/k6/smoke-test.js
```

- 1 virtual user
- 30 second duration
- Target: `http://localhost:4000/health`
- Threshold: p95 < 500 ms, error rate < 1%

## `spike-test.js` — Spike traffic pattern

Tests how the service handles a sudden burst:

```js
export const options = {
  stages: [
    { duration: '10s', target: 1   },   // warm-up
    { duration: '10s', target: 100 },   // spike to 100 VUs
    { duration: '10s', target: 1   },   // recover
  ],
};
```

Run manually:
```bash
TARGET_URL=http://localhost:4000/health k6 run backend/k6/spike-test.js
```

## `ci-load-test.js` — CI integration test

Used in GitHub Actions (`integration-test` job). Hits the backend's own endpoints to verify the API is functioning, not just the healthcheck.

```js
export const options = {
  vus:      5,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<3000'],
    http_req_failed:   ['rate<0.05'],
  },
};
```

Scenarios tested:
1. `GET /health` — must return 200
2. `GET /metrics` — must return Prometheus text
3. `GET /api/benchmark` without auth — must return 401
4. `GET /api/benchmark` with `X-API-Key: demo-key-12345` — must return 200

The script writes a summary to `ci-load-test-summary.json` via `handleSummary()`. That file is picked up by `check_regression.py` to compare against `analytics/baseline.json`.

### handleSummary output shape

```json
{
  "avg": 142.5,
  "p95": 320.0,
  "p99": 480.0,
  "rps": 4.8,
  "reqs": 144,
  "error_rate": 0.0069
}
```

## Running scripts manually

```bash
# Full load test against an external API
k6 run \
  --env TARGET_URL=https://httpbin.org/get \
  --env VUS=20 \
  --env DURATION=30s \
  backend/k6/load-test.js

# Smoke test
k6 run backend/k6/smoke-test.js

# Spike test
k6 run backend/k6/spike-test.js

# CI test (requires backend running on :4000)
k6 run --env BASE_URL=http://localhost:4000 backend/k6/ci-load-test.js
```

## k6 installation

k6 is installed in the Docker backend image when `INSTALL_K6=true` build arg is set. For local development:

**macOS:** `brew install k6`

**Linux:**
```bash
curl -L https://github.com/grafana/k6/releases/download/v0.49.0/k6-v0.49.0-linux-amd64.tar.gz \
  | tar xz --strip-components 1 -C /usr/local/bin
```

**Windows:** Download from [k6 releases](https://github.com/grafana/k6/releases) and add to PATH.
