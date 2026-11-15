# Interface Contract: `SecondWindReactive` (Reactive Lasna)

**Chain**: Reactive Lasna `5318007` · **System contract**: `0x8888888888888888888888888888888888888888`
**Purpose**: observe policy and liquidation events, compute the penalty and split, and dispatch the settlement callbacks. One reactive transaction produces up to two calls.

---

## Constructor

```solidity
constructor(
    address policyRegistry,   // Base Sepolia
    address morpho,           // 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb
    uint256 baseChainId,      // 84532
    uint256 unichainChainId   // 1301
) payable;
```

The callbacks do not exist yet at this point, so recipients are set afterwards. The constructor performs **five** subscriptions:

| # | Chain | Contract | `topic0` | Why |
|---|-------|----------|----------|-----|
| 1 | Base | `policyRegistry` | `PolicyCreated` | mirror terms, register on Unichain |
| 2 | Base | `policyRegistry` | `PremiumPaid` | advance `paidThrough` |
| 3 | Base | `policyRegistry` | `PolicyStatusChanged` | pause / cancel |
| 4 | Base | `morpho` | `Liquidate` | the trigger |
| 5 | Base | `address(0)` | `ReliefApplied` | reconcile `reliefUsed` |
| 6 | Unichain | `address(0)` | `ClaimPaid` | reconcile `cashPaid` |

Subscriptions 5 and 6 use a wildcard contract because the settlement contracts are deployed after the reactive contract. The handler filters on `log_.contractAddress` against the stored witness, so a same-topic event from another contract is ignored.

Gas per subscription is paid by the reactive contract in REACT. There are no cron subscriptions: the loop is entirely event-driven.

---

## Mirrored state

```solidity
struct Policy {
    address borrower;
    bytes32 marketId;
    uint256 lltv;
    uint256 coverageCap;
    uint256 cashCeiling;
    uint256 reliefCeiling;
    uint64  paidThrough;
    uint16  reliefShareBps;
    uint256 targetHealthWad;
    address cashDestination;
    uint8   status;          // 1 Active, 2 Paused, 3 Cancelled
}

mapping(uint256 => Policy)              public policies;
mapping(bytes32 => uint256)             public policyOfLoan;      // loanKey → policyId
mapping(address => uint256[])           public policiesOf;        // ≤ 8
mapping(bytes32 => bool)                public dispatched;
mapping(uint256 => uint256)             public reliefReserved;    // policyId → in flight
mapping(uint256 => uint256)             public cashReserved;      // policyId → in flight
mapping(bytes32 => uint256)             public reservedReliefByRun;
mapping(bytes32 => uint256)             public reservedCashByRun;
mapping(uint256 => uint256)             public reliefUsed;        // reconciled
mapping(uint256 => uint256)             public cashPaid;          // reconciled
mapping(address => uint64)              public lastClaimAt;
```

`reliefUsed` and `cashPaid` are **mirrors**, not authorities. They are advanced by `ReliefApplied` and `ClaimPaid` events. Between dispatch and reconciliation the in-flight amount sits in `reliefReserved[policyId]` / `cashReserved[policyId]`, so a second claim arriving in the same block cannot over-commit the ceiling. The per-`runId` maps exist only so reconciliation knows how much to release:

```text
on ReliefApplied(runId, policyId, spent):
    reliefReserved[policyId] -= reservedReliefByRun[runId]
    reliefUsed[policyId]     += spent
    delete reservedReliefByRun[runId]

on ClaimPaid(runId, policyId, amount):
    cashReserved[policyId] -= reservedCashByRun[runId]
    cashPaid[policyId]     += amount
    delete reservedCashByRun[runId]
```

---

## `react` routing

```solidity
function react(LogRecord memory log_) external onlySystem;
```

Order of checks, all cheap, none reverting:

1. `if (log_.topic0 == TOPIC_LIQUIDATE) return _onLiquidate(log_);`
2. `if (log_.topic0 == TOPIC_POLICY_CREATED) return _onPolicyCreated(log_);`
3. `if (log_.topic0 == TOPIC_PREMIUM_PAID) return _onPremiumPaid(log_);`
4. `if (log_.topic0 == TOPIC_STATUS_CHANGED) return _onStatusChanged(log_);`
5. `if (log_.topic0 == TOPIC_RELIEF_APPLIED) return _onReliefApplied(log_);`
6. `if (log_.topic0 == TOPIC_CLAIM_PAID) return _onClaimPaid(log_);`
7. return; // unknown topic: do nothing, cost nothing extra

Each handler first checks `log_.contractAddress` against the expected contract (or witness), then `log_.opCode`, then decodes `log_.data` with the exact tuple from the emission order. A malformed record returns early; it never reverts, because a revert is billed in full and would burn the contract's REACT reserve on junk.

---

## `_onLiquidate`

```text
runId     = keccak256(abi.encode(log_.chainId, bytes32(log_.txHash), log_.logIndex))
marketId  = bytes32(log_.topic1)
borrower  = address(uint160(log_.topic2))
(repaidAssets, , , , ) = abi.decode(log_.data, (uint256,uint256,uint256,uint256,uint256))

if dispatched[runId]                                  return
loanKey  = keccak256(abi.encode(marketId, borrower))
policyId = policyOfLoan[loanKey]; if (policyId == 0)  return   // unknown loan: ignore
p        = policies[policyId];    if (p.status != Active) return
if (p.paidThrough < block.timestamp)                  return   // premium lapsed: ignore
if (repaidAssets == 0)                                return

fee = FeeMath.penalty(repaidAssets, p.lltv)
if (fee == 0) return

cascade = lastClaimAt[borrower] != 0 && block.timestamp - lastClaimAt[borrower] <= 60

reliefAvail = p.reliefCeiling - reliefUsed[policyId] - reliefReserved[policyId]
cashAvail   = p.cashCeiling   - cashPaid[policyId]   - cashReserved[policyId]

if (cascade) {
    cashLimit   = 0
    reliefLimit = min(fee, reliefAvail)
} else {
    cashLimit   = min(fee * (10000 - p.reliefShareBps) / 10000, cashAvail)
    reliefLimit = min(fee * p.reliefShareBps / 10000, reliefAvail)
}

if (cashLimit == 0 && reliefLimit == 0) return     // nothing left to pay

dispatched[runId] = true
lastClaimAt[borrower] = block.timestamp

if (reliefLimit > 0) {
    reliefReserved[policyId] += reliefLimit
    reservedReliefByRun[runId] = reliefLimit
    _requestRelief(...)
}
if (cashLimit > 0) {
    cashReserved[policyId] += cashLimit
    reservedCashByRun[runId] = cashLimit
    _requestCash(...)
}
```

**Why `lastClaimAt` is keyed by borrower, not policy**: FR-007 protects a borrower whose loans are falling in sequence, which is a borrower-level condition, not a per-policy one.

---

## Callback payloads

The first parameter of every payload is `address`. It **must** be present and passed as `address(0)`; Reactive replaces that argument with the requesting reactive contract's address, which is what `onlyCallbackSender` checks on the destination.

**Relief** (destination: `reliefRecipient`, Base Sepolia, gas `400_000`)

```solidity
abi.encodeWithSignature(
    "settleCascade(address,bytes32,uint256,uint256,uint64,uint64)",
    address(0),      // injected sender
    runId,
    policyId,
    reliefLimit,
    decidedAt,       // uint64(block.timestamp) on Lasna
    liquidateBlock   // uint64(log_.blockNumber)
);
```

**Cash** (destination: `cashRecipient`, Unichain Sepolia, gas `300_000`)

```solidity
abi.encodeWithSignature(
    "payClaim(address,bytes32,uint256,uint256,uint64,uint64)",
    address(0),      // injected sender
    runId,
    policyId,
    cashLimit,
    paidThrough,     // p.paidThrough
    decidedAt
);
```

**Registration** (destination: `cashRecipient`, Unichain Sepolia, gas `200_000`)

```solidity
abi.encodeWithSignature(
    "registerPolicy(address,uint256,uint256,uint64,address)",
    address(0),      // injected sender
    policyId,
    cashCeiling,
    paidThrough,
    cashDestination
);
```

All three are issued with

```solidity
SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({
    chainId:  destinationChainId,
    recipient: recipient,
    gasLimit: limit,
    payload:  payload
}));
```

`decidedAt` is read once per `react()` call and reused for both callbacks, so the two branches cannot disagree about eligibility.

---

## One-time setters

```solidity
function setReliefRecipient(address) external onlyOwner;   // once
function setCashRecipient(address) external onlyOwner;     // once
function setSettlementWitnesses(address coveragePool, address claimVault) external onlyOwner; // once
function renounceOwnership() external onlyOwner;           // after wiring
```

Each setter reverts `AlreadySet` on a second call. There is no pause, no unsubscribe, and no way to change terms after deployment. After `renounceOwnership`, the contract has no privileged caller at all. This is the on-chain answer to FR-018 for the reactive layer.

`coverDebt()` is exposed publicly so anyone can settle the contract's REACT debt and restart the loop.

---

## Deployment order

1. `PolicyRegistry` (Base) — no dependency.
2. Mock tokens, Uniswap pool, Morpho market, loans (Base) — see `quickstart.md`.
3. `SecondWindReactive` (Lasna) — needs the registry and Morpho addresses.
4. `CoveragePool` (Base) — needs the reactive address.
5. `ClaimVault` (Unichain) — needs the reactive address.
6. `setReliefRecipient`, `setCashRecipient`, `setSettlementWitnesses` — one call each.
7. `renounceOwnership`.
8. Fund: REACT to the reactive contract, ETH to each callback contract via `proxy.depositTo(address)`.
9. `PolicyRegistry.setCoveragePool`, then renounce its ownership.

Step 9 is last because the registry's only privileged action is pointing at the pool.

---

## Revert-free guarantees

| Situation | Behaviour |
|-----------|-----------|
| Unknown event topic | Ignored |
| Wrong `opCode` | Ignored |
| Unknown `loanKey` | Ignored |
| Duplicate `runId` | Ignored before any callback |
| Policy paused or cancelled | Ignored |
| Premium lapsed | Ignored |
| Fee rounds to zero | Ignored |
| Both limits zero | Ignored |
| Recipient not yet set | Skips that branch, does not revert |

The reactive contract must never revert on data it does not control, because every revert is charged and repeated junk would drain it.
