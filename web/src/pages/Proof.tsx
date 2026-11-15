import { addresses, INFRASTRUCTURE } from '../config/addresses';
import { addressUrl } from '../lib/explorer';

const ROWS = [
  { label: 'PolicyRegistry', chain: 'base' as const, address: addresses.base.registry },
  { label: 'CoveragePool', chain: 'base' as const, address: addresses.base.coveragePool },
  { label: 'mUSDC (Base)', chain: 'base' as const, address: addresses.base.usdc },
  { label: 'Morpho Blue', chain: 'base' as const, address: INFRASTRUCTURE.morpho },
  { label: 'ClaimVault', chain: 'unichain' as const, address: addresses.unichain.claimVault },
  { label: 'mUSDC (Unichain)', chain: 'unichain' as const, address: addresses.unichain.usdc },
  { label: 'SecondWindReactive', chain: 'lasna' as const, address: addresses.lasna.reactive },
];

export default function Proof() {
  return (
    <section className="space-y-6">
      <header className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">Proof</h1>
        <p className="max-w-2xl text-sm text-ink/70">
          Addresses, subscriptions, runIds and measured latency, so every claim in the demo can be checked
          against an explorer.
        </p>
      </header>

      <div className="rounded-lg border border-pending/30 bg-pending/10 p-3 text-xs text-ink/80">
        Testnet only. Assets are mock tokens and the price oracle is a demo harness reading one Uniswap V3
        spot pool.
      </div>

      <div className="overflow-x-auto rounded-lg border border-ink/10">
        <table className="w-full text-sm">
          <thead className="bg-ink/5 text-left text-xs uppercase tracking-wide text-ink/60">
            <tr>
              <th className="px-3 py-2 font-medium">Contract</th>
              <th className="px-3 py-2 font-medium">Chain</th>
              <th className="px-3 py-2 font-medium">Address</th>
            </tr>
          </thead>
          <tbody>
            {ROWS.map((row) => {
              const url = addressUrl(row.chain, row.address);
              return (
                <tr key={row.label} className="border-t border-ink/10">
                  <td className="px-3 py-2">{row.label}</td>
                  <td className="px-3 py-2 capitalize text-ink/70">{row.chain}</td>
                  <td className="px-3 py-2 font-mono text-xs">
                    {url ? (
                      <a className="text-relief hover:underline" href={url} target="_blank" rel="noreferrer">
                        {row.address}
                      </a>
                    ) : (
                      row.address
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <p className="text-xs text-ink/60">
        Subscriptions, the last 20 runIds and the latency panel are added with the indexer.
      </p>
    </section>
  );
}
