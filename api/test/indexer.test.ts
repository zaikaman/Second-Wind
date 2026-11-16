import { describe, expect, it } from 'vitest';
import { encodeAbiParameters, encodeFunctionData, zeroAddress } from 'viem';
import type { Hex } from 'viem';
import { MemoryDb } from './utils/memory-db.js';
import { TOPICS, decodeLog, deriveRunId } from '../src/services/decoder.js';
import { applyEvent, deriveClaimStatus, refreshClaimStatus } from '../src/services/joiner.js';

const CHAIN_ID = 84_532;
const TX: Hex = `0x${'11'.repeat(32)}`;
const MARKET: Hex = `0x${'22'.repeat(32)}`;
const BORROWER: Hex = `0x${'33'.repeat(20)}`;
const DESTINATION: Hex = `0x${'44'.repeat(20)}`;
const MORPHO: Hex = `0x${'55'.repeat(20)}`;
const LOG_INDEX = 14;

const REACTIVE_CHAIN_ID = 5_318_007;
const REACTIVE: Hex = `0x${'aa'.repeat(20)}`;
const SYSTEM: Hex = `0x${'88'.repeat(20)}`;
const RUN_ID: Hex = `0x${'bb'.repeat(32)}`;

const SETTLE_ABI = [
  {
    type: 'function',
    name: 'settleCascade',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'sender', type: 'address' },
      { name: 'runId', type: 'bytes32' },
      { name: 'policyId', type: 'uint256' },
      { name: 'reliefLimit', type: 'uint256' },
      { name: 'decidedAt', type: 'uint64' },
      { name: 'liquidateBlock', type: 'uint64' },
    ],
    outputs: [],
  },
] as const;

const REGISTER_ABI = [
  {
    type: 'function',
    name: 'registerPolicy',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'sender', type: 'address' },
      { name: 'policyId', type: 'uint256' },
      { name: 'cashCeiling', type: 'uint256' },
      { name: 'paidThrough', type: 'uint64' },
      { name: 'destination', type: 'address' },
    ],
    outputs: [],
  },
] as const;

function topicAddress(address: Hex): Hex {
  return `0x${'0'.repeat(24)}${address.slice(2)}` as Hex;
}

function topicUint(value: bigint): Hex {
  return `0x${value.toString(16).padStart(64, '0')}` as Hex;
}

function liquidateLog() {
  return {
    address: MORPHO,
    topics: [TOPICS.liquidate, MARKET, topicAddress(BORROWER), topicAddress(BORROWER)] as Hex[],
    data: encodeAbiParameters(
      [{ type: 'uint256' }, { type: 'uint256' }, { type: 'uint256' }, { type: 'uint256' }, { type: 'uint256' }],
      [90_000n * 10n ** 18n, 0n, 0n, 0n, 0n],
    ),
    blockNumber: 100n,
    transactionHash: TX,
    logIndex: LOG_INDEX,
  };
}

function reliefLog(runId: Hex) {
  return {
    address: `0x${'66'.repeat(20)}` as Hex,
    topics: [TOPICS.reliefApplied, runId, topicUint(7n), MARKET] as Hex[],
    data: encodeAbiParameters(
      [{ type: 'uint256' }, { type: 'uint256' }, { type: 'uint256' }, { type: 'uint64' }],
      [2_367n * 10n ** 18n, 177_632n * 10n ** 18n, 1_150_000_000_000_000_000n, 1_700_000_000n],
    ),
    blockNumber: 101n,
    transactionHash: `0x${'77'.repeat(32)}` as Hex,
    logIndex: 2,
  };
}

function cashLog(runId: Hex) {
  return {
    address: `0x${'88'.repeat(20)}` as Hex,
    topics: [TOPICS.claimPaid, runId, topicUint(7n), topicAddress(DESTINATION)] as Hex[],
    data: encodeAbiParameters([{ type: 'uint256' }, { type: 'uint64' }], [1_578n * 10n ** 18n, 1_700_000_000n]),
    blockNumber: 200n,
    transactionHash: `0x${'99'.repeat(32)}` as Hex,
    logIndex: 3,
  };
}

/** The Lasna system contract's `CallbackRequest`, as the chain actually emits it. */
function callbackRequestLog(payload: Hex, gasLimit = 900_000n) {
  // The system contract stores `abi.encode(CallbackConfiguration_V_1_0)`, so the struct is encoded
  // as one dynamic tuple: 0x20 offset, then chainId, recipient, gasLimit, payload.
  const config = encodeAbiParameters(
    [
      {
        type: 'tuple',
        components: [
          { name: 'chainId', type: 'uint256' },
          { name: 'recipient', type: 'address' },
          { name: 'gasLimit', type: 'uint64' },
          { name: 'payload', type: 'bytes' },
        ],
      },
    ],
    [{ chainId: BigInt(CHAIN_ID), recipient: DESTINATION, gasLimit, payload }],
  );
  return {
    address: SYSTEM,
    topics: [
      TOPICS.callbackRequest,
      topicUint(BigInt(CHAIN_ID)),
      topicAddress(REACTIVE),
      topicAddress(DESTINATION),
    ] as Hex[],
    data: encodeAbiParameters([{ type: 'uint8' }, { type: 'bytes' }], [0, config]),
    blockNumber: 300n,
    transactionHash: `0x${'cc'.repeat(32)}` as Hex,
    logIndex: 4,
  };
}

function seedPolicy(db: MemoryDb): void {
  db.seed('policies_mirror', [
    {
      policy_id: '7',
      borrower: BORROWER,
      market_id: MARKET,
      relief_share_bps: 6000,
      lltv: (860_000_000_000_000_000n).toString(),
      relief_used: '0',
      cash_paid: '0',
    },
  ]);
}

describe('decoder', () => {
  it('decodes a Liquidate log and derives the shared runId', () => {
    const decoded = decodeLog(CHAIN_ID, liquidateLog());

    expect(decoded?.kind).toBe('liquidate');
    if (decoded?.kind !== 'liquidate') throw new Error('unreachable');
    expect(decoded.borrower).toBe(BORROWER);
    expect(decoded.marketId).toBe(MARKET);
    expect(decoded.repaidAssets).toBe(90_000n * 10n ** 18n);
    expect(decoded.runId).toBe(deriveRunId(CHAIN_ID, TX, LOG_INDEX));
  });

  it('rejects a log whose topic count does not match the event', () => {
    const malformed = { ...liquidateLog(), topics: [TOPICS.liquidate, MARKET] as Hex[] };
    expect(decodeLog(CHAIN_ID, malformed)).toBeNull();
  });

  it('ignores an unknown topic', () => {
    expect(decodeLog(CHAIN_ID, { ...liquidateLog(), topics: [`0x${'ab'.repeat(32)}` as Hex] })).toBeNull();
  });

  it('decodes the Lasna CallbackRequest and recovers the shared runId', () => {
    const payload = encodeFunctionData({
      abi: SETTLE_ABI,
      functionName: 'settleCascade',
      args: [zeroAddress, RUN_ID, 7n, 3_000n * 10n ** 18n, 1_700_000_000n, 100n],
    });

    const decoded = decodeLog(REACTIVE_CHAIN_ID, callbackRequestLog(payload));
    if (decoded?.kind !== 'callbackRequest') throw new Error('callback request did not decode');

    expect(decoded.sender).toBe(REACTIVE);
    expect(decoded.chainId).toBe(BigInt(CHAIN_ID));
    expect(decoded.recipient).toBe(DESTINATION);
    expect(decoded.gasLimit).toBe(900_000n);
    expect(decoded.runId).toBe(RUN_ID);
  });

  it('does not invent a runId for a registration callback', () => {
    const payload = encodeFunctionData({
      abi: REGISTER_ABI,
      functionName: 'registerPolicy',
      args: [zeroAddress, 7n, 2_000n * 10n ** 18n, 1_700_000_000n, DESTINATION],
    });

    const decoded = decodeLog(REACTIVE_CHAIN_ID, callbackRequestLog(payload, 500_000n));
    if (decoded?.kind !== 'callbackRequest') throw new Error('callback request did not decode');

    expect(decoded.runId).toBeNull();
  });

  it('skips a callback request whose configuration is not a V_1_0 struct', () => {
    const payload = encodeFunctionData({
      abi: SETTLE_ABI,
      functionName: 'settleCascade',
      args: [zeroAddress, RUN_ID, 7n, 3_000n * 10n ** 18n, 1_700_000_000n, 100n],
    });
    const log = callbackRequestLog(payload);
    const flat = encodeAbiParameters(
      [{ type: 'uint256' }, { type: 'address' }, { type: 'uint64' }, { type: 'bytes' }],
      [BigInt(CHAIN_ID), DESTINATION, 900_000n, payload],
    );

    const malformed = { ...log, data: encodeAbiParameters([{ type: 'uint8' }, { type: 'bytes' }], [0, flat]) };

    // Skipped, not thrown: a log this decoder cannot read must never stop the chain's cursor.
    expect(decodeLog(REACTIVE_CHAIN_ID, malformed)).toBeNull();
  });

  it('rejects a callback request whose indexed topics disagree with its payload', () => {
    const payload = encodeFunctionData({
      abi: SETTLE_ABI,
      functionName: 'settleCascade',
      args: [zeroAddress, RUN_ID, 7n, 3_000n * 10n ** 18n, 1_700_000_000n, 100n],
    });
    const log = callbackRequestLog(payload);
    const mismatched = { ...log, topics: [log.topics[0], log.topics[1], log.topics[2], topicAddress(BORROWER)] as Hex[] };

    expect(decodeLog(REACTIVE_CHAIN_ID, mismatched)).toBeNull();
  });
});

describe('joiner', () => {
  it('creates one claim row per liquidation and moves pending -> partial -> settled', async () => {
    const db = new MemoryDb();
    seedPolicy(db);

    const liquidate = decodeLog(CHAIN_ID, liquidateLog());
    if (liquidate?.kind !== 'liquidate') throw new Error('fixture did not decode');
    const runId = liquidate.runId;

    await applyEvent(db.asClient(), {
      chainId: CHAIN_ID,
      address: MORPHO,
      blockNumber: 100,
      blockTime: new Date('2026-11-15T09:31:12.000Z'),
      txHash: TX,
      logIndex: LOG_INDEX,
      decoded: liquidate,
    });

    expect(db.rows('claims')).toHaveLength(1);
    expect(db.rows('claims')[0]?.status).toBe('pending');

    // Re-indexing the same log must not create a second claim.
    await applyEvent(db.asClient(), {
      chainId: CHAIN_ID,
      address: MORPHO,
      blockNumber: 100,
      blockTime: new Date('2026-11-15T09:31:12.000Z'),
      txHash: TX,
      logIndex: LOG_INDEX,
      decoded: liquidate,
    });
    expect(db.rows('claims')).toHaveLength(1);

    const relief = decodeLog(CHAIN_ID, reliefLog(runId));
    if (relief?.kind !== 'reliefApplied') throw new Error('relief fixture did not decode');
    await applyEvent(db.asClient(), {
      chainId: CHAIN_ID,
      address: relayAddress(),
      blockNumber: 101,
      blockTime: new Date('2026-11-15T09:31:14.000Z'),
      txHash: `0x${'77'.repeat(32)}`,
      logIndex: 2,
      decoded: relief,
    });
    // One confirmed branch and one still in flight is pending, not partial: the receipt must not
    // claim half a settlement while the other chain has simply not landed yet.
    expect(db.rows('claims')[0]?.status).toBe('pending');

    // A branch that fails while the other confirmed is partial, and the failure stays visible.
    db.rows('claim_events').push({
      run_id: runId,
      chain_id: 1_301,
      kind: 'cash',
      status: 'failed',
      tx_hash: null,
      block_number: null,
      block_time: null,
      amount: '0',
      detail: {},
      error: 'DESTINATION_UNDERFUNDED',
    });
    await refreshClaimStatus(db.asClient(), runId);
    expect(db.rows('claims')[0]?.status).toBe('partial');

    const cash = decodeLog(1_301, cashLog(runId));
    if (cash?.kind !== 'claimPaid') throw new Error('cash fixture did not decode');
    await applyEvent(db.asClient(), {
      chainId: 1_301,
      address: `0x${'88'.repeat(20)}`,
      blockNumber: 200,
      blockTime: new Date('2026-11-15T09:31:14.410Z'),
      txHash: `0x${'99'.repeat(32)}`,
      logIndex: 3,
      decoded: cash,
    });

    const claim = db.rows('claims')[0];
    expect(claim?.status).toBe('settled');
    expect(claim?.total_latency_ms).toBe(2410);
    expect(db.rows('latency_samples')).toHaveLength(2);
  });

  it('derives status from branch rows alone', () => {
    expect(deriveClaimStatus({ relief: 'confirmed', cash: 'confirmed' })).toBe('settled');
    expect(deriveClaimStatus({ relief: 'confirmed', cash: 'failed' })).toBe('partial');
    expect(deriveClaimStatus({ relief: 'confirmed', cash: 'pending' })).toBe('pending');
    expect(deriveClaimStatus({ relief: 'failed', cash: 'failed' })).toBe('failed');
    expect(deriveClaimStatus({})).toBe('pending');
  });
});

function relayAddress(): Hex {
  return `0x${'66'.repeat(20)}`;
}
