import { Router } from 'express';
import { z } from 'zod';

export type ClaimSummary = {
  runId: string;
  policyId: string;
  status: 'pending' | 'partial' | 'settled' | 'failed';
  fee: string;
  mode: string;
  triggeredAt: string;
  settledAt: string | null;
  totalLatencyMs: number | null;
};

export type BranchView = {
  chainId: number;
  status: 'pending' | 'confirmed' | 'failed';
  txHash: string | null;
  blockTime: string | null;
  amount: string;
  latencyMs: number | null;
  explorer: string | null;
  marketId?: string | null;
  healthBefore?: string | null;
  healthAfter?: string | null;
  destination?: string | null;
};

export type ReceiptView = {
  runId: string;
  policyId: string;
  borrower: string;
  status: ClaimSummary['status'];
  trigger: {
    chainId: number;
    txHash: string;
    blockNumber: number;
    blockTime: string;
    logIndex: number;
    explorer: string | null;
  };
  reactive: { txHash: string | null; blockNumber: number | null; blockTime: string | null; explorer: string | null };
  fee: string;
  split: { mode: string; reliefLimit: string; cashLimit: string; shortfall: string };
  branches: { relief: BranchView | null; cash: BranchView | null };
  unspentRelief: string;
  failure: { code: string; message: string } | null;
  totalLatencyMs: number | null;
};

export type ClaimsStore = {
  list(input: { borrower?: string; limit: number; cursor: string | null }): Promise<{
    claims: ClaimSummary[];
    nextCursor: string | null;
  }>;
  receipt(runId: string): Promise<ReceiptView | null>;
};

const listQuery = z.object({
  borrower: z
    .string()
    .regex(/^0x[0-9a-fA-F]{40}$/)
    .optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().min(1).optional(),
});

/** `GET /claims` and the receipt endpoint. Reads only; no endpoint here moves funds. */
export function createClaimsRouter(store: ClaimsStore): Router {
  const router = Router();

  router.get('/claims', async (req, res, next) => {
    const parsed = listQuery.safeParse(req.query);
    if (!parsed.success) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? 'Invalid query.' } });
      return;
    }

    try {
      const { claims, nextCursor } = await store.list({
        borrower: parsed.data.borrower?.toLowerCase(),
        limit: parsed.data.limit,
        cursor: parsed.data.cursor ?? null,
      });
      res.set('Cache-Control', 'max-age=2');
      res.json({ claims, nextCursor });
    } catch (error) {
      next(error);
    }
  });

  router.get('/claims/:runId', async (req, res, next) => {
    const runId = req.params.runId;
    if (!/^0x[0-9a-fA-F]{64}$/.test(runId)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'runId must be a 32-byte hex string.' } });
      return;
    }

    try {
      const receipt = await store.receipt(runId.toLowerCase());
      if (!receipt) {
        res.status(404).json({ error: { code: 'NOT_FOUND', message: 'No claim with that runId.' } });
        return;
      }
      res.set('Cache-Control', 'max-age=5, stale-while-revalidate=30');
      res.json(receipt);
    } catch (error) {
      next(error);
    }
  });

  return router;
}
