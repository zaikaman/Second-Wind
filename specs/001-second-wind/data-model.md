# Phase 1 Data Model: Second Wind

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Date**: 2026-11-15

Two layers, deliberately separated:

1. **On-chain entities** are authoritative. Every number a user sees can be recomputed from these.
2. **Cache entities** in Supabase exist for joins, receipts, and percentiles. They are disposable: dropping every table and replaying the indexer must reproduce the same UI.

---

## 1. On-Chain Entities

### 1.1 Policy (`PolicyRegistry`, Base Sepolia)

One policy covers one loan. A Morpho loan is the pair `(marketId, borrower)` — Morpho holds one position per market per account, so there is no per-position identifier to use.

| Field | Type | Rule |
|-------|------|------|
| `policyId` | `uint256` | Sequential from 1. Never reused. |
| `borrower` | `address` | Policy owner. Only this address may pay, pause, resume, or cancel. |
| `marketId` | `bytes32` | Morpho market id. Must exist in Morpho. |
| `loanKey` | `bytes32` | `keccak256(abi.encode(marketId, borrower))`. Unique among non-cancelled policies. |
| `coverageCap` | `uint256` | Loan-asset units, 18 decimals. Bounds: `100e18 … 5_000e18`. |
| `cashCeiling` | `uint256` | `coverageCap * (10000 - reliefShareBps) / 10000`, frozen at creation. |
| `reliefCeiling` | `uint256` | `coverageCap - cashCeiling`, frozen at creation. |
| `premiumPerSecond` | `uint256` | `coverageCap * APR_BPS / (10000 * 365 days)`. Demo APR `300` = 3%. |
| `paidThrough` | `uint64` | Unix seconds. Set at creation to `now + premiumTermSeconds`, then advanced only by `payPremium`. Cap: `now + 365 days`. |
| `reliefShareBps` | `uint16` | `0 … 10000`. Demo `6000` = 60% relief. |
| `targetHealthWad` | `uint256` | `1.05e18 … 1.5e18`. Health the relief aims for. |
| `cashDestination` | `address` | Non-zero. Receives the cash share on Unichain. |
| `status` | `enum` | `None`, `Active`, `Paused`, `Cancelled`. |
| `reliefUsed` | `uint256` | Lifetime relief applied. Never decreases. |
| `cancelledAtBlock` | `uint64` | Base block number of cancellation, `0` while live. |
| `createdAt` | `uint64` | Block timestamp. |

**Validation on `createPolicy`**
- `marketParams.loanToken == coverAsset` and `marketParams.oracle != 0`.
- Market exists: `morpho.idToMarketParams(marketId).loanToken != 0`.
- Borrower has an open position: `collateral > 0` and `borrowShares > 0`.
- Position is healthy at creation: `health > 1e18`. Covering an already-liquidatable loan is out of scope.
- No `Active` or `Paused` policy already holds `loanKey`.
- `activePolicyCount(borrower) < 8` — bounds the loop in `CoveragePool`.
- `premiumTermSeconds` in `[1 days, 365 days]`; the first premium is collected in the same transaction, so no policy is ever created already expired.
- `cashDestination != address(0)`; `reliefShareBps <= 10000`; cap and target health inside their ranges.

**State transitions**

```text
None ──create──▶ Active ──pause──▶ Paused
                   ▲                  │
                   └────resume────────┘
Active / Paused ──cancel──▶ Cancelled   (terminal)

Active ──payPremium──▶ Active   (paidThrough increases; no other field changes)
```

Rules:
- `payPremium` is allowed while `Active` or `Paused` (paying ahead is never blocked).
- `cancel` is irreversible and does not refund premium. Completed claims are untouched (FR-014).
- No field of a live policy is mutable except `paidThrough`, `status` (pause/resume only), `reliefUsed` (by the pool), and `cancelledAtBlock`. This is what makes FR-018 enforceable: there is no setter for terms.

### 1.2 Claim Dispatch (`SecondWindReactive`, Lasna)

Per-liquidation state. Mirrors the policy subset needed to decide and dispatch.

| Field | Type | Rule |
|-------|------|------|
| `runId` | `bytes32` | `keccak256(abi.encode(originChainId, txHash, logIndex))` of the `Liquidate` log. |
| `policyId` | `uint256` | Resolved from `loanKey` of `(marketId, borrower)`. |
| `borrower` | `address` | From `Liquidate.topic2`. |
| `marketId` | `bytes32` | From `Liquidate.topic1` (the `id` argument). |
| `repaidAssets` | `uint256` | From `Liquidate.data[0]`. |
| `lltv` | `uint256` | Mirrored from `PolicyCreated`. Immutable per market. |
| `fee` | `uint256` | `repaidAssets * (LIF(lltv) - 1e18) / 1e18`, floor. |
| `cashLimit` | `uint256` | `fee * (10000 - reliefShareBps) / 10000`, capped by `cashCeiling - cashPaid - cashReserved`. |
| `reliefLimit` | `uint256` | `fee * reliefShareBps / 10000`, capped by `reliefCeiling - reliefUsed - reliefReserved`. |
| `mode` | `enum` | `Standard` or `Cascade`. `Cascade` forces `cashLimit = 0` and `reliefLimit = min(fee, reliefRemaining)`. |
| `decidedAt` | `uint64` | Lasna block timestamp. |
| `liquidateBlock` | `uint64` | `LogRecord.blockNumber` on Base. |

Guards before dispatch: `dispatched[runId] == false`, policy status `Active`, `paidThrough >= decidedAt`, `fee > 0`, at least one limit `> 0`, both recipients set.

Cascade rule: if `decidedAt - lastClaimAt[borrower] <= 60`, `mode = Cascade`. `lastClaimAt` updates on every dispatch, including a cascade.

### 1.3 Settlement Branch — Relief (`CoveragePool`, Base Sepolia)

| Field | Type | Rule |
|-------|------|------|
| `usedRuns` | `mapping(bytes32 => bool)` | One settlement per `runId`. |
| `premiumCollected` | `uint256` | Premium received, informational. |
| `reserveBalance` | `uint256` | `coverAsset.balanceOf(this)`. Not withdrawable by the owner. |

`settleCascade(address reactive, bytes32 runId, uint256 policyId, uint256 reliefLimit, uint256 decidedAt, uint256 liquidateBlock)`:
1. Auth: `onlyServiceProvider`, `onlyCallbackSender(reactive)`.
2. Replay: reject used `runId`.
3. Policy: exists, `status == Active`, `paidThrough >= decidedAt`, `cancelledAtBlock` is `0` or `> liquidateBlock`.
4. Cap: `reliefUsed + reliefSpent <= reliefCeiling` and `reliefSpent <= reliefLimit`.
5. Choose target (Section 1.4), compute `reliefSpent`, approve, `morpho.repay`.
6. Write `reliefUsed`, mark `runId`, emit `ReliefApplied`.

### 1.4 Loan Position (read from Morpho, never stored on Base)

| Field | Source |
|-------|--------|
| `collateral` | `morpho.position(marketId, borrower).collateral` |
| `borrowShares` | `morpho.position(...).borrowShares` |
| `debt` | `borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares)` |
| `price` | `oracle.price()` — loan per collateral, scaled `1e36` |
| `lltv` | `morpho.idToMarketParams(marketId).lltv` |
| `health` | `collateral * price / 1e36 * lltv / debt` |

`weakest(policies)` = minimum `health` among policies with `debt > 0`; ties break on the numerically lower `marketId`.

`repayForTarget(debt, collateralValue, lltv, targetHealth)` = `debt - (collateralValue * lltv / targetHealth)`, clamped to `[0, debt]`.

### 1.5 Settlement Branch — Cash (`ClaimVault`, Unichain Sepolia)

| Field | Type | Rule |
|-------|------|------|
| `terms[policyId].cashCeiling` | `uint256` | Written once by `registerPolicy`; immutable after. |
| `terms[policyId].destination` | `address` | Written once; immutable after. |
| `cashPaid[policyId]` | `uint256` | Lifetime cash paid. |
| `lastPaidThrough[policyId]` | `uint64` | Monotonic; rejects a stale window. |
| `usedRuns` | `mapping(bytes32 => bool)` | One settlement per `runId`. |
| `reserveBalance` | `uint256` | `coverAsset.balanceOf(this)`. Not withdrawable by the owner. |

`registerPolicy(address reactive, uint256 policyId, uint256 cashCeiling, uint64 paidThrough, address destination)`:
- Auth as above; idempotent — a second call with identical values is a no-op, different values revert `TermsMismatch`.
- Requires `destination != 0` and `cashCeiling <= MAX_CASH_CEILING` (`10_000e18`).

`payClaim(address reactive, bytes32 runId, uint256 policyId, uint256 cashAmount, uint64 paidThrough)`:
1. Auth, replay, terms must exist.
2. `paidThrough >= decidedAt` is enforced by the caller's payload; here `paidThrough >= lastPaidThrough[policyId]`.
3. `cashAmount > 0`, `cashPaid + cashAmount <= cashCeiling`, `reserveBalance >= cashAmount`.
4. `safeTransfer(destination, cashAmount)`, update counters, emit `ClaimPaid`.

### 1.6 Coverage Reserve (per chain)

| Field | Base Sepolia | Unichain Sepolia |
|-------|--------------|------------------|
| Asset | `mUSDC` (18 dp mock) | `mUSDC` (18 dp mock) |
| Holder | `CoveragePool` | `ClaimVault` |
| Funded by | deploy script + premium | deploy script |
| Withdrawable by owner | No — deposit-only | No — deposit-only |

Premium is collected on Base and does not fund the Unichain reserve. Cross-chain reserve rebalancing is explicitly out of scope in the spec; the demo pre-funds both.

### 1.7 Receipt (derived, not stored on chain)

A receipt is the indexer's join of one `runId`:

```text
receipt = {
  runId,
  policyId, borrower, marketId,
  trigger:  { chainId, txHash, blockNumber, logIndex, blockTime },
  fee,
  split:    { mode, cashLimit, reliefLimit, shortfall },
  relief:   { status, txHash, amount, marketId, healthBefore, healthAfter, latencyMs },
  cash:     { status, txHash, amount, destination, latencyMs },
  unspentRelief,
  settledAt,
  totalLatencyMs
}
```

`shortfall = fee - cashLimit - reliefLimit` (FR-003). `unspentRelief = reliefLimit - relief.amount` (FR-009).

---

## 2. Cache Schema (Supabase / Postgres)

All amounts are `numeric(38,18)` so they compare exactly with 18-decimal token units. Hashes and addresses are `text` (lowercase hex) for readability in the API.

```sql
create type claim_status   as enum ('pending', 'partial', 'settled', 'failed');
create type branch_status  as enum ('pending', 'confirmed', 'failed');
create type branch_kind    as enum ('relief', 'cash', 'dispatch', 'registration');

create table policies_mirror (
  policy_id          numeric(78,0) primary key,
  borrower           text        not null,
  market_id          text        not null,
  coverage_cap       numeric(38,18) not null,
  cash_ceiling       numeric(38,18) not null,
  relief_ceiling     numeric(38,18) not null,
  relief_used        numeric(38,18) not null default 0,
  cash_paid          numeric(38,18) not null default 0,
  relief_share_bps   integer     not null,
  premium_per_second numeric(38,18) not null,
  paid_through       bigint      not null,
  target_health      numeric(38,18) not null,
  cash_destination   text        not null,
  status             text        not null,
  created_at         timestamptz not null,
  updated_at         timestamptz not null default now()
);

create table claims (
  run_id            text primary key,
  policy_id         numeric(78,0) not null references policies_mirror(policy_id),
  borrower          text        not null,
  market_id         text        not null,
  origin_chain_id   integer     not null,
  origin_tx_hash    text        not null,
  origin_block      bigint      not null,
  origin_log_index  integer     not null,
  origin_block_time timestamptz not null,
  fee_amount        numeric(38,18) not null,
  cash_limit        numeric(38,18) not null,
  relief_limit      numeric(38,18) not null,
  mode              text        not null,
  status            claim_status not null default 'pending',
  decided_at        timestamptz not null,
  detected_at       timestamptz not null default now(),
  settled_at        timestamptz,
  total_latency_ms  integer
);

create table claim_events (
  id           bigserial primary key,
  run_id       text not null references claims(run_id) on delete cascade,
  chain_id     integer not null,
  kind         branch_kind not null,
  status       branch_status not null default 'pending',
  tx_hash      text,
  block_number bigint,
  block_time   timestamptz,
  amount       numeric(38,18),
  detail       jsonb not null default '{}'::jsonb,
  error        text,
  created_at   timestamptz not null default now(),
  unique (run_id, chain_id, kind)
);

create table latency_samples (
  id                bigserial primary key,
  run_id            text references claims(run_id) on delete cascade,
  branch            branch_kind not null,
  trial             integer not null,
  origin_block_time timestamptz not null,
  dispatch_time     timestamptz,
  confirm_block_time timestamptz,
  latency_ms        integer not null,
  created_at        timestamptz not null default now()
);

create table indexer_cursor (
  chain_id   integer primary key,
  last_block bigint not null,
  updated_at timestamptz not null default now()
);

create index on claims (borrower, origin_block_time desc);
create index on claims (status) where status <> 'settled';
create index on claim_events (run_id, chain_id);
create index on latency_samples (trial, branch);
```

**Invariants the API enforces when writing**
- A `claims` row is inserted when the `Liquidate` log is seen, before either branch confirms.
- A `claim_events` row is inserted per branch, keyed by `(run_id, chain_id, kind)`, so a re-index is an upsert, not a duplicate.
- `claims.status` becomes `settled` only when **both** branch rows are `confirmed`; `partial` when exactly one is confirmed and the other failed; `pending` otherwise (FR-017).
- `policies_mirror.relief_used` and `.cash_paid` are read from chain, never summed from claims. A missing log cannot corrupt the cap display.
- `latency_samples` are written once per confirmed branch, from block timestamps (authoritative), not from API receipt times.

---

## 3. Requirement → Test Map

| Requirement | Primary test |
|-------------|--------------|
| FR-001 policy creation | `PolicyRegistry.t.sol::test_CreatePolicy_StoresTerms` |
| FR-002 active only while paid | `PolicyRegistry.t.sol::test_Status_RequiresPaidPremium`, `CoveragePool.t.sol::test_ExpiredPremium_Rejected` |
| FR-003 premium accrues per second | `PolicyRegistry.t.sol::test_PayPremium_AdvancesPaidThrough`, fuzz on amount |
| FR-004 fee from repaid and LIF | `FeeMath.t.sol::test_Lif_AtEnabledLltvs`, `test_Fee_MatchesMorphoPenalty` |
| FR-005 claim capped by coverage | `CoveragePool.t.sol::test_Relief_CappedByCeiling`, `ClaimVault.t.sol::test_Cash_CappedByCeiling` |
| FR-006 split by relief share | `FeeMath.t.sol::test_Split_SumsToFee` |
| FR-007 second liquidation → all relief | `SecondWindReactive.t.sol::test_Cascade_Within60s_NoCash` |
| FR-008 relief on weakest, stops at target | `CoveragePool.t.sol::test_Weakest_Selected`, `test_Relief_StopsAtTargetHealth` |
| FR-009 unspent relief returns to coverage | `CoveragePool.t.sol::test_Unspent_LeavesReliefCapacity` |
| FR-010 both branches, one id | `integration/Join.t.sol::test_BothBranches_SameRunId` |
| FR-011 duplicate delivery rejected | `integration/Replay.t.sol::test_1000Replays_PayOnce` |
| FR-012 each branch verifies | `CoveragePool.t.sol::test_ReReadsMorpho`, `ClaimVault.t.sol::test_TermsMismatch_Reverts` |
| FR-013 cash only to destination | `ClaimVault.t.sol::test_Cash_GoesOnlyToRegisteredDestination`, `test_Relief_OnlyRepaysCoveredLoan` |
| FR-014 cancel stops future claims | `PolicyRegistry.t.sol::test_Cancel_StopsClaims`, `CoveragePool.t.sol::test_Cancelled_Rejected` |
| FR-015 never above cap | `FeeMath.t.sol::test_Split_NeverExceedsCap` (fuzz), `CoveragePool.t.sol::test_LifetimeCap` |
| FR-016 rejection has reason | `integration/Reasons.t.sol::test_EachRejection_HasReason` |
| FR-017 branch failure is isolated | `integration/Delay.t.sol::test_OneBranchFails_OtherStillSettles` |
| FR-018 operator cannot redirect | `CoveragePool.t.sol::test_NoWithdrawal`, `ClaimVault.t.sol::test_OwnerCannotWithdraw`, `SecondWindReactive.t.sol::test_Setters_OneTimeOnly` |
| FR-019 partial claim stays visible | `api/test/claims.test.ts::partial_claim_is_visible` |
| SC-001 / SC-002 latency | `ops/e2e/measure-latency.ts` (≥ 10 trials, p50 and p95 reported) |
| SC-003 no double pay | `integration/Replay.t.sol::test_1000Replays_PayOnce` |
| SC-004 twin loan survives | fork test `Fork.Survives.t.sol::test_CoveredTwin_SurvivesSecondCrash` |
| SC-006 onboarding under 2 minutes | manual stopwatch, recorded in `ops/docs/runbook.md` |
| SC-007 plain-language reasons | `api/test/reasons.test.ts` asserts every code has a sentence |
| SC-010 operator refusal recorded | `SecondWindReactive.t.sol::test_SetRecipient_SecondCallReverts` |

## 4. Amount Conventions

- All token amounts: `uint256`, 18 decimals. The demo deploys `mWETH` and `mUSDC` with 18 decimals each, which keeps the oracle conversion free of decimal scaling.
- Health and LIF: 18-decimal fixed point (`1e18` = 1.0).
- Basis points: `10000` = 100%.
- Oracle price: loan-asset units per collateral unit × `1e36` (Morpho's `ORACLE_PRICE_SCALE`).
- Timestamps: `uint64` Unix seconds. Counters that need block ordering use `uint64` block numbers and are only compared within one chain.
