import { Link } from 'react-router-dom';
import { useAccount } from 'wagmi';
import { ErrorState, OfflineBanner, Skeleton } from '../components/Async';
import { StatusChip } from '../components/StatusChip';
import { isConfigured, addresses } from '../config/addresses';
import type { OnChainPolicy } from '../config/contracts';
import { useHealth, formatHealthWad } from '../hooks/useHealth';
import { usePolicies } from '../hooks/usePolicies';
import { formatAmount, formatBps } from '../lib/format';
import type { ClaimStatus } from '../lib/api';

export default function Dashboard() {
  const { address, isConnected } = useAccount();
  const policies = usePolicies(address);

  return (
    <section className="space-y-4">
      <header className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">Your coverage</h1>
        <p className="max-w-2xl text-sm text-ink/70">
          Cover applies to one loan. When that loan is liquidated, the penalty is paid back automatically as
          cash on Unichain Sepolia and as debt relief on your weakest loan on Base Sepolia.
        </p>
      </header>

      <OfflineBanner />

      {!isConfigured(addresses.base.registry) ? (
        <div className="rounded-lg border border-pending/30 bg-pending/10 p-4 text-sm text-ink/80">
          This build has no deployed registry address. Set VITE_BASE_REGISTRY and rebuild.
        </div>
      ) : null}

      {!isConnected ? (
        <div className="rounded-lg border border-ink/10 bg-white/60 p-4 text-sm text-ink/70">
          Connect a wallet to read your positions directly from Morpho. Nothing is signed to view them.
        </div>
      ) : null}

      {isConnected && policies.isPending ? <Skeleton lines={4} /> : null}

      {policies.isError ? (
        <ErrorState message="Policies could not be read from Base Sepolia." onRetry={() => void policies.refetch()} />
      ) : null}

      {policies.isSuccess && policies.data.length === 0 ? (
        <div className="rounded-lg border border-ink/10 bg-white/60 p-4 text-sm text-ink/70">
          No policy on this wallet yet.{' '}
          <Link to="/cover/new" className="underline">
            Buy cover
          </Link>{' '}
          to cover one loan.
        </div>
      ) : null}

      <div className="grid gap-3 md:grid-cols-2">
        {policies.data?.map((policy) => <PolicyCard key={policy.policyId.toString()} policy={policy} />)}
      </div>

      <div className="flex flex-wrap gap-2">
        <Link to="/cover/new" className="rounded-md bg-ink px-3 py-2 text-sm font-medium text-paper hover:bg-ink/90">
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

const STATUS: Record<number, ClaimStatus> = { 1: 'settled', 2: 'partial', 3: 'failed' };

function PolicyCard({ policy }: { policy: OnChainPolicy }) {
  const health = useHealth(policy.borrower, policy.marketId);
  const status = STATUS[policy.status] ?? 'pending';
  const reliefRemaining = policy.reliefCeiling - policy.reliefUsed;

  return (
    <article className="space-y-2 rounded-lg border border-ink/10 bg-white/60 p-4">
      <header className="flex items-center justify-between gap-2">
        <Link to={`/policies/${policy.policyId}`} className="font-medium hover:underline">
          Policy {policy.policyId.toString()}
        </Link>
        <StatusChip status={status} />
      </header>

      <dl className="grid grid-cols-2 gap-1 text-sm">
        <Field label="Cap" value={formatAmount(policy.coverageCap)} />
        <Field label="Relief left" value={formatAmount(reliefRemaining)} />
        <Field label="Cash ceiling" value={formatAmount(policy.cashCeiling)} />
        <Field label="Relief share" value={formatBps(policy.reliefShareBps)} />
        <Field
          label="Health"
          value={health.isPending ? '…' : health.data ? formatHealthWad(health.data.healthWad) : '—'}
        />
        <Field label="Debt" value={health.data ? formatAmount(health.data.debt) : '—'} />
        <Field label="Collateral" value={health.data ? formatAmount(health.data.collateral) : '—'} />
        <Field label="Paid through" value={new Date(Number(policy.paidThrough) * 1000).toLocaleDateString()} />
      </dl>

      {health.data && health.data.healthWad < 10n ** 18n ? (
        <p className="text-xs text-failed">Health is below 1.0: this loan is liquidatable now.</p>
      ) : null}
    </article>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs text-ink/55">{label}</dt>
      <dd className="font-medium">{value}</dd>
    </div>
  );
}
