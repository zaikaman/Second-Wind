import type { ClaimStatus } from '../lib/api';

const STYLES: Record<ClaimStatus, string> = {
  settled: 'bg-settled/15 text-settled',
  partial: 'bg-pending/15 text-pending',
  pending: 'bg-ink/10 text-ink/70',
  failed: 'bg-failed/15 text-failed',
};

/** One visual vocabulary for claim and branch status, so a partial claim never reads as success. */
export function StatusChip({ status }: { status: ClaimStatus | 'confirmed' }) {
  const key: ClaimStatus = status === 'confirmed' ? 'settled' : status;
  return (
    <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide ${STYLES[key]}`}>
      {status}
    </span>
  );
}
