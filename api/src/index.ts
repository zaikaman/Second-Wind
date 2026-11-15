import { env } from './config/env.js';
import { createApp } from './app.js';
import { migrate } from './db/migrate.js';
import { createSupabase } from './db/supabase.js';
import { createRpcClients } from './lib/rpc.js';
import { logger } from './lib/logger.js';
import { createHealthProvider } from './services/health.js';

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

  const health = createHealthProvider({
    version: config.VERSION,
    clients,
    addresses: {
      coveragePool: config.COVERAGE_POOL_ADDRESS as `0x${string}`,
      claimVault: config.CLAIM_VAULT_ADDRESS as `0x${string}`,
      reactive: config.REACTIVE_ADDRESS as `0x${string}`,
    },
    proxies: {
      base: config.BASE_CALLBACK_PROXY as `0x${string}`,
      unichain: config.UNICHAIN_CALLBACK_PROXY as `0x${string}`,
    },
    db,
  });

  const app = createApp({
    version: config.VERSION,
    corsOrigins: config.CORS_ORIGINS.split(',')
      .map((origin) => origin.trim())
      .filter((origin) => origin.length > 0),
    health,
  });

  // The indexer (Base, Unichain, Lasna poll loops) starts here in the product phase; see
  // specs/001-second-wind/tasks.md T133. Nothing else in this process depends on it.
  const server = app.listen(config.PORT, () => {
    logger.info({ port: config.PORT, version: config.VERSION }, 'api listening');
  });

  const shutdown = (signal: string): void => {
    logger.info({ signal }, 'shutting down');
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
