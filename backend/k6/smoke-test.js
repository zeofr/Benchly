/**
 * k6 Smoke Test — minimal load to verify the stack is alive
 *
 * Runs 1 VU for 30 seconds. If this fails, something is fundamentally broken.
 * Run this first after deploying to Kubernetes to confirm everything works
 * before running the spike test.
 *
 * Usage:
 *   MINIKUBE_IP=$(minikube ip)
 *   k6 run --env BASE_URL=http://$MINIKUBE_IP:30080 backend/k6/smoke-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';

export var options = {
  vus:      1,
  duration: '30s',
  thresholds: {
    'http_req_duration': ['p(95)<500'],
    'http_req_failed':   ['rate<0.01'],
    'checks':            ['rate>0.99'],
  },
};

export default function () {
  var baseUrl = __ENV.BASE_URL || 'http://localhost:4000';
  var apiKey  = __ENV.API_KEY  || 'demo-key-12345';

  var health = http.get(baseUrl + '/health');
  check(health, {
    'smoke: health 200':        function(r) { return r.status === 200; },
    'smoke: has ok status':     function(r) {
      try { return JSON.parse(r.body).status === 'ok'; } catch(e) { return false; }
    },
    'smoke: response under 1s': function(r) { return r.timings.duration < 1000; },
  });

  var metrics = http.get(baseUrl + '/metrics');
  check(metrics, {
    'smoke: metrics 200':       function(r) { return r.status === 200; },
    'smoke: prometheus format': function(r) { return r.body.indexOf('# HELP') !== -1; },
  });

  var authed = http.get(baseUrl + '/api/benchmark/history', {
    headers: { 'X-API-Key': apiKey },
  });
  check(authed, {
    'smoke: auth works':        function(r) { return r.status === 200; },
  });

  sleep(1);
}
