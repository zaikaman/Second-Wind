import type { Address, Hex } from 'viem';

/** The registry surface the app reads. Kept minimal on purpose: reads only, no writes here. */
export const registryReadAbi = [
  {
    type: 'function',
    name: 'policiesOf',
    stateMutability: 'view',
    inputs: [{ name: 'borrower', type: 'address' }],
    outputs: [{ name: '', type: 'uint256[]' }],
  },
  {
    type: 'function',
    name: 'getPolicy',
    stateMutability: 'view',
    inputs: [{ name: 'policyId', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'policyId', type: 'uint256' },
          { name: 'borrower', type: 'address' },
          { name: 'marketId', type: 'bytes32' },
          { name: 'loanKey', type: 'bytes32' },
          { name: 'coverageCap', type: 'uint256' },
          { name: 'cashCeiling', type: 'uint256' },
          { name: 'reliefCeiling', type: 'uint256' },
          { name: 'premiumPerSecond', type: 'uint256' },
          { name: 'paidThrough', type: 'uint64' },
          { name: 'reliefShareBps', type: 'uint16' },
          { name: 'targetHealthWad', type: 'uint256' },
          { name: 'cashDestination', type: 'address' },
          { name: 'status', type: 'uint8' },
          { name: 'reliefUsed', type: 'uint256' },
          { name: 'cancelledAtBlock', type: 'uint64' },
          { name: 'createdAt', type: 'uint64' },
        ],
      },
    ],
  },
] as const;

/** The Morpho surface the dashboard reads to show live health. */
export const morphoReadAbi = [
  {
    type: 'function',
    name: 'position',
    stateMutability: 'view',
    inputs: [
      { name: 'id', type: 'bytes32' },
      { name: 'user', type: 'address' },
    ],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'supplyShares', type: 'uint256' },
          { name: 'borrowShares', type: 'uint128' },
          { name: 'collateral', type: 'uint128' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'idToMarketParams',
    stateMutability: 'view',
    inputs: [{ name: 'id', type: 'bytes32' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'loanToken', type: 'address' },
          { name: 'collateralToken', type: 'address' },
          { name: 'oracle', type: 'address' },
          { name: 'irm', type: 'address' },
          { name: 'lltv', type: 'uint256' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'market',
    stateMutability: 'view',
    inputs: [{ name: 'id', type: 'bytes32' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'totalSupplyAssets', type: 'uint128' },
          { name: 'totalSupplyShares', type: 'uint128' },
          { name: 'totalBorrowAssets', type: 'uint128' },
          { name: 'totalBorrowShares', type: 'uint128' },
          { name: 'lastUpdate', type: 'uint128' },
          { name: 'fee', type: 'uint128' },
        ],
      },
    ],
  },
] as const;

export const oracleReadAbi = [
  { type: 'function', name: 'price', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

/** One decoded on-chain policy, as the hooks consume it. */
export type OnChainPolicy = {
  policyId: bigint;
  borrower: Address;
  marketId: Hex;
  coverageCap: bigint;
  cashCeiling: bigint;
  reliefCeiling: bigint;
  premiumPerSecond: bigint;
  paidThrough: bigint;
  reliefShareBps: number;
  targetHealthWad: bigint;
  cashDestination: Address;
  status: number;
  reliefUsed: bigint;
  createdAt: bigint;
};

/**
 * viem decodes a struct output either as a tuple or as an object with named fields, depending on
 * the exact ABI shape it was given. Reading both keeps the hook independent of that detail.
 */
export function policyField<T>(policy: unknown, index: number, name: string): T {
  if (Array.isArray(policy)) {
    return policy[index] as T;
  }
  return (policy as Record<string, T>)[name] as T;
}

export function tupleField<T>(value: unknown, index: number, name: string): T {
  return policyField<T>(value, index, name);
}
