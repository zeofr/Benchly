# Alertmanager Service

## Overview

Alertmanager v0.26 receives firing alerts from Prometheus, deduplicates and groups them, applies inhibition and silencing rules, and routes notifications to configured receivers (email, Slack, PagerDuty, etc.).

In the demo stack it is running but the receiver is set to `null` (no external notifications). Swap the receiver config to route alerts to your team's channel.

## Config file: `monitoring/alertmanager/alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait:      30s    # wait before sending first notification for a group
  group_interval:  5m     # how long to wait before sending new alerts for a group
  repeat_interval: 1h     # re-notify if alert is still firing after this interval
  receiver: 'null'        # change this to 'slack' or 'email' for real alerts

receivers:
  - name: 'null'           # discard all alerts (demo default)

  # Uncomment and fill in to enable Slack notifications:
  # - name: 'slack'
  #   slack_configs:
  #     - api_url: 'https://hooks.slack.com/services/T.../B.../...'
  #       channel: '#alerts'
  #       title: '{{ .GroupLabels.alertname }}'
  #       text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

## Alert flow

```
Prometheus evaluates rule
        │
        ▼ (rule fires)
Prometheus sends POST to http://alertmanager:9093/api/v2/alerts
        │
        ▼
Alertmanager groups alerts by alertname + severity
        │
        ▼ (after group_wait 30s)
Routes to receiver
        │
        ▼
Sends notification (Slack, email, PagerDuty, etc.)
```

## Alert labels and annotations

Each alert from `monitoring/prometheus/alerts.yml` includes:

```yaml
labels:
  severity: warning | critical
annotations:
  summary: "One-line description"
  description: "Detailed message with metric value"
```

Alertmanager uses `severity` to route critical alerts to a different (potentially faster) receiver if configured.

## Inhibition rules

Inhibition prevents low-severity alerts from firing when a high-severity alert for the same component is already active. Example: suppress `HighLatency` (warning) when `BackendDown` (critical) is already firing for the same job:

```yaml
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname']
```

(Not configured in the demo — add to `alertmanager.yml` as needed.)

## Access

- URL: `http://localhost:9093`
- UI shows active alerts, silences, and inhibitions

## Docker Compose config

```yaml
alertmanager:
  image: prom/alertmanager:v0.26.0
  volumes:
    - ./monitoring/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
  command:
    - '--config.file=/etc/alertmanager/alertmanager.yml'
  ports:
    - "9093:9093"
```

## Adding a Slack receiver (production example)

1. Create an incoming webhook in your Slack workspace
2. Update `alertmanager.yml`:

```yaml
route:
  receiver: 'slack'

receivers:
  - name: 'slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#benchly-alerts'
        title: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *Severity:* {{ .Labels.severity }}
          *Summary:* {{ .Annotations.summary }}
          *Details:* {{ .Annotations.description }}
          {{ end }}
        send_resolved: true
```

3. Hot-reload:

```bash
curl -X POST http://localhost:9093/-/reload
```

## Silencing an alert

```bash
# Via the UI at http://localhost:9093/#/silences
# Or via the API:
curl -X POST http://localhost:9093/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name": "alertname", "value": "HighCPUUsage", "isRegex": false}],
    "startsAt": "2024-01-01T00:00:00Z",
    "endsAt":   "2024-01-01T02:00:00Z",
    "comment":  "Planned maintenance",
    "createdBy": "admin"
  }'
```
