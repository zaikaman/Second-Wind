# Quickstart: Prove Second Wind Works

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Date**: 2026-11-15

This is a validation guide, not a tutorial. Follow it in order; each step has an observable outcome. If a step fails, stop — the later steps assume it passed.

---

## 0. Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| Foundry | latest | `forge --version` |
| Node.js | 20 LTS | `node --version` |
| npm | 10+ | `npm --version` |
| git | any | `git --version` |

Testnet funds:

| Chain | What | Where |
|-------|------|-------|
| Base Sepolia (84532) | ETH for deploy, liquidation, oracle swaps | Base Sepolia faucet |
| Unichain Sepolia (1301) | ETH for deploy + callback fees | Unichain Sepolia faucet |
| Reactive Lasna (5318007) | REACT for `react()` execution | Reactive faucet |

Have **three** funded EOAs: `DEPLOYER`, `BORROWER`, `LIQUIDATOR`. Sharing one key works but makes the demo harder to explain.

---

## 1. Configure

```bash
cp .env.example .env
```

```dotenv
# keys (never commit)
DEPLOYER_KEY=0x…
BORROWER_KEY=0x…
LIQUIDATOR_KEY=0x…

# rpc
BASE_SEPOLIA_RPC=https://sepolia.base.org
UNICHAIN_SEPOLIA_RPC=https://sepolia.unichain.org
LASNA_RPC=https://lasna-rpc.rnk.dev/

# fixed addresses
MORPHO=0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb
BASE_CALLBACK_PROXY=0x476F44b11F5C942c58f4c8E3d0300E5710743585
UNICHAIN_CALLBACK_PROXY=0x775c9B990ADe401060B78D0e98684eEf8d2466C1
UNISWAP_V3_FACTORY=0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24
UNISWAP_V3_NPM=0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2
UNISWAP_SWAP_ROUTER=0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4

# app
VITE_API_URL=http://localhost:8080
SUPABASE_URL=…
SUPABASE_SERVICE_KEY=…
ADMIN_TOKEN=…
```

`foundry.toml` must include the Omni remapping:

```toml
remappings = [
  "@reactive/=lib/reactive-lib-omni/",
  "@openzeppelin/=lib/openzeppelin-contracts/",
]
```

---

## 2. Build and test

```bash
cd contracts
forge install foundry-rs/forge-std
forge install Reactive-Network/reactive-lib-omni
forge install OpenZeppelin/openzeppelin-contracts
forge build
forge test -vv
```

**Expected**: all unit and integration tests pass. Fork tests are opt-in:

```bash
forge test --match-path 'test/fork/*' --fork-url $BASE_SEPOLIA_RPC -vv
```

If the fork suite fails on market creation, the LLTV is not enabled for that market — switch to `0.86e18` (already enabled) and re-run before touching any other code.

---

## 3. Deploy in order

The order is forced by two immutable links: each callback contract stores the reactive address, and the reactive contract stores each recipient.

```bash
# 1. registry (Base)
forge script script/DeployBase.s.sol:DeployBase --rpc-url $BASE_SEPOLIA_RPC --broadcast

# 2. reactive contract (Lasna) — needs the registry address
forge script script/DeployReactive.s.sol --rpc-url $LASNA_RPC --broadcast --value 0.5ether

# 3. coverage pool (Base) — needs the reactive address
forge script script/DeployBase.s.sol:DeployPool --rpc-url $BASE_SEPOLIA_RPC --broadcast

# 4. claim vault (Unichain) — needs the reactive address
forge script script/DeployUnichain.s.sol --rpc-url $UNICHAIN_SEPOLIA_RPC --broadcast

# 5. wire one-time setters, then renounce both owners
forge script script/Wire.s.sol:Wire --rpc-url $LASNA_RPC --broadcast
forge script script/Wire.s.sol:WireRegistry --rpc-url $BASE_SEPOLIA_RPC --broadcast
```

**Expected after step 5**:
- `SecondWindReactive.owner() == address(0)`
- `PolicyRegistry.owner() == address(0)`
- `setReliefRecipient` / `setCashRecipient` revert `AlreadySet`
- `PolicyRegistry.coveragePool() == CoveragePool`

Write every address into `ops/docs/addresses.md` as you go. The README and the `/proof` page read from that file.

---

## 4. Fund the three contracts (do not skip)

This is the step that silently breaks the loop later.

```bash
# Reactive contract: REACT for react() execution
cast send $SYSTEM "depositTo(address)" $REACTIVE \
  --value 0.5ether --rpc-url $LASNA_RPC --private-key $DEPLOYER_KEY

# Base callback contract: ETH for callback delivery
cast send $BASE_CALLBACK_PROXY "depositTo(address)" $COVERAGE_POOL \
  --value 0.05ether --rpc-url $BASE_SEPOLIA_RPC --private-key $DEPLOYER_KEY

# Unichain callback contract: ETH for callback delivery
cast send $UNICHAIN_CALLBACK_PROXY "depositTo(address)" $CLAIM_VAULT \
  --value 0.05ether --rpc-url $UNICHAIN_SEPOLIA_RPC --private-key $DEPLOYER_KEY
```

**Expected**: each `debt(address)` returns `0` and each `reserves(address)` returns a non-zero value.

```bash
cast call $SYSTEM "debt(address)(uint256)" $REACTIVE --rpc-url $LASNA_RPC
cast call $BASE_CALLBACK_PROXY "debt(address)(uint256)" $COVERAGE_POOL --rpc-url $BASE_SEPOLIA_RPC
cast call $UNICHAIN_CALLBACK_PROXY "debt(address)(uint256)" $CLAIM_VAULT --rpc-url $UNICHAIN_SEPOLIA_RPC
```

A non-zero debt means the contract receives nothing. Fix it now, not during recording.

---

## 5. Seed the market and the three loans

```bash
forge script script/SeedMarket.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
```

Creates, on Base Sepolia:

1. `mWETH` and `mUSDC` (18 decimals each).
2. A Uniswap V3 `mWETH/mUSDC` pool at price 2500, seeded with a narrow, deep range.
3. A Morpho market with `lltv = 0.86`, `oracle = MorphoV3Oracle(pool)`.
4. Liquidity supplied to Morpho.
5. Three positions:

| Loan | Owner | Collateral | Debt | Health @ 2500 |
|------|-------|------------|------|---------------|
| A | borrower | 100 mWETH | 180,000 mUSDC | 1.1944 |
| B | borrower | 20 mWETH | 34,000 mUSDC | 1.2647 |
| B′ | borrower | 20 mWETH | 34,000 mUSDC | 1.2647 |

6. `mUSDC` reserves: 250,000 to `CoveragePool`, 250,000 to `ClaimVault` (mUSDC is minted separately on each chain).

**Expected**: the script prints all three health factors and asserts each is `> 1.0`.

---

## 6. Create two policies

Through the UI (`/cover/new`), or:

```bash
cast send $REGISTRY \
  "createPolicy(bytes32,uint256,uint16,uint256,address,uint32)" \
  $MARKET_B 5000000000000000000000 6000 1150000000000000000 $BORROWER_UNICHAIN 2592000 \
  --rpc-url $BASE_SEPOLIA_RPC --private-key $BORROWER_KEY
```

(30 days of premium is collected in the same transaction, so the policy is live on creation.)

Create one for **A** and one for **B**. Leave **B′** uncovered — it is the control.

**Expected**:
- Two `PolicyCreated` logs on Base.
- Two `PolicyRegistered` logs on Unichain, from the same reactive contract, within a few seconds.
- `/policies?borrower=…` shows `cashCeiling 2000`, `reliefCeiling 3000`, `paidThrough` 30 days out.

Top up if the demo runs past the term (optional):

```bash
cast send $REGISTRY "payPremium(uint256,uint256)" 1 1000000000000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC --private-key $BORROWER_KEY
```

**Expected**: `PremiumPaid` on Base, and `paidThrough` advances by `amount / premiumPerSecond` seconds.

---

## 7. Run the loop

```bash
# crash 1: swap price 2500 → 2050, then liquidate loan A for 90,000
forge script script/Crash.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast --private-key $LIQUIDATOR_KEY

# crash 2: swap price 2050 → 1960 (after settlement + margin, see §9)
forge script script/Crash.s.sol:Crash2 --rpc-url $BASE_SEPOLIA_RPC --broadcast --private-key $LIQUIDATOR_KEY
```

**Expected after crash 1**:

| Observable | Value |
|------------|-------|
| `Liquidate` on Base | one log, `repaidAssets = 90,000` |
| Reactive tx on Lasna | one tx, two `CallbackRequest` entries |
| CoveragePool | repays 2,367.4 mUSDC on loan B |
| ClaimVault | transfers 1,578.3 mUSDC to the borrower's Unichain address |
| Both branches | same `runId` |
| `GET /claims/:runId` | `status: "settled"`, `totalLatencyMs` under 5000 |
| Loan B health | 1.0371 → 1.1147 |

**Expected after crash 2**:

| Loan | Health @ 1960 | Outcome |
|------|---------------|---------|
| B (covered, relieved) | 1.0657 | survives |
| B′ (control) | 0.9915 | liquidated |
| A | 1.0145 | survives |

That is SC-004: one covered loan survives the exact move that liquidates an identical uncovered loan.

---

## 8. Prove the invariants (the acceptance run)

```bash
# 8.1 Replay: same runId, 1,000 times, both branches
forge test --match-test test_1000Replays_PayOnce -vv

# 8.2 One branch delayed or failing; the other must still settle
forge test --match-test test_OneBranchFails_OtherStillSettles -vv

# 8.3 Cancel then liquidate: nothing pays
cast send $REGISTRY "cancelPolicy(uint256)" 2 --rpc-url $BASE_SEPOLIA_RPC --private-key $BORROWER_KEY
forge script script/Crash.s.sol:Crash3 --rpc-url $BASE_SEPOLIA_RPC --broadcast
cast call $CLAIM_VAULT "cashPaidOf(uint256)(uint256)" 2 --rpc-url $UNICHAIN_SEPOLIA_RPC
# expected: unchanged from before the crash

# 8.4 Cap: a claim larger than remaining capacity pays only the remainder
forge test --match-test test_Relief_CappedByCeiling -vv

# 8.5 No operator withdrawal path exists
cast call $COVERAGE_POOL "owner()(address)" --rpc-url $BASE_SEPOLIA_RPC
# expected: revert or 0x0 — the function should not exist at all
```

---

## 9. Measure latency honestly

```bash
cd ops
npm install
npx tsx e2e/measure-latency.ts --trials 10
```

Each trial: reset price, liquidate a fresh loan, wait for both branches, record latency from origin block time to destination block time. Writes `ops/docs/latency.md`.

**Report all four numbers** — p50, p95, max, trials — on the `/proof` page and in the video. Do not round down or drop a slow trial.

**Set the demo's crash-2 delay** from the measurement, not from hope:

```
delay = max(8s, ceil(1.5 × measured p95))
```

With a measured p95 of 3.4 s that is 8 s. The video can still show B′ liquidated seconds after B is saved; the claim "before the next liquidation" is then true by construction, and the measured number is the one shown on screen.

---

## 10. Ship

```bash
# web → Vercel
cd web && npm run build && vercel --prod

# api → Heroku
cd api && git push heroku main
```

**Expected**: `GET https://<app>.herokuapp.com/health` returns `status: "ok"` with all three `funding.*.ok` true, and the Vercel deployment can create a policy and read a receipt.

---

## 11. Acceptance checklist

| Check | Pass condition | Spec link |
|-------|----------------|-----------|
| Automatic payout | One liquidation produces a cash transfer with no borrower transaction | FR-010, SC-001 |
| Two branches, one id | Both receipts share `runId`, from one reactive tx | FR-010 |
| Cascade relief | Covered loan B survives; uncovered twin B′ does not | SC-004 |
| Cap | No branch ever pays past its ceiling | FR-015 |
| Replay | 1,000 duplicate deliveries, one payment | FR-011, SC-003 |
| Lapse | Lapsed premium pays nothing, with a reason | FR-002, FR-016 |
| Cancel | Cancel stops future claims, keeps past ones | FR-014 |
| Isolation | One branch failing never marks the other failed or complete | FR-017, FR-019 |
| Latency | p50 ≤ 3 s, p95 ≤ 5 s over ≥ 10 trials | SC-001, SC-002 |
| No operator power | No withdrawal, no pause, no term edit, owners renounced | FR-018, SC-010 |

If any row fails, the build is not done — regardless of how good the video looks.
