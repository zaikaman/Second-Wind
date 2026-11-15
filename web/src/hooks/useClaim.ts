import { useQuery } from '@tanstack/react-query';
import { fetchClaims, fetchReceipt } from '../lib/api';

/** Polls a receipt every 2 s while a branch is still in flight (T143). */
export function useClaim(runId: string | undefined) {
  return useQuery({
    queryKey: ['claim', runId],
    enabled: Boolean(runId),
    queryFn: () => fetchReceipt(runId as string),
    retry: 1,
    refetchInterval: (query) => {
      const status = query.state.data?.status;
      return status === 'pending' || status === 'partial' ? 2_000 : false;
    },
  });
}

/** The receipts list, refreshed only when the page is opened or focused. */
export function useReceipts(limit = 20) {
  return useQuery({
    queryKey: ['receipts', limit],
    queryFn: () => fetchClaims(limit),
    retry: 1,
  });
}
