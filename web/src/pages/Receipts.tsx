import { Link } from 'react-router-dom';
import { ErrorState, OfflineBanner, Skeleton } from '../components/Async';
import { StatusChip } from '../components/StatusChip';
import { useReceipts } from '../hooks/useClaim';
import { formatAmount } from '../lib/format';

export default function Receipts() {
  const receipts = useReceipts();

  return (
    <section className="space-y-4">
      <header className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">Receipts</h1>
        <p className="max-w-2xl text-sm text-ink/70">
          One receipt per liquidation, joined by a single runId across both settlement branches.
        </p>
      </header>

      <OfflineBanner />

      {receipts.isPending ? <Skeleton lines={5} /> : null}

      {receipts.isError ? (
        <ErrorState message="Receipts are unavailable right now." onRetry={() => void receipts.refetch()} />
      ) : null}

      {receipts.isSuccess && receipts.data.length === 0 ? (
        <div className="rounded-lg border border-ink/10 bg-white/60 p-4 text-sm text-ink/70">
          No claims yet. A receipt appears the moment a covered loan is liquidated, without any borrower
          transaction.
        </div>
      ) : null}

      {receipts.isSuccess && receipts.data.length > 0 ? (
        <ul className="divide-y divide-ink/10 rounded-lg border border-ink/10 bg-white/60">
          {receipts.data.map((claim) => (
            <li key={claim.runId}>
              <Link
                to={`/receipts/${claim.runId}`}
                className="flex flex-wrap items-center justify-between gap-3 px-4 py-3 hover:bg-ink/5"
              >
                <span className="flex items-center gap-3">
                  <StatusChip status={claim.status} />
                  <span className="font-mono text-xs text-ink/70">{claim.runId.slice(0, 14)}…</span>
                </span>
                <span className="flex flex-wrap items-center gap-4 text-sm">
                  <span>
                    <span className="text-ink/55">policy</span> {claim.policyId}
                  </span>
                  <span>
                    <span className="text-ink/55">fee</span> {formatAmount(claim.fee)}
                  </span>
                  <span>
                    <span className="text-ink/55">latency</span>{' '}
                    {claim.totalLatencyMs === null ? '—' : `${claim.totalLatencyMs} ms`}
                  </span>
                  <span className="text-xs text-ink/50">{new Date(claim.triggeredAt).toLocaleString()}</span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}
