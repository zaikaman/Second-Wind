import type { ReactNode } from 'react';
import { Link, useParams } from 'react-router-dom';
import { Card, ErrorState, OfflineBanner, Skeleton } from '../components/Async';
import { CopyValue } from '../components/CopyValue';
import { StatusChip } from '../components/StatusChip';
import { useClaim } from '../hooks/useClaim';
import { ApiError } from '../lib/api';
import type { BranchView, Receipt as ReceiptData } from '../lib/api';
import { formatAmount } from '../lib/format';

export default function Receipt() {
  const { runId } = useParams<{ runId: string }>();
  const claim = useClaim(runId);

  if (!runId) {
    return <ErrorState message="No runId in the URL." />;
  }

  if (claim.isPending) {
    return (
      <section className="space-y-4">
        <h1 className="text-2xl font-semibold tracking-tight">Receipt</h1>
        <Skeleton lines={6} />
      </section>
    );
  }

  if (claim.isError) {
    const notFound = claim.error instanceof ApiError && claim.error.status === 404;
    return (
      <section className="space-y-4">
        <h1 className="text-2xl font-semibold tracking-tight">Receipt</h1>
        <ErrorState
          message={notFound ? 'No claim with that runId yet.' : 'The receipt could not be loaded.'}
          onRetry={() => void claim.refetch()}
        />
      </section>
    );
  }

  return <ReceiptView receipt={claim.data} />;
}

function ReceiptView({ receipt }: { receipt: ReceiptData }) {
  return (
    <section className="space-y-4">
      <OfflineBanner />

      <header className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-semibold tracking-tight">Receipt</h1>
            <StatusChip status={receipt.status} />
          </div>
          <p className="text-sm text-ink/70">
            One liquidation, two chains, the same runId. Nobody signed a claim transaction.
          </p>
          <CopyValue value={receipt.runId} chars={10} />
        </div>
        <Link
          to={`/policies/${receipt.policyId}`}
          className="rounded-md border border-ink/15 px-3 py-2 text-sm font-medium hover:bg-ink/5"
        >
          Policy {receipt.policyId}
        </Link>
      </header>

      {receipt.failure ? (
        <div className="rounded-lg border border-failed/30 bg-failed/5 p-3 text-sm">
          <p className="font-medium text-failed">{receipt.failure.code}</p>
          <p className="text-ink/70">{receipt.failure.message}</p>
        </div>
      ) : null}

      <div className="grid gap-3 md:grid-cols-2">
        <Card title="Trigger" status={<StatusChip status="confirmed" />}>
          <dl className="space-y-1 text-sm">
            <Row label="Chain" value={`Base Sepolia (${receipt.trigger.chainId})`} />
            <Row label="Block" value={receipt.trigger.blockNumber.toLocaleString()} />
            <Row label="Log index" value={String(receipt.trigger.logIndex)} />
            <Row label="Time" value={new Date(receipt.trigger.blockTime).toLocaleString()} />
            <Row label="Transaction" value={<ExplorerLink href={receipt.trigger.explorer} hash={receipt.trigger.txHash} />} />
          </dl>
        </Card>

        <Card title="Dispatch" status={<StatusChip status={receipt.reactive.txHash ? 'confirmed' : 'pending'} />}>
          <dl className="space-y-1 text-sm">
            <Row label="Chain" value="Reactive Lasna" />
            <Row label="Block" value={receipt.reactive.blockNumber?.toLocaleString() ?? '—'} />
            <Row label="Time" value={receipt.reactive.blockTime ? new Date(receipt.reactive.blockTime).toLocaleString() : '—'} />
            <Row
              label="Transaction"
              value={receipt.reactive.txHash ? <ExplorerLink href={receipt.reactive.explorer} hash={receipt.reactive.txHash} /> : '—'}
            />
          </dl>
        </Card>

        <BranchCard title="Relief on Base" branch={receipt.branches.relief} limit={receipt.split.reliefLimit} />
        <BranchCard title="Cash on Unichain" branch={receipt.branches.cash} limit={receipt.split.cashLimit} />
      </div>

      <Card title="Split">
        <dl className="grid gap-1 text-sm sm:grid-cols-2">
          <Row label="Fee" value={formatAmount(receipt.fee)} />
          <Row label="Mode" value={receipt.split.mode} />
          <Row label="Relief limit" value={formatAmount(receipt.split.reliefLimit)} />
          <Row label="Cash limit" value={formatAmount(receipt.split.cashLimit)} />
          <Row label="Unspent relief" value={formatAmount(receipt.unspentRelief)} />
          <Row label="Shortfall" value={formatAmount(receipt.split.shortfall)} />
          <Row label="Total latency" value={receipt.totalLatencyMs === null ? '—' : `${receipt.totalLatencyMs} ms`} />
          <Row label="Settled" value={receipt.status === 'settled' ? 'yes' : 'not yet'} />
        </dl>
      </Card>
    </section>
  );
}

function BranchCard({ title, branch, limit }: { title: string; branch: BranchView | null; limit: string }) {
  if (!branch) {
    return (
      <Card title={title} status={<StatusChip status="pending" />}>
        <p className="text-sm text-ink/60">No delivery for this branch yet. Limit was {formatAmount(limit)}.</p>
      </Card>
    );
  }

  return (
    <Card title={title} status={<StatusChip status={branch.status} />}>
      <dl className="space-y-1 text-sm">
        <Row label="Amount" value={formatAmount(branch.amount)} />
        <Row label="Limit" value={formatAmount(limit)} />
        <Row label="Latency" value={branch.latencyMs === null ? '—' : `${branch.latencyMs} ms`} />
        <Row label="Block time" value={branch.blockTime ? new Date(branch.blockTime).toLocaleString() : '—'} />
        {branch.marketId ? <Row label="Market" value={<CopyValue value={branch.marketId} chars={6} />} /> : null}
        {branch.healthBefore && branch.healthAfter ? (
          <Row
            label="Health"
            value={`${(Number(branch.healthBefore) / 1e18).toFixed(3)} -> ${(Number(branch.healthAfter) / 1e18).toFixed(3)}`}
          />
        ) : null}
        {branch.destination ? <Row label="Destination" value={<CopyValue value={branch.destination} chars={5} />} /> : null}
        <Row
          label="Transaction"
          value={branch.txHash ? <ExplorerLink href={branch.explorer} hash={branch.txHash} /> : '—'}
        />
      </dl>
    </Card>
  );
}

function Row({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className="text-ink/55">{label}</dt>
      <dd className="text-right font-medium">{value}</dd>
    </div>
  );
}

function ExplorerLink({ href, hash }: { href: string | null; hash: string }) {
  return (
    <span className="inline-flex items-center gap-2">
      <CopyValue value={hash} chars={5} />
      {href ? (
        <a href={href} target="_blank" rel="noreferrer" className="text-xs text-ink/70 underline">
          explorer
        </a>
      ) : null}
    </span>
  );
}
