import { useParams } from 'react-router-dom';

export default function Policy() {
  const { id } = useParams<{ id: string }>();

  return (
    <section className="space-y-4">
      <header className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">Policy {id ?? '—'}</h1>
        <p className="max-w-2xl text-sm text-ink/70">
          Capacity bars, the paid-through countdown, pause, resume and cancel belong here. The policy id is
          read from the URL, so a receipt can link straight to it.
        </p>
      </header>

      <div className="rounded-lg border border-ink/10 bg-white/60 p-4 text-sm text-ink/70">
        Policy details load from Base Sepolia once the registry reads are wired.
      </div>
    </section>
  );
}
