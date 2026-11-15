import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { createClaimsStore } from '../src/services/claims-store.js';
import { MemoryDb } from './utils/memory-db.js';

const RUN_ID = `0x${'ab'.repeat(32)}`;
const BORROWER = `0x${'33'.repeat(20)}`;
const MARKET = `0x${'22'.repeat(32)}`;
const RELIEF_TX = `0x${'77'.repeat(32)}`;
const CASH_TX = `0x${'99'.repeat(32)}`;
const DISPATCH_TX = `0x${'cc'.repeat(32)}`;

type SettledBody = {
  status: string;
  fee: string;
  split: { reliefLimit: string };
  branches: {
    relief: { status: string; healthAfter: string; explorer: string };
    cash: { status: string; explorer: string };
  };
  reactive: { txHash: string };
  unspentRelief: string;
  totalLatencyMs: number | null;
};

type PartialBody = {
  status: string;
  branches: { cash: { status: string } };
  failure: { code: string; message: string } | null;
  unspentRelief: string;
};

const servers: Server[] = [];

function claimRow(status: string) {
  return {
    run_id: RUN_ID,
    policy_id: '7',
    borrower: BORROWER,
    market_id: MARKET,
    origin_chain_id: 84_532,
    origin_tx_hash: `0x${'11'.repeat(32)}`,
    origin_block: 34_120_877,
    origin_log_index: 14,
    origin_block_time: '2026-11-15T09:31:12.000Z',
    fee_amount: (3_945_720_250_521_920_610_000n).toString(),
    cash_limit: (1_578_288_100_208_768_244_000n).toString(),
    relief_limit: (2_367_432_150_313_152_366_000n).toString(),
    mode: 'standard',
    status,
    settled_at: status === 'settled' ? '2026-11-15T09:31:14.410Z' : null,
    total_latency_ms: status === 'settled' ? 2410 : null,
  };
}

function branchRows(cashStatus: 'confirmed' | 'failed') {
  return [
    {
      run_id: RUN_ID,
      chain_id: 84_532,
      kind: 'relief',
      status: 'confirmed',
      tx_hash: RELIEF_TX,
      block_number: 34_120_878,
      block_time: '2026-11-15T09:31:14.000Z',
      amount: (2_367_432_150_313_152_366_000n).toString(),
      detail: {
        marketId: MARKET,
        debtAfter: (177_632_577_999_999_999_000_002n).toString(),
        healthAfter: '1150000000000000000',
      },
      error: null,
    },
    {
      run_id: RUN_ID,
      chain_id: 1_301,
      kind: 'cash',
      status: cashStatus,
      tx_hash: cashStatus === 'confirmed' ? CASH_TX : null,
      block_number: cashStatus === 'confirmed' ? 200 : null,
      block_time: cashStatus === 'confirmed' ? '2026-11-15T09:31:14.410Z' : null,
      amount: cashStatus === 'confirmed' ? (1_578_288_100_208_768_244_000n).toString() : '0',
      detail: { destination: `0x${'44'.repeat(20)}` },
      error: cashStatus === 'failed' ? 'DESTINATION_UNDERFUNDED' : null,
    },
    {
      run_id: RUN_ID,
      chain_id: 5_318_007,
      kind: 'dispatch',
      status: 'confirmed',
      tx_hash: DISPATCH_TX,
      block_number: 9_021_099,
      block_time: '2026-11-15T09:31:13.000Z',
      amount: null,
      detail: { gasLimit: '300000' },
      error: null,
    },
  ];
}

async function serve(db: MemoryDb): Promise<string> {
  const app = createApp({
    version: '9.9.9',
    corsOrigins: ['http://localhost:5173'],
    health: async () => ({
      version: '9.9.9',
      chains: {
        base: { chainId: 84_532, head: 1, indexed: 1, lagBlocks: 0 },
        unichain: { chainId: 1_301, head: 1, indexed: 1, lagBlocks: 0 },
        reactive: { chainId: 5_318_007, head: 1, indexed: 1, lagBlocks: 0 },
      },
      funding: {
        reactive: { native: '0.0000', debt: '0', reserves: '0.0000' },
        coveragePool: { native: '0.0000', debt: '0', reserves: '0.0000' },
        claimVault: { native: '0.0000', debt: '0', reserves: '0.0000' },
      },
      lastIndexedAt: null,
    }),
    claims: createClaimsStore(db.asClient()),
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

describe('claims API', () => {
  it('returns a settled receipt with string amounts and explorer links', async () => {
    const db = new MemoryDb();
    db.seed('claims', [claimRow('settled')]);
    db.seed('claim_events', branchRows('confirmed'));

    const base = await serve(db);
    const response = await fetch(`${base}/claims/${RUN_ID}`);
    const body = (await response.json()) as SettledBody;

    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toContain('max-age=5');
    expect(body.status).toBe('settled');
    expect(typeof body.fee).toBe('string');
    expect(body.split.reliefLimit).toBe((2_367_432_150_313_152_366_000n).toString());
    expect(body.branches.relief.status).toBe('confirmed');
    expect(body.branches.relief.healthAfter).toBe('1150000000000000000');
    expect(body.branches.relief.explorer).toContain('basescan');
    expect(body.branches.cash.explorer).toContain('uniscan');
    expect(body.reactive.txHash).toBe(DISPATCH_TX);
    expect(body.unspentRelief).toBe('0');
    expect(body.totalLatencyMs).toBe(2410);
  });

  it('makes a partial claim visible with the failing branch named', async () => {
    const db = new MemoryDb();
    db.seed('claims', [claimRow('partial')]);
    db.seed('claim_events', branchRows('failed'));

    const base = await serve(db);
    const response = await fetch(`${base}/claims/${RUN_ID}`);
    const body = (await response.json()) as PartialBody;

    expect(response.status).toBe(200);
    expect(body.status).toBe('partial');
    expect(body.branches.cash.status).toBe('failed');
    expect(body.failure).toEqual({ code: 'DESTINATION_UNDERFUNDED', message: 'DESTINATION_UNDERFUNDED' });
    expect(body.unspentRelief).toBe('0');
  });

  it('lists claims newest first with a cursor', async () => {
    const db = new MemoryDb();
    db.seed('claims', [claimRow('settled')]);
    db.seed('claim_events', branchRows('confirmed'));

    const base = await serve(db);
    const response = await fetch(`${base}/claims?limit=10`);
    const body = (await response.json()) as { claims: { runId: string }[]; nextCursor: string | null };

    expect(response.status).toBe(200);
    expect(body.claims).toHaveLength(1);
    expect(body.claims[0]?.runId).toBe(RUN_ID);
    expect(body.nextCursor).toBeNull();
  });

  it('answers 404 for an unknown runId', async () => {
    const db = new MemoryDb();
    const base = await serve(db);
    const response = await fetch(`${base}/claims/0x${'00'.repeat(32)}`);
    const body = (await response.json()) as { error: { code: string } };

    expect(response.status).toBe(404);
    expect(body.error.code).toBe('NOT_FOUND');
  });
});
