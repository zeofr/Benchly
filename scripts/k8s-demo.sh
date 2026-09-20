#!/usr/bin/env bash
# =============================================================================
# Benchly — Live Demo Script (HPA Scaling Demo)
# =============================================================================
# This is the sequence of commands to demonstrate during an interview.
# Run it after k8s-setup.sh has completed successfully.
#
# What this demonstrates:
#   1. Cluster and pod health
#   2. Services routing
#   3. Prometheus receiving metrics
#   4. Grafana showing dashboards
#   5. k6 spike test generating load
#   6. HPA detecting CPU threshold breach
#   7. Replica count scaling from 2 → up to 5
#   8. Load-down triggering scale-down cooldown
# =============================================================================

set -euo pipefail

NAMESPACE="benchmark"
MINIKUBE_IP=$(minikube ip)
BACKEND_URL="http://$MINIKUBE_IP:30080"

echo ""
echo "============================================="
echo "  Benchly — HPA Scaling Demo"
echo "============================================="
echo ""

# ── Phase 1: Verify cluster health ───────────────────────────────────────────
echo "PHASE 1: Cluster Health Check"
echo "─────────────────────────────"
echo ""

echo "Nodes:"
kubectl get nodes
echo ""

echo "All pods in benchmark namespace:"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""

echo "Services:"
kubectl get services -n "$NAMESPACE"
echo ""

echo "HPA (current state — should show 2/2 replicas before load):"
kubectl get hpa -n "$NAMESPACE"
echo ""

# ── Phase 2: Verify backend is reachable ─────────────────────────────────────
echo "PHASE 2: Backend Health Verification"
echo "─────────────────────────────────────"
echo ""

echo "Testing health endpoint: $BACKEND_URL/health"
HEALTH=$(curl -sf "$BACKEND_URL/health" 2>/dev/null || echo '{"error":"unreachable"}')
echo "$HEALTH" | python3 -m json.tool 2>/dev/null || echo "$HEALTH"
echo ""

echo "Testing metrics endpoint (first 5 lines):"
curl -sf "$BACKEND_URL/metrics" 2>/dev/null | head -5 || echo "metrics endpoint not reachable via frontend — try direct port-forward"
echo ""

# ── Phase 3: Run smoke test ───────────────────────────────────────────────────
echo "PHASE 3: Smoke Test (1 VU, 30s — confirms stack is healthy)"
echo "─────────────────────────────────────────────────────────────"
echo ""
echo "Running: k6 run --env BASE_URL=$BACKEND_URL backend/k6/smoke-test.js"
echo ""

k6 run \
  --env BASE_URL="$BACKEND_URL" \
  --env API_KEY="demo-key-12345" \
  backend/k6/smoke-test.js

echo ""

# ── Phase 4: Start HPA watcher in background ─────────────────────────────────
echo "PHASE 4: Starting HPA watcher in background"
echo "─────────────────────────────────────────────"
echo ""
echo "Watching HPA every 10s (in separate process)..."
echo "You will see replica count change as load increases."
echo ""

# Write HPA observations to a log file for the debrief
HPA_LOG="/tmp/benchly-hpa-log.txt"
> "$HPA_LOG"

(
  while true; do
    TIMESTAMP=$(date '+%H:%M:%S')
    HPA_LINE=$(kubectl get hpa backend-hpa -n "$NAMESPACE" \
      --no-headers 2>/dev/null || echo "hpa not available")
    echo "$TIMESTAMP  $HPA_LINE" | tee -a "$HPA_LOG"
    sleep 10
  done
) &
HPA_WATCHER_PID=$!

echo "HPA watcher PID: $HPA_WATCHER_PID"
echo "Logs: $HPA_LOG"
echo ""

# ── Phase 5: Spike test ───────────────────────────────────────────────────────
echo "PHASE 5: SPIKE TEST — Watch Replicas Scale!"
echo "─────────────────────────────────────────────"
echo ""
echo "Load profile:"
echo "  0–30s:    warm up  (2 VUs)"
echo "  30–60s:   ramp up  (2 → 30 VUs) ← HPA threshold breach expected here"
echo "  60–150s:  sustain  (30 VUs)      ← Replicas scale 2 → 3 → 4 → 5"
echo "  150–180s: peak     (50 VUs)"
echo "  180–210s: ramp down (50 → 0)"
echo ""
echo "Running spike test now..."
echo ""

k6 run \
  --env BASE_URL="$BACKEND_URL" \
  --env API_KEY="demo-key-12345" \
  backend/k6/spike-test.js

echo ""
echo "Spike test complete."
echo ""

# ── Phase 6: Post-load HPA state ─────────────────────────────────────────────
echo "PHASE 6: Post-Load State"
echo "─────────────────────────"
echo ""

echo "HPA state immediately after spike (note: scale-down has 5min cooldown):"
kubectl get hpa -n "$NAMESPACE"
echo ""

echo "Pod count:"
kubectl get pods -n "$NAMESPACE" -l app=backend
echo ""

echo "HPA scale log (from watcher):"
cat "$HPA_LOG"
echo ""

# Stop HPA watcher
kill "$HPA_WATCHER_PID" 2>/dev/null || true

# ── Phase 7: Observability ───────────────────────────────────────────────────
echo "PHASE 7: Observability"
echo "─────────────────────"
echo ""
echo "Open Grafana to see the spike in charts:"
echo "  URL:      http://$MINIKUBE_IP:30300"
echo "  Login:    admin / admin"
echo "  Dashboard: Benchly → Benchly — API Performance"
echo ""
echo "Metrics to point out in Grafana:"
echo "  - HTTP Request Rate: spike visible"
echo "  - p95 Latency: shows latency under load"
echo "  - CPU Utilization: shows what triggered HPA"
echo "  - Backend Pod Count: should show 2→3→4→5→(cooling down)"
echo ""
echo "Open Prometheus to show raw metrics:"
echo "  URL: http://$MINIKUBE_IP:30090"
echo '  Query: rate(http_requests_total[1m])'
echo '  Query: kube_horizontalpodautoscaler_status_current_replicas{namespace="benchmark"}'
echo ""

# ── Phase 8: Scale-down observation ──────────────────────────────────────────
echo "PHASE 8: Scale-Down (5-minute cooldown)"
echo "─────────────────────────────────────────"
echo ""
echo "The HPA has a 5-minute (300s) scale-down stabilization window."
echo "This prevents thrashing when load briefly dips and returns."
echo ""
echo "To watch scale-down live, run in another terminal:"
echo "  watch -n 5 kubectl get hpa -n benchmark"
echo ""
echo "You will see REPLICAS decrease from 5 → 4 → 3 → 2 over ~5-10 minutes."
echo ""

echo "============================================="
echo "  Demo Complete!"
echo "============================================="
echo ""
