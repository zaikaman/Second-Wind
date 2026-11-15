import { useQuery } from '@tanstack/react-query';
import { createPublicClient, formatUnits, http } from 'viem';
import type { Address, Hex } from 'viem';
import { baseSepoliaChain } from '../config/chains';
import { INFRASTRUCTURE } from '../config/addresses';
import { morphoReadAbi, oracleReadAbi, tupleField } from '../config/contracts';

const client = createPublicClient({ chain: baseSepoliaChain, transport: http() });

const VIRTUAL_SHARES = 1_000_000n;
const VIRTUAL_ASSETS = 1n;

export type MarketHealth = {
  marketId: Hex;
  collateral: bigint;
  debt: bigint;
  healthWad: bigint;
  price: bigint;
};

/**
 * Live health for one market and borrower, straight from Morpho and the oracle, refreshed every 3 s
 * (T144). Nothing here is cached by the API: during a crash the number must move with the chain.
 */
export function useHealth(borrower: Address | undefined, marketId: Hex | undefined) {
  return useQuery({
    queryKey: ['health', borrower, marketId],
    enabled: Boolean(borrower && marketId),
    refetchInterval: 3_000,
    queryFn: async (): Promise<MarketHealth | null> => {
      if (!borrower || !marketId) {
        return null;
      }

      const [position, params, market] = await Promise.all([
        client.readContract({
          address: INFRASTRUCTURE.morpho,
          abi: morphoReadAbi,
          functionName: 'position',
          args: [marketId, borrower],
          // A read client never signs; viem's parameter type still asks for the EIP-7702 field.
          authorizationList: undefined,
        }),
        client.readContract({
          address: INFRASTRUCTURE.morpho,
          abi: morphoReadAbi,
          functionName: 'idToMarketParams',
          args: [marketId],
          authorizationList: undefined,
        }),
        client.readContract({
          address: INFRASTRUCTURE.morpho,
          abi: morphoReadAbi,
          functionName: 'market',
          args: [marketId],
          authorizationList: undefined,
        }),
      ]);

      const collateral = tupleField<bigint>(position, 2, 'collateral');
      const borrowShares = tupleField<bigint>(position, 1, 'borrowShares');
      if (collateral === 0n || borrowShares === 0n) {
        return null;
      }

      const totalAssets = tupleField<bigint>(market, 2, 'totalBorrowAssets');
      const totalShares = tupleField<bigint>(market, 3, 'totalBorrowShares');
      const lltv = tupleField<bigint>(params, 4, 'lltv');
      const oracle = tupleField<Address>(params, 2, 'oracle');

      const price = await client.readContract({
        address: oracle,
        abi: oracleReadAbi,
        functionName: 'price',
        authorizationList: undefined,
      });

      const debt = totalShares === 0n ? 0n : (borrowShares * (totalAssets + VIRTUAL_ASSETS) + totalShares + VIRTUAL_SHARES - 1n) / (totalShares + VIRTUAL_SHARES);
      const collateralValue = (collateral * price) / 10n ** 36n;
      const healthWad = debt === 0n ? 0n : (collateralValue * lltv) / debt;

      return { marketId, collateral, debt, healthWad, price };
    },
  });
}

/** Formats a wad health factor as three decimals. */
export function formatHealthWad(value: bigint): string {
  return Number(formatUnits(value, 18)).toFixed(3);
}
