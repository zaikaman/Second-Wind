export type ExplorerChainId = number;

const BASES: Record<number, string> = {
  84_532: 'https://sepolia.basescan.org',
  1_301: 'https://sepolia.uniscan.xyz',
  5_318_007: 'https://lasna.reactscan.net',
};

/** Explorer link for a transaction or address, or null for a chain without a known explorer. */
export function explorerUrl(chainId: ExplorerChainId, kind: 'tx' | 'address', value: string): string | null {
  const base = BASES[chainId];
  if (!base || !value.startsWith('0x')) {
    return null;
  }
  return `${base}/${kind}/${value}`;
}
