# Deployed Addresses

> **Do not edit by hand.** Written by the deploy scripts (`contracts/script/*.s.sol`) through
> `Json.s.sol`, which also updates `ops/addresses.json`. Hand edits are overwritten on the next deploy
> and cannot be matched against a commit.

Testnets only: Base Sepolia `84532`, Unichain Sepolia `1301`, Reactive Lasna `5318007`.
All assets are mocks and worth nothing.

Cycle 3, recorded 2026-11-16. The addresses below are the live set used by `ops/addresses.json`, the
API, and the web app. The transaction column comes from `contracts/broadcast/`; `Json.s.sol` currently
writes the JSON address book only, so this table is transcribed from both sources until the script gap
is closed.

## Base Sepolia (84532)

| Contract         | Address                                      | Deployed in tx                                                                                   |
| ---------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `mWETH`          | `0xB547F81A71913053F954aD9488701285ec78A0AA` | [`0xc2a9493c`](https://sepolia.basescan.org/tx/0xc2a9493c1867d911d36c580d0b5cd5369708d27fca85523251f90eb548d202a2) |
| `mUSDC`          | `0x0593BB352B8505Fe3B55cB05f0bf0cbd2236ca2d` | [`0x9f8a4cde`](https://sepolia.basescan.org/tx/0x9f8a4cde523fe8b453f56ca7c8896fde4edb58178da46c739df59cf043753844) |
| `PolicyRegistry` | `0x2E741106500c595ec308fe0EeeF8A7f311a23F8C` | [`0x6d28fafa`](https://sepolia.basescan.org/tx/0x6d28fafae277892a8fa0ebf1b74ca0b641a0858ef73f396835675213bcaf263b) |
| `CoveragePool`   | `0xb14CFFaE677078353F878EF365CFFECE6A52F143` | [`0x77d54bda`](https://sepolia.basescan.org/tx/0x77d54bdad85d90307c2598caa0f49cd190425822372a63797d4cf8bf942179ff) |
| `UniswapV3Pool`  | `0x889507e13541c42d93ECD3b88872c4a6905Dd795` | created by `SeedMarket.s.sol`                                                                     |
| `MorphoV3Oracle` | `0x379b9eFC75EB3CDFf62953ff08C28827D6b481c1` | [`0x6e05bb1a`](https://sepolia.basescan.org/tx/0x6e05bb1a26bfb5f7be308d2ec22093e4b843b849de6aa264d6af7c0e6c0caa33) |
| Morpho market id | `0x436c8831b1a98b563b0d8b700b0ed2284ee525815c52edf075fdac59779104d5` | created by `SeedMarket.s.sol`                                     |

## Unichain Sepolia (1301)

| Contract     | Address                                      | Deployed in tx                                                                                   |
| ------------ | -------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `mUSDC`      | `0x8F1ee89106D38d2BD72c3463A5b9B293C0367Be7` | [`0x7d4a9542`](https://sepolia.uniscan.xyz/tx/0x7d4a9542a8c672e296185a7afe51f300ad35cbb0fa68ba006db6fef12a5fe37a) |
| `ClaimVault` | `0x9ab39cfE0836ecE969C9988DE8183965B9350010` | [`0xa95f5be8`](https://sepolia.uniscan.xyz/tx/0xa95f5be8368310bc02c924e90bc7278950b1826518702950e6932e8a0e28f1f4) |

## Reactive Lasna (5318007)

| Contract             | Address                                      | Deployed in tx                                                                                   |
| -------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `SecondWindReactive` | `0x56Ec8ee8c1693508dEC7a08876831f1cCd2e0286` | [`0x8caa692f`](https://lasna.reactscan.net/tx/0x8caa692fdac9aea63b33f9b5e21670a9d3019972c76f1810f1c819285d2ca9df) |

The reactive deployment tx carries six subscription logs from the system contract
`0x8888...8888`, one per event: five on chain 84532 (three registry events, `Liquidate` on Morpho Blue,
`ReliefApplied`) and one on chain 1301 (`ClaimPaid`). Each log names the watched contract and the
`topic0` filter, with the remaining topics set to the wildcard value used by `REACTIVE_IGNORE`.

## Fixed infrastructure (not deployed by this repo)

| Name                        | Chain            | Address                                      |
| --------------------------- | ---------------- | -------------------------------------------- |
| Morpho Blue                 | Base Sepolia     | `0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb` |
| Callback proxy              | Base Sepolia     | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` |
| Callback proxy              | Unichain Sepolia | `0x775c9B990ADe401060B78D0e98684eEf8d2466C1` |
| Uniswap V3 factory          | Base Sepolia     | `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24` |
| Uniswap V3 position manager | Base Sepolia     | `0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2` |
| Uniswap SwapRouter02        | Base Sepolia     | `0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4` |
