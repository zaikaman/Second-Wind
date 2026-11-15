import { formatUnits } from 'viem';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { ChainReport, HealthProvider, HealthSnapshot } from '../routes/health.js';
import { head } from '../lib/rpc.js';
import type { RpcClient } from '../lib/rpc.js';

/** The callback proxies expose `debt(address)` and `reserves(address)` for funded contracts. */
const PROXY_ABI = [
  {
    type: 'function',
    name: 'debt',
    stateMutability: 'view',
    inputs: [{ name: 'contract_', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'reserves',
    stateMutability: 'view',
    inputs: [{ name: 'contract_', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

export type HealthDeps = {
  version: string;
  clients: { base: RpcClient; unichain: RpcClient; reactive: RpcClient };
  addresses: {
    coveragePool: `0x${string}`;
    claimVault: `0x${string}`;
    reactive: `0x${string}`;
  };
  proxies: {
    base: `0x${string}`;
    unichain: `0x${string}`;
  };
  db: SupabaseClient;
};

type ChainKey = 'base' | 'unichain' | 'reactive';
const CHAIN_IDS: Record<ChainKey, number> = { base: 84_532, unichain: 1_301, reactive: 5_318_007 };

function ether(value: bigint): string {
  return Number(formatUnits(value, 18)).toFixed(4);
}

async function chainReport(key: ChainKey, client: RpcClient, indexed: number | null): Promise<ChainReport> {
  const chainId = CHAIN_IDS[key];
  const blockNumber = await head(client);
  return {
    chainId,
    head: blockNumber,
    indexed,
    lagBlocks: blockNumber !== null && indexed !== null ? Math.max(blockNumber - indexed, 0) : null,
  };
}

async function fundingReport(
  client: RpcClient,
  proxy: `0x${string}`,
  account: `0x${string}`,
): Promise<{ native: string; debt: string; reserves: string }> {
  try {
    const [balance, debt, reserves] = await Promise.all([
      client.getBalance({ address: account }),
      client.readContract({ address: proxy, abi: PROXY_ABI, functionName: 'debt', args: [account] }),
      client.readContract({ address: proxy, abi: PROXY_ABI, functionName: 'reserves', args: [account] }),
    ]);
    return { native: ether(balance), debt: ether(debt), reserves: ether(reserves) };
  } catch {
    // A read failure must not take the health endpoint down; an unknown debt reads as unfunded.
    return { native: '0.0000', debt: 'unknown', reserves: '0.0000' };
  }
}

async function indexedHeights(db: SupabaseClient): Promise<Record<number, number>> {
  try {
    const { data, error } = await db.from('indexer_cursor').select('chain_id,last_block');
    if (error || !data) {
      return {};
    }
    const heights: Record<number, number> = {};
    for (const row of data as { chain_id: number; last_block: number }[]) {
      heights[row.chain_id] = Number(row.last_block);
    }
    return heights;
  } catch {
    return {};
  }
}

/** Builds the `/health` payload from chain reads and the indexer cursor table. */
export function createHealthProvider(deps: HealthDeps): HealthProvider {
  return async (): Promise<HealthSnapshot> => {
    const indexed = await indexedHeights(deps.db);

    const [base, unichain, reactive] = await Promise.all([
      chainReport('base', deps.clients.base, indexed[CHAIN_IDS.base] ?? null),
      chainReport('unichain', deps.clients.unichain, indexed[CHAIN_IDS.unichain] ?? null),
      chainReport('reactive', deps.clients.reactive, indexed[CHAIN_IDS.reactive] ?? null),
    ]);

    const [reactiveFunding, coverageFunding, vaultFunding] = await Promise.all([
      fundingReport(deps.clients.reactive, deps.addresses.reactive, deps.addresses.reactive),
      fundingReport(deps.clients.base, deps.proxies.base, deps.addresses.coveragePool),
      fundingReport(deps.clients.unichain, deps.proxies.unichain, deps.addresses.claimVault),
    ]);

    const indexedValues = [base.indexed, unichain.indexed, reactive.indexed].filter(
      (value): value is number => value !== null,
    );

    return {
      version: deps.version,
      chains: { base, unichain, reactive },
      funding: {
        reactive: reactiveFunding,
        coveragePool: coverageFunding,
        claimVault: vaultFunding,
      },
      lastIndexedAt: indexedValues.length > 0 ? new Date().toISOString() : null,
    };
  };
}
