# ── Stage 1: Install production dependencies ─────────────────────────────────
# Separate stage so devDependencies (jest, eslint, nodemon) never reach the
# runtime image. npm ci runs once here; the runtime stage just copies the
# resulting node_modules directory.
FROM node:24-slim AS builder

WORKDIR /app
COPY backend/package*.json ./
RUN npm ci --only=production

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM node:24-slim

# Non-root user for security
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Bring in pre-built node_modules from the builder stage
COPY --from=builder /app/node_modules ./node_modules
COPY backend/src/ ./src/
COPY backend/k6/ ./k6/
COPY backend/package.json ./

# Install k6 only when INSTALL_K6=true.
# Default is false so CI image scans don't need it.
# docker-compose and the k8s build guide both pass INSTALL_K6=true.
ARG INSTALL_K6=false
RUN if [ "$INSTALL_K6" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends curl ca-certificates && \
      ARCH=$(uname -m) && \
      if [ "$ARCH" = "x86_64" ]; then K6_ARCH="amd64"; else K6_ARCH="arm64"; fi && \
      curl -L "https://github.com/grafana/k6/releases/download/v0.49.0/k6-v0.49.0-linux-${K6_ARCH}.tar.gz" \
        -o /tmp/k6.tar.gz && \
      tar -xzf /tmp/k6.tar.gz -C /tmp && \
      mv "/tmp/k6-v0.49.0-linux-${K6_ARCH}/k6" /usr/local/bin/k6 && \
      rm -rf /tmp/k6* && \
      apt-get purge -y --auto-remove curl && \
      rm -rf /var/lib/apt/lists/*; \
    fi

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:4000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "src/index.js"]
