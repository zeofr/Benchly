# Grafana Service

## Overview

Grafana v10.2 provides the **visualization layer** for all Prometheus metrics. It comes pre-provisioned with a Prometheus datasource and a Benchly-specific dashboard so it works out of the box with no manual setup.

## Access

| Setting | Value |
|---------|-------|
| URL | `http://localhost:3001` |
| Username | `admin` |
| Password | `admin` (or `$GRAFANA_PASSWORD` env var) |

## Provisioning layout

```
monitoring/grafana/
├── provisioning/
│   ├── datasources/
│   │   └── prometheus.yml    # Auto-wires Prometheus datasource
│   └── dashboards/
│       └── dashboard.yml     # Tells Grafana where to load dashboard JSON files
└── dashboards/
    └── benchmark-dashboard.json   # Main Benchly dashboard
```

### Datasource provisioning (`provisioning/datasources/prometheus.yml`)

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

This runs at container start — no need to add the datasource manually.

### Dashboard provisioning (`provisioning/dashboards/dashboard.yml`)

```yaml
apiVersion: 1
providers:
  - name: Benchly
    folder: Benchly
    type: file
    options:
      path: /var/lib/grafana/dashboards
```

All `.json` files in `/var/lib/grafana/dashboards` are loaded automatically.

## Main dashboard panels

The `benchmark-dashboard.json` includes panels for:

| Panel | Metric | Visualization |
|-------|--------|--------------|
| Request Rate | `rate(http_requests_total[1m])` | Time series |
| p95 Latency | `histogram_quantile(0.95, rate(...[5m]))` | Time series |
| Error Rate % | `rate(5xx) / rate(all) * 100` | Stat + time series |
| Active Load Tests | `load_tests_total{status="queued"}` | Stat |
| Heap Memory % | `heap_used / heap_total * 100` | Gauge |
| CPU Usage % | `rate(process_cpu_seconds_total[2m]) * 100` | Time series |
| Event Loop Lag | `nodejs_eventloop_lag_mean_seconds * 1000` | Time series |
| Analytics Analyses | `analytics_analyses_total` | Stat |

## Docker Compose config

```yaml
grafana:
  image: grafana/grafana:10.2.3
  environment:
    GF_SECURITY_ADMIN_USER:     admin
    GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:-admin}
    GF_USERS_ALLOW_SIGN_UP:     "false"
  volumes:
    - grafana_data:/var/lib/grafana
    - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
    - ./monitoring/grafana/dashboards:/var/lib/grafana/dashboards:ro
  depends_on:
    prometheus:
      condition: service_healthy
```

Dashboard data persists in the `grafana_data` named volume.

## Kubernetes

`k8s/grafana.yaml` deploys Grafana with the same provisioning volumes mounted from a ConfigMap. The service is a `ClusterIP` exposed internally; use port-forward or an Ingress to access it:

```bash
kubectl port-forward -n benchmark svc/grafana 3001:3000
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GF_SECURITY_ADMIN_USER` | `admin` | Admin username |
| `GF_SECURITY_ADMIN_PASSWORD` | `admin` | Admin password |
| `GF_USERS_ALLOW_SIGN_UP` | `"false"` | Disable self-registration |

## Importing / exporting dashboards

Export a dashboard from the Grafana UI (Share → Export JSON) and save to `monitoring/grafana/dashboards/`. It will be picked up automatically on next container start.

## Alert notifications (via Alertmanager)

Grafana does not directly receive Prometheus alerts — those are routed through Alertmanager (see `09-alertmanager.md`). Grafana can be configured with its own contact points for dashboard alerts (Grafana-managed alerts), but in this project alerting is handled by Prometheus + Alertmanager.
