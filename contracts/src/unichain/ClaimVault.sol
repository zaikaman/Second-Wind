// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReasonCodes } from "../libraries/ReasonCodes.sol";

/// @title ClaimVault
/// @notice Holds the cash reserve on Unichain Sepolia and pays the cash share to the borrower's
///         registered destination, with no borrower action.
/// @dev This chain cannot read Base. Every fact it enforces is either registered once at policy
///      creation or carried in the claim payload and checked against the registered terms. The
///      destination is never taken from the payload, so a buggy reactive contract can overstate an
///      amount but can never redirect a payout.
contract ClaimVault is AbstractCallback, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Terms written once, when the reactive contract observes `PolicyCreated`.
    struct Terms {
        uint256 cashCeiling;
        address destination;
        bool registered;
    }

    event PolicyRegistered(uint256 indexed policyId, uint256 cashCeiling, address destination, uint64 paidThrough);

    event ClaimPaid(
        bytes32 indexed runId, uint256 indexed policyId, address indexed destination, uint256 amount, uint64 paidThrough
    );

    error DuplicateRun(bytes32 runId, bytes32 reasonCode);
    error UnknownPolicy(uint256 policyId, bytes32 reasonCode);
    error PremiumLapsed(uint64 paidThrough, uint64 decidedAt, bytes32 reasonCode);
    error StaleWindow(uint64 paidThrough, uint64 lastPaidThrough, bytes32 reasonCode);
    error ZeroFee(bytes32 reasonCode);
    error CapExceeded(uint256 requested, uint256 remaining, bytes32 reasonCode);
    error ReserveInsufficient(uint256 required, uint256 available, bytes32 reasonCode);
    error TermsMismatch(uint256 policyId);
    error ZeroDestination();
    error CeilingTooLarge(uint256 cashCeiling);
    error SettlementNotImplemented();

    /// @notice Hard ceiling on any single policy's cash cover.
    uint256 public constant MAX_CASH_CEILING = 10_000e18;

    /// @notice Cover asset (mUSDC on Unichain). Immutable.
    IERC20 public immutable coverAsset;

    mapping(uint256 => Terms) private _terms;
    mapping(uint256 => uint256) private _cashPaid;
    mapping(uint256 => uint64) private _lastPaidThrough;
    mapping(bytes32 => bool) public usedRuns;

    /// @param callbackProxy_ Unichain Sepolia callback proxy (`0x775c…`).
    /// @param reactiveContract_ `SecondWindReactive` on Lasna.
    /// @param coverAsset_ mUSDC on Unichain Sepolia.
    constructor(IPayable callbackProxy_, address reactiveContract_, address coverAsset_)
        AbstractCallback(callbackProxy_, reactiveContract_)
    {
        coverAsset = IERC20(coverAsset_);
    }

    /// @notice Native ETH for callback delivery arrives here.
    receive() external payable override { }

    /// @notice Writes the cash terms for a policy exactly once.
    /// @dev Idempotent: a repeat with identical values is a no-op that emits nothing. Any different
    ///      value reverts, because terms are write-once.
    function registerPolicy(
        address reactive_,
        uint256 policyId,
        uint256 cashCeiling,
        uint64 paidThrough,
        address destination
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        if (destination == address(0)) {
            revert ZeroDestination();
        }
        if (cashCeiling > MAX_CASH_CEILING) {
            revert CeilingTooLarge(cashCeiling);
        }

        Terms storage t = _terms[policyId];
        if (t.registered) {
            if (t.cashCeiling != cashCeiling || t.destination != destination) {
                revert TermsMismatch(policyId);
            }
            return;
        }

        _terms[policyId] = Terms({ cashCeiling: cashCeiling, destination: destination, registered: true });
        _lastPaidThrough[policyId] = paidThrough;

        emit PolicyRegistered(policyId, cashCeiling, destination, paidThrough);
    }

    /// @notice Pays the cash share for one liquidation.
    /// @dev Phase 2 scaffolding: authentication, the replay guard and the "terms must exist" check
    ///      are final; the ceiling, reserve and transfer steps are implemented in Phase 3 (T109-T111).
    function payClaim(
        address reactive_,
        bytes32 runId,
        uint256 policyId,
        uint256 cashAmount,
        uint64 paidThrough,
        uint64 decidedAt
    ) external onlyServiceProvider onlyCallbackSender(reactive_) nonReentrant {
        if (usedRuns[runId]) {
            revert DuplicateRun(runId, ReasonCodes.DUPLICATE_DELIVERY);
        }
        if (!_terms[policyId].registered) {
            revert UnknownPolicy(policyId, ReasonCodes.UNKNOWN_LOAN);
        }
        cashAmount;
        paidThrough;
        decidedAt;
        revert SettlementNotImplemented();
    }

    /// @notice Cash cover originally registered for a policy.
    function cashCeilingOf(uint256 policyId) external view returns (uint256) {
        return _terms[policyId].cashCeiling;
    }

    /// @notice Cash already paid for a policy.
    function cashPaidOf(uint256 policyId) external view returns (uint256) {
        return _cashPaid[policyId];
    }

    /// @notice Address that receives this policy's cash share.
    function destinationOf(uint256 policyId) external view returns (address) {
        return _terms[policyId].destination;
    }

    /// @notice The premium window this vault last observed for a policy.
    function lastPaidThroughOf(uint256 policyId) external view returns (uint64) {
        return _lastPaidThrough[policyId];
    }

    /// @notice The reserve this contract can actually pay from.
    function reserveBalance() external view returns (uint256) {
        return coverAsset.balanceOf(address(this));
    }

    /// @notice True once a `runId` has been settled here.
    function usedRun(bytes32 runId) external view returns (bool) {
        return usedRuns[runId];
    }

    /// @notice Pays this contract's callback-proxy debt from its own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
