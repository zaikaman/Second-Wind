import { env } from './config/env.js';
import { createApp } from './app.js';
import { migrate } from './db/migrate.js';
import { createSupabase } from './db/supabase.js';
import { createRpcClients } from './lib/rpc.js';
import { logger } from './lib/logger.js';
import { createHealthProvider } from './services/health.js';
import { createClaimsStore } from './services/claims-store.js';
import { createPoliciesStore } from './services/policies-store.js';
import { createPositionReader, createHealthAtReader } from './services/positions.js';
import { createStatsStore } from './services/stats-store.js';
import { startIndexer } from './services/indexer.js';
import { formatUnits } from 'viem';
import type { Hex } from 'viem';

const SHUTDOWN_GRACE_MS = 10_000;

async function main(): Promise<void> {
  const config = env();

  // Migrations run once at boot under an advisory lock, so a second dyno waits instead of racing.
  const applied = await migrate(config.DATABASE_URL);
  logger.info({ applied }, 'database ready');

  const clients = createRpcClients({
    base: config.BASE_SEPOLIA_RPC,
    unichain: config.UNICHAIN_SEPOLIA_RPC,
    lasna: config.LASNA_RPC,
  });
  const db = createSupabase(config.SUPABASE_URL, config.SUPABASE_SERVICE_KEY);

  const addresses = {
    coveragePool: config.COVERAGE_POOL_ADDRESS as Hex,
    claimVault: config.CLAIM_VAULT_ADDRESS as Hex,
    reactive: config.REACTIVE_ADDRESS as Hex,
    registry: config.BASE_REGISTRY_ADDRESS as Hex,
    morpho: config.MORPHO as Hex,
  };

  const health = createHealthProvider({
    version: config.VERSION,
    clients,
    addresses: {
      coveragePool: addresses.coveragePool,
      claimVault: addresses.claimVault,
      reactive: addresses.reactive,
    },
    proxies: {
      base: config.BASE_CALLBACK_PROXY as Hex,
      unichain: config.UNICHAIN_CALLBACK_PROXY as Hex,
    },
    db,
  });

  const ERC20_BALANCE_ABI = [
    {
      type: 'function',
      name: 'balanceOf',
      stateMutability: 'view',
      inputs: [{ name: 'account', type: 'address' }],
      outputs: [{ type: 'uint256' }],
    },
  ] as const;

  const readReserve = async (chain: 'base' | 'unichain', asset: Hex, holder: Hex): Promise<string> => {
    try {
      const balance = await clients[chain].readContract({
        address: asset,
        abi: ERC20_BALANCE_ABI,
        functionName: 'balanceOf',
        args: [holder],
      });
      return formatUnits(balance, 18);
    } catch {
      return '0';
    }
  };

  const claims = createClaimsStore(db);
  const policies = createPoliciesStore(db, createPositionReader(clients.base, addresses.morpho));
  const stats = createStatsStore(db, async () => ({
    base: await readReserve('base', config.BASE_COVER_ASSET as Hex, addresses.coveragePool),
    unichain: await readReserve('unichain', config.UNICHAIN_COVER_ASSET as Hex, addresses.claimVault),
  }));

  const app = createApp({
    version: config.VERSION,
    corsOrigins: config.CORS_ORIGINS.split(',')
      .map((origin) => origin.trim())
      .filter((origin) => origin.length > 0),
    health,
    claims,
    policies,
    stats,
  });

  const stopIndexer = startIndexer({
    db,
    clients,
    addresses: {
      base: { registry: addresses.registry, morpho: addresses.morpho, coveragePool: addresses.coveragePool },
      unichain: { claimVault: addresses.claimVault },
      reactive: { contract: addresses.reactive, system: config.REACTIVE_SYSTEM_CONTRACT as Hex },
    },
    startBlocks: { base: config.INDEXER_START_BASE, unichain: config.INDEXER_START_UNICHAIN, reactive: config.INDEXER_START_REACTIVE },
    confirmations: config.INDEXER_CONFIRMATIONS,
    pollIntervalMs: config.INDEXER_POLL_MS,
    readHealthBefore: createHealthAtReader(clients.base, addresses.morpho),
  });

  const server = app.listen(config.PORT, () => {
    logger.info({ port: config.PORT, version: config.VERSION }, 'api listening');
  });

  const shutdown = (signal: string): void => {
    logger.info({ signal }, 'shutting down');
    stopIndexer();
    server.close(() => {
      logger.info('drained');
      process.exit(0);
    });
    setTimeout(() => {
      logger.error('drain timed out');
      process.exit(1);
    }, SHUTDOWN_GRACE_MS).unref();
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main().catch((error: unknown) => {
  logger.error({ err: error }, 'fatal');
  process.exit(1);
});
