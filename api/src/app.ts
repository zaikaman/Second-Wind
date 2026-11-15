import express from 'express';
import type { ErrorRequestHandler } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { logger, requestLogger } from './lib/logger.js';
import { createHealthRouter } from './routes/health.js';
import type { HealthProvider } from './routes/health.js';

export type AppDeps = {
  version: string;
  corsOrigins: string[];
  health: HealthProvider;
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

  app.use((_req, res) => {
    res.status(404).json({ error: { code: 'NOT_FOUND', message: 'No such route.' } });
  });
  app.use(errorHandler);

  return app;
}
