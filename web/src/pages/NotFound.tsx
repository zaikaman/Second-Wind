import { Link } from 'react-router-dom';

export default function NotFound() {
  return (
    <section className="space-y-3">
      <h1 className="text-2xl font-semibold tracking-tight">Page not found</h1>
      <p className="text-sm text-ink/70">That route does not exist in this app.</p>
      <Link to="/" className="inline-block text-sm font-medium text-relief hover:underline">
        Back to coverage
      </Link>
    </section>
  );
}
