/** Typed access to the read-only API. Every amount crosses the wire as a decimal string. */

const BASE_URL = (import.meta.env.VITE_API_URL ?? 'http://localhost:8080').replace(/\/$/, '');

export type ClaimStatus = 'pending' | 'partial' | 'settled' | 'failed';

export type ClaimSummary = {
  runId: string;
  policyId: string;
  status: ClaimStatus;
  fee: string;
  mode: string;
  triggeredAt: string;
  settledAt: string | null;
  totalLatencyMs: number | null;
};

export type BranchView = {
  chainId: number;
  status: 'pending' | 'confirmed' | 'failed';
  txHash: string | null;
  blockTime: string | null;
  amount: string;
  latencyMs: number | null;
  explorer: string | null;
  marketId?: string | null;
  healthBefore?: string | null;
  healthAfter?: string | null;
  destination?: string | null;
};

export type Receipt = {
  runId: string;
  policyId: string;
  borrower: string;
  status: ClaimStatus;
  trigger: {
    chainId: number;
    txHash: string;
    blockNumber: number;
    blockTime: string;
    logIndex: number;
    explorer: string | null;
  };
  reactive: { txHash: string | null; blockNumber: number | null; blockTime: string | null; explorer: string | null };
  fee: string;
  split: { mode: string; reliefLimit: string; cashLimit: string; shortfall: string };
  branches: { relief: BranchView | null; cash: BranchView | null };
  unspentRelief: string;
  failure: { code: string; message: string } | null;
  totalLatencyMs: number | null;
};

export type Position = { collateral: string; debt: string; health: string; liquidatable: boolean } | null;

export type Policy = {
  policyId: string;
  borrower: string;
  marketId: string;
  coverageCap: string;
  cashCeiling: string;
  reliefCeiling: string;
  reliefUsed: string;
  cashPaid: string;
  reliefRemaining: string;
  cashRemaining: string;
  reliefShare: string;
  premiumPerSecond: string;
  premiumApr: string;
  paidThrough: string;
  premiumActive: boolean;
  targetHealth: string;
  cashDestination: string;
  status: string;
  createdAt: string;
  position: Position;
};

export type ChainHealth = { chainId: number; head: number | null; indexed: number | null; lagBlocks: number | null };
export type FundingHealth = { native: string; debt: string; reserves: string; ok: boolean };
export type Health = {
  status: string;
  version: string;
  chains: { base: ChainHealth; unichain: ChainHealth; reactive: ChainHealth };
  funding: { reactive: FundingHealth; coveragePool: FundingHealth; claimVault: FundingHealth };
  lastIndexedAt: string | null;
};

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

async function getJson<T>(path: string): Promise<T> {
  const response = await fetch(`${BASE_URL}${path}`, { headers: { accept: 'application/json' } });
  if (!response.ok) {
    let code = 'HTTP_ERROR';
    let message = `Request failed with status ${response.status}.`;
    try {
      const body = (await response.json()) as { error?: { code?: string; message?: string } };
      code = body.error?.code ?? code;
      message = body.error?.message ?? message;
    } catch {
      // A non-JSON error body is still an error; keep the status-derived message.
    }
    throw new ApiError(response.status, code, message);
  }
  return (await response.json()) as T;
}

export function fetchReceipt(runId: string): Promise<Receipt> {
  return getJson<Receipt>(`/claims/${runId}`);
}

export async function fetchClaims(limit = 20): Promise<ClaimSummary[]> {
  const body = await getJson<{ claims: ClaimSummary[] }>(`/claims?limit=${limit}`);
  return body.claims;
}

export function fetchPolicy(policyId: string): Promise<Policy> {
  return getJson<Policy>(`/policies/${policyId}`);
}

export function fetchHealth(): Promise<Health> {
  return getJson<Health>('/health');
}
