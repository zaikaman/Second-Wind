import { createPublicClient, defineChain, http } from 'viem';
import { baseSepolia, unichainSepolia } from 'viem/chains';

/** Reactive Lasna: no viem preset, so it is declared explicitly. */
export const lasna = defineChain({
  id: 5_318_007,
  name: 'Reactive Lasna',
  nativeCurrency: { name: 'REACT', symbol: 'REACT', decimals: 18 },
  rpcUrls: { default: { http: ['https://lasna-rpc.rnk.dev/'] } },
  blockExplorers: { default: { name: 'ReactScan', url: 'https://lasna.reactscan.net' } },
  testnet: true,
});

export type RpcUrls = { base: string; unichain: string; lasna: string };

const TIMEOUT_MS = 10_000;
const RETRY_COUNT = 2;

const transport = (url: string) => http(url, { timeout: TIMEOUT_MS, retryCount: RETRY_COUNT, retryDelay: 300 });

function client(url: string) {
  return createPublicClient({ chain: baseSepolia, transport: transport(url) });
}

/** The client type shared by all three chains. */
export type RpcClient = ReturnType<typeof client>;

export type RpcClients = {
  base: RpcClient;
  unichain: RpcClient;
  reactive: RpcClient;
};

/**
 * Public clients with a request timeout and two retries, so a flaky RPC degrades instead of hanging.
 *
 * Only `getBlockNumber`, `getBalance` and `readContract` are used, and their signatures are
 * identical on every chain. viem derives block and transaction types from each chain's serializers,
 * which makes the three clients nominally different types, so the Unichain and Lasna clients are
 * aligned to the Base client's type.
 */
export function createRpcClients(urls: RpcUrls): RpcClients {
  return {
    base: client(urls.base),
    unichain: createPublicClient({
      chain: unichainSepolia,
      transport: transport(urls.unichain),
    }) as unknown as RpcClient,
    reactive: createPublicClient({
      chain: lasna,
      transport: transport(urls.lasna),
    }) as unknown as RpcClient,
  };
}

/** Chain head as a number, or null when the RPC is unreachable. */
export async function head(client: RpcClient): Promise<number | null> {
  try {
    return Number(await client.getBlockNumber());
  } catch {
    return null;
  }
}
