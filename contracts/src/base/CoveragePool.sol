// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMorpho } from "../interfaces/IMorpho.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { HealthMath } from "../libraries/HealthMath.sol";
import { ReasonCodes } from "../libraries/ReasonCodes.sol";
import { PolicyRegistry } from "./PolicyRegistry.sol";

/// @title CoveragePool
/// @notice Holds the relief reserve on Base Sepolia, receives premium, and repays debt on the
///         borrower's weakest covered loan when the reactive contract asks.
/// @dev Deliberately absent: no `withdraw` for an owner, no `pause`, no upgrade hook. Committed
///      reserves cannot be pulled, so the pool cannot stall a valid claim by emptying the account.
contract CoveragePool is AbstractCallback, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event ReliefApplied(
        bytes32 indexed runId,
        uint256 indexed policyId,
        bytes32 indexed marketId,
        uint256 reliefSpent,
        uint256 debtAfter,
        uint256 healthAfter,
        uint64 appliedAt
    );

    error DuplicateRun(bytes32 runId, bytes32 reasonCode);
    error PolicyNotLive(uint256 policyId, uint8 status, bytes32 reasonCode);
    error PremiumLapsed(uint64 paidThrough, uint64 decidedAt, bytes32 reasonCode);
    error PolicyCancelled(uint256 policyId, uint64 cancelledAtBlock, bytes32 reasonCode);
    error CapExceeded(uint256 requested, uint256 remaining, bytes32 reasonCode);
    error NoActiveLoan(bytes32 runId, bytes32 reasonCode);
    error ReserveInsufficient(uint256 required, uint256 available, bytes32 reasonCode);

    /// @notice Cover asset (mUSDC). Immutable, like every other term of the product.
    IERC20 public immutable coverAsset;
    /// @notice Policy registry on this chain.
    address public immutable registry;
    /// @notice Morpho Blue on this chain.
    IMorpho public immutable morpho;

    /// @notice One settlement per liquidation log.
    mapping(bytes32 => bool) public usedRuns;

    /// @notice One open position, as the cascade sees it.
    struct Loan {
        bytes32 marketId;
        uint256 debt;
        uint256 collateral;
        uint256 price;
        uint256 lltv;
        uint256 health;
    }

    /// @param callbackProxy_ Base Sepolia callback proxy (`0x476F…`).
    /// @param reactiveContract_ `SecondWindReactive` on Lasna. Immutable: a wrong address cannot be
    ///        repaired, only redeployed, which is why the deploy script asserts it.
    /// @param registry_ `PolicyRegistry` on Base Sepolia.
    /// @param morpho_ Morpho Blue on Base Sepolia.
    /// @param coverAsset_ mUSDC on Base Sepolia.
    constructor(
        IPayable callbackProxy_,
        address reactiveContract_,
        address registry_,
        address morpho_,
        address coverAsset_
    ) AbstractCallback(callbackProxy_, reactiveContract_) {
        coverAsset = IERC20(coverAsset_);
        registry = registry_;
        morpho = IMorpho(morpho_);
    }

    /// @notice Native ETH for callback delivery arrives here.
    receive() external payable override { }

    /// @notice Pays this contract's callback-proxy debt from its own balance, so anyone can revive
    ///         the loop after the reserve runs dry.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice The reserve this contract can actually pay from.
    function reserveBalance() external view returns (uint256) {
        return coverAsset.balanceOf(address(this));
    }

    /// @notice True once a `runId` has been settled here.
    function usedRun(bytes32 runId) external view returns (bool) {
        return usedRuns[runId];
    }

    /// @notice Pulls reserve tokens in. Deposit-only: there is no matching withdrawal.
    function deposit(uint256 amount) external nonReentrant {
        coverAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Settles the relief branch for one liquidation by repaying debt on the borrower's
    ///         weakest covered loan, stopping at the policy's target health.
    /// @dev Checks, then effects, then the interaction: the run is marked used and the relief is
    ///      recorded before the external `repay`, so a reentrant delivery cannot settle twice.
    /// @param reactive_ Injected by the proxy; must equal `_CALLBACK_SENDER`.
    /// @param runId Identifier shared with the cash branch.
    /// @param policyId Policy that covers the liquidated loan.
    /// @param reliefLimit Most this branch may spend.
    /// @param decidedAt Lasna timestamp at which eligibility was decided.
    /// @param liquidateBlock Base block number of the liquidation log.
    function settleCascade(
        address reactive_,
        bytes32 runId,
        uint256 policyId,
        uint256 reliefLimit,
        uint64 decidedAt,
        uint64 liquidateBlock
    ) external onlyServiceProvider onlyCallbackSender(reactive_) nonReentrant {
        if (usedRuns[runId]) {
            revert DuplicateRun(runId, ReasonCodes.DUPLICATE_DELIVERY);
        }

        PolicyRegistry registryContract = PolicyRegistry(registry);
        PolicyRegistry.Policy memory p = registryContract.getPolicy(policyId);
        _requireLive(p, policyId, decidedAt, liquidateBlock);

        uint256 remaining = p.reliefCeiling - p.reliefUsed;
        if (reliefLimit == 0 || reliefLimit > remaining) {
            revert CapExceeded(reliefLimit, remaining, ReasonCodes.COVERAGE_EXHAUSTED);
        }

        Loan memory loan = _weakestLoan(p.borrower);
        if (loan.marketId == bytes32(0)) {
            revert NoActiveLoan(runId, ReasonCodes.UNKNOWN_LOAN);
        }

        uint256 reliefSpent = _reliefAmount(loan, p.targetHealthWad, reliefLimit);
        if (reliefSpent == 0) {
            // The claim is valid, the relief is simply unnecessary: the position already meets the
            // target. Consume the run so a redelivery cannot pay later, and emit the zero.
            usedRuns[runId] = true;
            emit ReliefApplied(runId, policyId, loan.marketId, 0, loan.debt, loan.health, uint64(block.timestamp));
            return;
        }

        uint256 available = coverAsset.balanceOf(address(this));
        if (available < reliefSpent) {
            revert ReserveInsufficient(reliefSpent, available, ReasonCodes.DESTINATION_UNDERFUNDED);
        }

        usedRuns[runId] = true;
        registryContract.recordRelief(policyId, reliefSpent);

        IMorpho.MarketParams memory params = morpho.idToMarketParams(loan.marketId);
        // `forceApprove` rather than `approve`: a failed partial repay can leave a non-zero
        // allowance, and a plain approve would then revert forever.
        coverAsset.forceApprove(address(morpho), reliefSpent);
        morpho.repay(params, reliefSpent, 0, p.borrower, "");

        emit ReliefApplied(
            runId,
            policyId,
            loan.marketId,
            reliefSpent,
            _debtOf(loan.marketId, p.borrower),
            _healthOf(loan.marketId, p.borrower),
            uint64(block.timestamp)
        );
    }

    /// @dev Rejects anything that was not live and paid at the moment the claim was decided.
    function _requireLive(PolicyRegistry.Policy memory p, uint256 policyId, uint64 decidedAt, uint64 liquidateBlock)
        private
        pure
    {
        if (p.status == PolicyRegistry.Status.Cancelled) {
            // A cancellation after the liquidation block does not erase a claim that was already
            // valid when the crash happened (FR-014).
            if (p.cancelledAtBlock <= liquidateBlock) {
                revert PolicyCancelled(policyId, p.cancelledAtBlock, ReasonCodes.POLICY_CANCELLED);
            }
        } else if (p.status != PolicyRegistry.Status.Active) {
            revert PolicyNotLive(
                policyId,
                uint8(p.status),
                p.status == PolicyRegistry.Status.Paused ? ReasonCodes.POLICY_PAUSED : ReasonCodes.POLICY_CANCELLED
            );
        }
        if (p.paidThrough < decidedAt) {
            revert PremiumLapsed(p.paidThrough, decidedAt, ReasonCodes.PREMIUM_LAPSED);
        }
    }

    /// @dev Relief is the smallest of the limit, the debt, and the amount needed to reach target.
    function _reliefAmount(Loan memory loan, uint256 targetHealthWad, uint256 reliefLimit)
        private
        pure
        returns (uint256)
    {
        uint256 collateralValue = HealthMath.collateralValue(loan.collateral, loan.price);
        uint256 wanted = HealthMath.repayForTarget(loan.debt, collateralValue, loan.lltv, targetHealthWad);
        if (wanted > reliefLimit) {
            wanted = reliefLimit;
        }
        if (wanted > loan.debt) {
            wanted = loan.debt;
        }
        return wanted;
    }

    /// @dev Enumerates the borrower's policies (at most eight) and returns the lowest-health open
    ///      position, ties broken by the numerically lower market id.
    function _weakestLoan(address borrower) private view returns (Loan memory) {
        PolicyRegistry registryContract = PolicyRegistry(registry);
        uint256[] memory ids = registryContract.policiesOf(borrower);

        HealthMath.Candidate[] memory candidates = new HealthMath.Candidate[](ids.length);
        uint256 count;
        for (uint256 i = 0; i < ids.length; ++i) {
            bytes32 marketId = registryContract.getPolicy(ids[i]).marketId;
            IMorpho.Position memory position = morpho.position(marketId, borrower);
            if (position.collateral == 0 || position.borrowShares == 0) {
                continue;
            }
            IMorpho.MarketParams memory params = morpho.idToMarketParams(marketId);
            uint256 debt = HealthMath.toAssetsUp(
                position.borrowShares,
                morpho.market(marketId).totalBorrowAssets,
                morpho.market(marketId).totalBorrowShares
            );
            candidates[count] = HealthMath.Candidate({
                marketId: marketId,
                healthWad: HealthMath.health(position.collateral, IOracle(params.oracle).price(), params.lltv, debt),
                debt: debt
            });
            ++count;
        }

        (uint256 index, bool found) = HealthMath.weakest(candidates);
        if (!found) {
            return Loan(bytes32(0), 0, 0, 0, 0, 0);
        }
        return _loanOf(candidates[index].marketId, borrower);
    }

    /// @dev Reads one open position, including the values the cascade needs to size the repayment.
    function _loanOf(bytes32 marketId, address borrower) private view returns (Loan memory loan) {
        IMorpho.Position memory position = morpho.position(marketId, borrower);
        IMorpho.MarketParams memory params = morpho.idToMarketParams(marketId);
        loan.marketId = marketId;
        loan.collateral = position.collateral;
        loan.price = IOracle(params.oracle).price();
        loan.lltv = params.lltv;
        loan.debt = _debtOf(marketId, borrower);
        loan.health = HealthMath.health(loan.collateral, loan.price, loan.lltv, loan.debt);
    }

    function _debtOf(bytes32 marketId, address borrower) private view returns (uint256) {
        IMorpho.Market memory m = morpho.market(marketId);
        return HealthMath.toAssetsUp(
            morpho.position(marketId, borrower).borrowShares, m.totalBorrowAssets, m.totalBorrowShares
        );
    }

    function _healthOf(bytes32 marketId, address borrower) private view returns (uint256) {
        IMorpho.Position memory position = morpho.position(marketId, borrower);
        IMorpho.MarketParams memory params = morpho.idToMarketParams(marketId);
        return HealthMath.health(
            position.collateral, IOracle(params.oracle).price(), params.lltv, _debtOf(marketId, borrower)
        );
    }
}
