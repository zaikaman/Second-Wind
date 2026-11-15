export default function Receipts() {
  return (
    <section className="space-y-4">
      <header className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">Receipts</h1>
        <p className="max-w-2xl text-sm text-ink/70">
          One receipt per liquidation, joined by a single runId across both settlement branches.
        </p>
      </header>

      <div className="rounded-lg border border-ink/10 bg-white/60 p-4 text-sm text-ink/70">
        No claims yet. Receipts appear after the first settlement.
      </div>
    </section>
  );
}
