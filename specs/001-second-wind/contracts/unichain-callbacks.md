# Interface Contract: `ClaimVault` (Unichain Sepolia)

**Chain**: Unichain Sepolia `1301` · **Callback proxy**: `0x775c9B990ADe401060B78D0e98684eEf8d2466C1`
**Purpose**: hold the cash reserve on the destination chain and pay the cash share to the borrower's registered destination, with no borrower action.

Inherits `AbstractCallback` (Omni) and `ReentrancyGuard`.

This chain cannot read Base. Every fact it enforces is either (a) registered once at policy creation, or (b) carried in the claim payload and checked against the registered terms. It never trusts a payload value it has seen before with a different value.

---

## Constructor

```solidity
constructor(
    IPayable callbackProxy,     // 0x775c… on Unichain Sepolia
    address  reactiveContract,  // same SecondWindReactive address as on Base
    address  coverAsset         // mUSDC (Unichain deployment)
) payable AbstractCallback(callbackProxy, reactiveContract);
```

---

## Events

```solidity
event PolicyRegistered(
    uint256 indexed policyId,
    uint256 cashCeiling,
    address destination,
    uint64  paidThrough
);   // opCode 2, data = 3 words

event ClaimPaid(
    bytes32 indexed runId,
    uint256 indexed policyId,
    address indexed destination,
    uint256 amount,
    uint64  paidThrough
);   // opCode 4, data = 2 words
```

`SecondWindReactive` subscribes to `ClaimPaid` on Unichain to reconcile its mirrored `cashPaid`. This is the only Unichain → Lasna signal, and it makes the reactive contract's cash ceiling accurate without polling.

---

## `registerPolicy`

```solidity
function registerPolicy(
    address reactive_,
    uint256 policyId,
    uint256 cashCeiling,
    uint64  paidThrough,
    address destination
) external onlyServiceProvider onlyCallbackSender(reactive_);
```

- Sent by the reactive contract when it observes `PolicyCreated` on Base. This closes the ordering gap where the first claim could arrive before the terms exist.
- **Idempotent**: a repeat with identical values is a no-op that emits nothing; any different value reverts `TermsMismatch`. Terms are therefore write-once.
- Reverts: `ZeroDestination`, `CeilingTooLarge` (`> 10_000e18`), `PolicyAlreadyRegistered` with different values.
- `paidThrough` here is only the initial value; it advances through claim payloads. `lastPaidThrough` is initialised to it.

---

## `payClaim`

```solidity
function payClaim(
    address reactive_,
    bytes32 runId,
    uint256 policyId,
    uint256 cashAmount,
    uint64  paidThrough,
    uint64  decidedAt
) external onlyServiceProvider onlyCallbackSender(reactive_) nonReentrant;
```

### Execution order

1. **Auth**: proxy + reactive sender.
2. **Replay**: `require(!usedRuns[runId], DuplicateRun(runId))`.
3. **Terms exist**: `terms[policyId].destination != address(0)` → else `UnknownPolicy`.
4. **Eligibility**:
   - `paidThrough >= decidedAt` → else `PremiumLapsed`.
   - `paidThrough >= lastPaidThrough[policyId]` → else `StaleWindow`. Stops a replayed older claim from reopening an expired window.
5. **Bounds**:
   - `cashAmount > 0` → else `ZeroFee`.
   - `cashPaid[policyId] + cashAmount <= cashCeiling` → else `CapExceeded`.
   - `coverAsset.balanceOf(this) >= cashAmount` → else `ReserveInsufficient`.
6. **Effects**: `usedRuns[runId] = true`, `cashPaid += cashAmount`, `lastPaidThrough = paidThrough`.
7. **Interaction**: `coverAsset.safeTransfer(destination, cashAmount)`.
8. **Event**: `ClaimPaid(runId, policyId, destination, cashAmount, paidThrough)`.

### Why the destination is not in the payload

The payload carries the amount, not the recipient. The recipient is fixed at registration. A compromised or buggy reactive contract can therefore overstate an amount but can never redirect a payout to a different address — the strongest form of FR-013 and FR-018 available on a chain that cannot read Base.

---

## Views

```solidity
function cashCeilingOf(uint256 policyId) external view returns (uint256);
function cashPaidOf(uint256 policyId) external view returns (uint256);
function destinationOf(uint256 policyId) external view returns (address);
function reserveBalance() external view returns (uint256);
function usedRun(bytes32 runId) external view returns (bool);
function coverDebt() external;   // exposes AbstractPayer._coverDebt()
```

---

## Reverts and reason codes

| Revert | Reason code | Plain language |
|--------|-------------|----------------|
| `DuplicateRun` | `DUPLICATE_DELIVERY` | "This liquidation was already settled." |
| `UnknownPolicy` | `UNKNOWN_LOAN` | "This policy has no cash cover registered on this chain." |
| `PremiumLapsed` | `PREMIUM_LAPSED` | "The premium was not paid for this period." |
| `StaleWindow` | `PREMIUM_LAPSED` | "This claim refers to an older premium period." |
| `ZeroFee` | `ZERO_FEE` | "The liquidation penalty rounded to zero." |
| `CapExceeded` | `COVERAGE_EXHAUSTED` | "The remaining cash cover is smaller than this claim." |
| `ReserveInsufficient` | `DESTINATION_UNDERFUNDED` | "The cash reserve does not hold enough to pay this claim." |
| `TermsMismatch` | `TERMS_MISMATCH` | "The policy terms on this chain do not match the claim." |

---

## Deliberately absent

- **No `withdraw`**: the reserve is deposit-only.
- **No `setTerms`**: there is no function that edits a registered policy.
- **No `emergencyPause`**: failure isolation is handled by the reactive contract and by funding, not by a switch that can freeze a valid claim.

---

## Invariants asserted in tests

1. `sum(cashPaid) <= sum(cashCeiling)` per policy; a fuzz run never exceeds the ceiling.
2. A duplicate `runId` transfers nothing.
3. The transferred recipient always equals the address captured at registration, regardless of payload contents.
4. A claim that fails any check leaves `cashPaid`, `lastPaidThrough`, and `usedRuns` untouched (no partial effects).
5. After a successful claim, `reserveBalance` decreased by exactly `cashAmount`.
