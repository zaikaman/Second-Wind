import { useParams } from 'react-router-dom';

export default function Receipt() {
  const { runId } = useParams<{ runId: string }>();

  return (
    <section className="space-y-4">
      <header className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">Receipt</h1>
        <p className="max-w-2xl font-mono text-xs text-ink/60">{runId ?? 'no runId in the URL'}</p>
        <p className="max-w-2xl text-sm text-ink/70">
          The receipt shows the trigger, the Lasna dispatch, the relief branch on Base Sepolia and the cash
          branch on Unichain Sepolia, each with its own status, amount, transaction link and latency.
        </p>
      </header>

      <div className="rounded-lg border border-ink/10 bg-white/60 p-4 text-sm text-ink/70">
        Receipt data loads from the indexer API.
      </div>
    </section>
  );
}
