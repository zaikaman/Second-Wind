import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import type { HealthSnapshot } from '../src/routes/health.js';

function snapshot(overrides?: { debt?: string }): HealthSnapshot {
  return {
    version: '9.9.9',
    chains: {
      base: { chainId: 84_532, head: 100, indexed: 99, lagBlocks: 1 },
      unichain: { chainId: 1_301, head: 200, indexed: 200, lagBlocks: 0 },
      reactive: { chainId: 5_318_007, head: 300, indexed: null, lagBlocks: null },
    },
    funding: {
      reactive: { native: '0.4200', debt: overrides?.debt ?? '0', reserves: '0.1000' },
      coveragePool: { native: '0.0310', debt: '0', reserves: '0.0200' },
      claimVault: { native: '0.0280', debt: '0', reserves: '0.0200' },
    },
    lastIndexedAt: '2026-11-15T09:41:02Z',
  };
}

const servers: Server[] = [];

async function serve(data: HealthSnapshot): Promise<string> {
  const app = createApp({
    version: '9.9.9',
    corsOrigins: ['http://localhost:5173'],
    health: async () => data,
  });
  const server = app.listen(0);
  servers.push(server);
  await new Promise<void>((resolve) => server.once('listening', resolve));
  const { port } = server.address() as AddressInfo;
  return `http://127.0.0.1:${port}`;
}

afterEach(async () => {
  await Promise.all(
    servers.splice(0).map(
      (server) =>
        new Promise<void>((resolve) => {
          server.close(() => resolve());
        }),
    ),
  );
});

describe('GET /health', () => {
  it('returns 200 with the documented shape and no caching', async () => {
    const base = await serve(snapshot());
    const response = await fetch(`${base}/health`);

    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(response.headers.get('x-request-id')).toBeTruthy();

    const body = (await response.json()) as Record<string, unknown>;
    expect(body.status).toBe('ok');
    expect(body.version).toBe('9.9.9');
    expect(Object.keys(body.chains as object)).toEqual(['base', 'unichain', 'reactive']);
    expect(Object.keys(body.funding as object)).toEqual(['reactive', 'coveragePool', 'claimVault']);
    expect(body.lastIndexedAt).toBe('2026-11-15T09:41:02Z');

    const funding = body.funding as {
      reactive: { ok: boolean };
      coveragePool: { ok: boolean };
    };
    expect(funding.reactive.ok).toBe(true);
    expect(funding.coveragePool.ok).toBe(true);
  });

  it('marks a contract with non-zero debt as not ok', async () => {
    const base = await serve(snapshot({ debt: '0.42' }));
    const response = await fetch(`${base}/health`);
    const body = (await response.json()) as {
      funding: { reactive: { debt: string; ok: boolean } };
    };

    expect(response.status).toBe(200);
    expect(body.funding.reactive.debt).toBe('0.42');
    expect(body.funding.reactive.ok).toBe(false);
  });

  it('answers 404 with the error envelope for unknown routes', async () => {
    const base = await serve(snapshot());
    const response = await fetch(`${base}/nope`);
    const body = (await response.json()) as { error: { code: string; message: string } };

    expect(response.status).toBe(404);
    expect(body.error.code).toBe('NOT_FOUND');
  });
});
