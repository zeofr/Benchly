# Redis Service

## Overview

Redis 7 acts as the **message broker and job store** for BullMQ. It decouples the API (which enqueues jobs) from the Worker (which dequeues and executes them). Redis does not store application business data — only ephemeral job state that BullMQ manages.

## Connection details

| Setting | Value |
|---------|-------|
| Host | `redis` (Docker / K8s service name) |
| Port | `6379` |
| Password | None (demo) — set `REDIS_PASSWORD` env var for production |

## BullMQ queue: `load-tests`

BullMQ uses Redis to implement reliable job queues with:
- **At-least-once delivery** — jobs are re-tried on failure
- **Concurrency control** — worker processes at most 3 jobs simultaneously
- **Job lifecycle tracking** — `waiting → active → completed / failed`
- **Persistence** — `appendonly yes` ensures jobs survive Redis restarts

### Queue key structure in Redis

BullMQ stores jobs under keys like:
```
bull:load-tests:waiting      # sorted set of waiting job IDs
bull:load-tests:active       # sorted set of active job IDs
bull:load-tests:completed    # sorted set of completed job IDs
bull:load-tests:failed       # sorted set of failed job IDs
bull:load-tests:<id>         # hash with job data and metadata
```

### Job retention

```js
defaultJobOptions: {
  attempts:          2,               // retry once on failure (5s delay)
  backoff:           { type: 'fixed', delay: 5000 },
  removeOnComplete:  100,             // keep last 100 completed jobs
  removeOnFail:      50,              // keep last 50 failed jobs
}
```

This prevents unbounded memory growth in Redis.

## Redis connection config

```js
const redisConnection = {
  host:                  process.env.REDIS_HOST || 'localhost',
  port:                  parseInt(process.env.REDIS_PORT) || 6379,
  password:              process.env.REDIS_PASSWORD || undefined,
  maxRetriesPerRequest:  null,   // required by BullMQ
};
```

`maxRetriesPerRequest: null` disables ioredis's default retry loop so BullMQ can manage its own retry strategy.

## Docker Compose config

```yaml
redis:
  image: redis:7-alpine
  command: redis-server --appendonly yes   # AOF persistence
  volumes:
    - redis_data:/data
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
    interval: 10s
    retries: 5
```

The `--appendonly yes` flag enables Append-Only File (AOF) persistence so in-flight jobs are not lost if Redis restarts.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_HOST` | `localhost` | Redis hostname |
| `REDIS_PORT` | `6379` | Redis port |
| `REDIS_PASSWORD` | — | Optional password |

## Inspecting the queue

```bash
# Connect to Redis CLI
docker exec -it benchmark-redis redis-cli

# See all BullMQ keys
KEYS bull:*

# Count waiting jobs
LLEN bull:load-tests:waiting

# Check a specific job
HGETALL "bull:load-tests:<job-id>"
```

## Scaling note

For production with multiple worker replicas, Redis must be a single shared instance (or a Redis Cluster). Multiple workers competing for the same queue is safe — BullMQ uses atomic Lua scripts (`EVALSHA`) to ensure only one worker claims each job.
