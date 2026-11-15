export type ExplorerChain = 'base' | 'unichain' | 'lasna';

const BASES: Record<ExplorerChain, string | null> = {
  base: 'https://sepolia.basescan.org',
  unichain: 'https://sepolia.uniscan.xyz',
  lasna: 'https://lasna.reactscan.net',
};

function link(chain: ExplorerChain, path: string): string | null {
  const base = BASES[chain];
  if (!base) {
    return null;
  }
  return `${base}${path}`;
}

/** Explorer URL for a transaction, or null when the chain has no known explorer. */
export function txUrl(chain: ExplorerChain, hash: string): string | null {
  if (!hash || !hash.startsWith('0x')) {
    return null;
  }
  return link(chain, `/tx/${hash}`);
}

/** Explorer URL for an address, or null when the chain has no known explorer. */
export function addressUrl(chain: ExplorerChain, address: string): string | null {
  if (!address || !address.startsWith('0x')) {
    return null;
  }
  return link(chain, `/address/${address}`);
}
