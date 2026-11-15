# Phase 0 Research: Second Wind

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Date**: 2026-11-15

All unknowns from Technical Context are resolved below. Each entry records the decision, why it was chosen, and what was rejected.

---

## R1 — Reactive API generation: Omni, not Legacy

**Decision**: Build against **Reactive Omni** using `reactive-lib-omni`.
- Base contract: `AbstractReactive` (`src/base/AbstractReactive.sol`), remapped as `@reactive/`.
- `react(LogRecord memory log_) external onlySystem`
- Subscriptions via `SYSTEM.subscribe(chainId, contract, topic0, topic1, topic2, topic3)` where `SYSTEM = 0x8888888888888888888888888888888888888888`
- Callbacks via `SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({chainId, recipient, gasLimit, payload}))`
- `LogRecord` fields: `chainId`, `contractAddress`, `topic0..topic3`, `data`, `blockNumber`, `opCode`, `blockHash`, `txHash`, `logIndex`

**Rationale**: The buildathon runs on Omni. Legacy (`vm` modifier, `emit Callback`, `service.subscribe`) still works for already-deployed contracts but is the wrong target for new code. Omni block time is ~1 s with instant finality, which is what makes the "2 seconds" claim reachable.

**Alternatives considered**:
- Legacy Reactive: rejected — deprecated path, and the new auth model (`onlySystem`, `onlyCallbackSender`) is stronger.
- Off-chain keeper + hot wallet: rejected — the product's premise is that the pool cannot pay slowly, and a server key is exactly the thing being removed. Also fails the Integration criterion.

**Consequences recorded for implementation**:
- `react()` must **not** revert as a filter. A revert is caught, billed in full, and logged as `ReactiveContractReverted`. Unknown logs return early.
- `opCode` is the topic count, not a boolean. Decode only after checking it (e.g. `opCode == 4` for `Liquidate`).
- `blockHash` and `txHash` are `uint256` in `LogRecord`, so cast to `bytes32` when deriving `runId`.

---

## R2 — Callback authentication

**Decision**: Both destination contracts inherit `AbstractCallback` with `(IPayable callbackProxy_, address callbackSender_)` and expose settlement behind `onlyServiceProvider` + `onlyCallbackSender(reactive_)`.

- Base Sepolia proxy: `0x476F44b11F5C942c58f4c8E3d0300E5710743585`
- Unichain Sepolia proxy: `0x775c9B990ADe401060B78D0e98684eEf8d2466C1`
- `callbackSender_` is the deployed `SecondWindReactive` address, immutable.

**Rationale**: Two independent checks. `onlyServiceProvider` proves the call came through the network's proxy; `onlyCallbackSender` proves it came from *our* reactive contract. Either alone is bypassable. Both are immutable, which also satisfies FR-018: the pool operator cannot repoint the authority.

**Alternatives considered**:
- A mutable `guardian` address with an owner setter: rejected — an operator-controlled redirect is exactly the attack FR-018 forbids.
- Checking a signature in the payload: rejected — the injected-address model is the network's own pattern and has no key management.

**Deployment consequence** (from the docs): the reactive contract must be deployed **before** the callback contracts, because `_CALLBACK_SENDER` is immutable. Recipients are then set on the reactive contract through one-time owner setters.

---

## R3 — One reactive transaction, two callbacks, one `runId`

**Decision**:
- `runId = keccak256(abi.encode(uint256 originChainId, bytes32 txHash, uint256 logIndex))` of the `Liquidate` log.
- The same `runId` is placed in **both** payloads.
- Each destination keeps `mapping(bytes32 => bool) used` and reverts with `DuplicateRun(runId)` on reuse.
- The reactive contract keeps `mapping(bytes32 => bool) dispatched` and returns early on reuse, before any callback is requested.

**Rationale**: A reactive transaction may request several callbacks — the network records them as an array indexed by the reactive tx hash. Using one identifier is what lets the indexer prove the two settlements came from one event (FR-010, SC-003).

**Alternatives considered**:
- Separate IDs per branch: rejected — the join becomes a heuristic (same borrower, close in time) and duplicate detection weakens.
- A counter on Lasna as the ID: rejected — it is not derivable from the origin event, so the indexer cannot verify it without trusting the API.

**Verification**: the test suite asserts both branches report the same `runId` for one `Liquidate`, and that 1,000 repeated deliveries produce exactly one transfer per branch.

---

## R4 — Penalty math and rounding

**Decision**:
```
LIF(lltv)      = min(1.15e18, 1e36 / (1e18 - 0.3e18 * (1e18 - lltv) / 1e18))
fee            = repaidAssets * (LIF - 1e18) / 1e18          // floor
cashLimit      = fee * (10000 - reliefShareBps) / 10000       // floor
reliefLimit    = fee * reliefShareBps / 10000                 // floor
```
All arithmetic in `FeeMath`, `uint256`, 18-decimal fixed point, division always rounds **down**. `cashLimit + reliefLimit <= fee` is an invariant asserted in tests.

**Rationale**: Rounding down means the pool can never pay more than the computed penalty, and the sum invariant removes a class of off-by-one cap violations. At `lltv = 0.86e18`, `LIF = 1.043841e18` and the penalty is **4.3841%**, matching the demo numbers.

**Alternatives considered**:
- Rounding up on the payout: rejected — favours the borrower at the pool's expense and breaks the cap invariant.
- Floating point or `wad` mul-div with a different scale: rejected — 18-decimal integer math matches the token decimals and Morpho's own convention.

**Edge cases covered by tests**: zero `repaidAssets` (fee 0, no callback), `lltv` at each value Morpho enables (0.77, 0.86, 0.91, 0.945, 0.965, 0.98), and `lltv` above 0.98 where the 1.15 cap binds. Note `lltv` is immutable per market and is mirrored to Lasna at policy creation, never read from the loan at claim time.

---

## R5 — Coverage accounting across two chains (per-branch ceilings)

**Decision**: Split the policy cap once, at creation:
```
cashCeiling   = coverageCap * (10000 - reliefShareBps) / 10000
reliefCeiling = coverageCap - cashCeiling
```
Each branch enforces its own ceiling against its own local counter:
- `ClaimVault.cashPaidTotal[policyId] + cashAmount <= cashCeiling`
- `PolicyRegistry.reliefUsed[policyId] + reliefSpent <= reliefCeiling`

**Rationale**: The alternative — one shared `usedCoverage` counter — needs the Base branch to report unspent relief back to Lasna. A plain Base contract cannot request a callback; only a reactive contract can. That would require a second reactive hop, a second subscription, and a window where the cap is over-committed between dispatch and reconciliation. Splitting the ceiling makes every cap check local, synchronous, and individually testable, and `cashCeiling + reliefCeiling == coverageCap` proves FR-015 by construction.

**Accepted cost**: relief that stops at target health leaves unused relief capacity rather than converting to cash. FR-009 says unspent relief returns to coverage; here it returns to *relief* coverage and is visible in the receipt as `unspentRelief`. This is disclosed in the UI.

**Alternatives considered**:
- Reserve-then-reconcile on Lasna: works, but adds a reconciliation subscription and a failure mode where a lost `ReliefApplied` event under-counts usage. Rejected for the deadline.
- Let the cash branch read Base state: impossible without a bridge.

---

## R6 — Where relief is computed and applied

**Decision**: On **Base**, inside `CoveragePool.settleCascade`.
1. Read the policy from `PolicyRegistry` (same chain, authoritative).
2. Enumerate the borrower's active policies (bounded to 8).
3. For each, read `morpho.position(marketId, borrower)` and `morpho.idToMarketParams(marketId)`.
4. Convert borrow shares to assets, value collateral at `oracle.price()`, compute health.
5. Pick the lowest health position with debt > 0.
6. `repayNeeded = debt - collateralValue * lltv / targetHealth`; `reliefSpent = min(reliefLimit, debt, repayNeeded)`.
7. `morpho.repay(marketParams, reliefSpent, 0, borrower, "")`.
8. Update `reliefUsed`, emit `ReliefApplied(runId, policyId, marketId, reliefSpent, healthAfter)`.

**Rationale**: Only Base can read Morpho and the oracle. Sending position snapshots to Lasna would create a stale-data problem and a second trust boundary. FR-012 explicitly wants the destination to verify, and this design verifies everything that matters.

**Alternatives considered**:
- Compute the weakest loan on Lasna from mirrored snapshots: rejected — snapshots lag, and a lagging snapshot picks the wrong loan at exactly the wrong moment.
- Always relieve the triggering loan: rejected — fails FR-008 and the whole cascade story.

**Test coverage**: weakest selection with 1, 2, and 3 policies; ties broken by lowest market id; a policy with zero debt skipped; single-loan borrower receives the full relief share (SC-008).

---

## R7 — Clocks: `decidedAt` and `liquidateBlock`

**Decision**: Each payload carries two time facts.
- `decidedAt` — the Lasna block timestamp when `react()` ran.
- `liquidateBlock` — the Base block number from `LogRecord.blockNumber`.

Eligibility rules:
- Premium: both branches require `paidThrough >= decidedAt`. Neither branch consults its own wall clock for eligibility.
- Cancellation: Base requires `cancelledAtBlock == 0 || cancelledAtBlock > liquidateBlock`, so a cancellation that lands after the liquidation cannot retroactively void a valid claim.

**Rationale**: Cross-chain clocks differ. Comparing Base's `block.timestamp` against a premium value at settlement time makes the two branches disagree when a premium period ends mid-flight, producing a split receipt for no product reason. A single `decidedAt` makes the answer identical on both chains while still letting each branch verify the policy state it can see.

**Alternatives considered**:
- Local-clock eligibility on each chain: rejected — split outcomes on the boundary case, which the spec calls out explicitly.
- Only `block.number` comparisons: rejected — Base Sepolia has ~2 s blocks, so block numbers are not a time source for a 60-second window.

**Residual risk, documented**: Lasna timestamps track wall clock within a few seconds. The 60-second cascade rule (FR-007) therefore has a ±5 s tolerance. It changes which loans are treated as the trigger loan, never whether a payout happens.

---

## R8 — Price source: Uniswap V3 spot, demo-only

**Decision**: `MorphoV3Oracle` implements `IOracle.price()` as `(sqrtPriceX96^2 / 2^192) * 1e36`, adjusted for token decimals, reading `IUniswapV3Pool.slot0()` from a pool created for the demo. If the pool address is `address(0)`, the contract reads an owner-set price and emits `FallbackPriceUsed` on every read. The UI labels the oracle "demo harness — single spot source".

**Rationale**: Morpho needs an `IOracle`; mock tokens have no Chainlink feed. A spot read from a pool we seed makes the crash a **real swap** producing a **real** liquidation, which is far more convincing than an admin price poke. Because we own the pool's liquidity and nobody else trades the mock pair, the price is stable between swaps, so the demo is deterministic without an override.

**Alternatives considered**:
- Chainlink/Pyth: no feed for mock tokens on Base Sepolia.
- Uniswap V3 TWAP (`observe`): needs observation history the pool does not have on day one.
- Admin price on the happy path: rejected as the default — it makes the liquidation look staged.

**Disclosure**: `MorphoV3Oracle` carries a contract-level comment and an `isDemoHarness()` view returning `true`; the `/proof` page displays it. Production would need a multi-source oracle, which the spec lists as out of scope.

---

## R9 — Idempotency and duplicate delivery

**Decision**: Three layers.
1. **Lasna**: `dispatched[runId]` — return early, no callbacks.
2. **Base**: `usedRuns[runId]` in `CoveragePool` — revert `DuplicateRun`.
3. **Unichain**: `usedRuns[runId]` in `ClaimVault` — revert `DuplicateRun`.

Plus a per-branch balance check immediately before transfer/repay, and `nonReentrant` on both settlement functions.

**Rationale**: FR-011 and SC-003 demand zero double payments under 1,000 repeated deliveries. Defence in depth matters because the two branches fail independently: a replay could reach one destination without the other.

**Alternatives considered**:
- Only the Lasna guard: rejected — a re-org or a manual re-dispatch would bypass it.
- Nullifier-style hash of the full payload: rejected — the payload contains mutable fields (`decidedAt`), so the same claim could hash differently.

**Test**: a `ReplayHarness` calls each settlement function 1,000 times with the same `runId`; the test asserts exactly one state change and 999 `DuplicateRun` reverts.

---

## R10 — Storage: Supabase as a cache, not a ledger

**Decision**: Supabase Postgres stores four tables (`claims`, `claim_events`, `policies_mirror`, `latency_samples`) plus `indexer_cursor`. Every row is derived from chain logs and can be rebuilt by replaying from a cursor. The API serves reads from Postgres; the frontend never talks to Supabase directly (no anon key in the bundle).

**Rationale**: Receipts need a timeline (trigger → Lasna dispatch → each branch confirmation) that no single chain exposes. Postgres gives cheap ordering and aggregation, and the latency endpoint needs percentiles. Keeping the DB as a cache means a wrong or lost row is recoverable, and no product behaviour depends on it.

**Alternatives considered**:
- Read straight from RPC in the frontend: rejected — three chains, many calls, and no join. Would also expose rate limits to the user.
- A full custom database on Heroku Postgres: rejected — the user specified Supabase, and it is free at demo scale.
- No database, in-memory only: rejected — Heroku dynos restart, and the demo needs receipts to survive a restart.

**Schema authority**: `data-model.md` holds the DDL. Migrations live in `api/src/db/migrations` and run once at boot with an advisory lock.

---

## R11 — Identity and wallet connection

**Decision**: No accounts. The connected wallet address is the identity. `wagmi` + `viem` + RainbowKit, chains configured as Base Sepolia and Unichain Sepolia. Creating a policy is **one** transaction on Base; claiming is **zero** transactions.

**Rationale**: FR-001 to FR-014 are all keyed by borrower address. Accounts would add auth, session, and privacy surface for no product gain. One signature to buy cover and zero to claim is also the clearest possible demo of the value proposition.

**Alternatives considered**:
- Email or social login with a custodial wallet: rejected — contradicts "the payout is enforced by a contract, not trusted to a server".
- WalletConnect-only: kept as an option inside RainbowKit; injected wallets remain the default for the demo.

**Chain switching**: only used when a write needs Base. Reads run on both chains in parallel through TanStack Query. If the wallet is on the wrong chain, the write button becomes a `Switch to Base Sepolia` button; no silent chain change.

---

## R12 — Funding, gas budgets, and monitoring

**Decision**:
- Reactive contract funded with **REACT** at deploy; `coverDebt()` exposed publicly so anyone can revive it.
- `CoveragePool` and `ClaimVault` funded through their callback proxy's `depositTo(address)` in native ETH, **and** seeded with reserve tokens.
- Callback gas limits: relief `400,000`, cash `300,000`. Both are above the 100,000 minimum with room for the proxy's accounting overhead.
- The reactive transaction stays well under the 900,000 cap: two `requestCallbackV_1_0` calls plus bookkeeping.
- `/health` reports, for all three contracts: native balance, proxy `debt(address)`, proxy `reserves(address)`, and whether debt > 0. The UI shows a red banner when any of them is unfunded.

**Rationale**: Both sides fail silently when unfunded — the reactive contract stops receiving events, and a callback contract stops receiving deliveries. This is the single most likely way for a working demo to die between rehearsal and recording, so it is monitored, not documented-and-forgotten.

**Alternatives considered**:
- Assume deployment funding is enough: rejected — a callback revert is still charged, so a bug can drain the reserve during rehearsal.
- Let the API top up automatically: rejected — that reintroduces a hot wallet with spending power.

**Measured at M0**: actual REACT cost per `react()` and actual ETH cost per callback, recorded in `ops/docs/latency.md` with the funding multiple needed for 100 demo runs.

---

## R13 — Why the second chain is gated

**Decision**: Unichain ships only if it passes **20 consecutive end-to-end runs** with both branches confirmed and the same `runId`. Otherwise the build ships single-destination (cash and relief both on Base) and the README says so.

**Rationale**: Two callback destinations double the ways the loop can break, and the judging criteria weight a working loop over an ambitious broken one. A gate with a number is a decision made in advance, not a judgement call at 3 a.m.

**Alternatives considered**:
- Ship two chains regardless: rejected — a demo with one branch missing fails the Integration criterion harder than a clean single-chain loop.
- Drop Unichain now: rejected — the fork view and the "one event, two settlements" claim are the strongest part of the story. Gate it, do not pre-emptively abandon it.
