/** Fixed, public infrastructure addresses (not deployed by this repo). */
export const INFRASTRUCTURE = {
  morpho: '0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb',
} as const;

const ZERO = '0x0000000000000000000000000000000000000000';

export type Address = `0x${string}`;

function parseAddress(value: string | undefined): Address {
  return value && /^0x[0-9a-fA-F]{40}$/.test(value) ? (value as Address) : (ZERO as Address);
}

/**
 * Deployed contract addresses, written by the deploy scripts into `ops/addresses.json`
 * and mirrored into the Vite environment for this build.
 */
export const addresses = {
  base: {
    registry: parseAddress(import.meta.env.VITE_BASE_REGISTRY),
    coveragePool: parseAddress(import.meta.env.VITE_BASE_COVERAGE_POOL),
    usdc: parseAddress(import.meta.env.VITE_BASE_USDC),
  },
  unichain: {
    claimVault: parseAddress(import.meta.env.VITE_UNICHAIN_CLAIM_VAULT),
    usdc: parseAddress(import.meta.env.VITE_UNICHAIN_USDC),
  },
  lasna: {
    reactive: parseAddress(import.meta.env.VITE_REACTIVE_CONTRACT),
  },
} as const;

export function isConfigured(address: string): boolean {
  return address !== ZERO;
}

/**
 * Fails at boot when a production build is missing an address. A zero address in the bundle
 * means every read returns "no policy" and every write goes nowhere, which is far harder to
 * diagnose from the UI than a loud error at startup.
 */
export function assertConfiguredAddresses(): void {
  if (!import.meta.env.PROD) {
    return;
  }

  const missing: string[] = [];
  if (!isConfigured(addresses.base.registry)) missing.push('VITE_BASE_REGISTRY');
  if (!isConfigured(addresses.base.coveragePool)) missing.push('VITE_BASE_COVERAGE_POOL');
  if (!isConfigured(addresses.base.usdc)) missing.push('VITE_BASE_USDC');
  if (!isConfigured(addresses.unichain.claimVault)) missing.push('VITE_UNICHAIN_CLAIM_VAULT');
  if (!isConfigured(addresses.unichain.usdc)) missing.push('VITE_UNICHAIN_USDC');
  if (!isConfigured(addresses.lasna.reactive)) missing.push('VITE_REACTIVE_CONTRACT');

  if (missing.length > 0) {
    throw new Error(`Missing deployed addresses in this build: ${missing.join(', ')}`);
  }
}
