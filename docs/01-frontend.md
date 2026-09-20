# Frontend Service

## Overview

The frontend is a **React 18 single-page application** built with Vite. It lets users configure load tests, watch results in real time via Server-Sent Events, browse history, and compare multiple runs side-by-side. In production it is served by an nginx container on port 8080 (mapped to host 3000).

## Tech stack

| Layer | Library / Tool |
|-------|---------------|
| Framework | React 18 |
| Build | Vite 5 |
| HTTP client | Axios |
| Charts | Recharts |
| Testing | Vitest + Testing Library |
| Linting | ESLint |
| Container | nginx:alpine |

## Source layout

```
frontend/src/
├── api/
│   └── client.js          # Axios wrapper — sets base URL, API key header
├── components/
│   ├── BenchmarkForm.jsx   # Load test configuration form
│   ├── Dashboard.jsx       # Live results panel
│   ├── ResultsHistory.jsx  # Paginated history table
│   ├── CompareView.jsx     # Side-by-side comparison of two runs
│   ├── ErrorBoundary.jsx   # React error boundary wrapper
│   └── Toast.jsx           # Notification toasts
├── App.jsx                 # Root — sidebar, routing, SSE connection
├── App.css
├── index.css
└── main.jsx                # Vite entry point
```

## Key components

### `App.jsx`
The root component owns all top-level state:
- `activeTest` — the currently running or most-recent test result
- `view` — `'home' | 'history' | 'compare'` drives which panel is shown
- `backendStatus` — polls `GET /health` every 30 s to show online/offline badge
- `serviceStatuses` — polls Grafana, Prometheus, and Jaeger using `no-cors` fetch for sidebar health dots

**SSE connection** — when `activeTest.testId` is set and status is not terminal, an `EventSource` is opened to `GET /api/events/:testId`. Incoming JSON messages update `activeTest` in place. On SSE error it falls back to 2-second polling against `GET /api/benchmark/:testId`.

### `BenchmarkForm.jsx`
Collects:
- `apiUrl` — validated with `new URL()`
- `testName` — optional label
- `vus` — virtual users (1–100)
- `duration` — `10s | 30s | 1m | 2m`
- `method` — `GET | POST | PUT | PATCH | DELETE`
- `authMode` — None / Bearer Token / API Key / Custom JSON headers
- Advanced: ramp-up time, per-request timeout, JSON payload body

Presets (Light / Medium / Stress) set `vus` and `duration` in one click. Test configs can be saved to `localStorage` as named templates and reapplied.

### `Dashboard.jsx`
Displays live metrics cards for the active test:
- Average, min, max response time
- Requests per second
- Total requests
- Error rate (with colour coding — green < 5%, amber < 50%, red ≥ 50%)
- AI/Pandas analysis summary if the analytics service responded

### `ResultsHistory.jsx`
Fetches `GET /api/benchmark` (up to 200 results). Renders a sortable table. Each row has a **Compare** button that pushes the test ID to `CompareView`.

### `CompareView.jsx`
Lets users pick any two historical runs and shows a grouped bar chart (Recharts) with response time, RPS, and error rate side by side.

## API client (`src/api/client.js`)

```js
// Determines the backend URL:
//   1. VITE_API_URL env var (set at build time for Docker / K8s)
//   2. window.RUNTIME_API_URL (injected by nginx at container start)
//   3. Falls back to http://localhost:4000
export function getBackendUrl() { ... }

// All requests include:
//   X-API-Key: demo-key-12345   (or VITE_API_KEY env var)
//   bypass-tunnel-reminder: true
const apiClient = {
  runBenchmark(params),   // POST /api/benchmark/run
  getResults(id),         // GET  /api/benchmark/:id
  listResults(limit),     // GET  /api/benchmark
};
```

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `VITE_API_URL` | `http://localhost:4000` | Backend URL injected at build time |
| `VITE_API_KEY` | `demo-key-12345` | API key sent in `X-API-Key` header |

## Docker build

```dockerfile
# Stage 1 — build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build        # outputs to /app/dist

# Stage 2 — serve
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
```

## nginx config highlights

- Listens on `8080` (non-root, required for Kubernetes `runAsNonRoot`)
- All routes fall through to `index.html` (React Router SPA support)
- `/api/` and `/auth/` are proxied to `backend:4000`
- Gzip enabled for JS, CSS, JSON, HTML
- Security headers: `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`

## Running locally

```bash
cd frontend
npm install
npm run dev        # Vite dev server on :5173 with HMR

npm run test       # Vitest unit tests (single run)
npm run lint       # ESLint
npm run build      # Production bundle → dist/
```

## Tests

Tests live in `frontend/src/tests/`. They use `@testing-library/react` with `jsdom`. Run:

```bash
npm run test       # single run
npm run test:ci    # verbose output for CI
```
