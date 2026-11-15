export default function App() {
  return (
    <main className="flex min-h-full flex-col items-center justify-center gap-3 p-8">
      <h1 className="text-3xl font-semibold tracking-tight">Second Wind</h1>
      <p className="text-sm text-ink/70">
        Testnet demo — Base Sepolia, Unichain Sepolia, Reactive Lasna.
      </p>
      <span className="rounded-full bg-pending/15 px-3 py-1 text-xs font-medium text-pending">
        testnet only
      </span>
    </main>
  );
}
