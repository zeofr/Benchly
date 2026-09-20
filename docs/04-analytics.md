# Analytics Service

## Overview

The analytics service is a **FastAPI microservice** (Python) that wraps a Pandas-based performance analysis engine. It receives k6 benchmark summaries and returns:
- Extracted and normalised metrics
- A natural-language diagnosis (findings + suggestions)
- An HPA replica recommendation based on observed RPS
- A one-line summary for quick scanning

It is called by the Worker after every k6 run and also exposes its own Prometheus metrics endpoint.

## Tech stack

| Component | Library |
|-----------|---------|
| HTTP framework | FastAPI |
| ASGI server | Uvicorn |
| Data analysis | Pandas |
| Validation | Pydantic v2 |
| Metrics | `prometheus_client` |

## Source layout

```
analytics/
├── api.py                 # FastAPI app — routes, Prometheus metrics, payload normalisation
├── processor.py           # Analysis engine — extract_metrics, generate_diagnosis, recommend_hpa
├── ingest_k6.py           # CLI utility: convert raw k6 JSON → compact summary
├── check_regression.py    # CLI utility: compare summary against baseline
├── baseline.json          # Baseline thresholds for regression checks
├── sample_k6_summary.json # Sample input for local testing
├── requirements.txt       # Python dependencies
├── Dockerfile             # Container definition
└── run_local.sh           # One-liner to start with uvicorn --reload
```

## API endpoints

### `POST /analyse`

Main endpoint. Accepts a flexible k6 summary and returns a full analysis.

**Request body** (all fields optional except at least one metric value):

```json
{
  "avg_response_time": 142.5,
  "p95_latency_ms": 380.0,
  "p99_latency_ms": 520.0,
  "requests_per_sec": 18.4,
  "total_requests": 184,
  "error_rate_pct": 1.63,
  "current_replicas": 1
}
```

Also accepts:
- Short aliases: `avg`, `p95`, `p99`, `rps`, `reqs`, `error_rate`
- Full k6 JSON shape: `{ "metrics": { "http_req_duration": {...}, "http_reqs": {...} } }`
- Any extra fields are silently accepted (`extra = "allow"`)

**Response body:**

```json
{
  "metrics": {
    "avg": 142.5,
    "p95": 380.0,
    "rps": 18.4,
    "error_rate": 0.0163
  },
  "diagnosis": {
    "findings": [
      "p95 latency is high (380 ms).",
      "Throughput observed ~18.4 RPS."
    ],
    "suggestions": [
      "Investigate slow database queries, external API calls, and long middleware.",
      "Consider horizontal scaling or optimizing the hot path."
    ]
  },
  "hpa_recommendation": {
    "current_replicas": 1,
    "recommended_replicas": 1,
    "rationale": "Observed RPS 18.4 divided by target_per_pod 200 -> 1 replicas",
    "yaml_snippet": "apiVersion: autoscaling/v2\n..."
  },
  "summary": "p95 latency is high (380 ms). | Throughput observed ~18.4 RPS. | Recommended replicas: 1"
}
```

### `GET /health`

Liveness probe.

```json
{ "status": "ok", "service": "benchly-analytics" }
```

### `GET /metrics`

Prometheus text format. Custom metrics:

| Metric | Type | Description |
|--------|------|-------------|
| `analytics_requests_total{endpoint, status}` | Counter | Total HTTP requests |
| `analytics_request_duration_seconds{endpoint}` | Histogram | Request latency |
| `analytics_analyses_total` | Counter | Benchmark analyses processed |
| `analytics_high_latency_detections_total` | Counter | Runs with p95 > 300 ms |
| `analytics_high_error_rate_detections_total` | Counter | Runs with error rate > 1% |

### `GET /`

Returns a service info object listing all endpoints.

## Analysis engine (`processor.py`)

### `extract_metrics(summary)`

Walks the input dictionary and maps all known field name variants to a canonical flat dict:
- Tries compact keys first (`avg`, `p95`, `p99`, `rps`, `reqs`, `error_rate`)
- Falls back to full k6 JSON nested structure (`metrics.http_req_duration.values.p(95)`)
- Detects values in seconds (< 0.01) and converts to ms

### `generate_diagnosis(metrics)`

Applies threshold rules:

| Condition | Finding | Suggestion |
|-----------|---------|------------|
| p95 > 300 ms | "p95 latency is high" | Investigate slow DB queries, external calls, middleware |
| error_rate > 1% | "High error rate: X%" | Add retries, tighten validation, improve error logging |
| RPS present | "Throughput observed ~X RPS" | Combined with latency check for scale suggestion |
| No latency data | "Latency metrics missing" | Capture `http_req_duration` in k6 |

### `recommend_hpa(metrics, current_replicas)`

Formula: `desired = ceil(rps / 200)` where 200 = `DEFAULT_TARGET_RPS_PER_POD`.

Returns a dict with `recommended_replicas`, the calculation rationale, and a ready-to-apply HPA YAML snippet.

## Payload normalisation (`api.py — _normalise_payload`)

Handles the mismatch between the frontend's compact format and processor.py's expected field names:

```
avg_response_time  →  avg
p95_latency_ms     →  p95
p99_latency_ms     →  p99
requests_per_sec   →  rps
total_requests     →  reqs
error_rate_pct     →  error_rate  (÷100 to convert % → ratio)
```

Any `error_rate` value > 1.0 is also auto-converted from percent to ratio.

## Regression check CLI (`check_regression.py`)

Used in CI (`pr-analytics` GitHub Actions job) to detect performance regressions:

```bash
python analytics/check_regression.py summary.json analytics/baseline.json
```

Compares `p95_latency_ms` and `error_rate` against baseline values with a configurable tolerance (default 20%). Exits `1` if any regression is detected, `0` otherwise.

`baseline.json` example:
```json
{
  "p95_latency_ms": 200,
  "error_rate": 0.01,
  "tolerance_percent": 20
}
```

## Docker

```bash
docker build -t benchly-analytics ./analytics
docker run -p 8001:8001 benchly-analytics
```

The Dockerfile installs Python dependencies with `pip install --no-cache-dir` and starts Uvicorn:

```dockerfile
CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8001"]
```

## Running locally

```bash
cd analytics
pip install -r requirements.txt
uvicorn api:app --host 0.0.0.0 --port 8001 --reload

# Or
bash run_local.sh
```

Test the endpoint:
```bash
curl -X POST http://localhost:8001/analyse \
  -H 'Content-Type: application/json' \
  -d @sample_k6_summary.json | python -m json.tool
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | — | Reserved for future LLM-powered diagnosis (not currently used) |
