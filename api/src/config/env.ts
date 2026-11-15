import { z } from 'zod';

const address = z.string().regex(/^0x[0-9a-fA-F]{40}$/, 'must be a 0x-prefixed 20-byte address');

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(8080),
  VERSION: z.string().min(1).default('0.1.0'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),

  BASE_SEPOLIA_RPC: z.string().url(),
  UNICHAIN_SEPOLIA_RPC: z.string().url(),
  LASNA_RPC: z.string().url(),

  SUPABASE_URL: z.string().url(),
  SUPABASE_SERVICE_KEY: z.string().min(1),
  DATABASE_URL: z.string().min(1),

  CORS_ORIGINS: z.string().default('http://localhost:5173'),
  ADMIN_TOKEN: z.string().min(1).optional(),

  MORPHO: address,
  BASE_CALLBACK_PROXY: address,
  UNICHAIN_CALLBACK_PROXY: address,

  COVERAGE_POOL_ADDRESS: address,
  CLAIM_VAULT_ADDRESS: address,
  REACTIVE_ADDRESS: address,
});

export type Env = z.infer<typeof schema>;

function fail(message: string): never {
  // A missing or malformed variable must stop the process before it starts serving wrong answers.
  console.error(message);
  process.exit(1);
}

/** Parses the process environment, exiting with a readable message when anything is missing. */
export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((issue) => `  - ${issue.path.join('.') || '(root)'}: ${issue.message}`)
      .join('\n');
    fail(`Invalid environment configuration:\n${details}\n\nCopy .env.example to .env and fill it in.`);
  }
  return parsed.data;
}

let cached: Env | undefined;

/** The process-wide configuration. Parsed once, on first use. */
export function env(): Env {
  cached ??= loadEnv();
  return cached;
}
