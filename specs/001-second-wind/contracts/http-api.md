# Interface Contract: HTTP API (Node.js on Heroku)

**Base URL**: `https://<app>.herokuapp.com` (demo), `http://localhost:8080` (local)
**Consumer**: the React SPA only. No third-party consumers, no public write endpoints.
**Source of truth**: chain. Every field here is derived; the database can be wiped and rebuilt.

All responses are `application/json; charset=utf-8`. All amounts are **decimal strings in token units** (`"3945.704"`), never JSON numbers, so JavaScript cannot lose precision. All timestamps are ISO-8601 UTC.

---

## Common shapes

### Error

```json
{ "error": { "code": "NOT_FOUND", "message": "No claim with that runId." } }
```

| HTTP | `code` | When |
|------|--------|------|
| 400 | `BAD_REQUEST` | Zod validation failed |
| 404 | `NOT_FOUND` | Unknown policy or claim |
| 409 | `STALE_CURSOR` | Cursor from a schema version the server no longer serves |
| 429 | `RATE_LIMITED` | 60 requests/minute per IP |
| 503 | `INDEXER_LAG` | Chain head is more than 60 s ahead of the cursor |

### `GET /health`

Always 200 while the process is alive. Used by Heroku and by the UI banner.

```json
{
  "status": "ok",
  "version": "1.4.2",
  "chains": {
    "base":     { "chainId": 84532,  "head": 34120998, "indexed": 34120996, "lagBlocks": 2 },
    "unichain": { "chainId": 1301,   "head": 18821402, "indexed": 18821400, "lagBlocks": 2 },
    "reactive": { "chainId": 5318007,"head": 9021144,  "indexed": 9021144,  "lagBlocks": 0 }
  },
  "funding": {
    "reactive":     { "native": "0.42", "debt": "0", "reserves": "0.10", "ok": true },
    "coveragePool": { "native": "0.031", "debt": "0", "reserves": "0.02", "ok": true },
    "claimVault":   { "native": "0.028", "debt": "0", "reserves": "0.02", "ok": true }
  },
  "lastIndexedAt": "2026-11-15T09:41:02Z"
}
```

`funding.*.ok` is `debt == "0"`. When any is false, the UI shows a red banner naming the contract — this is the failure mode that most often kills a working demo between rehearsal and recording.

---

## `GET /policies/:policyId`

```json
{
  "policyId": "7",
  "borrower": "0x9a1f…",
  "marketId": "0x3c2b…",
  "market": { "collateral": "mWETH", "loan": "mUSDC", "lltv": "0.86" },
  "coverageCap": "5000.0",
  "cashCeiling": "2000.0",
  "reliefCeiling": "3000.0",
  "reliefUsed": "2367.4",
  "cashPaid": "1578.3",
  "reliefRemaining": "632.6",
  "cashRemaining": "421.7",
  "reliefShare": "0.60",
  "premiumPerSecond": "0.000004756",
  "premiumApr": "0.03",
  "paidThrough": "2026-12-15T00:00:00Z",
  "premiumActive": true,
  "targetHealth": "1.15",
  "cashDestination": "0x77be…",
  "status": "active",
  "createdAt": "2026-11-15T08:02:11Z",
  "position": {
    "collateral": "100.0",
    "debt": "90000.0",
    "health": "1.0612",
    "liquidatable": false
  }
}
```

`position` is read live from Base on request (not cached), so the dashboard cannot show a stale health factor during a crash. If the RPC read fails, the field is `null` and the HTTP response is still 200 — a stale number is worse than a missing one.

## `GET /policies?borrower=0x…`

Returns `{ "policies": [ …summary objects… ] }`, newest first. Summary omits `position`.

---

## `GET /claims?borrower=0x…&limit=20&cursor=…`

```json
{
  "claims": [
    {
      "runId": "0x8f2c…",
      "policyId": "7",
      "status": "settled",
      "fee": "3945.704",
      "mode": "standard",
      "triggeredAt": "2026-11-15T09:31:12Z",
      "settledAt": "2026-11-15T09:31:14Z",
      "totalLatencyMs": 2410
    }
  ],
  "nextCursor": null
}
```

`status` is `pending | partial | settled | failed` and is computed from the branch rows, never stored independently (FR-017).

---

## `GET /claims/:runId`

The receipt. This is the endpoint the demo video shows.

```json
{
  "runId": "0x8f2c…",
  "policyId": "7",
  "borrower": "0x9a1f…",
  "status": "settled",
  "trigger": {
    "chainId": 84532,
    "txHash": "0x41aa…",
    "blockNumber": 34120877,
    "blockTime": "2026-11-15T09:31:12Z",
    "logIndex": 14,
    "explorer": "https://sepolia.basescan.org/tx/0x41aa…"
  },
  "reactive": {
    "txHash": "0x77c1…",
    "blockNumber": 9021099,
    "blockTime": "2026-11-15T09:31:13Z",
    "explorer": "https://lasna.reactscan.net/tx/0x77c1…"
  },
  "fee": "3945.704",
  "split": {
    "mode": "standard",
    "reliefLimit": "2367.422",
    "cashLimit": "1578.281",
    "shortfall": "0.0"
  },
  "branches": {
    "relief": {
      "chainId": 84532,
      "status": "confirmed",
      "txHash": "0x9d02…",
      "blockTime": "2026-11-15T09:31:14Z",
      "amount": "2367.422",
      "marketId": "0x8b11…",
      "healthBefore": "1.0371",
      "healthAfter": "1.1147",
      "latencyMs": 2180,
      "explorer": "https://sepolia.basescan.org/tx/0x9d02…"
    },
    "cash": {
      "chainId": 1301,
      "status": "confirmed",
      "txHash": "0x3fe0…",
      "blockTime": "2026-11-15T09:31:14Z",
      "amount": "1578.281",
      "destination": "0x77be…",
      "latencyMs": 2410,
      "explorer": "https://sepolia.uniscan.xyz/tx/0x3fe0…"
    }
  },
  "unspentRelief": "0.0",
  "failure": null,
  "totalLatencyMs": 2410
}
```

Partial case: one branch `confirmed`, the other `failed` with `failure: { "code": "DESTINATION_UNDERFUNDED", "message": "The cash reserve does not hold enough to pay this claim." }`. The `status` is `partial`, and the UI shows which half landed rather than a spinner (FR-019).

---

## `GET /stats/latency?trials=20`

```json
{
  "trials": 20,
  "from": "2026-11-15T09:00:00Z",
  "to": "2026-11-15T10:00:00Z",
  "overall": { "p50": 2380, "p95": 3410, "max": 4120 },
  "byBranch": {
    "relief": { "p50": 2180, "p95": 3120, "max": 3900, "count": 20 },
    "cash":   { "p50": 2410, "p95": 3410, "max": 4120, "count": 20 }
  },
  "samples": [
    { "runId": "0x8f2c…", "branch": "cash", "trial": 1, "latencyMs": 2410 }
  ]
}
```

Latency is measured from the **origin block timestamp** to the **destination block timestamp** of the confirming transaction. Not from an API receipt time, which would measure the indexer rather than the product. The `/proof` page prints the query used so a judge can reproduce it.

## `GET /stats/coverage`

```json
{
  "policies": 2,
  "claims": 1,
  "premiumCollected": "24.66",
  "cashPaid": "1578.281",
  "reliefApplied": "2367.422",
  "reserveBase": "250000.0",
  "reserveUnichain": "250000.0",
  "branchCeilings": { "cash": "2000.0", "relief": "3000.0" }
}
```

## `GET /reasons`

The plain-language catalog, so the frontend never hard-codes sentences and every rejection reason is testable in one place (SC-007).

```json
{
  "PREMIUM_LAPSED": "The premium was not paid for this period.",
  "COVERAGE_EXHAUSTED": "The remaining cover is smaller than this claim.",
  "UNKNOWN_LOAN": "No open loan was found for this policy.",
  "DUPLICATE_DELIVERY": "This liquidation was already settled.",
  "DESTINATION_UNDERFUNDED": "The reserve does not hold enough to pay this claim.",
  "POLICY_CANCELLED": "Cover was cancelled before the liquidation.",
  "POLICY_PAUSED": "Cover was paused when the claim arrived.",
  "ZERO_FEE": "The liquidation penalty rounded to zero.",
  "TERMS_MISMATCH": "The policy terms on this chain do not match the claim."
}
```

---

## `POST /internal/reindex`

Header: `Authorization: Bearer $ADMIN_TOKEN`. Body: `{ "chainId": 84532, "fromBlock": 34120000 }`.
Runs synchronously for a bounded range and returns the number of rows upserted. Used only during development; not linked from the UI. If `ADMIN_TOKEN` is unset, the route returns 404 — the endpoint does not exist until someone configures it.

---

## Behaviour rules

- **Read-only by default.** No endpoint moves funds or signs anything.
- **CORS**: allow-list contains the Vercel production domain and `http://localhost:5173`.
- **Caching**: `/health` is `no-store`; `/claims/:runId` is `max-age=5, stale-while-revalidate=30`; everything else `max-age=2`.
- **Idempotent indexer**: every write is an `upsert` keyed by `(run_id, chain_id, kind)`, so a restart or overlap cannot duplicate a receipt.
- **No secrets to the browser**: the SPA never holds a Supabase key. If the API is down, the UI falls back to direct chain reads for policy state and shows receipts as unavailable rather than empty.
