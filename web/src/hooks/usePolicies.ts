import { useQuery } from '@tanstack/react-query';
import { createPublicClient, http } from 'viem';
import type { Address } from 'viem';
import { baseSepoliaChain } from '../config/chains';
import { addresses, isConfigured } from '../config/addresses';
import { INFRASTRUCTURE } from '../config/addresses';
import { policyField, registryReadAbi } from '../config/contracts';
import type { OnChainPolicy } from '../config/contracts';

const client = createPublicClient({ chain: baseSepoliaChain, transport: http() });

/** Reads the borrower's policies from Base and refetches every 5 s (T142). */
export function usePolicies(borrower: Address | undefined) {
  return useQuery({
    queryKey: ['policies', borrower, addresses.base.registry],
    enabled: Boolean(borrower) && isConfigured(addresses.base.registry) && isConfigured(INFRASTRUCTURE.morpho),
    refetchInterval: 5_000,
    queryFn: async (): Promise<OnChainPolicy[]> => {
      if (!borrower) {
        return [];
      }

      const ids = await client.readContract({
        address: addresses.base.registry,
        abi: registryReadAbi,
        functionName: 'policiesOf',
        args: [borrower],
        // A read client never signs; viem's parameter type still asks for the EIP-7702 field.
        authorizationList: undefined,
      });

      const policies = await Promise.all(
        ids.map(async (id) => {
          const raw = await client.readContract({
            address: addresses.base.registry,
            abi: registryReadAbi,
            functionName: 'getPolicy',
            args: [id],
            authorizationList: undefined,
          });

          return {
            policyId: policyField<bigint>(raw, 0, 'policyId'),
            borrower: policyField<Address>(raw, 1, 'borrower'),
            marketId: policyField<`0x${string}`>(raw, 2, 'marketId'),
            coverageCap: policyField<bigint>(raw, 4, 'coverageCap'),
            cashCeiling: policyField<bigint>(raw, 5, 'cashCeiling'),
            reliefCeiling: policyField<bigint>(raw, 6, 'reliefCeiling'),
            premiumPerSecond: policyField<bigint>(raw, 7, 'premiumPerSecond'),
            paidThrough: policyField<bigint>(raw, 8, 'paidThrough'),
            reliefShareBps: Number(policyField<number>(raw, 9, 'reliefShareBps')),
            targetHealthWad: policyField<bigint>(raw, 10, 'targetHealthWad'),
            cashDestination: policyField<Address>(raw, 11, 'cashDestination'),
            status: Number(policyField<number>(raw, 12, 'status')),
            reliefUsed: policyField<bigint>(raw, 13, 'reliefUsed'),
            createdAt: policyField<bigint>(raw, 15, 'createdAt'),
          } satisfies OnChainPolicy;
        }),
      );

      return policies;
    },
  });
}
