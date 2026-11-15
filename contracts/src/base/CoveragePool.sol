// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMorpho } from "../interfaces/IMorpho.sol";
import { ReasonCodes } from "../libraries/ReasonCodes.sol";

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
    error SettlementNotImplemented();

    /// @notice Cover asset (mUSDC). Immutable, like every other term of the product.
    IERC20 public immutable coverAsset;
    /// @notice Policy registry on this chain.
    address public immutable registry;
    /// @notice Morpho Blue on this chain.
    IMorpho public immutable morpho;

    /// @notice One settlement per liquidation log.
    mapping(bytes32 => bool) public usedRuns;

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

    /// @notice Settles the relief branch for one liquidation.
    /// @dev Phase 2 scaffolding: the authentication and replay guards are final; the cascade
    ///      (policy re-read, weakest-loan selection, repay) is implemented in Phase 3 (T104-T108),
    ///      which is why this reverts instead of silently doing nothing.
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
        policyId;
        reliefLimit;
        decidedAt;
        liquidateBlock;
        revert SettlementNotImplemented();
    }
}
