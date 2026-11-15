import type { SupabaseClient } from '@supabase/supabase-js';
import type { Hex } from 'viem';
import { penalty, split } from '../lib/fee-math.js';
import { logger } from '../lib/logger.js';
import { recordLatency } from './latency.js';
import type { Decoded } from './decoder.js';

export type ClaimStatus = 'pending' | 'partial' | 'settled' | 'failed';
export type BranchStatus = 'pending' | 'confirmed' | 'failed';

export type IndexedEvent = {
  chainId: number;
  address: Hex;
  blockNumber: number;
  blockTime: Date;
  txHash: Hex;
  logIndex: number;
  decoded: Decoded;
};

/**
 * A claim is settled only when both branches confirmed, partial when exactly one did, failed when
 * both did. `pending` is the answer for every other combination, including one confirmed and one
 * still in flight (FR-017: status is derived, never stored independently).
 */
export function deriveClaimStatus(branches: Record<string, BranchStatus | undefined>): ClaimStatus {
  const relief = branches.relief;
  const cash = branches.cash;

  if (relief === 'confirmed' && cash === 'confirmed') return 'settled';
  if (
    (relief === 'confirmed' && cash === 'failed') ||
    (cash === 'confirmed' && relief === 'failed')
  ) {
    return 'partial';
  }
  if (relief === 'failed' && cash === 'failed') return 'failed';
  return 'pending';
}

/** Applies one decoded log to the cache. Every write is an upsert, so re-indexing is safe. */
export async function applyEvent(db: SupabaseClient, event: IndexedEvent): Promise<void> {
  const { decoded } = event;

  switch (decoded.kind) {
    case 'policyCreated':
      await db.from('policies_mirror').upsert(
        {
          policy_id: decoded.policyId.toString(),
          borrower: decoded.borrower.toLowerCase(),
          market_id: decoded.marketId.toLowerCase(),
          coverage_cap: decoded.coverageCap.toString(),
          cash_ceiling: decoded.cashCeiling.toString(),
          relief_ceiling: decoded.reliefCeiling.toString(),
          relief_used: '0',
          cash_paid: '0',
          relief_share_bps: decoded.reliefShareBps,
          premium_per_second: decoded.premiumPerSecond.toString(),
          paid_through: Number(decoded.paidThrough),
          target_health: decoded.targetHealthWad.toString(),
          cash_destination: decoded.cashDestination.toLowerCase(),
          status: 'active',
          lltv: decoded.lltv.toString(),
          created_at: event.blockTime.toISOString(),
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'policy_id' },
      );
      return;

    case 'premiumPaid':
      await db
        .from('policies_mirror')
        .update({ paid_through: Number(decoded.paidThrough), updated_at: new Date().toISOString() })
        .eq('policy_id', decoded.policyId.toString());
      return;

    case 'statusChanged':
      await db
        .from('policies_mirror')
        .update({ status: statusName(decoded.status), updated_at: new Date().toISOString() })
        .eq('policy_id', decoded.policyId.toString());
      return;

    case 'liquidate':
      await recordLiquidate(db, event, decoded);
      return;

    case 'reliefApplied':
      await recordBranch(db, event, {
        runId: decoded.runId,
        chainId: event.chainId,
        kind: 'relief',
        status: 'confirmed',
        amount: decoded.reliefSpent,
        detail: {
          marketId: decoded.marketId,
          debtAfter: decoded.debtAfter.toString(),
          healthAfter: decoded.healthAfter.toString(),
        },
      });
      await db
        .from('policies_mirror')
        .update({ relief_used: decoded.reliefSpent.toString() })
        .eq('policy_id', decoded.policyId.toString());
      return;

    case 'claimPaid':
      await recordBranch(db, event, {
        runId: decoded.runId,
        chainId: event.chainId,
        kind: 'cash',
        status: 'confirmed',
        amount: decoded.amount,
        detail: { destination: decoded.destination, paidThrough: Number(decoded.paidThrough) },
      });
      await db
        .from('policies_mirror')
        .update({ cash_paid: decoded.amount.toString() })
        .eq('policy_id', decoded.policyId.toString());
      return;

    case 'callbackRequest':
      if (!decoded.runId) {
        return;
      }
      await db.from('claim_events').upsert(
        {
          run_id: decoded.runId.toLowerCase(),
          chain_id: event.chainId,
          kind: 'dispatch',
          status: 'confirmed',
          tx_hash: event.txHash.toLowerCase(),
          block_number: event.blockNumber,
          block_time: event.blockTime.toISOString(),
          detail: { recipient: decoded.recipient, gasLimit: decoded.gasLimit.toString() },
        },
        { onConflict: 'run_id,chain_id,kind' },
      );
      return;
  }
}

async function recordLiquidate(
  db: SupabaseClient,
  event: IndexedEvent,
  decoded: Extract<Decoded, { kind: 'liquidate' }>,
): Promise<void> {
  const { data: policy, error: policyError } = await db
    .from('policies_mirror')
    .select('policy_id, lltv, relief_share_bps')
    .eq('borrower', decoded.borrower.toLowerCase())
    .eq('market_id', decoded.marketId.toLowerCase())
    .order('policy_id', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (policyError || !policy) {
    // The policy log has not been indexed yet. Skipping is safe: the cursor only advances past
    // blocks whose logs were handled, so a later pass picks this liquidation up.
    logger.warn({ runId: decoded.runId }, 'liquidation seen before its policy; will retry');
    throw new Error('policy not indexed yet');
  }

  const fee = penalty(decoded.repaidAssets, BigInt(policy.lltv));
  const { cash, relief } = split(fee, Number(policy.relief_share_bps));

  await db.from('claims').upsert(
    {
      run_id: decoded.runId.toLowerCase(),
      policy_id: String(policy.policy_id),
      borrower: decoded.borrower.toLowerCase(),
      market_id: decoded.marketId.toLowerCase(),
      origin_chain_id: event.chainId,
      origin_tx_hash: event.txHash.toLowerCase(),
      origin_block: event.blockNumber,
      origin_log_index: event.logIndex,
      origin_block_time: event.blockTime.toISOString(),
      fee_amount: fee.toString(),
      cash_limit: cash.toString(),
      relief_limit: relief.toString(),
      mode: 'standard',
      status: 'pending',
      decided_at: event.blockTime.toISOString(),
    },
    { onConflict: 'run_id', ignoreDuplicates: true },
  );
}

async function recordBranch(
  db: SupabaseClient,
  event: IndexedEvent,
  branch: {
    runId: string;
    chainId: number;
    kind: 'relief' | 'cash';
    status: BranchStatus;
    amount: bigint;
    detail: Record<string, unknown>;
  },
): Promise<void> {
  const runId = branch.runId.toLowerCase();

  const { data: claim } = await db
    .from('claims')
    .select('origin_block_time')
    .eq('run_id', runId)
    .maybeSingle();

  await db.from('claim_events').upsert(
    {
      run_id: runId,
      chain_id: branch.chainId,
      kind: branch.kind,
      status: branch.status,
      tx_hash: event.txHash.toLowerCase(),
      block_number: event.blockNumber,
      block_time: event.blockTime.toISOString(),
      amount: branch.amount.toString(),
      detail: branch.detail,
    },
    { onConflict: 'run_id,chain_id,kind' },
  );

  if (claim?.origin_block_time) {
    await recordLatency(db, {
      runId,
      branch: branch.kind,
      originBlockTime: new Date(claim.origin_block_time),
      dispatchTime: null,
      confirmBlockTime: event.blockTime,
    });
  }

  await refreshClaimStatus(db, runId);
}

/** Recomputes `claims.status` from the branch rows and stamps the settlement time. */
export async function refreshClaimStatus(db: SupabaseClient, runId: string): Promise<ClaimStatus> {
  const { data, error } = await db
    .from('claim_events')
    .select('kind,status,block_time')
    .eq('run_id', runId)
    .in('kind', ['relief', 'cash']);

  if (error) {
    throw new Error(`claim status read failed: ${error.message}`);
  }

  const rows = (data ?? []) as { kind: string; status: BranchStatus; block_time: string | null }[];
  const branches: Record<string, BranchStatus | undefined> = {};
  let latest = 0;
  for (const row of rows) {
    branches[row.kind] = row.status;
    if (row.status === 'confirmed' && row.block_time) {
      latest = Math.max(latest, new Date(row.block_time).getTime());
    }
  }

  const status = deriveClaimStatus(branches);

  const { data: origin } = await db
    .from('claims')
    .select('origin_block_time')
    .eq('run_id', runId)
    .maybeSingle();

  const totalLatency =
    status === 'settled' && origin?.origin_block_time && latest > 0
      ? Math.max(0, latest - new Date(origin.origin_block_time).getTime())
      : null;

  await db
    .from('claims')
    .update({
      status,
      settled_at: status === 'settled' ? new Date(latest || Date.now()).toISOString() : null,
      total_latency_ms: totalLatency,
    })
    .eq('run_id', runId);

  return status;
}

function statusName(status: number): string {
  switch (status) {
    case 1:
      return 'active';
    case 2:
      return 'paused';
    case 3:
      return 'cancelled';
    default:
      return 'none';
  }
}
