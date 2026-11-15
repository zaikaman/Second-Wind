# Implementation Plan: Second Wind

**Branch**: `main` | **Date**: 2026-11-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-second-wind/spec.md`

## Summary

Second Wind pays a borrower back for the liquidation penalty automatically, in about two seconds, and routes part of that payout into the borrower's weakest loan so the next price move does not liquidate it.

The technical shape is a **Reactive Omni** contract on Lasna that watches `Liquidate` and policy events on Base Sepolia, computes the penalty and the cash/relief split, and fans out **two callbacks from one reactive transaction**: debt relief on Base Sepolia and a cash payout on Unichain Sepolia. Both callbacks carry one `runId`, so the indexer can join them into a single receipt. The chain is the source of truth; the Node service only indexes and serves reads.

The delivery order is deliberately asymmetric: **Base + Lasna first** (one callback, fully working product), **Unichain second** (second callback, only kept if it passes 20 consecutive end-to-end runs). This protects the deadline without pretending the two-chain loop is free.

## Technical Context

**Language/Version**: Solidity `0.8.29` (contracts); TypeScript `5.6` (web, api, scripts); Node.js `20` LTS

**Primary Dependencies**:
- Contracts: Foundry (`forge`, `cast`, `anvil`), `reactive-lib-omni` (Omni interfaces; import prefix `@reactive/`), OpenZeppelin Contracts `5.x` (`Ownable`, `ReentrancyGuard`, `SafeERC20`, `Pausable`), local minimal interfaces for Morpho Blue and Uniswap V3 (interfaces only, to avoid pragma conflicts)
- Web: React `18`, Vite `5`, `wagmi` `2`, `viem` `2`, RainbowKit `2`, TanStack Query `5`, Tailwind CSS `3`, React Router `6`
- API: Express `4`, Zod `3`, `@supabase/supabase-js` `2`, `pino` `9`

**Storage**: Supabase Postgres, used as a **read cache and receipt store only**. On-chain state is authoritative; every API field is recomputable from chain data. No user accounts: the wallet address is the identity.

**Testing**: Foundry (unit, fuzz, forked Base Sepolia), Vitest (api and web logic), Playwright (one smoke path), and a custom `ops/e2e` latency harness that measures real callback delivery over at least 10 trials.

**Target Platform**: Vercel (static SPA), Heroku (Node dyno, one web process), Base Sepolia `84532` + Unichain Sepolia `1301` + Reactive Lasna `5318007`

**Project Type**: monorepo — on-chain contracts + web application + indexing API

**Performance Goals**:
- Claim settlement: median ≤ 3 s, p95 ≤ 5 s, from `Liquidate` block time to both callback receipts
- API read p95 < 300 ms; indexer lag < 3 s behind chain head
- Dashboard first meaningful paint < 2 s on a laptop connection

**Constraints**:
- Callback gas limit minimum is **100,000**; a reactive transaction is capped at **900,000** gas
- The reactive contract pays for `react()` in **REACT** on Lasna; each callback contract pays for delivery in that chain's **native ETH**. Both must stay funded or delivery silently stops.
- Testnets only. No mainnet, no mixed mainnet/testnet pair.
- Payloads must declare an `address` as their **first parameter**; Reactive replaces its first 160 bits with the requesting reactive contract address.
- No secrets in the repo; all addresses and chain IDs are explicit config.
- All work on `main`. New feature work gets a folder under `specs/`, never a branch.

**Scale/Scope**: 1 demo borrower, 3 loans across 2 markets, 2 active policies; 5 deployed contracts plus 1 reactive contract; 4 web routes; 6 API endpoints; ≥ 10 measured trials; a 1,000-delivery replay test.

## Constitution Check

*GATE: must pass before Phase 0 research. Re-checked after Phase 1 design.*

| # | Principle | Gate question | Result | Evidence |
|---|-----------|---------------|--------|----------|
| I | Clear, Focused Code | Does each contract have one job, with shared math factored out? | PASS | One contract per responsibility; `FeeMath` and `HealthMath` hold the only financial formulas; no contract both holds funds and decides eligibility. |
| II | Secure Contract Boundaries | Is every external entry point authenticated, input-checked, and replay-safe? | PASS | Both destination contracts inherit `AbstractCallback` (`onlyServiceProvider` + `onlyCallbackSender`); `runId` replay guard on every settlement; per-branch coverage ceilings; Base re-reads Morpho, oracle, and registry instead of trusting Lasna numbers; `nonReentrant` on all fund-moving paths; borrower policy list bounded to 8. |
| III | Tests Define Expected Behavior | Is every requirement backed by a test that fails before the code exists? | PASS | Requirement-to-test map in `data-model.md`; unit + fuzz for math and caps, fork tests for real Morpho, replay and delay tests for both branches. |
| IV | Verify Cross-Chain Integration | Are the two branches proven to share one `runId`, resist replay, and fail independently? | PASS | Integration suite asserts one `runId` on both branches, 1,000 duplicate deliveries pay once, and a stalled branch never marks the other complete; latency claims come from measured trials, not estimates. |
| V | Maintainability and Simplicity | Is this the simplest design that meets the spec? | PASS | Single accountant for fee math, no reverse message from Base to Lasna, no server key, no upgradeable proxies. Non-obvious choices documented in `research.md`. |

No constitutional violations. Complexity is tracked below for transparency, not as an exception.

**Post-Design Re-check** (after Phase 1): all five gates still PASS. The per-branch ceiling decision (R5) removed a reverse cross-chain message, lowering total complexity. The demo oracle (R8) is isolated in one contract and labelled demo-only, satisfying the constitution's oracle disclosure rule.

## Project Structure

### Documentation (this feature)

```text
specs/001-second-wind/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R12
├── data-model.md        # Phase 1: on-chain entities + Supabase schema
├── quickstart.md        # Phase 1: deploy, fund, demo, measure
├── contracts/           # Phase 1: interface contracts
│   ├── policy-registry.md
│   ├── base-callbacks.md
│   ├── unichain-callbacks.md
│   ├── reactive-contract.md
│   └── http-api.md
├── checklists/
│   └── requirements.md  # 15/15 spec quality
└── tasks.md             # Phase 2 (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
contracts/                          # Foundry project, one toolchain for three chains
├── src/
│   ├── base/
│   │   ├── PolicyRegistry.sol      # policy lifecycle, loan binding, branch ceilings
│   │   ├── CoveragePool.sol        # AbstractCallback; holds reserves; repays debt
│   │   └── MorphoV3Oracle.sol      # IOracle over a Uniswap V3 pool (demo harness)
│   ├── unichain/
│   │   └── ClaimVault.sol          # AbstractCallback; holds reserves; pays cash share
│   ├── reactive/
│   │   └── SecondWindReactive.sol  # mirrors policies, computes fee/split, dispatches
│   ├── libraries/
│   │   ├── FeeMath.sol             # LIF, penalty, split
│   │   ├── HealthMath.sol          # health factor, weakest-loan selection, repay target
│   │   └── Topics.sol              # event topic0 constants
│   ├── interfaces/
│   │   ├── IMorpho.sol             # minimal Morpho Blue surface
│   │   ├── IOracle.sol
│   │   └── IUniswapV3Pool.sol
│   └── mocks/
│       ├── MockERC20.sol           # mWETH / mUSDC
│       ├── MockOracle.sol          # deterministic unit-test oracle
│       └── MockSystemContract.sol  # stands in at 0x8888… for `react()` tests
├── test/
│   ├── unit/                       # FeeMath, PolicyRegistry, both callback contracts
│   ├── integration/                # runId join, replay, delayed branch
│   └── fork/                       # real Morpho + Uniswap on Base Sepolia
├── script/
│   ├── DeployBase.s.sol
│   ├── DeployUnichain.s.sol
│   ├── DeployReactive.s.sol
│   ├── SeedMarket.s.sol            # tokens, pool, market, three loans
│   ├── Crash.s.sol                 # swap price, liquidate
│   └── Wire.s.sol                  # one-time setters, then renounce
├── lib/                            # forge-std, reactive-lib-omni, openzeppelin
└── foundry.toml

web/                                # React + Vite → Vercel
├── src/
│   ├── pages/                      # Dashboard, NewCover, Receipts, Receipt, Proof
│   ├── components/                 # HealthBar, PolicyCard, BranchStatus, Timeline
│   ├── hooks/                      # usePolicies, useClaims, useChainStatus
│   ├── lib/                        # contracts, format, explorer links
│   └── config/                     # chains, addresses, abis
├── index.html
├── vite.config.ts
└── package.json

api/                                # Node.js → Heroku
├── src/
│   ├── index.ts                    # express app, graceful shutdown
│   ├── routes/                     # health, policies, claims, stats
│   ├── services/
│   │   ├── indexer.ts              # poll Base, Unichain, Lasna
│   │   ├── joiner.ts               # merge branches by runId
│   │   └── latency.ts              # block-time based measurements
│   ├── db/                         # supabase client + SQL migrations
│   └── config/                     # env schema (zod)
├── Procfile
└── package.json

ops/
├── e2e/                            # run-demo.ts, measure-latency.ts, replay.ts
└── docs/                           # runbook.md, latency.md, addresses.md

specs/001-second-wind/              # this feature's artifacts
```

**Structure Decision**: A monorepo with four deployable units (`contracts`, `web`, `api`, `ops`). The contracts are one Foundry project because the three contracts share math, topics, and interfaces, and because a single `forge test` must cover the cross-chain invariants. `web` and `api` are separate because they deploy to different platforms with different build steps. `ops` holds the demo and measurement scripts so neither the web bundle nor the API image ships them.

## Design Decisions That Shape the Build

These are resolved in `research.md`; they are restated here because they determine the task breakdown.

1. **One reactive transaction, two callbacks, one `runId`.** `runId = keccak256(originChainId, txHash, logIndex)` of the `Liquidate` log. Both destinations store it and reject a second use.
2. **Per-branch coverage ceilings (R5).** A policy's `coverageCap` is split once, at creation, into a cash ceiling and a relief ceiling using `reliefShareBps`. Each branch enforces its own ceiling locally. Sum of ceilings equals the cap, so the cap holds without a Base→Lasna reverse message.
3. **Lasna decides, Base re-verifies.** Lasna computes the penalty from `repaidAssets` and the market's LLTV. Base independently re-reads the policy, the Morpho position, and the oracle price, and caps relief by `reliefCeiling - reliefUsed`.
4. **Relief target is chosen on Base.** `HealthMath.weakest` runs where Morpho state lives. Relief stops at `targetHealth` or when the relief limit is spent, whichever is first.
5. **Eligibility is decided once, at a single timestamp.** The payload carries `decidedAt` (Lasna time) and `liquidateBlock` (Base block number), so both branches reach the same premium answer and Base can still honour a claim whose liquidation preceded a cancellation.
6. **No pause, no admin rescue, no upgradeability.** The reactive contract's owner may set each recipient and witness exactly once, then ownership is renounced. Neither destination exposes a withdrawal of committed reserves.

## Delivery Milestones

| Milestone | Scope | Exit criterion |
|-----------|-------|----------------|
| M0 — Loop proof | Official Omni `Hello World` on Base Sepolia origin → Base Sepolia destination; measure one callback | One reactive tx, one callback, measured latency recorded |
| M1 — Base only | `PolicyRegistry`, `CoveragePool`, oracle, market seed, one loan, one policy, one liquidation, relief paid | Relief lands without borrower action; `runId` replay rejected |
| M2 — Two branches | `ClaimVault` on Unichain, second callback from the same reactive tx | Both branches share `runId`; 20 consecutive runs |
| M3 — Product surface | Dashboard, new-cover flow, receipts, `/proof` page, indexer API | A new wallet can buy cover and read a receipt unaided |
| M4 — Demo | Scripted crash, second crash, latency report, video | Under 3 minutes, all hashes visible, p95 stated honestly |

**Gate on M2:** if Unichain does not pass 20 consecutive runs by the end of day 3, ship M1 + a single-destination build and state that clearly. The product still pays in seconds; only the fork view is lost.

## Risks and Fallbacks

| Risk | Likelihood | Mitigation | Fallback |
|------|------------|------------|----------|
| Two-chain callback latency exceeds 5 s p95 | Medium | Measure at M0 before building; tune gas limits; keep payloads small | Single-destination mode: cash and relief both on Base; disclose the change |
| Reactive contract runs out of REACT | Medium | Fund at deploy, expose `coverDebt()`, monitor debt in the API health check | Top up via `depositTo()`; the loop resumes automatically |
| Callback contract accrues ETH debt and stops receiving | Medium | Fund both at deploy; health check reads `debt(address)` and alerts | `depositTo()` through the proxy |
| Real Uniswap swap does not move the mock pool enough | Low | Seed a narrow, deep range; measure the resulting price before the demo | Oracle fallback mode (pool = `address(0)`, admin price) — labelled demo-only in the UI |
| Morpho on Base Sepolia rejects the demo market params | Low | Fork test creates the exact market before the demo | Use a second LLTV already enabled (`0.77`) and re-scale the numbers |
| Cancellation races a claim in flight | Low | Claim carries `liquidateBlock`; Base honours a claim whose liquidation preceded cancellation | Receipt shows a partial settlement with the reason |

## Complexity Tracking

No constitution violations. The table records the two places where the design is deliberately less naive than the minimum, and why the simpler option was rejected.

| Item | Why needed | Simpler alternative rejected because |
|------|------------|--------------------------------------|
| Two destination chains | The product's claim is that one event enforces two settlements on two chains, joined by one `runId`. This is the Integration criterion. | A single-chain payout is a transfer, not a cross-chain product; it also fails the "cash on Unichain" half of the demo. |
| Per-branch coverage ceilings | Removes a reverse Base→Lasna message and keeps every cap check local and testable. | A single shared counter needs the Base branch to report unspent relief back to Lasna, which requires another cross-chain hop, another failure mode, and leaves a window where the cap is over-committed. |
| Demo oracle over a Uniswap V3 spot price | The demo needs a real swap to produce a real liquidation without a Chainlink feed on mock tokens. | A hard-coded price makes the liquidation staged in the wrong sense; a TWAP needs observation history the pool does not have. The oracle is one contract, labelled demo-only, and disclosed in the UI. |
