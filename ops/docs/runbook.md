# Runbook

Operational order for the demo. Anything not written here is described in
[`specs/001-second-wind/quickstart.md`](../../specs/001-second-wind/quickstart.md), which is the
source of truth; this file is the checklist you follow while doing it.

Testnets only: Base Sepolia `84532`, Unichain Sepolia `1301`, Reactive Lasna `5318007`.

## Deploy

Order is forced by two immutable links: each callback contract stores the reactive address, and the
reactive contract stores each recipient.

1. `make -C contracts deploy-base` — `mWETH`, `mUSDC`, `PolicyRegistry` on Base Sepolia.
2. `make -C contracts deploy-reactive` — `SecondWindReactive` on Lasna, funded with `--value` for REACT.
3. `forge script script/DeployBase.s.sol:DeployPool` — `CoveragePool` on Base Sepolia.
4. `make -C contracts deploy-unichain` — `mUSDC` and `ClaimVault` on Unichain Sepolia.
5. `forge script script/Wire.s.sol` (Lasna) then `:WireRegistry` (Base) — one-time setters, then renounce.

After each step, confirm the new addresses landed in [`addresses.md`](./addresses.md) and `ops/addresses.json`.

## Fund

The loop silently stops if either side runs dry.

- Lasna: `SYSTEM.depositTo(secondWindReactive)` with REACT for `react()` execution.
- Base Sepolia: `BASE_CALLBACK_PROXY.depositTo(coveragePool)` with ETH for callback delivery.
- Unichain Sepolia: `UNICHAIN_CALLBACK_PROXY.depositTo(claimVault)` with ETH for callback delivery.

Check: `debt(address)` is `0` on each contract and `reserves(address)` is non-zero.

## Seed

`make -C contracts seed` creates the mock tokens, the Uniswap pool at 2500, the Morpho market
(`lltv = 0.86`), liquidity, and the three loans (A 100/180,000 · B 20/34,000 · B′ 20/34,000), then
funds `CoveragePool` and `ClaimVault` with 250,000 mUSDC each.

Expected: the script prints three health factors, all above `1.0`.

## Demo

1. Create a policy on A and one on B (30-day term). Leave B′ uncovered — it is the control.
2. `make -C contracts crash1` — swap 2500 → 2050, then liquidate A for 90,000.
3. Watch the receipt: Base relief must land while the cash branch is still pending, then both settle
   under one `runId`.
4. Wait `ops/demo.json` delay, then `make -C contracts crash2` — swap 2050 → 1960, liquidate B′ only.
5. B survives, B′ does not.

## Measure

```bash
cd ops && npx tsx e2e/measure-latency.ts --trials 10
```

Records p50, p95, max and trial count per branch into `ops/docs/latency.md`. Set the crash-2 delay from
the measurement: `delay = max(8s, ceil(1.5 × p95))`, written to `ops/demo.json`. Report the measured
numbers; never estimate.

## Recover

| Symptom                                       | Cause                                               | Fix                                                                                          |
| --------------------------------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Reactive tx fires but no callback lands       | Callback contract has no ETH for delivery           | `depositTo` through the callback proxy on that chain                                         |
| `react()` stops firing                        | Reactive contract out of REACT                      | `SYSTEM.depositTo(reactiveContract)` on Lasna                                                |
| Claim stuck `partial` on one branch           | That branch reverted (unfunded, lapsed policy, cap) | Read the reason code in the receipt, fund or top up premium, re-run the demo loan            |
| Oracle price drifted from the script's target | Prior swap moved the pool                           | Re-run `SeedMarket.s.sol` on a fresh market, or use the `pool == address(0)` oracle fallback |
| Second setter call reverts `AlreadySet`       | Owners already renounced                            | Expected; redeploy rather than reuse                                                         |
