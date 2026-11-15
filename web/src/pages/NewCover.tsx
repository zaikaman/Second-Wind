export default function NewCover() {
  return (
    <section className="space-y-4">
      <header className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">Buy cover</h1>
        <p className="max-w-2xl text-sm text-ink/70">
          One transaction on Base Sepolia buys cover and prepays the premium. The cash destination is the
          address that receives the payout on Unichain Sepolia, and it cannot be changed afterwards.
        </p>
      </header>

      <div className="rounded-lg border border-ink/10 bg-white/60 p-4 text-sm text-ink/70">
        The market picker, coverage cap, relief share, target health, term and destination fields are wired
        to the registry in the product phase.
      </div>
    </section>
  );
}
