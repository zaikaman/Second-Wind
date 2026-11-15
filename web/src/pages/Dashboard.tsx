import { Link } from 'react-router-dom';

export default function Dashboard() {
  return (
    <section className="space-y-4">
      <header className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">Your coverage</h1>
        <p className="max-w-2xl text-sm text-ink/70">
          Cover applies to one loan. When that loan is liquidated, the penalty is paid back automatically as
          cash on Unichain Sepolia and as debt relief on your weakest loan on Base Sepolia.
        </p>
      </header>

      <div className="rounded-lg border border-ink/10 bg-white/60 p-4 text-sm text-ink/70">
        Policy cards appear here once a policy exists on Base Sepolia. Connect a wallet to read your
        positions directly from Morpho.
      </div>

      <div className="flex flex-wrap gap-2">
        <Link
          to="/cover/new"
          className="rounded-md bg-ink px-3 py-2 text-sm font-medium text-paper hover:bg-ink/90"
        >
          Buy cover
        </Link>
        <Link
          to="/receipts"
          className="rounded-md border border-ink/15 px-3 py-2 text-sm font-medium text-ink hover:bg-ink/5"
        >
          View receipts
        </Link>
      </div>
    </section>
  );
}
