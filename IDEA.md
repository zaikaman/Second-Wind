# Second Wind

**Track:** Every Second Counts
**Chain:** Base Sepolia + Unichain Sepolia + Reactive Lasna
**One line:** When a loan gets liquidated, Second Wind pays the fee back in about 2 seconds — and uses part of the money to protect the borrower's next loan.

---

## 1. The problem

You borrow money and leave crypto as a promise to pay. If the price falls, the protocol sells your crypto. It also takes a fee for doing it. At Morpho with 86% LLTV, that fee is **4.38%** of the debt. On $90,000, that is **$3,945** gone.

It gets worse. The forced sale moves the price, so your **other** loans get closer to the same edge. A few seconds later, they can be sold too. Nobody sells insurance for this, and no one can file a claim in seconds at 3am.

## 2. What it does

Second Wind is insurance for the liquidation fee. You pay a small amount per day. If you are liquidated, it pays automatically in about 2 seconds:

- **40% cash** to your wallet on Unichain
- **60% debt relief** on your weakest loan on Base

The second part is the point. A smaller debt has more room before the next sale. Your next loan survives.

If you have only one loan, the relief goes back into that same loan. Two loans is a demo choice, not a rule.

## 3. Example

| Step | What happens |
|---|---|
| Start | Bob: 100 mWETH collateral, $180,000 debt, HF 1.19 |
| Crash | Price $2,500 → $2,050 |
| Sale | Liquidator repays $90,000, seizes 45.83 mWETH, Bob pays **$3,945** fee |
| 2s later | Second Wind sends **$1,578 cash** to Bob on Unichain |
| 2s later | Second Wind repays **$2,367** of Bob's second loan on Base |
| 6s later | Price falls again. Twin loan (no cover) is sold. Bob's second loan survives. |

Fee formula (Morpho constants): `LIF = min(1.15, 1 / (1 - 0.3 * (1 - lltv)))`. At 86% LLTV, LIF = 1.04384.

## 4. Why Reactive is needed

- The event is on **Base**. The cash is on **Unichain**. The rule cannot live on either chain alone.
- The party that owes the payout is the **pool**, and a pool has every reason to pay slowly. So the payout must be **enforced by a contract**, not trusted to a server.
- One Lasna transaction produces **two callbacks** on two chains, joined by one `runId`.
- No server, no hot wallet, no keeper. The rule is public and auditable.

## 5. Loop

1. Real Uniswap V3 swap moves the price. Morpho emits `Liquidate`.
2. Lasna decodes the event, matches the policy, computes the fee, splits it, dedupes by `runId`.
3. Two callbacks from one transaction:
   - Base → `CoveragePool.settleCascade` → repay debt on the weakest position
   - Unichain → `ClaimVault.payClaim` → pay the cash share
4. Indexer joins both branches by `runId`. UI shows the fork and the receipt.

## 6. Contracts

| Contract | Chain | Job |
|---|---|---|
| `PolicyRegistry` | Base | create / pay / cancel policy, emit events |
| `CoveragePool` | Base | hold reserves, repay debt on behalf of the borrower |
| `ClaimVault` | Unichain | hold reserves, pay the cash share, enforce caps |
| `MorphoV3Oracle` | Base | Morpho oracle reading a Uniswap V3 pool (demo harness) |
| `SecondWindReactive` | Lasna | mirror policies, compute fee, split, dispatch two callbacks |

Both destinations accept calls only from their callback proxy, only from the recorded guardian, and only once per `runId`. Base re-reads Morpho and the oracle; it never trusts Lasna's numbers.

## 7. Demo (under 3 minutes)

1. Two identical loans: **B** (covered) and **B′** (not covered).
2. Crash. A third loan is liquidated. The fee receipt appears.
3. One Lasna transaction lights up two branches. Base repays debt. Unichain pays cash.
4. Crash 2. **B survives. B′ is liquidated.** Same crash, same blocks.
5. Latency: p50 ~2.4s for both branches. The payout lands seconds before B′ crosses the line.

## 8. Known risks

- **Two chains is the main risk.** Build Base first. Add Unichain only if it works 20 runs in a row.
- **Insurance economics** are illustrative, not actuarial. Cap coverage, disclose the pricing model.
- **Single-pool oracle** is a demo harness. Production needs Chainlink/Pyth + TWAP.
- **The crash is staged** (as in every demo). The liquidation, the fee, the repayments, and both callbacks are real.

## 9. Field note (Nov 15, 2026)

23 builds on DoraHacks. **No liquidation or lending product.** Most common: stop-loss / take-profit (7). Three builds already claim 1–2s speed, so speed alone does not win. Second Wind is the only insurance build and the only one that pays after the event.

## 10. Next step

Day 1: deploy the official Reactive basic demo on Base Sepolia + Lasna and measure the loop. Then confirm that one `Liquidate` log produces one Lasna log with two `Callback` logs.
