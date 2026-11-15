# Feature Specification: Second Wind

**Branch**: `main`

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Second Wind — automatic penalty insurance for liquidated loans that also protects the borrower's next loan"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic payout after a liquidation (Priority: P1)

A borrower whose loan is partially liquidated receives the liquidation fee back automatically, within seconds. No claim form, no support ticket, no wallet action, and no need to be awake.

**Why this priority**: This is the core promise. Without an automatic, fast payout there is no product; everything else is an enhancement of this moment.

**Independent Test**: Register one policy on one test loan, cause one liquidation, and observe a payout plus a receipt. No other feature is required.

**Acceptance Scenarios**:

1. **Given** an active policy with coverage remaining, **When** a covered loan is liquidated, **Then** the borrower receives a payout equal to the liquidation fee, capped by remaining coverage, within 5 seconds.
2. **Given** the premium has not been paid for the current period, **When** the covered loan is liquidated, **Then** no payout occurs and the borrower sees the reason "premium not paid".
3. **Given** the claim is larger than the remaining coverage, **When** the payout is made, **Then** the payout equals the remaining coverage and the receipt shows the shortfall.

---

### User Story 2 - The next loan survives the cascade (Priority: P2)

When a payout is made, part of it reduces the debt on the borrower's weakest loan. A follow-on price move that would liquidate that loan no longer does.

**Why this priority**: This is the differentiator. A payout alone is a reimbursement; routing part of it into the next loan is what stops the second, larger loss.

**Independent Test**: Open two identical loans, cover only one, apply the same two price moves, and observe that the covered loan survives while the identical uncovered loan is liquidated.

**Acceptance Scenarios**:

1. **Given** a policy with a relief share above zero, **When** a claim is paid, **Then** the relief share reduces the debt of the weakest covered loan until the target health is reached or the share is exhausted.
2. **Given** the target health is reached before the relief share is exhausted, **When** the claim completes, **Then** the unspent amount returns to the policy's coverage and is reported in the receipt.
3. **Given** a second liquidation for the same borrower within 60 seconds of the first, **When** the second claim is paid, **Then** the whole claim is applied as relief and no cash is paid.
4. **Given** the borrower has only one loan, **When** a claim is paid, **Then** the relief share is applied to that same loan.

---

### User Story 3 - The borrower can see and control coverage (Priority: P3)

The borrower can see premium paid-through, remaining coverage, the relief split, and a receipt for every claim. They can stop coverage at any time.

**Why this priority**: Trust. A financial product that pays automatically must be inspectable, and a borrower must always be able to leave.

**Independent Test**: Open a policy, read its state, complete one claim, read the receipt, then cancel and confirm that a later liquidation pays nothing.

**Acceptance Scenarios**:

1. **Given** an active policy, **When** the borrower views it, **Then** remaining coverage, premium paid-through, relief share, target health, and payout destination are visible.
2. **Given** a completed claim, **When** the borrower opens the receipt, **Then** it lists the fee, cash paid, relief spent, unspent amount, remaining coverage, and the time of each settlement step.
3. **Given** the borrower cancels the policy, **When** a later liquidation occurs, **Then** no payout and no relief are made.
4. **Given** a claim was rejected, **When** the borrower opens it, **Then** the rejection reason is shown in plain language.

---

### Edge Cases

- The liquidation happens in the same second the premium period ends.
- The claim is larger than the remaining coverage.
- The borrower is liquidated twice within 60 seconds, and again after 60 seconds.
- The relief target is already met, so no debt is repaid.
- The relief destination is temporarily unable to receive funds.
- The cash destination is temporarily unable to receive funds.
- The same liquidation record is delivered more than once.
- The borrower cancels while a claim is in flight.
- The liquidation repays a very small amount, so the fee rounds to zero.
- Two liquidations for the same borrower occur in the same block.
- The price moves between the moment the claim is decided and the moment it settles.
- The covered loan is closed by the borrower before any liquidation.
- The coverage pool reserve on one settlement network is insufficient while the other is funded.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A borrower MUST be able to register a policy that names the covered loan, the coverage cap, the premium rate, the relief share, the target health, and the payout destination.
- **FR-002**: A policy MUST be active only while premium is paid through the current time.
- **FR-003**: Premium MUST accrue per second and MUST be prepayable for a term.
- **FR-004**: On a covered liquidation, the system MUST compute the fee from the amount repaid and the protocol's liquidation incentive for that loan.
- **FR-005**: The claim MUST equal the fee, capped by the policy's remaining coverage.
- **FR-006**: The claim MUST be split between cash and relief according to the policy's relief share.
- **FR-007**: A second liquidation for the same borrower within 60 seconds MUST convert the entire claim to relief.
- **FR-008**: Relief MUST reduce debt on the borrower's weakest covered loan, and MUST stop at the target health or when the relief share is exhausted, whichever comes first.
- **FR-009**: Unspent relief MUST return to the policy's remaining coverage and MUST appear in the receipt.
- **FR-010**: Both settlement branches MUST complete without any borrower action and MUST each produce an auditable record joined by a single claim identifier.
- **FR-011**: The system MUST reject duplicate delivery of the same liquidation and MUST NOT pay twice.
- **FR-012**: Each settlement branch MUST independently verify the loan state, the policy state, and the remaining coverage before moving funds.
- **FR-013**: Cash MUST be payable only to the registered destination, and relief MUST be applicable only to debt repayment on a covered loan.
- **FR-014**: A borrower MUST be able to cancel or pause a policy; cancellation MUST stop future claims and MUST NOT reverse completed ones.
- **FR-015**: No claim and no policy lifetime MAY pay more than the coverage cap.
- **FR-016**: Every rejection MUST be recorded with a machine-readable reason and a plain-language explanation: premium not paid, coverage exhausted, unknown loan, duplicate delivery, or destination underfunded.
- **FR-017**: A failure or delay on one settlement branch MUST NOT cause the other branch to be reported as complete.
- **FR-018**: The pool operator MUST NOT be able to redirect a payout, stall a valid claim, or change the terms of an active policy.
- **FR-019**: A partially settled claim MUST remain visible and auditable until it is resolved or explicitly abandoned.

### Key Entities

- **Policy**: the borrower's coverage contract. Attributes: covered loan, coverage cap, premium rate, premium paid-through, relief share, target health, payout destination, status (active, paused, cancelled).
- **Claim**: one settlement attempt triggered by one liquidation. Attributes: claim identifier, triggering event, fee amount, cash amount, relief limit, relief spent, unspent amount, status, timestamps for each step.
- **Loan position**: the covered borrowing position. Attributes: collateral, debt, liquidation threshold, health, liquidation fee rate.
- **Coverage reserve**: the funds available to pay claims, held separately on each settlement network, with per-claim and per-period limits.
- **Receipt**: the borrower-facing record of a claim, linking the triggering event, both settlement steps, amounts, and timing.

### Out of Scope

- Underwriting, actuarial pricing, and capital raising for the coverage reserve.
- Cover for losses other than the liquidation fee (for example, principal loss or bad debt).
- Cover for a loan that is already liquidatable when the policy is registered.
- Automatic rebalancing of reserves between settlement networks.
- Discretionary, manually approved, or good-will payouts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: At least 95% of covered liquidations are fully settled within 5 seconds of the liquidation, measured across at least 10 trials.
- **SC-002**: The median time from liquidation to full settlement is at most 3 seconds, and the 95th percentile is at most 5 seconds.
- **SC-003**: Every covered liquidation produces exactly one receipt, and zero duplicate payouts occur across 1,000 repeated deliveries of the same liquidation.
- **SC-004**: In 10 out of 10 trials, a covered second loan survives a follow-on price move that liquidates an identical uncovered loan.
- **SC-005**: No claim pays more than the policy cap, and no claim pays more than the fee, in any trial.
- **SC-006**: A new borrower can register a policy and see the resulting coverage in under 2 minutes.
- **SC-007**: Every rejection path shows a reason the borrower can understand without reading code.
- **SC-008**: A borrower with a single loan receives the full relief share on that loan.
- **SC-009**: The borrower can cancel coverage and observe that a later liquidation pays nothing, in 100% of trials.
- **SC-010**: An operator-side attempt to redirect a payout or stall a valid claim is refused, and the refusal is recorded.

## Assumptions

- Borrowers may hold one or more covered loans; relief targets the weakest one.
- The demo runs on test networks with a controllable loan market and price source. The liquidation is real, but the price move that causes it is induced for the demo.
- The coverage reserve is funded with test assets. Pricing is illustrative and is not claimed to be actuarially sound.
- Coverage reserves are held on each settlement network, and rebalancing between them happens outside the product.
- The demo's price source is a single market and is therefore manipulable; production would require a robust, multi-source price.
- Payouts are made in the loan asset.
- The borrower is responsible for keeping the premium paid; the product does not auto-debit a wallet.
- Coverage is capped per policy. The product does not promise unlimited solvency.
