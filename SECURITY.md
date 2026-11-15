# Security

## This is a testnet demo

Second Wind runs on **Base Sepolia (84532)**, **Unichain Sepolia (1301)**, and **Reactive Lasna (5318007)** only. It never touches mainnet.

Everything it moves is a **mock asset**: `mWETH` and `mUSDC` are minted by demo scripts and have no value. The price feed is a single Uniswap V3 pool read (`MorphoV3Oracle`), not a production oracle, and it is labelled demo-only in the UI.

## What that means for reports

- Do not use this code, or any address it deploys, to custody real funds.
- "Mock tokens are worth nothing" is expected behaviour, not a bug.
- The insurance economics are illustrative, not actuarial.

## Reporting a real issue

If you find a bug in the contracts, the API, or the web app, open a GitHub issue with:

1. The chain and contract address (or the commit hash) involved.
2. The transaction hash or request that reproduces it.
3. What you expected versus what happened.

Please do not exploit a bug against a deployment you do not own. There is no bug bounty; there are also no real assets.
