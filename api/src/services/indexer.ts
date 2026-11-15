import type { SupabaseClient } from '@supabase/supabase-js';
import type { Hex } from 'viem';
import { logger } from '../lib/logger.js';
import type { RpcClient } from '../lib/rpc.js';
import { decodeLog } from './decoder.js';
import { applyEvent } from './joiner.js';

export type IndexerChain = 'base' | 'unichain' | 'reactive';

export type IndexerDeps = {
  db: SupabaseClient;
  clients: { base: RpcClient; unichain: RpcClient; reactive: RpcClient };
  addresses: {
    base: { registry: Hex; morpho: Hex; coveragePool: Hex };
    unichain: { claimVault: Hex };
    reactive: { contract: Hex };
  };
  /** Block to start from when no cursor exists yet. */
  startBlocks: Record<IndexerChain, number>;
  /** Blocks to lag the head by before indexing, so a reorg is unlikely to be indexed. */
  confirmations: number;
  pollIntervalMs: number;
};

const CHAIN_IDS: Record<IndexerChain, number> = { base: 84_532, unichain: 1_301, reactive: 5_318_007 };

const WATCHED: Record<IndexerChain, (deps: IndexerDeps) => Hex[]> = {
  base: (deps) => [deps.addresses.base.registry, deps.addresses.base.morpho, deps.addresses.base.coveragePool],
  unichain: (deps) => [deps.addresses.unichain.claimVault],
  reactive: (deps) => [deps.addresses.reactive.contract],
};

/** Cursor for one chain, or null when the chain has never been indexed. */
export async function readCursor(db: SupabaseClient, chainId: number): Promise<bigint | null> {
  const { data, error } = await db
    .from('indexer_cursor')
    .select('last_block')
    .eq('chain_id', chainId)
    .maybeSingle();

  if (error) {
    throw new Error(`cursor read failed for ${chainId}: ${error.message}`);
  }
  return data?.last_block === undefined || data?.last_block === null ? null : BigInt(data.last_block);
}

export async function writeCursor(db: SupabaseClient, chainId: number, lastBlock: bigint): Promise<void> {
  const { error } = await db
    .from('indexer_cursor')
    .upsert(
      { chain_id: chainId, last_block: Number(lastBlock), updated_at: new Date().toISOString() },
      { onConflict: 'chain_id' },
    );
  if (error) {
    throw new Error(`cursor write failed for ${chainId}: ${error.message}`);
  }
}

/**
 * One bounded pass over a chain: read the head, fetch the logs the watched contracts emitted since
 * the cursor, apply each one, then advance the cursor. Exported so tests and `POST /internal/reindex`
 * can run it synchronously.
 */
export async function runOnce(deps: IndexerDeps, chain: IndexerChain): Promise<number> {
  const chainId = CHAIN_IDS[chain];
  const client = deps.clients[chain];
  const head = Number(await client.getBlockNumber());
  const target = head - deps.confirmations;
  if (target <= 0) {
    return 0;
  }

  const cursor = await readCursor(deps.db, chainId);
  const from = Number(cursor ?? BigInt(deps.startBlocks[chain] - 1)) + 1;
  if (from > target) {
    return 0;
  }

  const logs = await client.getLogs({
    address: WATCHED[chain](deps),
    fromBlock: BigInt(from),
    toBlock: BigInt(target),
  });

  const blockTimes = new Map<number, Date>();
  let applied = 0;

  for (const log of logs) {
    const blockNumber = Number(log.blockNumber);
    if (!log.topics.length || log.transactionHash === null || log.logIndex === null) {
      continue;
    }

    const decoded = decodeLog(chainId, {
      address: log.address,
      topics: log.topics as Hex[],
      data: log.data,
      blockNumber: log.blockNumber,
      transactionHash: log.transactionHash,
      logIndex: log.logIndex,
    });
    if (!decoded) {
      continue;
    }

    let blockTime = blockTimes.get(blockNumber);
    if (!blockTime) {
      const block = await client.getBlock({ blockNumber: BigInt(blockNumber) });
      blockTime = new Date(Number(block.timestamp) * 1000);
      blockTimes.set(blockNumber, blockTime);
    }

    try {
      await applyEvent(deps.db, {
        chainId,
        address: log.address,
        blockNumber,
        blockTime,
        txHash: log.transactionHash,
        logIndex: log.logIndex,
        decoded,
      });
      applied += 1;
    } catch (error) {
      // The cursor must not advance past a log that could not be applied, or the claim would be
      // lost. Stop this pass here; the next pass retries from the same block.
      logger.warn({ err: error, chain, blockNumber }, 'indexer stopped early; will retry');
      await writeCursor(deps.db, chainId, BigInt(blockNumber - 1));
      return applied;
    }
  }

  await writeCursor(deps.db, chainId, BigInt(target));
  return applied;
}

/**
 * Three independent poll loops. Each chain fails on its own: a Base outage does not stop Unichain,
 * and a thrown error is logged and retried on the next tick rather than killing the process.
 */
export function startIndexer(deps: IndexerDeps): () => void {
  let stopped = false;
  const timers: NodeJS.Timeout[] = [];

  const loop = (chain: IndexerChain): void => {
    const tick = async (): Promise<void> => {
      if (stopped) return;
      try {
        const applied = await runOnce(deps, chain);
        if (applied > 0) {
          logger.info({ chain, applied }, 'indexed blocks');
        }
      } catch (error) {
        logger.error({ err: error, chain }, 'indexer pass failed');
      } finally {
        if (!stopped) {
          timers.push(setTimeout(tick, deps.pollIntervalMs));
        }
      }
    };
    void tick();
  };

  (['base', 'unichain', 'reactive'] as const).forEach(loop);

  return () => {
    stopped = true;
    for (const timer of timers) {
      clearTimeout(timer);
    }
  };
}
