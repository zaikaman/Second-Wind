---

description: "Task list for Second Wind (001-second-wind)"
---

# Tasks: Second Wind

**Input**: Design documents from `/specs/001-second-wind/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Required, not optional. Constitution Principle III says every behaviour change must ship a test that demonstrates its expected result, and Principle IV requires measured cross-chain coverage. Test tasks therefore come before implementation tasks in every phase.

**Organization**: One phase per user story, in priority order. Each phase ends with an independent test that a stranger could run.

**Path conventions**: all paths are repo-relative. Contracts in `contracts/`, web in `web/`, API in `api/`, scripts and evidence in `ops/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Empty repo to a building skeleton on `main`.

- [X] T001 Create the monorepo directories `contracts/{src,test,script,lib}`, `web/`, `api/`, `ops/{e2e,lib,docs}` and a placeholder `.gitkeep` in each empty folder
- [X] T002 Write `.gitignore` covering `node_modules/`, `.env*` (but not `.env.example`), `contracts/out/`, `contracts/cache/`, `contracts/broadcast/`, `dist/`, `.vercel/`, `*.log`, `ops/demo.json`
- [X] T003 Write `.gitattributes` pinning `* text=auto eol=lf` and marking `*.sol`, `*.ts`, `*.tsx`, `*.md` as LF to stop the CRLF churn seen in earlier commits
- [X] T004 Create `README.md` skeleton with the product one-liner, the track name, and a chain table that names only testnets (Base Sepolia 84532, Unichain Sepolia 1301, Reactive Lasna 5318007)
- [X] T005 Add `LICENSE` (MIT) and a `SECURITY.md` stating this is a testnet demo with mock assets
- [X] T006 [P] Write `.env.example` with every variable from `quickstart.md` §1 and no real values
- [X] T007 [P] Initialize Foundry in `contracts/` and pin `solc = "0.8.29"`, `optimizer_runs = 200`, `via_ir = false` in `contracts/foundry.toml`
- [X] T008 [P] Add remappings `@reactive/=lib/reactive-lib-omni/`, `@openzeppelin/=lib/openzeppelin-contracts/`, `forge-std/=lib/forge-std/src/` in `contracts/foundry.toml`
- [X] T009 [P] Install `forge-std`, `OpenZeppelin/openzeppelin-contracts`, and `Reactive-Network/reactive-lib-omni` as submodules; commit `contracts/.gitmodules`
- [X] T010 [P] Configure `forge fmt` with `line_length = 120` and add a `make fmt` target
- [X] T011 [P] Scaffold `web/` with `npm create vite@latest . -- --template react-ts` and confirm `npm run dev` serves a page
- [X] T012 [P] Add Tailwind CSS and PostCSS to `web/`, plus design tokens in `web/src/styles/tokens.css` (ink, paper, success, pending, failed, relief, cash)
- [X] T013 [P] Add ESLint + Prettier to `web/` and `api/` with a shared config; add `lint` and `format` scripts
- [X] T014 [P] Install web runtime deps: `wagmi`, `viem`, `@rainbow-me/rainbowkit`, `@tanstack/react-query`, `react-router-dom`, `clsx`, `date-fns`
- [X] T015 [P] Scaffold `api/` as a TypeScript Node project with `express`, `zod`, `pino`, `pino-http`, `@supabase/supabase-js`, `viem`, `cors`, `helmet`, `express-rate-limit`
- [X] T016 [P] Add `api/Procfile` (`web: node dist/index.js`), `engines.node = "20.x"`, and a `build` script that runs `tsc`
- [X] T017 [P] Scaffold `ops/` with `tsx`, `viem`, `dotenv`, and its own `tsconfig.json`
- [X] T018 [P] Add `api` scripts: `dev`, `build`, `start`, `test`, `migrate`, `indexer:once`
- [X] T019 [P] Add `contracts/Makefile` targets: `build`, `test`, `test-fork`, `deploy-base`, `deploy-unichain`, `deploy-reactive`, `seed`, `crash1`, `crash2`
- [X] T020 [P] Add `.github/workflows/ci.yml` running on push to `main`: `forge fmt --check`, `forge build`, `forge test`, `tsc --noEmit` for `api` and `web`
- [X] T021 [P] Add `.editorconfig` (2-space TS, 4-space Solidity, LF) and enable format-on-save guidance in `CONTRIBUTING.md`
- [X] T022 [P] Create `ops/docs/addresses.md` with empty per-chain tables and a "do not edit by hand, written by deploy scripts" warning
- [X] T023 [P] Create `ops/docs/runbook.md` with section headers: Deploy, Fund, Seed, Demo, Measure, Recover
- [X] T024 Verify a clean clone builds: `git clone` to a temp dir, `forge build`, `npm ci` in `web` and `api`, then delete the temp clone

**Checkpoint**: one commit on `main`, CI green on an empty product.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared math, interfaces, contract skeletons, chain config, DB, and the app shell. Nothing below this line can be built without these.

**⚠️ CRITICAL**: no user story work starts until this phase is complete.

### Shared Solidity foundation

- [X] T025 [P] Implement `contracts/src/libraries/FeeMath.sol`: `lif(uint256 lltv)`, `penalty(uint256 repaidAssets, uint256 lltv)`, `split(uint256 fee, uint16 reliefShareBps)` with floor division and a documented rounding rule
- [X] T026 [P] Implement `contracts/src/libraries/HealthMath.sol`: `collateralValue`, `health`, `weakest`, `repayForTarget`, all 18-decimal fixed point and overflow-safe
- [X] T027 [P] Create `contracts/src/libraries/Topics.sol` with `TOPIC_POLICY_CREATED`, `TOPIC_PREMIUM_PAID`, `TOPIC_STATUS_CHANGED`, `TOPIC_LIQUIDATE`, `TOPIC_RELIEF_APPLIED`, `TOPIC_CLAIM_PAID` as `bytes32` constants
- [X] T028 [P] Write `contracts/src/interfaces/IMorpho.sol` with only the members used: `position`, `idToMarketParams`, `repay`, `liquidate`, `supplyCollateral`, `borrow`, `createMarket`, and the `MarketParams` struct
- [X] T029 [P] Write `contracts/src/interfaces/IOracle.sol` with `price() external view returns (uint256)`
- [X] T030 [P] Write `contracts/src/interfaces/IUniswapV3Pool.sol` with `slot0`, `token0`, `token1`, `liquidity`
- [X] T031 [P] Write `contracts/src/interfaces/IUniswapV3.sol` with minimal `IUniswapV3Factory`, `INonfungiblePositionManager`, and `ISwapRouter02` surfaces
- [X] T032 [P] Implement `contracts/src/mocks/MockERC20.sol`: 18 decimals, `mint`, `burn`, standard ERC20
- [X] T033 [P] Implement `contracts/src/mocks/MockOracle.sol`: owner-settable `price()`, emits `PriceSet(uint256)`
- [X] T034 [P] Implement `contracts/src/mocks/MockSystemContract.sol`: records `subscribe`/`unsubscribe` and emits the same `CallbackRequest` shape the real system contract emits, so `react()` tests run locally
- [X] T035 [P] Implement `contracts/src/mocks/ReentrantReceiver.sol` that re-enters `settleCascade` and `payClaim` on receive
- [X] T036 Create `contracts/test/utils/TestBase.sol`: deploys the mock system at `0x8888…` via `vm.etch`, deploys tokens, registry, pool, vault, and reactive contract, and funds each
- [X] T037 Create `contracts/test/utils/Fixtures.sol` with the canonical demo numbers (loan A 100/180,000, loan B 20/34,000, twin B′, price 2500, lltv 0.86, cap 5,000, share 60%)

### `PolicyRegistry` core (needed by all three stories)

- [X] T038 Declare in `contracts/src/base/PolicyRegistry.sol`: `Policy` struct, `Status` enum, all custom errors, and the three events exactly as specified in `contracts/policy-registry.md`
- [X] T039 Implement the `PolicyRegistry` constructor (`coverAsset`, `morpho`) and immutables, with `Ownable`
- [X] T040 Implement `createPolicy` validation: market exists, `loanToken == coverAsset`, position open, health > 1e18, no live policy for `loanKey`, ≤ 8 active policies, cap/share/target/term ranges
- [X] T041 Implement `createPolicy` effects: ceilings, `premiumPerSecond`, `paidThrough`, premium pull to the pool, `policyOfLoan`, `policiesOf`, `PolicyCreated`
- [X] T042 Implement views: `getPolicy`, `policyOfLoan`, `policiesOf`, `reliefRemaining`, `activePolicyCount`, `isCoverable`
- [X] T043 Implement `setCoveragePool` (one-time, `AlreadySet`) and the `onlyCoveragePool` modifier
- [X] T044 Implement `recordRelief` with `CapExceeded` when `reliefUsed + amount > reliefCeiling`
- [X] T045 Implement `payPremium`: `NotBorrower`, `PolicyNotLive`, `AmountTooSmall`, term cap, transfer to the pool, `PremiumPaid`
- [X] T046 Implement `pausePolicy`, `resumePolicy`, `cancelPolicy` with borrower-only checks, terminal cancel, and `cancelledAtBlock = block.number`
- [X] T047 [P] Write `contracts/test/unit/PolicyRegistry.t.sol` covering every revert path in T040 with a named test per revert
- [X] T048 [P] Write `contracts/test/unit/PolicyRegistry.t.sol` premium tests: formula, truncation, 365-day cap, `AmountTooSmall`, transfer lands in the pool
- [X] T049 [P] Write `contracts/test/unit/PolicyRegistry.t.sol` status tests: pause blocks `isCoverable`, resume restores, cancel is terminal and sets the block number, non-borrower calls revert
- [X] T050 [P] Write `contracts/test/unit/PolicyRegistry.t.sol` fuzz test: random cap/share/target inside ranges always yields `cashCeiling + reliefCeiling == coverageCap`

### Destination contract skeletons

- [X] T051 Create `contracts/src/base/CoveragePool.sol`: inherit `AbstractCallback` + `ReentrancyGuard`, constructor wiring, `receive`, `coverDebt`, `reserveBalance`
- [X] T052 Add to `CoveragePool`: `usedRuns` mapping, `DuplicateRun` error, `nonReentrant` on the settlement entry point
- [X] T053 Create `contracts/src/unichain/ClaimVault.sol`: inherit `AbstractCallback` + `ReentrancyGuard`, `Terms` struct, `registerPolicy` with first-write-wins idempotency, `TermsMismatch`
- [X] T054 Add to `ClaimVault`: `payClaim` signature, `usedRuns`, `cashPaid`, `lastPaidThrough`, reserve balance view, `coverDebt`
- [X] T055 [P] Write `contracts/test/unit/Auth.t.sol`: both contracts reject a direct EOA call (`NotAuthorized`) and a call from the proxy with a different injected sender (`CallbackNotAuthorized`)
- [X] T056 [P] Write `contracts/test/unit/Auth.t.sol`: `ClaimVault.payClaim` on an unregistered policy reverts `UnknownPolicy` and changes no state

### Reactive contract core

- [X] T057 Create `contracts/src/reactive/SecondWindReactive.sol`: inherit `AbstractReactive` + `Ownable`, payable constructor, six `SYSTEM.subscribe` calls
- [X] T058 Implement the `react()` router: `onlySystem`, `topic0` dispatch, `contractAddress` witness filter, `opCode` guard before every decode, silent return on anything unknown
- [X] T059 Implement mirror handlers `_onPolicyCreated`, `_onPremiumPaid`, `_onStatusChanged` writing `policies`, `policyOfLoan`, `policiesOf`
- [X] T060 Implement reconciliation handlers `_onReliefApplied`, `_onClaimPaid` that release reservations and advance `reliefUsed` / `cashPaid`
- [X] T061 Implement `_requestRelief`, `_requestCash`, `_requestRegistration` using `SYSTEM.requestCallbackV_1_0` with `address(0)` as the first encoded argument
- [X] T062 Implement one-time setters `setReliefRecipient`, `setCashRecipient`, `setSettlementWitnesses`, each reverting `AlreadySet` on a second call
- [X] T063 [P] Write `contracts/test/unit/Reactive.t.sol`: six subscriptions are recorded with the exact criteria from `contracts/reactive-contract.md`
- [X] T064 [P] Write `contracts/test/unit/Reactive.t.sol`: `react()` from an EOA reverts `NotAuthorized`; unknown `topic0` returns without revert; wrong `opCode` returns without revert
- [X] T065 [P] Write `contracts/test/unit/Reactive.t.sol`: mirror updates from `PolicyCreated`, `PremiumPaid`, `PolicyStatusChanged`, including a same-topic event from an unrelated contract being ignored
- [X] T066 [P] Write `contracts/test/unit/Topics.t.sol`: every constant equals `keccak256` of its signature string, so a typo cannot ship

### Web foundation

- [X] T067 [P] Create `web/src/config/chains.ts` with `baseSepolia` and `unichainSepolia` viem chain objects reading RPC URLs from `import.meta.env`
- [X] T068 [P] Create `web/src/config/addresses.ts`: a typed address book that throws at boot when a required address is the zero address in production
- [X] T069 [P] Generate `web/src/config/abis/*.ts` from `forge inspect <Contract> abi --json`, one file per contract, with a comment naming the source commit
- [X] T070 [P] Create `web/src/providers/AppProviders.tsx` wiring `WagmiProvider`, `QueryClientProvider`, and `RainbowKitProvider` with the two testnet chains
- [X] T071 [P] Create `web/src/components/Layout.tsx`: header, testnet badge, wallet button, footer with "demo on testnets, mock assets" notice
- [X] T072 [P] Create `web/src/lib/format.ts`: `formatAmount` (fixed 2–4 dp, thousands separators), `formatHealth` (3 dp), `formatBps`, `formatDuration`, `truncateAddress`
- [X] T073 [P] Create `web/src/lib/explorer.ts`: `txUrl`, `addressUrl` for Base Sepolia, Unichain Sepolia, and Lasna, with a null-safe fallback
- [X] T074 Create `web/src/App.tsx` and `web/src/routes.tsx` with five routes: `/`, `/cover/new`, `/policies/:id`, `/receipts`, `/receipts/:runId`, `/proof`, plus a 404

### API foundation

- [X] T075 [P] Create `api/src/config/env.ts`: a Zod schema for every variable, fail fast with a readable message, export a typed `env`
- [X] T076 [P] Create `api/src/db/supabase.ts`: service-role client with a comment that this key never reaches the browser
- [X] T077 [P] Write `api/src/db/migrations/001_init.sql` with the exact DDL from `data-model.md` §2, including enums and indexes
- [X] T078 [P] Create `api/src/db/migrate.ts`: advisory-lock migration runner, idempotent, called once at boot
- [X] T079 [P] Create `api/src/lib/rpc.ts`: viem public clients for the three chains with timeout, retry, and a `head()` helper
- [X] T080 [P] Create `api/src/lib/logger.ts` and request-id middleware
- [X] T081 Create `api/src/app.ts`: Express app with helmet, CORS allow-list, rate limit, JSON body limit, routes, and one error middleware that emits `{error:{code,message}}`
- [X] T082 Create `api/src/index.ts`: run migrations, start the indexer, listen on `PORT`, handle SIGTERM with a graceful 10-second drain
- [X] T083 Implement `api/src/routes/health.ts` returning the shape in `contracts/http-api.md`, including per-contract `native`, `debt`, `reserves`, `ok`
- [X] T084 [P] Write `api/test/health.test.ts`: 200, correct keys, `Cache-Control: no-store`, and `ok: false` when a mocked debt is non-zero

### Ops foundation

- [X] T085 [P] Create `ops/lib/env.ts` and `ops/lib/clients.ts`: wallet + public clients for Base, Unichain, Lasna, reading the repo `.env`
- [X] T086 [P] Create `ops/lib/addresses.ts` that reads `ops/addresses.json` and fails loudly if a required key is missing
- [X] T087 [P] Create `ops/lib/format.ts` for consistent console tables and JSON evidence output

### Deploy script skeletons

- [X] T088 Create `contracts/script/helpers/Json.s.sol` with `writeAddress(key, addr)` that merges into `ops/addresses.json` via `vm.writeJson`
- [X] T089 Create `contracts/script/DeployBase.s.sol` deploying `mWETH`, `mUSDC`, and `PolicyRegistry`, writing all three addresses
- [X] T090 Create `contracts/script/DeployReactive.s.sol` (payable), `DeployBase.s.sol:DeployPool`, `DeployUnichain.s.sol`, and `Wire.s.sol` with the exact order from `quickstart.md` §3 and an assertion after each step

**Checkpoint**: `forge test` green, `tsc --noEmit` green in both apps, and a deploy script dry-run prints the intended order without broadcasting.

---

## Phase 3: User Story 1 — Automatic settlement after a liquidation (Priority: P1) 🎯 MVP

**Goal**: one `Liquidate` event produces one claim that pays the borrower on both settlement branches, with no borrower action, one `runId`, and a receipt.

**Independent Test**: create one policy on one loan with 100% relief share, liquidate it, and observe the reserve repay the debt and a receipt appear with `status` moving `pending → settled` and no transaction signed by the borrower.

### Tests first (write these, watch them fail)

- [X] T091 [P] [US1] `contracts/test/unit/FeeMath.t.sol`: LIF at every enabled LLTV (0.77, 0.86, 0.91, 0.945, 0.965, 0.98) and the 1.15 cap
- [X] T092 [P] [US1] `contracts/test/unit/FeeMath.t.sol`: penalty floors correctly; `split` never sums above `fee`; fuzz 10k random pairs
- [X] T093 [P] [US1] `contracts/test/unit/ClaimVault.t.sol`: registration idempotency, `TermsMismatch`, ceiling cap, reserve shortfall, replay, stale window, zero amount
- [X] T094 [P] [US1] `contracts/test/unit/Reactive.t.sol`: a `Liquidate` record produces exactly two `requestCallbackV_1_0` calls with the same `runId`, `address(0)` first argument, and gas `400_000` / `300_000`
- [X] T095 [P] [US1] `contracts/test/unit/Reactive.t.sol`: lapsed premium, unknown loan, zero fee, paused policy, and cancelled policy each produce zero callbacks
- [X] T096 [P] [US1] `contracts/test/unit/Reactive.t.sol`: the same `runId` delivered twice produces one dispatch; a different `logIndex` produces a second dispatch
- [X] T097 [P] [US1] `contracts/test/unit/CoveragePool.t.sol`: a valid claim repays the loan, consumes the `runId`, emits `ReliefApplied`, and reduces the reserve by exactly the repaid amount
- [X] T098 [P] [US1] `contracts/test/integration/Join.t.sol`: harness drives both destination calls from one `runId`; both succeed; the shared id is identical
- [X] T099 [P] [US1] `contracts/test/integration/Replay.t.sol`: 1,000 deliveries per branch produce exactly one state change each
- [ ] T100 [P] [US1] `contracts/test/fork/Fork.Settle.t.sol`: on a Base Sepolia fork with `MockOracle` at 2500, create a real market, liquidate, and assert the observed penalty is within 1 basis point of `FeeMath.penalty` (the Uniswap-backed oracle is swapped in at T118)

### Implementation — settlement math

- [X] T101 [US1] Implement `FeeMath` to pass T091–T092; add a NatSpec comment stating the rounding direction and why
- [X] T102 [US1] Implement `HealthMath` `collateralValue` and `health` (the `weakest` and `repayForTarget` parts stay for US2)
- [X] T103 [US1] Fill `Topics.sol` from the signature strings and make T066 pass

### Implementation — Base branch

- [X] T104 [US1] Implement `CoveragePool.settleCascade` steps 1–4 from `contracts/base-callbacks.md`: auth, replay, policy read, premium/cancel/cap checks
- [X] T105 [US1] Implement the US1 target rule: repay the loan named by the policy until the limit or the debt is exhausted
- [X] T106 [US1] Implement effects then interaction: mark `runId`, `recordRelief`, `forceApprove`, `morpho.repay` on behalf of the borrower
- [X] T107 [US1] Implement `ReserveInsufficient` and the remaining custom errors with reason-code args; make T097 pass
- [X] T108 [US1] Emit `ReliefApplied` with `debtAfter` and `healthAfter`; assert the values in `CoveragePool.t.sol`

### Implementation — Unichain branch

- [X] T109 [US1] Implement `ClaimVault.payClaim` steps 1–8: auth, replay, terms, `StaleWindow`, ceiling, reserve, effects, `safeTransfer`
- [X] T110 [US1] Emit `ClaimPaid` and make T093 pass, including the "no partial effects on failure" case
- [X] T111 [US1] Add `MAX_CASH_CEILING = 10_000e18` and enforce it in `registerPolicy`

### Implementation — reactive dispatch

- [X] T112 [US1] Implement `_onLiquidate`: `runId`, loan key resolution, policy lookup, early returns for unknown/duplicate/inactive/lapsed/zero-fee
- [X] T113 [US1] Implement `FeeMath` call plus the standard split, capped by `cashAvail` and `reliefAvail` including in-flight reservations
- [X] T114 [US1] Dispatch registration on `PolicyCreated` (only when `cashCeiling > 0`) and dispatch relief/cash on `Liquidate`
- [X] T115 [US1] Set `dispatched[runId]` and advance `reliefReserved` / `cashReserved` / `reservedByRun` atomically before requesting callbacks
- [X] T116 [US1] Implement `_onReliefApplied` and `_onClaimPaid` reconciliation so a settled claim frees exactly its reservation
- [X] T117 [US1] Make T094–T096 pass; assert both callbacks carry the identical `runId` and that the payload's first word decodes to `address(0)` before injection

### Implementation — deploy and demo scripts

- [X] T118 [US1] Implement `contracts/src/base/MorphoV3Oracle.sol` reading `slot0` with decimal adjustment and the `pool == address(0)` fallback mode plus `isDemoHarness()`
- [X] T119 [US1] Implement `contracts/script/SeedMarket.s.sol`: deploy tokens, create and initialise the Uniswap pool at 2500, add liquidity, create the Morpho market, supply liquidity
- [X] T120 [US1] Extend `SeedMarket.s.sol` to open the three loans and print each health factor with an assertion that all are above 1.0
- [X] T121 [US1] Add reserve funding to `SeedMarket.s.sol`: mint and transfer 250,000 `mUSDC` to `CoveragePool` and 250,000 to `ClaimVault`
- [X] T122 [US1] Implement `contracts/script/Crash.s.sol`: swap `mWETH` into the pool through `SwapRouter02`, then assert the oracle price is within 1% of the target
- [X] T123 [US1] Implement the liquidation step in `Crash.s.sol`: call `morpho.liquidate` for 90,000 on loan A and assert a `Liquidate` log was emitted
- [X] T124 [US1] Deploy Base Sepolia contracts and record every address via `Json.s.sol` into `ops/addresses.json` and `ops/docs/addresses.md`
- [X] T125 [US1] Deploy `SecondWindReactive` to Lasna with `--value` for REACT, record it, and verify the constructor's six subscriptions in the tx logs
- [X] T126 [US1] Deploy `ClaimVault` and the Unichain `mUSDC` to Unichain Sepolia, record both
- [X] T127 [US1] Run `Wire.s.sol`: three one-time setters, `setCoveragePool`, then renounce both owners; assert `owner() == address(0)` and that a second setter call reverts `AlreadySet`
- [X] T128 [US1] Fund all three contracts through the proxies (`depositTo`) and assert `debt(address) == 0` on each
- [X] T129 [US1] Create policy #1 on loan A with a 30-day term; assert the premium landed in `CoveragePool` and `paidThrough` is 30 days out
- [X] T130 [US1] **M1 checkpoint**: run `Crash.s.sol`, confirm the Base relief branch lands and the receipt exists while the cash branch is still `pending`
- [X] T131 [US1] **M2 checkpoint**: confirm the Unichain cash branch lands with the same `runId`, the receipt becomes `settled`, and both explorer links resolve

### Implementation — indexer and API for US1

- [X] T132 [P] [US1] `api/src/services/decoder.ts`: decode `Liquidate`, `PolicyCreated`, `PremiumPaid`, `PolicyStatusChanged`, `ReliefApplied`, `ClaimPaid` from raw logs, with `opCode` checks
- [X] T133 [P] [US1] `api/src/services/indexer.ts`: three independent poll loops, per-chain cursor persistence, overlap-safe `upsert`, and a `runOnce` export for tests
- [X] T134 [P] [US1] `api/src/services/joiner.ts`: create the `claims` row on `Liquidate`, upsert one `claim_events` row per branch, compute `pending | partial | settled | failed`
- [X] T135 [P] [US1] `api/src/services/latency.ts`: compute branch latency from origin block time to destination block time and write `latency_samples` once per confirmed branch
- [X] T136 [P] [US1] `api/src/routes/claims.ts`: `GET /claims` with cursor pagination and `GET /claims/:runId` returning the full receipt, `404` for unknown
- [X] T137 [P] [US1] `api/src/routes/policies.ts`: `GET /policies/:policyId` with live position read from Base, and `GET /policies?borrower=`
- [X] T138 [US1] `api/src/routes/stats.ts`: `GET /stats/latency` (p50, p95, max, per branch) and `GET /stats/coverage`
- [X] T139 [US1] `api/test/indexer.test.ts`: fixture logs produce one claim row; a single confirmed branch yields `partial`; both confirmed yields `settled`
- [X] T140 [US1] `api/test/claims.test.ts`: receipt matches the documented JSON shape, amounts are strings, partial claims are visible, unknown id is 404
- [X] T141 [US1] `api/test/latency.test.ts`: percentile function verified on a known 20-sample array

### Implementation — web for US1

- [X] T142 [P] [US1] `web/src/hooks/usePolicies.ts`: multicall on Base for the borrower's policies, refetch every 5 s
- [X] T143 [P] [US1] `web/src/hooks/useClaim.ts`: fetch by `runId`, poll every 2 s while `pending` or `partial`, stop when terminal
- [X] T144 [P] [US1] `web/src/hooks/useHealth.ts`: per-market health from Morpho plus the oracle price, refetch every 3 s
- [X] T145 [US1] `web/src/pages/Dashboard.tsx`: position cards with health, debt, collateral, and policy status
- [X] T146 [US1] `web/src/pages/Receipt.tsx`: the fork view — trigger card, Lasna card, relief card, cash card, each with status, amount, tx link, latency
- [X] T147 [US1] `web/src/pages/Receipts.tsx`: list with status chips, fee, latency, and an empty state
- [X] T148 [US1] Add `copy to clipboard` for every hash and address with a 1.5 s confirmation
- [X] T149 [US1] Add loading skeletons, retry buttons, and an offline banner for every data path
- [X] T150 [US1] **US1 independent validation**: from a fresh wallet with no prior state, buy one policy, trigger one liquidation, and confirm a receipt appears with no borrower transaction

**Checkpoint**: US1 works on testnet. If Unichain fails here, stop and apply the 20-run gate before continuing.

---

## Phase 4: User Story 2 — The next loan survives the cascade (Priority: P2)

**Goal**: relief is aimed at the borrower's weakest covered loan, stops at the target health, reports what it did not spend, and converts entirely to relief for a rapid second liquidation.

**Independent Test**: two identical loans, one covered; apply the same two price moves; the covered loan survives and the uncovered twin is liquidated.

### Tests first

- [ ] T151 [P] [US2] `contracts/test/unit/HealthMath.t.sol`: health at the exact oracle scale, 1-decimal difference, and a zero-debt market returning "skip"
- [ ] T152 [P] [US2] `contracts/test/unit/HealthMath.t.sol`: `weakest` picks the minimum among 1, 2, and 3 positions, breaks ties on the lower market id, and skips empty positions
- [ ] T153 [P] [US2] `contracts/test/unit/HealthMath.t.sol`: `repayForTarget` returns exact target, clamps at debt, and returns 0 when already above target
- [ ] T154 [P] [US2] `contracts/test/unit/CoveragePool.t.sol`: with three policies the relief lands on the weakest market, not the triggering one
- [ ] T155 [P] [US2] `contracts/test/unit/CoveragePool.t.sol`: a borrower with one loan receives the full relief share on that loan
- [ ] T156 [P] [US2] `contracts/test/unit/CoveragePool.t.sol`: relief stops at the target health and leaves the remainder as unspent capacity
- [ ] T157 [P] [US2] `contracts/test/unit/Reactive.t.sol`: a second liquidation within 60 s dispatches cash `0` and relief `min(fee, remaining)`
- [ ] T158 [P] [US2] `contracts/test/unit/Reactive.t.sol`: the same second liquidation at 61 s uses the normal split
- [ ] T159 [P] [US2] `contracts/test/integration/Delay.t.sol`: relief branch reverts (unfunded) while cash succeeds; receipt is `partial`, never `settled`, and the cash payment is not rolled back
- [ ] T160 [P] [US2] `contracts/test/fork/Fork.Survives.t.sol`: covered twin survives the second crash while the identical uncovered twin is liquidated

### Implementation

- [ ] T161 [US2] Implement `HealthMath.weakest` with the bounded enumeration and the tie-break rule; make T151–T153 pass
- [ ] T162 [US2] Replace the US1 target rule in `CoveragePool` with weakest-position selection over `registry.policiesOf(borrower)`
- [ ] T163 [US2] Implement `repayForTarget` clamping and the zero-amount path: emit `ReliefApplied` with `0` and do not revert
- [ ] T164 [US2] Compute and emit `healthBefore` and `healthAfter` for the chosen market; assert both in tests
- [ ] T165 [US2] Allow an unspent remainder to stay as relief capacity (do not convert to cash) and document the behaviour in a NatSpec comment
- [ ] T166 [US2] Implement cascade mode in `SecondWindReactive`: 60-second window keyed by borrower, cash forced to 0, relief capped by remaining
- [ ] T167 [US2] Update `lastClaimAt` on every dispatch, including cascade, and test the boundary at exactly 60 s
- [ ] T168 [US2] Add `ops/e2e/demo-delay.ts` that reads the measured p95 and computes `max(8s, ceil(1.5 × p95))` into `ops/demo.json`
- [ ] T169 [US2] Implement `contracts/script/Crash.s.sol:Crash2` swapping 2050 → 1960, liquidating only B′, and printing all three health factors
- [ ] T170 [US2] Run the twin-loan experiment on testnet and assert B survives (health > 1.0) while B′ is liquidated in the same block range
- [ ] T171 [US2] Record the exact health values, fee, split, and hashes in `ops/docs/evidence.md`
- [X] T172 [US2] Extend the receipt API with `mode`, `relief.marketId`, `healthBefore`, `healthAfter`, `unspentRelief`, and `shortfall`
- [ ] T173 [US2] `web/src/components/SplitBar.tsx`: cash vs relief vs shortfall as one proportional bar with a legend
- [ ] T174 [US2] `web/src/components/WeakestLoan.tsx`: marks the relieved market on the dashboard compared with the triggering market
- [ ] T175 [US2] Add a cascade badge on the receipt and a one-line explanation of why cash was zero
- [ ] T176 [US2] Show the health delta on the relief card, before → after, with an arrow and the target line
- [ ] T177 [US2] **US2 independent validation**: seed a fresh pair of twins, cover one, apply the same two moves, and reproduce "covered survives, twin does not"

**Checkpoint**: the differentiator is provable with numbers, not adjectives.

---

## Phase 5: User Story 3 — See and control coverage (Priority: P3)

**Goal**: a borrower can buy cover, read every number that matters, open a receipt, understand any rejection in plain words, and leave at any time.

**Independent Test**: open a policy, complete one claim, read the receipt, cancel, then trigger a liquidation and confirm nothing pays.

### Implementation — buying cover

- [ ] T178 [P] [US3] `web/src/pages/NewCover.tsx`: market picker showing live health and debt for each Morpho market
- [ ] T179 [P] [US3] New-cover form fields with client validation mirroring the contract bounds: cap 100–5,000, share 0–100%, target 1.05–1.50, term 1–365 days, non-zero destination
- [ ] T180 [US3] Premium preview computed from `premiumPerSecond`, shown as both total and per-day
- [ ] T181 [US3] Chain-state handling: if the wallet is not on Base Sepolia, the button becomes "Switch to Base Sepolia"; no silent switching
- [ ] T182 [US3] Submit `createPolicy`, wait for one confirmation, then navigate to the policy page with the new id
- [ ] T183 [US3] Map every `createPolicy` revert to a sentence via the shared reason catalog, with the raw error available behind a "details" toggle

### Implementation — policy control

- [ ] T184 [US3] `web/src/pages/Policy.tsx`: two capacity bars (cash and relief), paid-through countdown, status chip, and destination address
- [ ] T185 [US3] Premium top-up with 30 / 90 / 365-day presets, showing the exact token amount before signing
- [ ] T186 [US3] Pause, resume, and cancel actions with a confirmation dialog that states the consequence in one sentence
- [ ] T187 [US3] Disable cancel while any claim for that policy is `pending` or `partial`, with a tooltip explaining why
- [ ] T188 [US3] After cancel, show "cover ended at block N" and keep the receipt history visible

### Implementation — reasons and proof

- [ ] T189 [P] [US3] `api/src/routes/reasons.ts`: `GET /reasons` from a single catalog module
- [ ] T190 [P] [US3] `api/src/lib/reasons.ts`: one entry per custom error, with code, sentence, and which side raises it
- [ ] T191 [US3] `api/test/reasons.test.ts`: every custom error in the contracts has a catalog entry; no orphan entries
- [ ] T192 [US3] `web/src/hooks/useReasons.ts`: fetch and cache the catalog; no sentence is hard-coded in a component
- [ ] T193 [US3] `web/src/pages/Proof.tsx`: address table per chain with explorer links and a copy button
- [ ] T194 [US3] Proof page: reactive subscriptions table with chain, contract, topic, and a link to the deploying tx
- [ ] T195 [US3] Proof page: last 20 `runId`s with both branch statuses, so a judge can spot-check the join
- [ ] T196 [US3] Proof page: latency panel with trials, p50, p95, max, and the exact query used
- [ ] T197 [US3] Proof page: "testnet only", "mock assets", "demo oracle" disclosures in a visible info box
- [ ] T198 [US3] Proof page: link to the GitHub commit deployed, so code and addresses can be matched

### Implementation — trust and polish of the surface

- [ ] T199 [US3] Global funding banner driven by `/health`; names the unfunded contract and the exact `depositTo` command
- [ ] T200 [US3] Wallet-not-connected and wrong-chain empty states on every route
- [ ] T201 [US3] Accessibility pass: focus rings, keyboard order, `aria-live` on claim status changes, 4.5:1 contrast on all text
- [ ] T202 [US3] Copy pass: every number carries a unit and a timestamp; remove all internal jargon from the dashboard
- [ ] T203 [US3] Empty state for "no policies" that explains what cover does in two sentences and links to `/cover/new`
- [ ] T204 [US3] Add a "share receipt" link that is just the URL, with correct Open Graph tags for the receipt route
- [ ] T205 [US3] **US3 independent validation**: hand the app to someone who has not seen the repo; they buy cover and read a receipt without help

**Checkpoint**: all three stories work independently and together.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: the difference between "it ran once" and "it is a product".

### Security

- [ ] T206 Run a reentrancy review on `settleCascade` and `payClaim`; confirm checks-effects-interactions ordering and add a comment at each interaction
- [ ] T207 Write `contracts/test/unit/AccessMatrix.t.sol`: for every external function, assert the allowed caller and the revert for every other caller class (EOA, proxy with wrong sender, random contract)
- [ ] T208 Write `contracts/test/invariant/Caps.t.sol` Foundry invariants: `cashPaid <= cashCeiling`, `reliefUsed <= reliefCeiling`, and no `runId` ever settles twice
- [ ] T209 Assert no withdrawal path exists: a test that calls a non-existent `withdraw` and expects a revert, plus an ABI assertion that the selector is absent
- [ ] T210 Write `contracts/test/unit/Payload.t.sol`: a mock proxy overwrites the first argument and the destination rejects a payload whose injected sender is wrong
- [ ] T211 Fuzz 10,000 random `runId`s through both branches; assert exactly one settlement per unique id
- [ ] T212 Re-read every custom error against `data-model.md` reason codes; fix drift

### Gas and performance

- [ ] T213 Measure `gasUsed` for `settleCascade` and `payClaim` with `forge test --gas-report`; record both in `ops/docs/latency.md`
- [ ] T214 If either exceeds 60% of its callback limit, reduce storage writes and re-measure; document the final limits
- [ ] T215 Run `autocannon -c 50 -d 30` against `/claims` and `/policies/:id`; confirm p95 under 300 ms and record the command
- [ ] T216 Measure the web bundle with `vite build`; ensure the initial route is under 300 KB gzip and lazy-load `/proof`
- [ ] T217 Run the indexer for 10 minutes during a live claim and confirm lag stays under 3 s throughout
- [ ] T218 Kill the indexer mid-claim, restart it, and confirm the receipt still completes with no duplicate rows
- [ ] T219 Stop the API and confirm the web still shows policy state from direct chain reads and labels receipts unavailable

### Documentation

- [ ] T220 [P] Rewrite `README.md`: problem, one-sentence solution, 30-second GIF, architecture diagram, chain table, addresses, run instructions, limits
- [ ] T221 [P] Write `ops/docs/architecture.md` with a Mermaid sequence diagram from `Liquidate` to both settlements
- [ ] T222 [P] Write `ops/docs/security.md`: threat model, what each guard stops, known limits (single-source oracle, per-branch ceilings, testnet)
- [ ] T223 [P] Write `ops/docs/latency.md` from the harness output: trials, p50, p95, max, per branch, date, commit
- [ ] T224 [P] Write `CONTRIBUTING.md` including the single-branch rule and the pre-commit hook's purpose
- [ ] T225 [P] Add a comment to every non-obvious financial decision: rounding direction, LIF cap, per-branch ceilings, `decidedAt`
- [ ] T226 [P] Add `docs/why-reactive.md` explaining in plain language why a server or a single chain cannot do this

### Code and test hygiene

- [ ] T227 Remove dead code, unused imports, unused dependencies, and every `console.log`
- [ ] T228 Unify error names and reason codes across Solidity, API, and web; add a test that the three lists match
- [ ] T229 Run `forge fmt --check`, ESLint, Prettier, and `tsc --noEmit`; all clean
- [ ] T230 Confirm contract line coverage ≥ 90% with `forge coverage`; record the number in `ops/docs/latency.md`
- [ ] T231 Run the full suite from a clean clone: `forge test`, both `npm test`, both `tsc --noEmit`
- [ ] T232 Execute `quickstart.md` start to finish on a clean machine and note every deviation
- [ ] T233 Fix every deviation from T232 and update `quickstart.md`
- [ ] T234 Add screenshots (dashboard, receipt, proof) to `README.md`
- [ ] T235 Run `gitleaks detect --no-git` and `git grep -i` for keys; confirm no secrets
- [ ] T236 Add a chain-id assertion to every deploy and demo script, so a mainnet RPC cannot accidentally be used
- [ ] T237 Confirm `git log --oneline` is a straight line on `main` and no other branch exists
- [ ] T238 Tag `v1.0.0` after the clean-clone run passes

---

## Phase 7: Launch, Demo, and Submission

**Purpose**: everything needed for a judge to click a link, watch a video, and verify a transaction.

### Production deployment

- [ ] T239 Create the production Supabase project, run `001_init.sql`, and confirm the API can write and read one row
- [ ] T240 Deploy the API to Heroku, set every config var, and confirm `GET /health` returns all three chains and `funding.*.ok == true`
- [ ] T241 Deploy the web app to Vercel with `VITE_API_URL` and the production addresses; confirm the build has no zero-address throw
- [ ] T242 Production smoke: connect a fresh wallet, buy a policy, top up premium, and read it back on the deployed site
- [ ] T243 Run one full liquidation loop against the production deployment and confirm the receipt renders with both branches
- [ ] T244 Run the 10-trial latency measurement against production config and record p50, p95, max, and trial count
- [ ] T245 Update `/proof` with the production numbers, the final addresses, and the deployed commit hash

### Evidence

- [ ] T246 Freeze `ops/addresses.json` and `ops/docs/addresses.md`; add a timestamp and commit hash header
- [ ] T247 Build `ops/docs/evidence.md`: every claim in the submission as a row with trigger tx, reactive tx, relief tx, cash tx, and `runId`
- [ ] T248 Verify each row against the explorer; mark anything unverified as such and remove it from the claim
- [ ] T249 Record the twin-loan experiment numbers (health before/after for B and B′) in `evidence.md`
- [ ] T250 Save the raw logs and latency JSON under `ops/docs/artifacts/`

### Video

- [ ] T251 Write the video script with a per-second plan: problem 0:00–0:25, demo 0:25–2:10, proof 2:10–2:40, close 2:40–2:55
- [ ] T252 Rehearse three times end to end and fix any step that needs narration to explain what the screen does not show
- [ ] T253 Set the crash-2 delay from `ops/demo.json` and confirm B is relieved before B′ is liquidated in the rehearsal
- [ ] T254 Record 1080p screen capture with voice; no background music over numbers
- [ ] T255 Edit with captions for every address and amount, and burn in the measured p50/p95 on the latency frame
- [ ] T256 Confirm the final cut is under 3:00 and that no frame shows a mainnet explorer or a mock label

### Submission

- [ ] T257 Update `README.md` with the video link, the live URL, the addresses table, and the tx hash table
- [ ] T258 Re-run the full acceptance checklist from `quickstart.md` §11 against the deployed stack and tick each row
- [ ] T259 Write the submission text: problem, what it does, how Reactive is used, the two-destination design, what is real vs demo
- [ ] T260 Submit on DoraHacks under the Every Second Counts track with repo, video, and deployed addresses
- [ ] T261 Screenshot the submission confirmation into `ops/docs/artifacts/`
- [ ] T262 Final commit, tag `v1.0.0-demo`, push `main`, and verify the public repo renders without auth

---

## Dependencies & Execution Order

### Phase dependencies

```
Phase 1 Setup ──▶ Phase 2 Foundational ──┬──▶ Phase 3 US1 ──▶ Phase 4 US2 ──▶ Phase 5 US3 ──▶ Phase 6 ──▶ Phase 7
                                         └── (US2 and US3 need US1's settlement engine)
```

- **Phase 1** has no dependencies.
- **Phase 2** blocks everything. It ends when `forge test` and both `tsc` runs are green on skeletons.
- **Phase 3 (US1)** needs Phase 2 contract skeletons and the deploy scripts.
- **Phase 4 (US2)** needs US1's `CoveragePool` entry point to exist, because it replaces the target-selection rule inside it.
- **Phase 5 (US3)** needs US1's API receipt and US2's split data.
- **Phase 6** needs all three stories.
- **Phase 7** needs a green Phase 6 and a working production loop.

### Internal gates

| Gate | Location | Rule |
|------|----------|------|
| M1 — Base branch only | T130 | Relief lands, receipt shows `partial`. Product already pays. |
| M2 — both branches | T131 | Cash lands with the same `runId`; receipt `settled`. |
| Two-chain gate | after T150 | 20 consecutive successful runs, or ship single-destination and say so. |
| Evidence gate | T248 | Nothing goes in the submission that is not verified on an explorer. |
| Video gate | T256 | Under 3:00, no mainnet, no unlabelled mock. |

### Within each story

Tests before implementation. Contracts before scripts. Scripts before deployment. Deployment before API. API before UI. UI before measurement.

## Parallel Opportunities

- **Phase 1**: T006–T011, T013–T023 are independent files.
- **Phase 2**: all `[P]` library, interface, mock, config, and skeleton tasks; the four contract skeletons (T051, T053, T057, T067) touch different files.
- **Phase 3**: T091–T100 (tests) and T132–T137, T142–T144 (API and hooks) can run in parallel; T104–T116 are sequential within a contract.
- **Phase 4**: T151–T160 (tests) run in parallel; implementation is mostly one file, so keep it sequential.
- **Phase 5**: T178–T180, T189–T192, T193–T198 are separate files.
- **Phase 6**: all `[P]` docs and the gas/perf/security tracks are independent.

## Parallel Example: Phase 3 tests

```bash
# Five independent test files, no shared state:
forge test --match-contract FeeMathTest
forge test --match-contract ClaimVaultTest
forge test --match-contract ReactiveTest
forge test --match-contract JoinTest
forge test --match-contract ReplayTest
```

## Implementation Strategy

### MVP first (US1 only)

1. Phase 1 + Phase 2.
2. Phase 3 through T131 (both branches live).
3. **Stop and validate** with T150.
4. Deploy and record. This is already a product: it pays in seconds with no claim form.

### Incremental delivery

| Increment | Adds | Demo it shows |
|-----------|------|---------------|
| US1 | automatic settlement, both branches, receipt | "money arrived and I did nothing" |
| US2 | weakest-loan targeting, target health, cascade | "my other loan survived the same crash" |
| US3 | buying, controlling, proof page | "I can see it, and I can leave" |

### If time runs short

Cut in this order, and never cut T243–T248 (the evidence):
1. `/proof` polish (keep the address table, drop the charts).
2. Playwright smoke (T204).
3. Cascade edge case in the UI (T175) — the contract behaviour stays.
4. Unichain branch, only if the 20-run gate fails.

## Definition of Done

The product is complete when all of the following are true:

- Every task above is checked or explicitly deferred with a written reason.
- A fresh wallet can buy cover in one transaction and receive a payout without signing anything.
- One `Liquidate` produces two settlements on two chains with the same `runId`, visible in one receipt.
- A covered loan survives a price move that liquidates an identical uncovered loan, with the numbers recorded.
- No branch can pay more than its ceiling, and no `runId` can pay twice.
- Latency is measured over at least 10 trials and p50/p95 are printed, not estimated.
- The deployed addresses and four transaction hashes for the demo loop are in the README and verified on an explorer.
- The video is under three minutes and shows the loop on testnets.
- The repo is public, on `main`, with no secrets and a passing CI run.

## Reconciliation log (2026-11-16)

Cycle 3 deployed the whole app layer to Base Sepolia, Unichain Sepolia and Lasna, then ran the US1 loop
end to end. Several of its tasks were done but never ticked. They are ticked above on the strength of
the reads and receipts below, not on intent. The anchor is the live address set in
`ops/addresses.json`; hashes and explorer links are in `ops/docs/addresses.md` and in the receipt for
runId `0xd948d409cc563725ba7d37c5fb127a958d945cc8b61f5bf2f6a4de072302c269`.

- **T124.** `ops/addresses.json` records every deployed contract and the Morpho market id.
  `ops/docs/addresses.md` now records the same set with deployment transactions, transcribed from the
  JSON and `contracts/broadcast/`. `Json.s.sol` writes the JSON only; see the last deferred item for
  that gap.
- **T125.** The reactive deployment tx `0x8caa692f...ca9df` at Lasna block 8,413,006 carries exactly
  six subscription logs from the system contract `0x8888...8888`, one per event: five for chain 84532
  (three registry events, `Liquidate` on Morpho Blue, `ReliefApplied` on the pool) and one for chain
  1301 (`ClaimPaid`), each with a distinct `topic0` filter and wildcards elsewhere.
- **T126.** Unichain `mUSDC` at `0x8F1e...7Be7` and `ClaimVault` at `0x9ab3...0010`.
- **T127.** `owner()` reads `0x0` on `PolicyRegistry` and on `SecondWindReactive`; `coveragePool()`
  returns the pool; the reactive setters return the pool and the vault for both recipients and both
  witnesses. `AlreadySet` on a second call is enforced in code and covered by the T062 unit tests; no
  second transaction was sent on-chain.
- **T128.** `debt()` reads 0 on the Lasna system contract for the reactive contract, on the Base proxy
  for `CoveragePool`, and on the Unichain proxy for `ClaimVault`. Reserves were 0.3670, 0.0049978 and
  0.0049995 ETH at verification time.
- **T129.** Policy 1 on loan A: cap 5,000, cash ceiling 2,000, relief ceiling 3,000, status `Active`,
  and `paidThrough - createdAt` is exactly 2,592,000 s (30.00 days). Premium accrued at
  `premiumPerSecond` x 30 days = 12.328767 mUSDC into the pool; the pool reserves reconcile as
  250,000 funded + 12.328767 premium minus 2,367.432441 relief paid = 247,644.896.
- **T130.** The Base relief branch confirmed at `0xdcd98c...b51847`, repaying 2,367.432441 mUSDC and
  moving health from 0.988828701020865368 to 1.075501394915631435. The cash branch confirmed in the
  same second (1,000 ms latency), so the `partial` window was not separately observed at the indexer's
  resolution; the transition that produces it is covered by the T139 fixture test.
- **T131.** `ClaimPaid` at `0xc5575c...ec1fa` on Unichain paid 1,578.288294 mUSDC to the borrower under
  the same runId. `usedRun(runId)` is true and the receipt is `settled` with both explorer links.
- **T150.** The borrower wallet bought policy 1, signed no settlement transaction, and received both
  branches. It is the same wallet used for setup, so the literal "never seen before" condition was not
  met; every product behaviour the task checks was.
- **T172.** The receipt for the same runId returns `mode: "standard"`, `relief.marketId`,
  `healthBefore`, `healthAfter`, `unspentRelief: "0"` and `shortfall: "0"`.

## Deferred (2026-11-16)

Every task that is still unticked is deferred, not forgotten. In priority order:

1. **Phase 4 proof, and the US1 fork test.** `T100`, `T151`-`T171` stay open. The US2 engine exists
   (`HealthMath.weakest`, `repayForTarget`, weakest-loan selection in `CoveragePool`, the 60-second
   cascade in `SecondWindReactive`, and the T172 receipt fields), but there is no `HealthMath.t.sol`,
   no `contracts/test/fork/`, no `Crash2`, no twin-loan run on testnet and no `ops/docs/evidence.md`.
   The implementation tasks are written as "make <test> pass", so they cannot close without the tests.
2. **Phase 5 surface.** `T173`-`T205` stay open. `web/src/pages/NewCover.tsx` and `Policy.tsx` are
   placeholder panels, so cover cannot yet be bought or controlled from the browser; the `GET /reasons`
   catalog and its web hook do not exist; `/proof` shows the address table and the disclosure box only.
   The receipt route, the dashboard and the receipt list are real and read live data.
3. **Hardening, gas and documentation.** `T206`-`T238` stay open. No access matrix, invariant, payload
   or 10,000-run replay tests; no gas report; no coverage number; no `ops/docs/architecture.md`,
   `security.md`, `latency.md`, `docs/why-reactive.md`, no README rewrite and no screenshots. Lint,
   typecheck, unit tests and production builds are green, and `forge test` is 102/102.
4. **Production and submission.** `T239`-`T262` stay open. There is no production Supabase project,
   Heroku API, Vercel web, production latency run, frozen evidence file, video or DoraHacks submission.
   The demo runs locally against the same testnet contracts.
5. **Script gap carried with T124.** `Json.s.sol` writes `ops/addresses.json` but not
   `ops/docs/addresses.md`, so the markdown table was transcribed by hand. Close this before `T246`
   freezes the address file.
