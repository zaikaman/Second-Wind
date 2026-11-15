import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from 'dotenv';

/** Repository root, derived from this file's location so scripts work from any working directory. */
export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

config({ path: resolve(REPO_ROOT, '.env'), quiet: true });

export type Hex = `0x${string}`;

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing ${name}. Copy .env.example to ${resolve(REPO_ROOT, '.env')} and fill it in.`);
  }
  return value;
}

function privateKey(name: string): Hex {
  const value = required(name);
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new Error(`${name} must be a 32-byte hex private key.`);
  }
  return value as Hex;
}

/** Every environment value the ops scripts need, validated once. */
export const env = {
  get deployerKey(): Hex {
    return privateKey('DEPLOYER_KEY');
  },
  get borrowerKey(): Hex {
    return privateKey('BORROWER_KEY');
  },
  get liquidatorKey(): Hex {
    return privateKey('LIQUIDATOR_KEY');
  },
  get rpc() {
    return {
      base: required('BASE_SEPOLIA_RPC'),
      unichain: required('UNICHAIN_SEPOLIA_RPC'),
      lasna: required('LASNA_RPC'),
    } as const;
  },
  get morpho(): Hex {
    return required('MORPHO') as Hex;
  },
  get baseCallbackProxy(): Hex {
    return required('BASE_CALLBACK_PROXY') as Hex;
  },
  get unichainCallbackProxy(): Hex {
    return required('UNICHAIN_CALLBACK_PROXY') as Hex;
  },
} as const;
