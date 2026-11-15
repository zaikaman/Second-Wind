import { decodeAbiParameters, encodeAbiParameters, keccak256, toHex } from 'viem';
import type { Hex } from 'viem';

/**
 * Event signatures and topic0 values the indexer understands. The `opCode` the contracts rely on
 * is simply `topics.length`, so a log with the right topic0 and the wrong shape is rejected here
 * rather than decoded into nonsense.
 */
export const SIGNATURES = {
  policyCreated:
    'PolicyCreated(uint256,address,bytes32,uint256,uint256,uint256,uint256,uint64,uint16,uint256,address,uint256)',
  premiumPaid: 'PremiumPaid(uint256,uint64)',
  statusChanged: 'PolicyStatusChanged(uint256,uint8,uint64)',
  liquidate: 'Liquidate(bytes32,address,address,uint256,uint256,uint256,uint256,uint256)',
  reliefApplied: 'ReliefApplied(bytes32,uint256,bytes32,uint256,uint256,uint256,uint64)',
  claimPaid: 'ClaimPaid(bytes32,uint256,address,uint256,uint64)',
  callbackRequest: 'CallbackRequest(uint256,address,uint64,bytes)',
} as const;

export type SignatureName = keyof typeof SIGNATURES;

export const TOPICS = Object.fromEntries(
  Object.entries(SIGNATURES).map(([name, signature]) => [name, keccak256(toHex(signature))]),
) as Record<SignatureName, Hex>;

export type Decoded =
  | {
      kind: 'policyCreated';
      policyId: bigint;
      borrower: Hex;
      marketId: Hex;
      coverageCap: bigint;
      cashCeiling: bigint;
      reliefCeiling: bigint;
      premiumPerSecond: bigint;
      paidThrough: bigint;
      reliefShareBps: number;
      targetHealthWad: bigint;
      cashDestination: Hex;
      lltv: bigint;
    }
  | { kind: 'premiumPaid'; policyId: bigint; paidThrough: bigint }
  | { kind: 'statusChanged'; policyId: bigint; status: number }
  | {
      kind: 'liquidate';
      marketId: Hex;
      borrower: Hex;
      repaidAssets: bigint;
      repaidShares: bigint;
      seizedAssets: bigint;
      runId: Hex;
    }
  | {
      kind: 'reliefApplied';
      runId: Hex;
      policyId: bigint;
      marketId: Hex;
      reliefSpent: bigint;
      debtAfter: bigint;
      healthAfter: bigint;
      appliedAt: bigint;
    }
  | { kind: 'claimPaid'; runId: Hex; policyId: bigint; destination: Hex; amount: bigint; paidThrough: bigint }
  | { kind: 'callbackRequest'; chainId: bigint; recipient: Hex; gasLimit: bigint; runId: Hex | null };

export type RawLog = {
  address: Hex;
  topics: readonly Hex[];
  data: Hex;
  blockNumber: bigint | null;
  transactionHash: Hex | null;
  logIndex: number | null;
};

/** The run id both settlement contracts carry: `keccak256(abi.encode(chainId, txHash, logIndex))`. */
export function deriveRunId(chainId: number, txHash: Hex, logIndex: number): Hex {
  return keccak256(
    encodeAbiParameters(
      [{ type: 'uint256' }, { type: 'bytes32' }, { type: 'uint256' }],
      [BigInt(chainId), txHash, BigInt(logIndex)],
    ),
  );
}

/** Decodes one log, or returns null for anything the indexer does not handle. */
export function decodeLog(chainId: number, log: RawLog): Decoded | null {
  const topic0 = log.topics[0];
  if (!topic0) {
    return null;
  }

  switch (topic0) {
    case TOPICS.liquidate: {
      if (log.topics.length !== 4) return null;
      const [repaidAssets, repaidShares, seizedAssets] = decodeAbiParameters(
        [{ type: 'uint256' }, { type: 'uint256' }, { type: 'uint256' }],
        log.data,
      );
      return {
        kind: 'liquidate',
        marketId: asBytes32(log.topics[1]),
        borrower: asAddress(log.topics[3]),
        repaidAssets,
        repaidShares,
        seizedAssets,
        runId: deriveRunId(chainId, hash(log.transactionHash), index(log.logIndex)),
      };
    }

    case TOPICS.policyCreated: {
      if (log.topics.length !== 4) return null;
      const [coverageCap, cashCeiling, reliefCeiling, premiumPerSecond, paidThrough, reliefShareBps, targetHealthWad, cashDestination, lltv] =
        decodeAbiParameters(
          [
            { type: 'uint256' },
            { type: 'uint256' },
            { type: 'uint256' },
            { type: 'uint256' },
            { type: 'uint64' },
            { type: 'uint16' },
            { type: 'uint256' },
            { type: 'address' },
            { type: 'uint256' },
          ],
          log.data,
        );
      return {
        kind: 'policyCreated',
        policyId: asBigInt(log.topics[1]),
        borrower: asAddress(log.topics[2]),
        marketId: asBytes32(log.topics[3]),
        coverageCap,
        cashCeiling,
        reliefCeiling,
        premiumPerSecond,
        paidThrough,
        reliefShareBps: Number(reliefShareBps),
        targetHealthWad,
        cashDestination,
        lltv,
      };
    }

    case TOPICS.premiumPaid: {
      if (log.topics.length !== 2) return null;
      const [paidThrough] = decodeAbiParameters([{ type: 'uint64' }], log.data);
      return { kind: 'premiumPaid', policyId: asBigInt(log.topics[1]), paidThrough };
    }

    case TOPICS.statusChanged: {
      if (log.topics.length !== 2) return null;
      const [status] = decodeAbiParameters([{ type: 'uint8' }, { type: 'uint64' }], log.data);
      return { kind: 'statusChanged', policyId: asBigInt(log.topics[1]), status: Number(status) };
    }

    case TOPICS.reliefApplied: {
      if (log.topics.length !== 4) return null;
      const [reliefSpent, debtAfter, healthAfter, appliedAt] = decodeAbiParameters(
        [{ type: 'uint256' }, { type: 'uint256' }, { type: 'uint256' }, { type: 'uint64' }],
        log.data,
      );
      return {
        kind: 'reliefApplied',
        runId: asBytes32(log.topics[1]),
        policyId: asBigInt(log.topics[2]),
        marketId: asBytes32(log.topics[3]),
        reliefSpent,
        debtAfter,
        healthAfter,
        appliedAt,
      };
    }

    case TOPICS.claimPaid: {
      if (log.topics.length !== 4) return null;
      const [amount, paidThrough] = decodeAbiParameters([{ type: 'uint256' }, { type: 'uint64' }], log.data);
      return {
        kind: 'claimPaid',
        runId: asBytes32(log.topics[1]),
        policyId: asBigInt(log.topics[2]),
        destination: asAddress(log.topics[3]),
        amount,
        paidThrough,
      };
    }

    case TOPICS.callbackRequest: {
      if (log.topics.length !== 4) return null;
      const [chainId_, recipient, gasLimit] = [
        asBigInt(log.topics[1]),
        asAddress(log.topics[2]),
        asBigInt(log.topics[3]),
      ];
      const [payload] = decodeAbiParameters([{ type: 'bytes' }], log.data);
      return { kind: 'callbackRequest', chainId: chainId_, recipient, gasLimit, runId: runIdFromPayload(payload) };
    }

    default:
      return null;
  }
}

/**
 * Every settlement payload starts with `(address sender, bytes32 runId, ...)`, so the shared id is
 * the second 32-byte word after the 4-byte selector.
 */
function runIdFromPayload(payload: Hex): Hex | null {
  if (payload.length < 2 + 8 + 128) {
    return null;
  }
  return `0x${payload.slice(2 + 8 + 64, 2 + 8 + 128)}` as Hex;
}

function asBigInt(topic: Hex | undefined): bigint {
  return topic ? BigInt(topic) : 0n;
}

function asAddress(topic: Hex | undefined): Hex {
  return `0x${(topic ?? '0x').slice(-40).padStart(40, '0')}` as Hex;
}

function asBytes32(topic: Hex | undefined): Hex {
  return (topic ?? `0x${'0'.repeat(64)}`) as Hex;
}

function hash(value: Hex | null): Hex {
  if (!value) throw new Error('log is missing its transaction hash');
  return value;
}

function index(value: number | null): number {
  if (value === null) throw new Error('log is missing its index');
  return value;
}
