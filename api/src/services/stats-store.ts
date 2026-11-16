import type { SupabaseClient } from '@supabase/supabase-js';
import type { CoverageStats, LatencySample, StatsStore } from '../routes/stats.js';

type PolicyRow = {
  coverage_cap: string;
  cash_ceiling: string;
  relief_ceiling: string;
  cash_paid: string;
  relief_used: string;
  premium_per_second: string;
  paid_through: number;
  created_at: string;
};

/** Latency samples and lifetime totals, both straight from the cache. */
export function createStatsStore(
  db: SupabaseClient,
  readReserves: () => Promise<{ base: string; unichain: string }>,
): StatsStore {
  return {
    async latencySamples(limit) {
      const { data, error } = await db
        .from('latency_samples')
        .select('run_id,branch,trial,latency_ms')
        .order('id', { ascending: false })
        .limit(limit);
      if (error) {
        throw new Error(`latency read failed: ${error.message}`);
      }
      return ((data ?? []) as { run_id: string; branch: 'relief' | 'cash'; trial: number; latency_ms: number }[]).map(
        (row): LatencySample => ({
          runId: row.run_id,
          branch: row.branch,
          trial: Number(row.trial),
          latencyMs: Number(row.latency_ms),
        }),
      );
    },

    async coverage(): Promise<CoverageStats> {
      const [{ data: policies, error: policyError }, { count, error: claimError }, reserves] = await Promise.all([
        // Cast to text so the 21-digit wei amounts survive PostgREST's JSON number rendering.
        db
          .from('policies_mirror')
          .select(
            'coverage_cap::text,cash_ceiling::text,relief_ceiling::text,cash_paid::text,relief_used::text,premium_per_second::text,paid_through,created_at',
          ),
        db.from('claims').select('run_id', { count: 'exact', head: true }),
        readReserves(),
      ]);

      if (policyError || claimError) {
        throw new Error(`coverage read failed: ${policyError?.message ?? claimError?.message}`);
      }

      const rows = (policies ?? []) as PolicyRow[];
      let premium = 0n;
      let cash = 0n;
      let relief = 0n;
      let cashCeiling = 0n;
      let reliefCeiling = 0n;

      for (const row of rows) {
        const seconds = BigInt(Math.max(0, Number(row.paid_through) - Math.floor(new Date(row.created_at).getTime() / 1000)));
        premium += BigInt(row.premium_per_second) * seconds;
        cash += BigInt(row.cash_paid);
        relief += BigInt(row.relief_used);
        cashCeiling += BigInt(row.cash_ceiling);
        reliefCeiling += BigInt(row.relief_ceiling);
      }

      return {
        policies: rows.length,
        claims: count ?? 0,
        premiumCollected: premium.toString(),
        cashPaid: cash.toString(),
        reliefApplied: relief.toString(),
        reserveBase: reserves.base,
        reserveUnichain: reserves.unichain,
        branchCeilings: { cash: cashCeiling.toString(), relief: reliefCeiling.toString() },
      };
    },
  };
}
