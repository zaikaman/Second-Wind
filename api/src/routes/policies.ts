import { Router } from 'express';
import { z } from 'zod';

export type PositionView = {
  collateral: string;
  debt: string;
  health: string;
  liquidatable: boolean;
} | null;

export type PolicyView = {
  policyId: string;
  borrower: string;
  marketId: string;
  coverageCap: string;
  cashCeiling: string;
  reliefCeiling: string;
  reliefUsed: string;
  cashPaid: string;
  reliefRemaining: string;
  cashRemaining: string;
  reliefShare: string;
  premiumPerSecond: string;
  premiumApr: string;
  paidThrough: string;
  premiumActive: boolean;
  targetHealth: string;
  cashDestination: string;
  status: string;
  createdAt: string;
  position: PositionView;
};

export type PoliciesStore = {
  get(policyId: string): Promise<PolicyView | null>;
  listByBorrower(borrower: string): Promise<Omit<PolicyView, 'position'>[]>;
};

const borrowerQuery = z.object({
  borrower: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
});

/** `GET /policies/:policyId` and `GET /policies?borrower=`. Position is read live on request. */
export function createPoliciesRouter(store: PoliciesStore): Router {
  const router = Router();

  router.get('/policies', async (req, res, next) => {
    const parsed = borrowerQuery.safeParse(req.query);
    if (!parsed.success) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'borrower must be an address.' } });
      return;
    }

    try {
      const policies = await store.listByBorrower(parsed.data.borrower.toLowerCase());
      res.set('Cache-Control', 'max-age=2');
      res.json({ policies });
    } catch (error) {
      next(error);
    }
  });

  router.get('/policies/:policyId', async (req, res, next) => {
    const policyId = req.params.policyId;
    if (!/^[0-9]+$/.test(policyId)) {
      res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'policyId must be a number.' } });
      return;
    }

    try {
      const policy = await store.get(policyId);
      if (!policy) {
        res.status(404).json({ error: { code: 'NOT_FOUND', message: 'No policy with that id.' } });
        return;
      }
      res.set('Cache-Control', 'max-age=2');
      res.json(policy);
    } catch (error) {
      next(error);
    }
  });

  return router;
}
