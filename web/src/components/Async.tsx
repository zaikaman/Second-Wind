import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';

/** A loading placeholder with the same shape as the content it replaces. */
export function Skeleton({ lines = 3 }: { lines?: number }) {
  return (
    <div className="space-y-2" aria-hidden="true">
      {Array.from({ length: lines }).map((_, index) => (
        <div
          key={index}
          className="h-4 animate-pulse rounded bg-ink/10"
          style={{ width: `${100 - index * 12}%` }}
        />
      ))}
    </div>
  );
}

/** An error path with a retry that re-runs the query the caller owns. */
export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="rounded-lg border border-failed/30 bg-failed/5 p-4 text-sm">
      <p className="text-ink/80">{message}</p>
      {onRetry ? (
        <button
          type="button"
          onClick={onRetry}
          className="mt-2 rounded-md border border-ink/15 px-2.5 py-1.5 text-xs font-medium hover:bg-ink/5"
        >
          Try again
        </button>
      ) : null}
    </div>
  );
}

function useOnline(): boolean {
  const [online, setOnline] = useState(() => (typeof navigator === 'undefined' ? true : navigator.onLine));

  useEffect(() => {
    const wasOnline = () => setOnline(true);
    const wasOffline = () => setOnline(false);
    window.addEventListener('online', wasOnline);
    window.addEventListener('offline', wasOffline);
    return () => {
      window.removeEventListener('online', wasOnline);
      window.removeEventListener('offline', wasOffline);
    };
  }, []);

  return online;
}

/** Says plainly that the browser is offline instead of showing an empty list. */
export function OfflineBanner() {
  const online = useOnline();
  if (online) {
    return null;
  }
  return (
    <div className="rounded-lg border border-pending/30 bg-pending/10 p-3 text-sm text-ink/80">
      You are offline. Receipts and health will refresh when the connection returns.
    </div>
  );
}

/** A titled panel with a status line, used by every card on the receipt page. */
export function Card({
  title,
  status,
  children,
}: {
  title: string;
  status?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="rounded-lg border border-ink/10 bg-white/60 p-4">
      <header className="mb-2 flex items-center justify-between gap-2">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-ink/60">{title}</h2>
        {status}
      </header>
      {children}
    </section>
  );
}
