import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Client } from 'pg';
import { logger } from '../lib/logger.js';

const MIGRATIONS_DIR = join(dirname(fileURLToPath(import.meta.url)), 'migrations');

/** Arbitrary but stable advisory-lock key, so two booting dynos cannot migrate at once. */
const MIGRATION_LOCK = 732_410_001;

/**
 * Applies every unapplied migration inside one transaction, under an advisory lock, and records
 * each file in `schema_migrations`. Idempotent: running it twice applies nothing the second time.
 */
export async function migrate(databaseUrl: string): Promise<number> {
  const client = new Client({ connectionString: databaseUrl });
  await client.connect();

  try {
    await client.query('begin');
    await client.query('select pg_advisory_xact_lock($1)', [MIGRATION_LOCK]);
    await client.query(`
      create table if not exists schema_migrations (
        name       text primary key,
        applied_at timestamptz not null default now()
      )
    `);

    const files = (await readdir(MIGRATIONS_DIR)).filter((file) => file.endsWith('.sql')).sort();
    const appliedRows = await client.query<{ name: string }>('select name from schema_migrations');
    const applied = new Set(appliedRows.rows.map((row) => row.name));

    let count = 0;
    for (const file of files) {
      if (applied.has(file)) {
        continue;
      }
      const sql = await readFile(join(MIGRATIONS_DIR, file), 'utf8');
      await client.query(sql);
      await client.query('insert into schema_migrations (name) values ($1)', [file]);
      count += 1;
      logger.info({ migration: file }, 'applied migration');
    }

    await client.query('commit');
    return count;
  } catch (error) {
    await client.query('rollback');
    throw error;
  } finally {
    await client.end();
  }
}

async function main(): Promise<void> {
  const { env } = await import('../config/env.js');
  const applied = await migrate(env().DATABASE_URL);
  logger.info({ applied }, 'migrations complete');
}

const invokedDirectly = process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  main().catch((error: unknown) => {
    logger.error({ err: error }, 'migration failed');
    process.exit(1);
  });
}
