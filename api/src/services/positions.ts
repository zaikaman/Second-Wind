import { formatUnits } from 'viem';
import type { Hex } from 'viem';
import type { RpcClient } from '../lib/rpc.js';
import type { PositionView } from '../routes/policies.js';

/** The Morpho surface needed to show a live position. */
const MORPHO_ABI = [
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

const ORACLE_ABI = [
  { type: 'function', name: 'price', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

const WAD = 10n ** 18n;
const VIRTUAL_SHARES = 1_000_000n;
const VIRTUAL_ASSETS = 1n;

/**
 * Reads one position from Base on request, so a crash is never hidden behind a cached health
 * factor. Returns null on any read failure: a stale number is worse than a missing one.
 */
export function createPositionReader(client: RpcClient, morpho: Hex) {
  return async (marketId: Hex, borrower: Hex): Promise<PositionView> => {
    try {
      const [position, params] = await Promise.all([
        client.readContract({ address: morpho, abi: MORPHO_ABI, functionName: 'position', args: [marketId, borrower] }),
        client.readContract({ address: morpho, abi: MORPHO_ABI, functionName: 'idToMarketParams', args: [marketId] }),
      ]);
      if (position.collateral === 0n || position.borrowShares === 0n) {
        return null;
      }

      const market = await client.readContract({ address: morpho, abi: MORPHO_ABI, functionName: 'market', args: [marketId] });
      const price = await client.readContract({
        address: params.oracle,
        abi: ORACLE_ABI,
        functionName: 'price',
      });

      const debt = mulDivUp(position.borrowShares, market.totalBorrowAssets + VIRTUAL_ASSETS, market.totalBorrowShares + VIRTUAL_SHARES);
      const collateralValue = (position.collateral * price) / 10n ** 36n;
      const health = debt === 0n ? 0n : (collateralValue * params.lltv) / debt;

      return {
        collateral: formatUnits(position.collateral, 18),
        debt: formatUnits(debt, 18),
        health: Number(formatUnits(health, 18)).toFixed(4),
        liquidatable: health < WAD,
      };
    } catch {
      return null;
    }
  };
}

function mulDivUp(value: bigint, numerator: bigint, denominator: bigint): bigint {
  if (denominator === 0n) {
    return 0n;
  }
  return (value * numerator + denominator - 1n) / denominator;
}
