/**
 * k6 Spike Test — designed to trigger HPA scaling
 *
 * This test ramps from 0 to 50 virtual users in 30 seconds,
 * then sustains load for 2 minutes to keep CPU above the 70% HPA threshold,
 * then drops back to 0.
 *
 * Expected behavior with HPA:
 *   0–30s:   ramp up → CPU rises → HPA detects threshold breach
 *   30–90s:  30s stabilization window → HPA scales from 2 → 3 → up to 5 replicas
 *   90–150s: sustained load, HPA may add more replicas
 *   150–180s: ramp down → CPU falls → replicas stay for 5min cooldown
 *
 * Usage (against local Minikube backend via NodePort):
 *   MINIKUBE_IP=$(minikube ip)
 *   k6 run --env BASE_URL=http://$MINIKUBE_IP:30080 backend/k6/spike-test.js
 *
 * Usage (against backend Service directly via port-forward):
 *   kubectl port-forward svc/backend 4000:4000 -n benchmark &
 *   k6 run --env BASE_URL=http://localhost:4000 backend/k6/spike-test.js
 *
 * Watch HPA in another terminal:
 *   watch -n 2 kubectl get hpa -n benchmark
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

var errorRate    = new Rate('spike_error_rate');
var responseTime = new Trend('spike_response_time');
var requestCount = new Counter('spike_total_requests');

export var options = {
  stages: [
    // Phase 1: warm up — 2 VUs for 30s (establishes baseline, 2 replicas should handle this)
    { duration: '30s',  target: 2  },
    // Phase 2: ramp up — increase to 30 VUs over 30s
    // This is where CPU will breach 70% and HPA should trigger
    { duration: '30s',  target: 30 },
    // Phase 3: sustain spike — hold at 30 VUs for 90s
    // HPA has time to scale from 2 → 3 → 4 replicas
    { duration: '90s',  target: 30 },
    // Phase 4: peak — push to 50 VUs for 30s (may reach max 5 replicas)
    { duration: '30s',  target: 50 },
    // Phase 5: ramp down — reduce load
    { duration: '30s',  target: 0  },
  ],
  thresholds: {
    // We expect some degradation during spike — p99 < 3s is acceptable
    'http_req_duration': ['p(95)<3000', 'p(99)<5000'],
    // Error rate should stay below 10% even under spike
    'spike_error_rate': ['rate<0.10'],
  },
};

export default function () {
  var baseUrl = __ENV.BASE_URL || 'http://localhost:4000';
  var apiKey  = __ENV.API_KEY  || 'demo-key-12345';

  var params = {
    headers: {
      'Accept':    'application/json',
      'X-API-Key': apiKey,
    },
    timeout: '10s',
  };

  // ── Request 1: Health check (lightweight — measures pod responsiveness) ────
  var healthRes = http.get(baseUrl + '/health', params);
  responseTime.add(healthRes.timings.duration);
  errorRate.add(healthRes.status === 0 || healthRes.status >= 500);
  requestCount.add(1);

  check(healthRes, {
    'health: responded':   function(r) { return r.status > 0; },
    'health: not 5xx':     function(r) { return r.status < 500; },
    'health: under 2s':    function(r) { return r.timings.duration < 2000; },
  });

  sleep(0.1);

  // ── Request 2: Benchmark history (DB query — heavier, drives CPU/IO) ──────
  var historyRes = http.get(baseUrl + '/api/benchmark/history', params);
  responseTime.add(historyRes.timings.duration);
  // 401 is auth-valid — only count real failures
  errorRate.add(historyRes.status === 0 || historyRes.status >= 500);
  requestCount.add(1);

  check(historyRes, {
    'history: responded':  function(r) { return r.status > 0; },
    'history: not 5xx':    function(r) { return r.status < 500; },
  });

  sleep(0.1);

  // ── Request 3: Metrics endpoint (Prometheus scrape simulation) ────────────
  var metricsRes = http.get(baseUrl + '/metrics', { timeout: '5s' });
  requestCount.add(1);

  check(metricsRes, {
    'metrics: status 200': function(r) { return r.status === 200; },
  });

  sleep(0.2);
}

export function handleSummary(data) {
  var dur    = (data.metrics && data.metrics.http_req_duration && data.metrics.http_req_duration.values) || {};
  var reqs   = (data.metrics && data.metrics.http_reqs && data.metrics.http_reqs.values) || {};
  var errors = (data.metrics && data.metrics.spike_error_rate && data.metrics.spike_error_rate.values) || {};

  console.log('\n=== SPIKE TEST SUMMARY ===');
  console.log('Total requests:  ' + (reqs.count    || 0));
  console.log('RPS (avg):       ' + ((reqs.rate     || 0).toFixed(2)));
  console.log('p50 latency:     ' + ((dur['p(50)']  || 0).toFixed(0)) + 'ms');
  console.log('p95 latency:     ' + ((dur['p(95)']  || 0).toFixed(0)) + 'ms');
  console.log('p99 latency:     ' + ((dur['p(99)']  || 0).toFixed(0)) + 'ms');
  console.log('Error rate:      ' + (((errors.rate  || 0) * 100).toFixed(2)) + '%');
  console.log('=========================\n');

  return {
    stdout: JSON.stringify({
      total_requests:    reqs.count    || 0,
      requests_per_sec:  reqs.rate     || 0,
      p50_latency_ms:    dur['p(50)']  || 0,
      p95_latency_ms:    dur['p(95)']  || 0,
      p99_latency_ms:    dur['p(99)']  || 0,
      error_rate_pct:    (errors.rate  || 0) * 100,
    }, null, 2),
    'spike-test-summary.json': JSON.stringify({
      total_requests:    reqs.count    || 0,
      requests_per_sec:  reqs.rate     || 0,
      p50_latency_ms:    dur['p(50)']  || 0,
      p95_latency_ms:    dur['p(95)']  || 0,
      p99_latency_ms:    dur['p(99)']  || 0,
      error_rate_pct:    (errors.rate  || 0) * 100,
    }, null, 2),
  };
}
