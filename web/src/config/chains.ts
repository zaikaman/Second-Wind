import { defineChain } from 'viem';
import { baseSepolia, unichainSepolia } from 'viem/chains';
import type { Chain } from 'viem';

function rpcUrl(configured: string | undefined, fallback: string): string {
  return configured && configured.length > 0 ? configured : fallback;
}

/** Base Sepolia (84532): origin chain. Morpho, PolicyRegistry and CoveragePool live here. */
export const baseSepoliaChain: Chain = {
  ...baseSepolia,
  rpcUrls: {
    default: {
      http: [rpcUrl(import.meta.env.VITE_BASE_SEPOLIA_RPC, baseSepolia.rpcUrls.default.http[0])],
    },
  },
};

/** Unichain Sepolia (1301): cash payout destination. ClaimVault lives here. */
export const unichainSepoliaChain: Chain = {
  ...unichainSepolia,
  rpcUrls: {
    default: {
      http: [rpcUrl(import.meta.env.VITE_UNICHAIN_SEPOLIA_RPC, unichainSepolia.rpcUrls.default.http[0])],
    },
  },
};

/** Reactive Lasna (5318007): watches events and dispatches both callbacks. Read-only from the app. */
export const lasnaChain: Chain = defineChain({
  id: 5318007,
  name: 'Reactive Lasna',
  nativeCurrency: { name: 'REACT', symbol: 'REACT', decimals: 18 },
  rpcUrls: {
    default: { http: [rpcUrl(import.meta.env.VITE_LASNA_RPC, 'https://lasna-rpc.rnk.dev/')] },
  },
  blockExplorers: {
    default: { name: 'ReactScan', url: 'https://lasna.reactscan.net' },
  },
  testnet: true,
});

/** Chains the wallet can connect to. Lasna is read-only for this app. */
export const walletChains = [baseSepoliaChain, unichainSepoliaChain] as const;

export const CHAIN_IDS = {
  base: baseSepolia.id,
  unichain: unichainSepolia.id,
  lasna: lasnaChain.id,
} as const;
