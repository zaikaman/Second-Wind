import { createPublicClient, createWalletClient, defineChain, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia, unichainSepolia } from 'viem/chains';
import { env, type Hex } from './env.js';

/** Reactive Lasna has no viem preset. */
export const lasna = defineChain({
  id: 5_318_007,
  name: 'Reactive Lasna',
  nativeCurrency: { name: 'REACT', symbol: 'REACT', decimals: 18 },
  rpcUrls: { default: { http: ['https://lasna-rpc.rnk.dev/'] } },
  blockExplorers: { default: { name: 'ReactScan', url: 'https://lasna.reactscan.net' } },
  testnet: true,
});

const transport = (url: string) => http(url, { timeout: 15_000, retryCount: 2 });

/** Read clients for the three chains the demo touches. */
export function publicClients() {
  return {
    base: createPublicClient({ chain: baseSepolia, transport: transport(env.rpc.base) }),
    unichain: createPublicClient({ chain: unichainSepolia, transport: transport(env.rpc.unichain) }),
    reactive: createPublicClient({ chain: lasna, transport: transport(env.rpc.lasna) }),
  };
}

/** Signing client for one chain, from a key in the repo `.env`. */
export function walletClient(chain: 'base' | 'unichain' | 'lasna', key?: Hex) {
  const account = privateKeyToAccount(key ?? env.deployerKey);
  const chains = { base: baseSepolia, unichain: unichainSepolia, lasna } as const;
  return {
    account,
    client: createWalletClient({ account, chain: chains[chain], transport: transport(env.rpc[chain]) }),
  };
}
