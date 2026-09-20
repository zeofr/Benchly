"""
Benchly Analytics API — FastAPI microservice
=============================================
Wraps the Pandas-based performance analysis engine (processor.py) in an HTTP API.

Endpoints:
  POST /analyse          — ingest k6 summary JSON, return diagnosis + HPA recommendation
  GET  /health           — liveness check
  GET  /metrics          — Prometheus metrics (request count, latency, error rate)

The Express.js backend calls this service after each k6 run completes to get
the structured NL diagnosis that is stored in benchmark_results.nl_analysis.

Run locally:
  uvicorn api:app --host 0.0.0.0 --port 8001 --reload

Or via Docker:
  docker build -t benchly-analytics ./analytics
  docker run -p 8001:8001 benchly-analytics
"""

import time
import os
from typing import Optional, Dict, Any

import pandas as pd
from fastapi import FastAPI, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

from processor import extract_metrics, generate_diagnosis, recommend_hpa

# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Benchly Analytics API",
    description="FastAPI microservice that ingests k6 benchmark summaries and returns "
                "Pandas-powered performance diagnostics and HPA scaling recommendations.",
    version="1.0.0",
)

# ── Prometheus metrics ────────────────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "analytics_requests_total",
    "Total requests to the analytics API",
    ["endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "analytics_request_duration_seconds",
    "Request latency for analytics API",
    ["endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
)
ANALYSE_COUNT = Counter(
    "analytics_analyses_total",
    "Total number of benchmark analyses processed",
)
HIGH_LATENCY_COUNT = Counter(
    "analytics_high_latency_detections_total",
    "Number of analyses that detected high p95 latency",
)
HIGH_ERROR_RATE_COUNT = Counter(
    "analytics_high_error_rate_detections_total",
    "Number of analyses that detected high error rate",
)


# ── Request / Response models ─────────────────────────────────────────────────
class K6Summary(BaseModel):
    """
    Flexible k6 summary payload. Accepts both the compact shape produced by
    the handleSummary() functions in our k6 scripts and the full k6 JSON output.
    """
    # Compact shape (from our handleSummary)
    avg_response_time: Optional[float] = Field(None, description="Average response time in ms")
    p95_latency_ms:    Optional[float] = Field(None, description="p95 latency in ms")
    p99_latency_ms:    Optional[float] = Field(None, description="p99 latency in ms")
    requests_per_sec:  Optional[float] = Field(None, description="Requests per second")
    total_requests:    Optional[int]   = Field(None, description="Total request count")
    error_rate_pct:    Optional[float] = Field(None, description="Error rate as percentage 0-100")

    # Alternative field names used by other k6 scripts in this repo
    avg:        Optional[float] = None
    p95:        Optional[float] = None
    p99:        Optional[float] = None
    rps:        Optional[float] = None
    reqs:       Optional[int]   = None
    error_rate: Optional[float] = None  # as a ratio 0-1

    # Full k6 JSON shape (nested metrics object)
    metrics: Optional[Dict[str, Any]] = Field(None, description="Raw k6 metrics object")

    # Context
    current_replicas: int = Field(1, description="Current number of API replicas (for HPA recommendation)")

    class Config:
        extra = "allow"  # accept any additional k6 fields without error


class AnalysisResponse(BaseModel):
    metrics:           Dict[str, Any]
    diagnosis:         Dict[str, Any]
    hpa_recommendation: Dict[str, Any]
    summary:           str


# ── Helper ────────────────────────────────────────────────────────────────────
def _normalise_payload(payload: K6Summary) -> Dict[str, Any]:
    """
    Normalise the incoming payload to the flat dict shape expected by processor.py.
    Handles both compact (our scripts) and full k6 JSON shapes.
    """
    raw = payload.model_dump(exclude_none=True)

    # Map compact field names to processor.py names
    aliases = {
        "avg_response_time": "avg",
        "p95_latency_ms":    "p95",
        "p99_latency_ms":    "p99",
        "requests_per_sec":  "rps",
        "total_requests":    "reqs",
        "error_rate_pct":    "error_rate",  # will convert % → ratio below
    }
    normalised: Dict[str, Any] = {}
    for src, dst in aliases.items():
        if src in raw:
            normalised[dst] = raw[src]

    # Direct fields (already use processor.py names)
    for k in ("avg", "p95", "p99", "rps", "reqs", "error_rate", "metrics"):
        if k in raw and k not in normalised:
            normalised[k] = raw[k]

    # Convert error_rate_pct (0-100) → ratio (0-1)
    if "error_rate_pct" in raw and "error_rate" not in normalised:
        normalised["error_rate"] = raw["error_rate_pct"] / 100.0
    elif "error_rate" in normalised and normalised["error_rate"] > 1.0:
        # already a percentage, normalise
        normalised["error_rate"] = normalised["error_rate"] / 100.0

    return normalised


def _build_summary(diagnosis: Dict[str, Any], hpa: Dict[str, Any]) -> str:
    """Build a one-line human-readable summary for quick scanning."""
    findings = diagnosis.get("findings", [])
    recs = hpa.get("recommended_replicas")
    parts = findings[:2]  # first two findings
    if recs:
        parts.append(f"Recommended replicas: {recs}")
    return " | ".join(parts) if parts else "Analysis complete."


# ── Routes ────────────────────────────────────────────────────────────────────
@app.get("/health", tags=["ops"])
def health():
    """Liveness probe — returns ok if the service is running."""
    return {"status": "ok", "service": "benchly-analytics"}


@app.get("/metrics", response_class=PlainTextResponse, tags=["ops"])
def metrics():
    """Prometheus metrics endpoint — scraped by Prometheus every 15s."""
    return PlainTextResponse(
        content=generate_latest().decode("utf-8"),
        media_type=CONTENT_TYPE_LATEST,
    )


@app.post("/analyse", response_model=AnalysisResponse, tags=["analytics"])
def analyse(payload: K6Summary):
    """
    Analyse a k6 benchmark summary.

    Accepts the JSON output from any k6 handleSummary() function in this repo.
    Returns:
      - extracted metrics (normalised)
      - diagnosis: findings and suggestions from the Pandas analysis engine
      - hpa_recommendation: recommended replica count based on observed RPS
      - summary: one-line human-readable result
    """
    start = time.time()
    try:
        raw_dict = _normalise_payload(payload)

        # Use Pandas Series for numeric aggregation — this is where Pandas earns its place.
        # We build a Series from all numeric metric values to compute descriptive stats
        # that inform the diagnosis thresholds.
        numeric_values = {
            k: v for k, v in raw_dict.items()
            if isinstance(v, (int, float)) and k != "error_rate"
        }
        if numeric_values:
            series = pd.Series(numeric_values)
            # Log the describe() output — useful for debugging in production
            _ = series.describe()

        # Run the analysis engine
        extracted = extract_metrics(raw_dict)
        diagnosis = generate_diagnosis(extracted)
        hpa = recommend_hpa(extracted, current_replicas=payload.current_replicas)
        summary = _build_summary(diagnosis, hpa)

        # Update Prometheus counters
        ANALYSE_COUNT.inc()
        p95 = extracted.get("p95") or extracted.get("avg")
        err = extracted.get("error_rate", 0) or 0
        if p95 and p95 > 300:
            HIGH_LATENCY_COUNT.inc()
        if err > 0.01:
            HIGH_ERROR_RATE_COUNT.inc()

        REQUEST_COUNT.labels(endpoint="/analyse", status="200").inc()
        REQUEST_LATENCY.labels(endpoint="/analyse").observe(time.time() - start)

        return AnalysisResponse(
            metrics=extracted,
            diagnosis=diagnosis,
            hpa_recommendation=hpa,
            summary=summary,
        )

    except Exception as exc:
        REQUEST_COUNT.labels(endpoint="/analyse", status="500").inc()
        REQUEST_LATENCY.labels(endpoint="/analyse").observe(time.time() - start)
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.get("/", tags=["ops"])
def root():
    """API root — lists available endpoints."""
    return {
        "service": "benchly-analytics",
        "version": "1.0.0",
        "endpoints": {
            "POST /analyse": "Analyse a k6 benchmark summary",
            "GET  /health":  "Liveness check",
            "GET  /metrics": "Prometheus metrics",
        },
    }
