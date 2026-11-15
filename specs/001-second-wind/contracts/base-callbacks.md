# Interface Contract: `CoveragePool` (Base Sepolia)

**Chain**: Base Sepolia `84532` · **Callback proxy**: `0x476F44b11F5C942c58f4c8E3d0300E5710743585`
**Purpose**: hold relief reserves, receive premium, and repay debt on the borrower's weakest covered loan when the reactive contract asks.

Inherits `AbstractCallback` (Omni) and `ReentrancyGuard`.

---

## Constructor

```solidity
constructor(
    IPayable callbackProxy,     // 0x476F… on Base Sepolia
    address  reactiveContract,  // SecondWindReactive on Lasna, immutable
    address  registry,          // PolicyRegistry
    address  morpho,            // 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb
    address  coverAsset         // mUSDC
) payable AbstractCallback(callbackProxy, reactiveContract);
```

`_CALLBACK_SENDER` is immutable. A wrong address is unrecoverable and requires redeploying — the deploy script asserts it against the RC deployment output before proceeding.

---

## Event

```solidity
event ReliefApplied(
    bytes32 indexed runId,
    uint256 indexed policyId,
    bytes32 indexed marketId,
    uint256 reliefSpent,
    uint256 debtAfter,
    uint256 healthAfter,
    uint64  appliedAt
);   // opCode 4, data = 4 words
```

`SecondWindReactive` subscribes to this event to reconcile its mirrored `reliefUsed`. Without that reconciliation the reactive contract could over-issue relief after a claim that stopped early at the target health.

---

## Settlement entry point

```solidity
function settleCascade(
    address reactive_,       // injected by the proxy; must equal _CALLBACK_SENDER
    bytes32 runId,
    uint256 policyId,
    uint256 reliefLimit,
    uint64  decidedAt,
    uint64  liquidateBlock
) external onlyServiceProvider onlyCallbackSender(reactive_) nonReentrant;
```

### Execution order (checks → effects → interactions)

1. **Auth**: both modifiers. Direct calls from an EOA fail at `onlyServiceProvider`.
2. **Replay**: `require(!usedRuns[runId], DuplicateRun(runId))`.
3. **Policy read** from `PolicyRegistry`:
   - `status == Active` → else `PolicyNotLive`.
   - `paidThrough >= decidedAt` → else `PremiumLapsed(paidThrough, decidedAt)`.
   - `cancelledAtBlock == 0 || cancelledAtBlock > liquidateBlock` → else `PolicyCancelled`.
   - `reliefLimit > 0` and `reliefLimit <= reliefCeiling - reliefUsed` → else `CapExceeded`.
4. **Target selection** (`HealthMath.weakest`):
   - Enumerate `registry.policiesOf(borrower)` (≤ 8).
   - For each: read `morpho.position(marketId, borrower)`, `morpho.idToMarketParams(marketId)`, `oracle.price()`.
   - Skip markets with `debt == 0` or `collateral == 0`.
   - Pick minimum `health`; ties → lower `marketId`.
   - If none qualify → `NoActiveLoan`, `runId` is still consumed so a retry cannot pay twice.
5. **Amount**:
   ```
   collateralValue = collateral * price / 1e36
   repayForTarget  = debt - (collateralValue * lltv / targetHealth)
   reliefSpent     = min(reliefLimit, debt, max(repayForTarget, 0))
   ```
   If `reliefSpent == 0` (already at or above target), emit `ReliefApplied` with `0` and return. No revert: the claim is valid, the relief is simply unnecessary.
6. **Effects**: `usedRuns[runId] = true`, `registry.recordRelief(policyId, reliefSpent)`, cache `debtAfter` and `healthAfter`.
7. **Interaction**: `coverAsset.forceApprove(morpho, reliefSpent)`, `morpho.repay(marketParams, reliefSpent, 0, borrower, "")`.
   - `forceApprove` (not `approve`) because a failed partial repay can leave a non-zero allowance.
   - The repay is on behalf of `borrower`, so the debt reduction belongs to them.
8. **Event**: `ReliefApplied(...)`.
9. **Return value**: none. The indexer reads the event. This keeps the payload small and avoids a second source of truth.

### Reverts and reason codes

| Revert | Reason code | Plain language |
|--------|-------------|----------------|
| `DuplicateRun` | `DUPLICATE_DELIVERY` | "This liquidation was already settled." |
| `PolicyNotLive` | `POLICY_CANCELLED` / `POLICY_PAUSED` | "Cover was not active when this claim arrived." |
| `PremiumLapsed` | `PREMIUM_LAPSED` | "The premium was not paid for this period." |
| `PolicyCancelled` | `POLICY_CANCELLED` | "Cover was cancelled before the liquidation." |
| `CapExceeded` | `COVERAGE_EXHAUSTED` | "The remaining cover is smaller than this claim." |
| `NoActiveLoan` | `UNKNOWN_LOAN` | "No open loan was found for this policy." |
| `ReserveInsufficient` | `DESTINATION_UNDERFUNDED` | "The relief reserve does not hold enough to pay this claim." |
| `ZeroFee` | `ZERO_FEE` | "The liquidation penalty rounded to zero." |

Every revert carries the reason code as a custom error argument so the indexer can store it without parsing strings (FR-016).

---

## Other functions

```solidity
function coverDebt() external;              // exposes AbstractPayer._coverDebt()
function reserveBalance() external view returns (uint256);
function usedRun(bytes32 runId) external view returns (bool);
function deposit(uint256 amount) external;  // pulls coverAsset from msg.sender; no cap
receive() external payable;                 // inherited; funds callback gas
```

### Deliberately absent

- **No `withdraw`**, for the owner or anyone else. Committed reserves cannot be pulled, so the pool cannot stall a valid claim by emptying the account (FR-018).
- **No `pause`**. A pause is a stall with better manners.
- **No upgrade hook or proxy**. Redeployment is the upgrade path; that is acceptable for a one-week build and removes an admin key that could redirect funds.

---

## Invariants asserted in tests

1. `reliefSpent <= reliefLimit` and `reliefSpent <= debt`.
2. `registry.reliefUsed(policyId) <= reliefCeiling` after every call, for all inputs (fuzzed).
3. A second call with the same `runId` changes no state, ever.
4. `reserveBalance` decreases by exactly `reliefSpent` on success.
5. Health of the target market is strictly greater after the call when `reliefSpent > 0`.
6. The chosen market is the minimum-health market among the borrower's covered, indebted positions.
