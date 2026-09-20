/**
 * Worker Process — Separate from Backend API
 * Processes load test jobs from the BullMQ queue
 *
 * Run separately: node src/worker.js
 */

// MUST be first — instruments all subsequent requires
require('./tracing');
require('dotenv').config();
const { Worker } = require('bullmq');
const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');
const db = require('./db');
const logger = require('./logger');
const { redisConnection } = require('./queue');
const { notifyClients } = require('./routes/events');

// ── Worker Definition ─────────────────────────────────────────────────────────
const worker = new Worker(
  'load-tests',
  async (job) => {
    const { testId, apiUrl, vus, duration } = job.data;
    logger.info('Processing load test job', { testId, apiUrl, vus, duration });

    // Update status to running
    await db.updateBenchmarkStatus(testId, 'running');

    return new Promise((resolve, reject) => {
      const scriptPath = path.join(__dirname, '../k6/load-test.js');
      // Resolves to: backend/k6/load-test.js  ✓ (confirmed in project structure)
      const outputPath = path.join('/tmp', `k6-result-${testId}.json`);

      const { headers = {}, method = 'GET' } = job.data;

      const env = {
        ...process.env,
        TARGET_URL:     apiUrl,
        VUS:            String(vus),
        DURATION:       duration,
        CUSTOM_HEADERS: JSON.stringify(headers),
        HTTP_METHOD:    method,
      };

      execFile(
        'k6',
        [
          'run',
          '--out', `json=${outputPath}`,
          '--env', `TARGET_URL=${apiUrl}`,
          '--env', `VUS=${vus}`,
          '--env', `DURATION=${duration}`,
          '--env', `CUSTOM_HEADERS=${JSON.stringify(headers)}`,
          '--env', `HTTP_METHOD=${method}`,
          scriptPath,
        ],
        { env, timeout: 300000 },
        async (error, stdout, stderr) => {
          if (error) {
            logger.error('k6 execution failed', { testId, error: error.message, stderr });
            await db.saveBenchmark({
              test_id: testId,
              api_url: apiUrl,
              avg_response_time: 0,
              max_response_time: 0,
              min_response_time: 0,
              requests_per_sec: 0,
              total_requests: 0,
              failed_requests: 0,
              error_rate: 100,
              status: 'failed'
            });
            return reject(error);
          }

          // Parse k6 output
          const metrics = parseK6Output(outputPath);
          logger.info('k6 test completed', { testId, metrics });

          // Persist results
          await db.saveBenchmark({
            test_id: testId,
            api_url: apiUrl,
            ...metrics,
            status: 'completed'
          });

          // Call the FastAPI analytics service for NL diagnosis + HPA recommendation.
          // Falls back gracefully if the analytics service is unavailable.
          callAnalyticsService(testId, apiUrl, metrics).then((nl) => {
            if (nl) {
              db.saveBenchmark({
                test_id: testId,
                api_url: apiUrl,
                ...metrics,
                nl_analysis: JSON.stringify(nl),
                status: 'completed'
              }).catch((e) => logger.warn('Failed to persist analytics result', { testId, error: e.message }));
              notifyClients(testId, { ...metrics, test_id: testId, status: 'completed', analysis: nl });
            }
          }).catch((e) => logger.warn('Analytics service call failed', { testId, error: e.message }));

          // Notify SSE clients immediately with numeric metrics
          notifyClients(testId, { ...metrics, test_id: testId, status: 'completed' });

          // Cleanup
          try { fs.unlinkSync(outputPath); } catch {}
          resolve(metrics);
        }
      );
    });
  },
  {
    connection: redisConnection,
    concurrency: 3, // process up to 3 jobs concurrently
  }
);

// ── Event Handlers ────────────────────────────────────────────────────────────
worker.on('completed', (job) => {
  logger.info('Job completed', { jobId: job.id, testId: job.data.testId });
});

worker.on('failed', (job, err) => {
  logger.error('Job failed', { jobId: job?.id, testId: job?.data?.testId, error: err.message });
});

worker.on('error', (err) => {
  logger.error('Worker error', { error: err.message });
});

// ── Parse k6 Output ───────────────────────────────────────────────────────────
function parseK6Output(filePath) {
  const defaults = {
    avg_response_time: 0,
    max_response_time: 0,
    min_response_time: 0,
    requests_per_sec: 0,
    total_requests: 0,
    failed_requests: 0,
    error_rate: 0
  };

  try {
    if (!fs.existsSync(filePath)) return defaults;

    const lines = fs.readFileSync(filePath, 'utf8').trim().split('\n');
    const metrics = {};

    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        if (entry.type === 'Point' && entry.metric) {
          if (!metrics[entry.metric]) metrics[entry.metric] = [];
          metrics[entry.metric].push(entry.data.value);
        }
      } catch {}
    }

    const httpDuration = metrics['http_req_duration'] || [];
    const httpReqs = metrics['http_reqs'] || [];
    const httpFailed = metrics['http_req_failed'] || [];

    const avg = arr => arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0;
    const max = arr => arr.length ? Math.max(...arr) : 0;
    const min = arr => arr.length ? Math.min(...arr) : 0;

    const totalRequests = httpReqs.length;
    const failedRequests = httpFailed.filter(v => v === 1).length;

    return {
      avg_response_time: parseFloat(avg(httpDuration).toFixed(2)),
      max_response_time: parseFloat(max(httpDuration).toFixed(2)),
      min_response_time: parseFloat(min(httpDuration).toFixed(2)),
      requests_per_sec: parseFloat((totalRequests / 10).toFixed(2)),
      total_requests: totalRequests,
      failed_requests: failedRequests,
      error_rate: totalRequests > 0
        ? parseFloat(((failedRequests / totalRequests) * 100).toFixed(2))
        : 0
    };
  } catch (err) {
    logger.error('Failed to parse k6 output', { error: err.message });
    return defaults;
  }
}

// ── Analytics Service HTTP Client ────────────────────────────────────────────
/**
 * POST the k6 metrics to the FastAPI analytics service.
 * Returns the diagnosis + HPA recommendation, or null if the service is down.
 */
async function callAnalyticsService(testId, apiUrl, metrics) {
  const analyticsUrl = process.env.ANALYTICS_URL || 'http://analytics:8001';
  const payload = {
    avg_response_time: metrics.avg_response_time,
    p95_latency_ms:    metrics.max_response_time || metrics.avg_response_time,
    requests_per_sec:  metrics.requests_per_sec,
    total_requests:    metrics.total_requests,
    error_rate_pct:    metrics.error_rate || 0,
    current_replicas:  1,
  };

  try {
    const https = require('http');
    const body = JSON.stringify(payload);
    const url = new URL(`${analyticsUrl}/analyse`);

    return await new Promise((resolve, reject) => {
      const req = https.request(
        {
          hostname: url.hostname,
          port:     url.port || 8001,
          path:     url.pathname,
          method:   'POST',
          headers:  { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
          timeout:  15000,
        },
        (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try {
              const out = JSON.parse(data);
              logger.info('Analytics service responded', { testId, summary: out.summary });
              resolve(out);
            } catch (e) {
              reject(e);
            }
          });
        }
      );
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('Analytics service timeout')); });
      req.write(body);
      req.end();
    });
  } catch (err) {
    logger.warn('Analytics service unavailable, skipping NL analysis', { testId, error: err.message });
    return null;
  }
}


async function shutdown() {
  logger.info('Worker shutting down...');
  await worker.close();
  await db.pool.end();
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

// ── Start ─────────────────────────────────────────────────────────────────────
(async () => {
  try {
    await db.connect();
    logger.info('Worker started, waiting for jobs...');
  } catch (err) {
    logger.error('Worker startup failed', { error: err.message });
    process.exit(1);
  }
})();
