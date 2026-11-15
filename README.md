# Second Wind

**Track:** Every Second Counts — Base Sepolia + Unichain Sepolia + Reactive Lasna

When a loan gets liquidated, Second Wind pays the liquidation fee back in about two seconds — and uses part of the money to protect the borrower's next loan.

> This repository is a hackathon demo. It runs on testnets only, with mock assets and a demo oracle. Nothing here is production financial software.

## Chains

| Chain | Chain ID | Role |
|-------|----------|------|
| Base Sepolia | 84532 | Origin chain: Morpho market, `PolicyRegistry`, `CoveragePool` |
| Unichain Sepolia | 1301 | Cash payout destination: `ClaimVault` |
| Reactive Lasna | 5318007 | Watches origin events, computes the split, dispatches both callbacks |

## Status

Setup phase complete. Contracts, API, web, and ops scaffolding are in place; the settlement engine is built in later phases. See [`specs/001-second-wind/`](specs/001-second-wind/) for the spec, plan, and task list, and [`ops/docs/runbook.md`](ops/docs/runbook.md) to deploy and run the demo.

## Layout

```text
contracts/   Foundry project (Base Sepolia, Unichain Sepolia, Reactive Lasna)
web/         React + Vite dashboard and receipt view (Vercel)
api/         Read-only indexer and receipt API (Heroku)
ops/         Deploy evidence, runbook, demo and latency scripts
specs/       Feature specification, plan, contracts, tasks
```

## License

MIT — see [LICENSE](LICENSE).
