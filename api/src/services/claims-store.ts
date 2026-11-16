import { formatUnits } from 'viem';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { ClaimSummary, ClaimsStore, ReceiptView, BranchView } from '../routes/claims.js';
import { explorerUrl } from '../lib/explorer.js';

type ClaimRow = {
  run_id: string;
  policy_id: string;
  borrower: string;
  market_id: string;
  origin_chain_id: number;
  origin_tx_hash: string;
  origin_block: number;
  origin_log_index: number;
  origin_block_time: string;
  fee_amount: string;
  cash_limit: string;
  relief_limit: string;
  mode: string;
  status: ClaimSummary['status'];
  settled_at: string | null;
  total_latency_ms: number | null;
  health_before: string | null;
};

type EventRow = {
  chain_id: number;
  kind: 'relief' | 'cash' | 'dispatch' | 'registration';
  status: 'pending' | 'confirmed' | 'failed';
  tx_hash: string | null;
  block_number: number | null;
  block_time: string | null;
  amount: string | null;
  detail: Record<string, unknown> | null;
  error: string | null;
};

// Numeric columns are cast to text: PostgREST would otherwise render a 21-digit wei amount as a
// JSON number and JSON.parse would round it to a double before the API ever sees it.
const CLAIM_COLUMNS =
  'run_id,policy_id::text,borrower,market_id,origin_chain_id,origin_tx_hash,origin_block,origin_log_index,origin_block_time,fee_amount::text,cash_limit::text,relief_limit::text,mode,status,settled_at,total_latency_ms,health_before::text';

/** Reads the cache and shapes it into the documented receipt. All amounts stay decimal strings. */
export function createClaimsStore(db: SupabaseClient): ClaimsStore {
  return {
    async list({ borrower, limit, cursor }) {
      let query = db.from('claims').select(CLAIM_COLUMNS).order('origin_block', { ascending: false }).limit(limit + 1);

      if (borrower) {
        query = query.eq('borrower', borrower);
      }
      if (cursor) {
        const parsed = Number(cursor);
        if (Number.isFinite(parsed)) {
          query = query.lt('origin_block', parsed);
        }
      }

      const { data, error } = await query;
      if (error) {
        throw new Error(`claims list failed: ${error.message}`);
      }

      const rows = (data ?? []) as ClaimRow[];
      const page = rows.slice(0, limit);
      return {
        claims: page.map(toSummary),
        nextCursor: rows.length > limit ? String(page[page.length - 1]?.origin_block ?? '') : null,
      };
    },

    async receipt(runId) {
      const { data: claim, error } = await db.from('claims').select(CLAIM_COLUMNS).eq('run_id', runId).maybeSingle();
      if (error) {
        throw new Error(`claim read failed: ${error.message}`);
      }
      if (!claim) {
        return null;
      }

      const { data: events, error: eventError } = await db
        .from('claim_events')
        .select('chain_id,kind,status,tx_hash,block_number,block_time,amount::text,detail,error')
        .eq('run_id', runId);
      if (eventError) {
        throw new Error(`claim events read failed: ${eventError.message}`);
      }

      return toReceipt(claim as ClaimRow, (events ?? []) as EventRow[]);
    },
  };
}

function toSummary(row: ClaimRow): ClaimSummary {
  return {
    runId: row.run_id,
    policyId: String(row.policy_id),
    status: row.status,
    fee: row.fee_amount,
    mode: row.mode,
    triggeredAt: new Date(row.origin_block_time).toISOString(),
    settledAt: row.settled_at ? new Date(row.settled_at).toISOString() : null,
    totalLatencyMs: row.total_latency_ms,
  };
}

function toReceipt(claim: ClaimRow, events: EventRow[]): ReceiptView {
  const reliefEvent = events.find((event) => event.kind === 'relief');
  const cashEvent = events.find((event) => event.kind === 'cash');
  const dispatch = events.find((event) => event.kind === 'dispatch');
  const failed = events.find((event) => event.status === 'failed' && event.error);

  const relief = reliefEvent ? toBranch(reliefEvent, claim) : null;
  const cash = cashEvent ? toBranch(cashEvent, claim) : null;

  const reliefSpent = reliefEvent?.status === 'confirmed' ? BigInt(reliefEvent.amount ?? '0') : 0n;
  const unspent = BigInt(claim.relief_limit) - reliefSpent;

  return {
    runId: claim.run_id,
    policyId: String(claim.policy_id),
    borrower: claim.borrower,
    status: claim.status,
    trigger: {
      chainId: claim.origin_chain_id,
      txHash: claim.origin_tx_hash,
      blockNumber: Number(claim.origin_block),
      blockTime: new Date(claim.origin_block_time).toISOString(),
      logIndex: Number(claim.origin_log_index),
      explorer: explorerUrl(claim.origin_chain_id, 'tx', claim.origin_tx_hash),
    },
    reactive: {
      txHash: dispatch?.tx_hash ?? null,
      blockNumber: dispatch?.block_number ?? null,
      blockTime: dispatch?.block_time ? new Date(dispatch.block_time).toISOString() : null,
      explorer: dispatch?.tx_hash ? explorerUrl(dispatch.chain_id, 'tx', dispatch.tx_hash) : null,
    },
    fee: claim.fee_amount,
    split: {
      mode: claim.mode,
      reliefLimit: claim.relief_limit,
      cashLimit: claim.cash_limit,
      shortfall: (BigInt(claim.fee_amount) - BigInt(claim.relief_limit) - BigInt(claim.cash_limit)).toString(),
    },
    branches: { relief, cash },
    unspentRelief: unspent > 0n ? unspent.toString() : '0',
    failure: failed?.error ? { code: failed.error, message: failed.error } : null,
    totalLatencyMs: claim.total_latency_ms,
  };
}

function toBranch(event: EventRow, claim: ClaimRow): BranchView {
  const detail = event.detail ?? {};
  const amount = event.amount ?? '0';

  const branch: BranchView = {
    chainId: event.chain_id,
    status: event.status,
    txHash: event.tx_hash,
    blockTime: event.block_time ? new Date(event.block_time).toISOString() : null,
    amount,
    latencyMs: branchLatency(claim.origin_block_time, event.block_time),
    explorer: event.tx_hash ? explorerUrl(event.chain_id, 'tx', event.tx_hash) : null,
  };

  if (event.kind === 'relief') {
    branch.marketId = typeof detail.marketId === 'string' ? detail.marketId : null;
    branch.healthAfter = typeof detail.healthAfter === 'string' ? detail.healthAfter : null;
    branch.healthBefore = claim.health_before;
  } else {
    branch.destination = typeof detail.destination === 'string' ? detail.destination : null;
  }

  return branch;
}

function branchLatency(origin: string, confirmed: string | null): number | null {
  if (!confirmed) {
    return null;
  }
  return Math.max(0, new Date(confirmed).getTime() - new Date(origin).getTime());
}

/** Formats an 18-decimal integer as a plain decimal string, for stores that hold bigint sums. */
export function amountString(value: bigint): string {
  return formatUnits(value, 18);
}
