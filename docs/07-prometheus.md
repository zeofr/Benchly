# Prometheus Service

## Overview

Prometheus v2.48 is the **metrics collection and alerting engine**. It scrapes metric endpoints from the backend and analytics services every 10–15 seconds, evaluates alert rules, and feeds data to Grafana for visualisation.

## Config file: `monitoring/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval:     15s    # default poll frequency
  evaluation_interval: 15s    # how often alert rules are evaluated

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - /etc/prometheus/alerts.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'benchmark-backend'
    static_configs:
      - targets: ['backend:4000']
    metrics_path: '/metrics'
    scrape_interval: 10s        # faster for API metrics

  - job_name: 'benchmark-analytics'
    static_configs:
      - targets: ['analytics:8001']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

## Scraped metrics

### Backend (`backend:4000/metrics`)

| Metric | Type | Description |
|--------|------|-------------|
| `http_requests_total{method,route,status_code}` | Counter | HTTP request count |
| `http_request_duration_ms{method,route,status_code}` | Histogram | Request latency in ms |
| `load_tests_total{status}` | Counter | Load tests queued / failed |
| `nodejs_heap_size_used_bytes` | Gauge | Node.js heap memory used |
| `nodejs_heap_size_total_bytes` | Gauge | Node.js heap memory allocated |
| `process_cpu_seconds_total` | Counter | CPU time used |
| `nodejs_eventloop_lag_mean_seconds` | Gauge | Event loop lag |

### Analytics (`analytics:8001/metrics`)

| Metric | Type | Description |
|--------|------|-------------|
| `analytics_requests_total{endpoint,status}` | Counter | HTTP requests to analytics API |
| `analytics_request_duration_seconds{endpoint}` | Histogram | Analytics request latency |
| `analytics_analyses_total` | Counter | Total benchmark analyses |
| `analytics_high_latency_detections_total` | Counter | Detections of p95 > 300 ms |
| `analytics_high_error_rate_detections_total` | Counter | Detections of error rate > 1% |

## Alert rules: `monitoring/prometheus/alerts.yml`

| Alert | Expression | Severity | Fires after |
|-------|-----------|----------|-------------|
| `HighCPUUsage` | `rate(process_cpu_seconds_total[2m]) * 100 > 80` | warning | 2 min |
| `HighMemoryUsage` | `nodejs_heap_size_used / nodejs_heap_size_total * 100 > 85` | warning | 2 min |
| `HighErrorRate` | `rate(5xx) / rate(all) * 100 > 5` | critical | 1 min |
| `HighLatency` | `histogram_quantile(0.95, ...) > 2000 ms` | warning | 2 min |
| `BackendDown` | `up{job="benchmark-backend"} == 0` | critical | 30 s |
| `EventLoopLag` | `nodejs_eventloop_lag_mean_seconds * 1000 > 500` | warning | 1 min |

When an alert fires, Prometheus sends it to Alertmanager at `alertmanager:9093`.

## Useful PromQL queries

```promql
# p95 request latency over 5 minutes
histogram_quantile(0.95, rate(http_request_duration_ms_bucket[5m]))

# Request rate per second
rate(http_requests_total[1m])

# Error rate percentage
rate(http_requests_total{status_code=~"5.."}[5m])
/ rate(http_requests_total[5m]) * 100

# Heap memory usage percentage
nodejs_heap_size_used_bytes / nodejs_heap_size_total_bytes * 100

# Event loop lag in ms
nodejs_eventloop_lag_mean_seconds * 1000
```

## Access

- URL: `http://localhost:9090`
- No authentication (demo — add `--web.config.file` with basic auth for production)

## Docker Compose config

```yaml
prometheus:
  image: prom/prometheus:v2.48.1
  volumes:
    - ./monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - ./monitoring/prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.path=/prometheus'
    - '--web.enable-lifecycle'       # allows POST /-/reload for config hot-reload
  ports:
    - "9090:9090"
```

## Hot-reloading config

If you update `prometheus.yml` without restarting:

```bash
curl -X POST http://localhost:9090/-/reload
```

## Kubernetes

Prometheus is deployed via `k8s/prometheus.yaml`. In the K8s environment, pod annotations drive scraping:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port:   "4000"
  prometheus.io/path:   "/metrics"
```

Prometheus uses pod service discovery (`kubernetes_sd_configs`) to automatically pick up annotated pods.
