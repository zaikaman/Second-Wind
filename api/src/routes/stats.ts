import { Router } from 'express';
import { z } from 'zod';
import { percentiles } from '../services/latency.js';

export type LatencySample = {
  runId: string;
  branch: 'relief' | 'cash';
  trial: number;
  latencyMs: number;
};

export type CoverageStats = {
  policies: number;
  claims: number;
  premiumCollected: string;
  cashPaid: string;
  reliefApplied: string;
  reserveBase: string;
  reserveUnichain: string;
  branchCeilings: { cash: string; relief: string };
};

export type StatsStore = {
  latencySamples(limit: number): Promise<LatencySample[]>;
  coverage(): Promise<CoverageStats>;
};

const latencyQuery = z.object({ trials: z.coerce.number().int().min(1).max(200).default(20) });

/** `GET /stats/*`: percentiles (T138) and lifetime coverage totals. */
export function createStatsRouter(store: StatsStore): Router {
  const router = Router();

  router.get('/stats/latency', async (req, res, next) => {
    const parsed = latencyQuery.safeParse(req.query);
    if (!parsed.success) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'trials must be 1-200.' } });
      return;
    }

    try {
      const samples = await store.latencySamples(parsed.data.trials);
      const relief = samples.filter((sample) => sample.branch === 'relief').map((s) => s.latencyMs);
      const cash = samples.filter((sample) => sample.branch === 'cash').map((s) => s.latencyMs);
      const overall = percentiles(samples.map((s) => s.latencyMs));

      const timestamps = samples.map((sample) => sample.runId);
      res.set('Cache-Control', 'max-age=2');
      res.json({
        trials: parsed.data.trials,
        overall: { p50: overall.p50, p95: overall.p95, max: overall.max },
        byBranch: {
          relief: percentiles(relief),
          cash: percentiles(cash),
        },
        samples,
        runIds: timestamps,
      });
    } catch (error) {
      next(error);
    }
  });

  router.get('/stats/coverage', async (_req, res, next) => {
    try {
      const coverage = await store.coverage();
      res.set('Cache-Control', 'max-age=2');
      res.json(coverage);
    } catch (error) {
      next(error);
    }
  });

  return router;
}
