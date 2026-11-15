import { useEffect, useRef, useState } from 'react';
import { truncateAddress } from '../lib/format';

/**
 * A hash or address with a copy button that confirms for 1.5 s (T148). The full value stays
 * selectable and is exposed in the title attribute, so a failed clipboard write is not a dead end.
 */
export function CopyValue({ value, chars = 6 }: { value: string; chars?: number }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => {
    return () => {
      if (timer.current !== undefined) {
        window.clearTimeout(timer.current);
      }
    };
  }, []);

  const copy = async (): Promise<void> => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      if (timer.current !== undefined) {
        window.clearTimeout(timer.current);
      }
      timer.current = window.setTimeout(() => setCopied(false), 1_500);
    } catch {
      setCopied(false);
    }
  };

  return (
    <span className="inline-flex items-center gap-1.5">
      <code className="font-mono text-xs text-ink/80" title={value}>
        {truncateAddress(value, chars)}
      </code>
      <button
        type="button"
        onClick={() => void copy()}
        aria-label={copied ? 'Copied' : 'Copy value'}
        className="rounded border border-ink/15 px-1.5 py-0.5 text-[11px] text-ink/60 hover:bg-ink/5"
      >
        {copied ? 'copied' : 'copy'}
      </button>
    </span>
  );
}
