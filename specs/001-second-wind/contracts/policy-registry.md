# Interface Contract: `PolicyRegistry` (Base Sepolia)

**Chain**: Base Sepolia `84532`
**Purpose**: the borrower's side of the product. Creates policies, takes premium, records relief usage, and publishes the events the reactive contract mirrors.

---

## Events

All events are consumed by `SecondWindReactive`. Topic layouts are part of the interface: `opCode` (topic count) and `data` layout must not change without updating `Topics.sol` and the reactive decoder.

```solidity
event PolicyCreated(
    uint256 indexed policyId,
    address indexed borrower,
    bytes32 indexed marketId,
    uint256 coverageCap,
    uint256 cashCeiling,
    uint256 reliefCeiling,
    uint256 premiumPerSecond,
    uint64  paidThrough,
    uint16  reliefShareBps,
    uint256 targetHealthWad,
    address cashDestination,
    uint256 lltv
);   // opCode 4, data = 9 words, in declaration order

event PremiumPaid(
    uint256 indexed policyId,
    uint64 paidThrough
);   // opCode 2, data = 1 word

event PolicyStatusChanged(
    uint256 indexed policyId,
    uint8 status,              // 0 None, 1 Active, 2 Paused, 3 Cancelled
    uint64 cancelledAtBlock    // 0 unless status == 3
);   // opCode 2, data = 2 words
```

`lltv` is included in `PolicyCreated` because the reactive contract cannot read Morpho. It is immutable per market, so mirroring it once is enough for every later claim.

---

## Functions

### `createPolicy`

```solidity
function createPolicy(
    bytes32 marketId,
    uint256 coverageCap,
    uint16  reliefShareBps,
    uint256 targetHealthWad,
    address cashDestination,
    uint32  premiumTermSeconds
) external returns (uint256 policyId);
```

- `premiumPerSecond = coverageCap * APR_BPS / (10000 * 365 days)` with `APR_BPS = 300` (3% APR).
- `cashCeiling = coverageCap * (10000 - reliefShareBps) / 10000`; `reliefCeiling = coverageCap - cashCeiling`.
- `paidThrough = block.timestamp + premiumTermSeconds`, and the same call pulls `premiumPerSecond * premiumTermSeconds` of the cover asset from the borrower into `CoveragePool`. This is why creation is **one** transaction and the policy is live immediately: without it a policy would lapse in the same second it was created.
- `premiumTermSeconds` bounds: `1 days … 365 days`.
- Reverts: `MarketNotSupported`, `LoanNotOpen`, `LoanUnhealthy` (health ≤ 1e18), `PolicyExists` (an Active or Paused policy already holds this `loanKey`), `TooManyPolicies` (8), `CapOutOfRange`, `ShareOutOfRange`, `TargetOutOfRange`, `ZeroDestination`, `TermOutOfRange`.

**Side effect**: emits `PolicyCreated`, which is also the trigger for the Unichain registration callback.

### `payPremium`

```solidity
function payPremium(uint256 policyId, uint256 amount) external;
```

- Transfers `amount` of the cover asset from the borrower directly to `CoveragePool`.
- `paidThrough = min(paidThrough + amount / premiumPerSecond, block.timestamp + 365 days)`.
- Reverts: `NotBorrower`, `PolicyNotLive`, `AmountTooSmall` (`amount < premiumPerSecond` — otherwise the division truncates and the borrower pays for nothing).

### `pausePolicy` / `resumePolicy`

```solidity
function pausePolicy(uint256 policyId) external;
function resumePolicy(uint256 policyId) external;
```

- Borrower only. `Active → Paused`, `Paused → Active`.
- Pausing does not extend or refund `paidThrough`. Time keeps running while paused; a paused policy simply cannot claim.

### `cancelPolicy`

```solidity
function cancelPolicy(uint256 policyId) external;
```

- Borrower only. `Active | Paused → Cancelled` (terminal).
- Sets `cancelledAtBlock = block.number` and emits `PolicyStatusChanged`.
- No refund. A claim whose `liquidateBlock` precedes this block is still honoured (implemented in `CoveragePool`, not here).

### `recordRelief`

```solidity
function recordRelief(uint256 policyId, uint256 amount) external onlyCoveragePool;
```

- Increments `reliefUsed`. Reverts `CapExceeded` if it would pass `reliefCeiling`.
- Called only by `CoveragePool`, whose address is set exactly once.

### `setCoveragePool`

```solidity
function setCoveragePool(address pool) external onlyOwner;
```

- One-time: reverts `AlreadySet` if non-zero. Exists only because the pool is deployed after the registry.
- Owner is renounced in the deploy script after wiring, so this cannot be used to redirect anything later.

### Views

```solidity
function getPolicy(uint256 policyId) external view returns (Policy memory);
function policyOfLoan(bytes32 loanKey) external view returns (uint256);
function policiesOf(address borrower) external view returns (uint256[] memory); // ≤ 8
function reliefRemaining(uint256 policyId) external view returns (uint256);
function isCoverable(uint256 policyId) external view returns (bool);
```

`isCoverable` = `status == Active && paidThrough >= block.timestamp && reliefRemaining > 0`.

---

## Constants

| Name | Value | Meaning |
|------|-------|---------|
| `APR_BPS` | `300` | 3% annual premium |
| `MAX_POLICIES` | `8` | Bounds the relief loop |
| `MIN_CAP` | `100e18` | Smallest policy |
| `MAX_CAP` | `5_000e18` | Largest policy |
| `MIN_TARGET_HEALTH` | `1.05e18` | Lower bound on relief target |
| `MAX_TARGET_HEALTH` | `1.50e18` | Upper bound |
| `MAX_TERM` | `365 days` | Prepayment horizon |

---

## Access Control

| Caller | Allowed |
|--------|---------|
| Policy borrower | `payPremium`, `pausePolicy`, `resumePolicy`, `cancelPolicy` |
| `CoveragePool` | `recordRelief` |
| Owner | `setCoveragePool` once, then renounced |
| Anyone else | `createPolicy` only (their own policy), reads |

There is **no** function that changes the terms, cap, split, target, or destination of an existing policy. That is the contract-level proof of FR-018.
