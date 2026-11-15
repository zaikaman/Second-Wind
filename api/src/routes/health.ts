import { Router } from 'express';

export type FundingReport = {
  native: string;
  debt: string;
  reserves: string;
};

export type ChainReport = {
  chainId: number;
  head: number | null;
  indexed: number | null;
  lagBlocks: number | null;
};

export type HealthSnapshot = {
  version: string;
  chains: { base: ChainReport; unichain: ChainReport; reactive: ChainReport };
  funding: { reactive: FundingReport; coveragePool: FundingReport; claimVault: FundingReport };
  lastIndexedAt: string | null;
};

export type HealthProvider = () => Promise<HealthSnapshot>;

function funded(report: FundingReport): FundingReport & { ok: boolean } {
  return { ...report, ok: Number(report.debt) === 0 };
}

/**
 * `GET /health` is always 200 while the process is alive, because the UI banner and Heroku both
 * need an answer even when a dependency is down. A non-zero debt means the contract receives no
 * callbacks, which is the failure mode that kills a working demo silently.
 */
export function createHealthRouter(provider: HealthProvider): Router {
  const router = Router();

  router.get('/health', async (_req, res, next) => {
    try {
      const snapshot = await provider();
      res.set('Cache-Control', 'no-store');
      res.status(200).json({
        status: 'ok',
        version: snapshot.version,
        chains: snapshot.chains,
        funding: {
          reactive: funded(snapshot.funding.reactive),
          coveragePool: funded(snapshot.funding.coveragePool),
          claimVault: funded(snapshot.funding.claimVault),
        },
        lastIndexedAt: snapshot.lastIndexedAt,
      });
    } catch (error) {
      next(error);
    }
  });

  return router;
}
