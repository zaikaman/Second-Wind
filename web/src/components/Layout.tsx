import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Link, NavLink, Outlet } from 'react-router-dom';

const NAV = [
  { to: '/', label: 'Coverage', end: true },
  { to: '/cover/new', label: 'Buy cover', end: false },
  { to: '/receipts', label: 'Receipts', end: false },
  { to: '/proof', label: 'Proof', end: false },
];

export function Layout() {
  return (
    <div className="flex min-h-full flex-col">
      <header className="border-b border-ink/10 bg-paper">
        <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center gap-4 px-4 py-3">
          <Link to="/" className="flex items-baseline gap-2">
            <span className="text-lg font-semibold tracking-tight">Second Wind</span>
            <span className="rounded-full bg-pending/15 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-pending">
              testnet only
            </span>
          </Link>

          <nav className="flex flex-1 items-center gap-1 text-sm">
            {NAV.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) =>
                  `rounded-md px-2.5 py-1.5 transition-colors ${
                    isActive ? 'bg-ink/5 font-medium text-ink' : 'text-ink/70 hover:text-ink'
                  }`
                }
              >
                {item.label}
              </NavLink>
            ))}
          </nav>

          <ConnectButton showBalance={false} chainStatus="icon" accountStatus="address" />
        </div>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-8">
        <Outlet />
      </main>

      <footer className="border-t border-ink/10 bg-paper px-4 py-4 text-xs text-ink/60">
        <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center justify-between gap-2">
          <p>
            Demo on testnets only: Base Sepolia, Unichain Sepolia and Reactive Lasna. Assets are mock tokens
            and the price oracle is a demo harness.
          </p>
          <p className="font-mono">Every payout is enforced by a contract, not by this server.</p>
        </div>
      </footer>
    </div>
  );
}
