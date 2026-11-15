import express from 'express';
import type { ErrorRequestHandler } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { logger, requestLogger } from './lib/logger.js';
import { createHealthRouter } from './routes/health.js';
import type { HealthProvider } from './routes/health.js';
import { createClaimsRouter } from './routes/claims.js';
import type { ClaimsStore } from './routes/claims.js';
import { createPoliciesRouter } from './routes/policies.js';
import type { PoliciesStore } from './routes/policies.js';
import { createStatsRouter } from './routes/stats.js';
import type { StatsStore } from './routes/stats.js';

export type AppDeps = {
  version: string;
  corsOrigins: string[];
  health: HealthProvider;
  claims?: ClaimsStore;
  policies?: PoliciesStore;
  stats?: StatsStore;
};

const errorHandler: ErrorRequestHandler = (error, _req, res, _next) => {
  const message = error instanceof Error ? error.message : 'Unexpected error';
  logger.error({ err: error }, 'request failed');
  res.status(500).json({ error: { code: 'INTERNAL', message } });
};

/**
 * Builds the HTTP app. Dependencies are injected so tests can serve fixed health data without a
 * database or three RPC endpoints.
 */
export function createApp(deps: AppDeps) {
  const app = express();
  app.disable('x-powered-by');

  app.use(helmet());
  app.use(cors({ origin: deps.corsOrigins, credentials: false }));
  app.use(express.json({ limit: '64kb' }));
  app.use(
    rateLimit({
      windowMs: 60_000,
      limit: 60,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      handler: (_req, res) => {
        res.status(429).json({
          error: { code: 'RATE_LIMITED', message: 'Too many requests. Try again in a minute.' },
        });
      },
    }),
  );
  app.use(requestLogger);

  app.use(createHealthRouter(deps.health));
  if (deps.claims) {
    app.use(createClaimsRouter(deps.claims));
  }
  if (deps.policies) {
    app.use(createPoliciesRouter(deps.policies));
  }
  if (deps.stats) {
    app.use(createStatsRouter(deps.stats));
  }

  app.use((_req, res) => {
    res.status(404).json({ error: { code: 'NOT_FOUND', message: 'No such route.' } });
  });
  app.use(errorHandler);

  return app;
}
