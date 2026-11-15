import { formatUnits } from 'viem';

const amountFormatter = new Intl.NumberFormat('en-US', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 4,
});

/** Token amount from an 18-decimal integer, with thousands separators and 2-4 decimals. */
export function formatAmount(value: bigint | string, decimals = 18): string {
  const raw = typeof value === 'bigint' ? value : BigInt(value);
  return amountFormatter.format(Number(formatUnits(raw, decimals)));
}

/** Health factor from a WAD integer, three decimals: 1.195. */
export function formatHealth(value: bigint | string): string {
  const raw = typeof value === 'bigint' ? value : BigInt(value);
  return (Number(formatUnits(raw, 18))).toFixed(3);
}

/** Basis points as a percentage: 6000 -> "60%", 6250 -> "62.5%". */
export function formatBps(bps: number): string {
  const percent = bps / 100;
  return `${percent.toFixed(Number.isInteger(percent) ? 0 : 1)}%`;
}

/** Duration in seconds as a short human string: "30 days", "4 hours", "12 s". */
export function formatDuration(seconds: number | bigint): string {
  const total = Number(seconds);
  const day = 86_400;
  if (total >= day) {
    const days = Math.round(total / day);
    return `${days} ${days === 1 ? 'day' : 'days'}`;
  }
  if (total >= 3_600) {
    const hours = Math.round(total / 3_600);
    return `${hours} ${hours === 1 ? 'hour' : 'hours'}`;
  }
  if (total >= 60) {
    const minutes = Math.round(total / 60);
    return `${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`;
  }
  return `${total} s`;
}

/** Truncated address or hash: 0x1234…abcd. */
export function truncateAddress(value: string, chars = 4): string {
  if (value.length <= 2 + chars * 2) {
    return value;
  }
  return `${value.slice(0, 2 + chars)}…${value.slice(-chars)}`;
}

/** Display string for a nullable amount. */
export function formatMaybeAmount(value: string | null | undefined, decimals = 18): string {
  if (value === null || value === undefined || value === '') {
    return '—';
  }
  return formatAmount(value, decimals);
}
