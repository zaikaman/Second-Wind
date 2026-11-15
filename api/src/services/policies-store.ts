import type { SupabaseClient } from '@supabase/supabase-js';
import type { Hex } from 'viem';
import type { PoliciesStore, PolicyView, PositionView } from '../routes/policies.js';

type PolicyRow = {
  policy_id: string;
  borrower: string;
  market_id: string;
  coverage_cap: string;
  cash_ceiling: string;
  relief_ceiling: string;
  relief_used: string;
  cash_paid: string;
  relief_share_bps: number;
  premium_per_second: string;
  paid_through: number;
  target_health: string;
  cash_destination: string;
  status: string;
  created_at: string;
};

const COLUMNS =
  'policy_id,borrower,market_id,coverage_cap,cash_ceiling,relief_ceiling,relief_used,cash_paid,relief_share_bps,premium_per_second,paid_through,target_health,cash_destination,status,created_at';

/** Policy reads from the mirror; the position is fetched live by the supplied reader. */
export function createPoliciesStore(
  db: SupabaseClient,
  readPosition: (marketId: Hex, borrower: Hex) => Promise<PositionView>,
): PoliciesStore {
  return {
    async get(policyId) {
      const { data, error } = await db.from('policies_mirror').select(COLUMNS).eq('policy_id', policyId).maybeSingle();
      if (error) {
        throw new Error(`policy read failed: ${error.message}`);
      }
      if (!data) {
        return null;
      }
      const row = data as PolicyRow;
      return toView(row, await readPosition(row.market_id as Hex, row.borrower as Hex));
    },

    async listByBorrower(borrower) {
      const { data, error } = await db
        .from('policies_mirror')
        .select(COLUMNS)
        .eq('borrower', borrower)
        .order('policy_id', { ascending: false });
      if (error) {
        throw new Error(`policy list failed: ${error.message}`);
      }
      return ((data ?? []) as PolicyRow[]).map((row) => {
        const { position: _position, ...summary } = toView(row, null);
        return summary;
      });
    },
  };
}

function toView(row: PolicyRow, position: PositionView): PolicyView {
  const reliefUsed = BigInt(row.relief_used);
  const cashPaid = BigInt(row.cash_paid);
  const reliefShareBps = Number(row.relief_share_bps);
  const paidThrough = Number(row.paid_through);

  return {
    policyId: String(row.policy_id),
    borrower: row.borrower,
    marketId: row.market_id,
    coverageCap: row.coverage_cap,
    cashCeiling: row.cash_ceiling,
    reliefCeiling: row.relief_ceiling,
    reliefUsed: row.relief_used,
    cashPaid: row.cash_paid,
    reliefRemaining: (BigInt(row.relief_ceiling) - reliefUsed).toString(),
    cashRemaining: (BigInt(row.cash_ceiling) - cashPaid).toString(),
    reliefShare: (reliefShareBps / 10_000).toString(),
    premiumPerSecond: row.premium_per_second,
    premiumApr: '0.03',
    paidThrough: new Date(paidThrough * 1000).toISOString(),
    premiumActive: paidThrough * 1000 > Date.now(),
    targetHealth: row.target_health,
    cashDestination: row.cash_destination,
    status: row.status,
    createdAt: new Date(row.created_at).toISOString(),
    position,
  };
}
