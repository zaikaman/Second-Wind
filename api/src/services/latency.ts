import type { SupabaseClient } from '@supabase/supabase-js';
import { logger } from '../lib/logger.js';

export type LatencySummary = { p50: number; p95: number; max: number; count: number };

/**
 * Nearest-rank percentiles. Latency is measured from the origin (Base) block timestamp to the
 * destination block timestamp, never from API receipt time: the latter would measure this indexer
 * instead of the product.
 */
export function percentiles(values: number[]): LatencySummary {
  if (values.length === 0) {
    return { p50: 0, p95: 0, max: 0, count: 0 };
  }
  const sorted = [...values].sort((a, b) => a - b);
  return {
    p50: rank(sorted, 50),
    p95: rank(sorted, 95),
    max: sorted[sorted.length - 1] ?? 0,
    count: sorted.length,
  };
}

function rank(sorted: number[], percentile: number): number {
  const position = Math.ceil((percentile / 100) * sorted.length) - 1;
  return sorted[Math.min(Math.max(position, 0), sorted.length - 1)] ?? 0;
}

/** Milliseconds between two block timestamps, floored at zero. */
export function latencyMs(origin: Date, confirmed: Date): number {
  return Math.max(0, confirmed.getTime() - origin.getTime());
}

export type LatencyInput = {
  runId: string;
  branch: 'relief' | 'cash';
  originBlockTime: Date;
  dispatchTime: Date | null;
  confirmBlockTime: Date;
};

/**
 * Writes one sample per confirmed branch. A re-index finds the existing row by `(run_id, branch)`
 * and updates it instead of inserting a duplicate, so percentiles cannot be inflated by replay.
 */
export async function recordLatency(db: SupabaseClient, input: LatencyInput): Promise<void> {
  const value = latencyMs(input.originBlockTime, input.confirmBlockTime);

  const { data: existing, error: readError } = await db
    .from('latency_samples')
    .select('id')
    .eq('run_id', input.runId)
    .eq('branch', input.branch)
    .limit(1)
    .maybeSingle();

  if (readError) {
    logger.error({ err: readError, runId: input.runId }, 'latency read failed');
    return;
  }

  const row = {
    run_id: input.runId,
    branch: input.branch,
    trial: 0,
    origin_block_time: input.originBlockTime.toISOString(),
    dispatch_time: input.dispatchTime?.toISOString() ?? null,
    confirm_block_time: input.confirmBlockTime.toISOString(),
    latency_ms: value,
  };

  const { error } = existing?.id
    ? await db.from('latency_samples').update(row).eq('id', existing.id)
    : await db.from('latency_samples').insert(row);

  if (error) {
    logger.error({ err: error, runId: input.runId }, 'latency write failed');
  }
}
