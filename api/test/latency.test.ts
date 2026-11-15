import { describe, expect, it } from 'vitest';
import { latencyMs, percentiles } from '../src/services/latency.js';

describe('percentiles', () => {
  it('matches the nearest-rank definition on a known 20-sample array', () => {
    const samples = Array.from({ length: 20 }, (_, index) => (index + 1) * 1000);
    const summary = percentiles(samples);

    expect(summary.p50).toBe(10_000);
    expect(summary.p95).toBe(19_000);
    expect(summary.max).toBe(20_000);
    expect(summary.count).toBe(20);
  });

  it('does not mutate the input', () => {
    const samples = [300, 100, 200];
    percentiles(samples);
    expect(samples).toEqual([300, 100, 200]);
  });

  it('returns zeros for an empty sample', () => {
    expect(percentiles([])).toEqual({ p50: 0, p95: 0, max: 0, count: 0 });
  });
});

describe('latencyMs', () => {
  it('measures block time to block time and never goes negative', () => {
    const origin = new Date('2026-11-15T09:31:12.000Z');
    expect(latencyMs(origin, new Date('2026-11-15T09:31:14.410Z'))).toBe(2410);
    expect(latencyMs(origin, new Date('2026-11-15T09:31:11.000Z'))).toBe(0);
  });
});
