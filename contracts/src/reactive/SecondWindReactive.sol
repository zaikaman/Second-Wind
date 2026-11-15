// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FeeMath } from "../libraries/FeeMath.sol";
import { Topics } from "../libraries/Topics.sol";

/// @title SecondWindReactive
/// @notice Watches policy and liquidation events on Base Sepolia, computes the penalty and the
///         split, and dispatches up to two callbacks from one reactive transaction: debt relief on
///         Base Sepolia and a cash payout on Unichain Sepolia. Both carry the same `runId`.
/// @dev Every handler is revert-free by design: a revert is billed in full and repeated junk would
///      drain the contract's REACT reserve. Unknown topics, wrong `opCode`, unknown loans, lapsed
///      premium and duplicates all return early.
contract SecondWindReactive is AbstractReactive, Ownable {
    /// @notice The mirrored subset of a policy that Lasna needs to decide a claim.
    struct Policy {
        address borrower;
        bytes32 marketId;
        uint256 lltv;
        uint256 coverageCap;
        uint256 cashCeiling;
        uint256 reliefCeiling;
        uint64 paidThrough;
        uint16 reliefShareBps;
        uint256 targetHealthWad;
        address cashDestination;
        uint8 status;
    }

    /// @notice Per-liquidation working set, kept in memory so `_onLiquidate` stays under the EVM
    ///         stack limit without enabling the IR pipeline.
    struct ClaimContext {
        bytes32 runId;
        bytes32 marketId;
        address borrower;
        uint256 policyId;
        uint256 repaidAssets;
        uint64 decidedAt;
        uint64 liquidateBlock;
    }

    uint8 internal constant STATUS_ACTIVE = 1;
    uint8 internal constant STATUS_PAUSED = 2;
    uint8 internal constant STATUS_CANCELLED = 3;

    /// @notice A second liquidation inside this window converts the whole fee into relief.
    uint64 internal constant CASCADE_WINDOW = 60;
    uint64 internal constant RELIEF_GAS_LIMIT = 400_000;
    uint64 internal constant CASH_GAS_LIMIT = 300_000;
    uint64 internal constant REGISTRATION_GAS_LIMIT = 200_000;

    event ReliefRecipientSet(address indexed recipient);
    event CashRecipientSet(address indexed recipient);
    event SettlementWitnessesSet(address indexed coveragePool, address indexed claimVault);

    error AlreadySet();
    error ZeroAddress();

    /// @notice `PolicyRegistry` on Base Sepolia.
    address public immutable policyRegistry;
    /// @notice Morpho Blue on Base Sepolia, the source of `Liquidate`.
    address public immutable morpho;
    /// @notice Origin chain id (Base Sepolia, 84532).
    uint256 public immutable baseChainId;
    /// @notice Cash destination chain id (Unichain Sepolia, 1301).
    uint256 public immutable unichainChainId;

    address public reliefRecipient;
    address public cashRecipient;
    address public coveragePoolWitness;
    address public claimVaultWitness;

    mapping(uint256 => Policy) public policies;
    mapping(bytes32 => uint256) public policyOfLoan;
    mapping(address => uint256[]) public policiesOf;
    mapping(bytes32 => bool) public dispatched;
    mapping(uint256 => uint256) public reliefReserved;
    mapping(uint256 => uint256) public cashReserved;
    mapping(bytes32 => uint256) public reservedReliefByRun;
    mapping(bytes32 => uint256) public reservedCashByRun;
    mapping(uint256 => uint256) public reliefUsed;
    mapping(uint256 => uint256) public cashPaid;
    mapping(address => uint64) public lastClaimAt;

    /// @param policyRegistry_ PolicyRegistry on Base Sepolia.
    /// @param morpho_ Morpho Blue on Base Sepolia.
    /// @param baseChainId_ Origin chain id.
    /// @param unichainChainId_ Cash destination chain id.
    constructor(address policyRegistry_, address morpho_, uint256 baseChainId_, uint256 unichainChainId_)
        payable
        Ownable(msg.sender)
    {
        if (policyRegistry_ == address(0) || morpho_ == address(0)) {
            revert ZeroAddress();
        }
        policyRegistry = policyRegistry_;
        morpho = morpho_;
        baseChainId = baseChainId_;
        unichainChainId = unichainChainId_;

        // Settlement contracts do not exist yet; wildcard contract subscriptions plus a stored
        // witness keep the loop closed without redeploying this contract later.
        SYSTEM.subscribe(baseChainId_, policyRegistry_, uint256(Topics.POLICY_CREATED), 0, 0, 0);
        SYSTEM.subscribe(baseChainId_, policyRegistry_, uint256(Topics.PREMIUM_PAID), 0, 0, 0);
        SYSTEM.subscribe(baseChainId_, policyRegistry_, uint256(Topics.STATUS_CHANGED), 0, 0, 0);
        SYSTEM.subscribe(baseChainId_, morpho_, uint256(Topics.LIQUIDATE), 0, 0, 0);
        SYSTEM.subscribe(baseChainId_, address(0), uint256(Topics.RELIEF_APPLIED), 0, 0, 0);
        SYSTEM.subscribe(unichainChainId_, address(0), uint256(Topics.CLAIM_PAID), 0, 0, 0);
    }

    /// @notice Entry point for every subscribed log. Routes cheaply and never reverts on data it
    ///         does not control.
    function react(IReactive.LogRecord calldata log_) external onlySystem {
        if (log_.topic0 == uint256(Topics.LIQUIDATE)) {
            _onLiquidate(log_);
            return;
        }
        if (log_.topic0 == uint256(Topics.POLICY_CREATED)) {
            _onPolicyCreated(log_);
            return;
        }
        if (log_.topic0 == uint256(Topics.PREMIUM_PAID)) {
            _onPremiumPaid(log_);
            return;
        }
        if (log_.topic0 == uint256(Topics.STATUS_CHANGED)) {
            _onStatusChanged(log_);
            return;
        }
        if (log_.topic0 == uint256(Topics.RELIEF_APPLIED)) {
            _onReliefApplied(log_);
            return;
        }
        if (log_.topic0 == uint256(Topics.CLAIM_PAID)) {
            _onClaimPaid(log_);
        }
    }

    /// @notice Sets the Base Sepolia callback recipient exactly once.
    function setReliefRecipient(address recipient) external onlyOwner {
        if (reliefRecipient != address(0)) {
            revert AlreadySet();
        }
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        reliefRecipient = recipient;
        emit ReliefRecipientSet(recipient);
    }

    /// @notice Sets the Unichain Sepolia callback recipient exactly once.
    function setCashRecipient(address recipient) external onlyOwner {
        if (cashRecipient != address(0)) {
            revert AlreadySet();
        }
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        cashRecipient = recipient;
        emit CashRecipientSet(recipient);
    }

    /// @notice Pins the two settlement contracts whose events are mirrored back. One-time.
    function setSettlementWitnesses(address coveragePool, address claimVault) external onlyOwner {
        if (coveragePoolWitness != address(0) || claimVaultWitness != address(0)) {
            revert AlreadySet();
        }
        if (coveragePool == address(0) || claimVault == address(0)) {
            revert ZeroAddress();
        }
        coveragePoolWitness = coveragePool;
        claimVaultWitness = claimVault;
        emit SettlementWitnessesSet(coveragePool, claimVault);
    }

    /// @notice Pays the contract's REACT debt from its own balance, so anyone can restart the loop.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice The mirrored policy, for tests, the indexer and the proof page.
    function getPolicy(uint256 policyId) external view returns (Policy memory) {
        return policies[policyId];
    }

    // ---------------------------------------------------------------------------------------
    // Handlers
    // ---------------------------------------------------------------------------------------

    /// @dev Morpho's log layout is `Liquidate(bytes32 indexed id, address indexed caller,
    ///      address indexed borrower, …)`, so the borrower is topic3, not topic2.
    function _onLiquidate(IReactive.LogRecord calldata log_) internal {
        if (log_.chainId != baseChainId || log_.contractAddress != morpho) {
            return;
        }
        if (log_.opCode != 4 || log_.data.length < 5 * 32) {
            return;
        }

        ClaimContext memory ctx = ClaimContext({
            runId: keccak256(abi.encode(log_.chainId, bytes32(log_.txHash), log_.logIndex)),
            marketId: bytes32(log_.topic1),
            borrower: address(uint160(log_.topic3)),
            policyId: 0,
            repaidAssets: 0,
            decidedAt: uint64(block.timestamp),
            liquidateBlock: uint64(log_.blockNumber)
        });

        if (dispatched[ctx.runId]) {
            return;
        }

        ctx.policyId = policyOfLoan[keccak256(abi.encode(ctx.marketId, ctx.borrower))];
        if (ctx.policyId == 0) {
            return;
        }

        Policy storage p = policies[ctx.policyId];
        if (p.status != STATUS_ACTIVE || p.paidThrough < ctx.decidedAt) {
            return;
        }

        (ctx.repaidAssets,,,,) = abi.decode(log_.data, (uint256, uint256, uint256, uint256, uint256));
        if (ctx.repaidAssets == 0) {
            return;
        }

        uint256 fee = FeeMath.penalty(ctx.repaidAssets, p.lltv);
        if (fee == 0) {
            return;
        }

        (uint256 cashLimit, uint256 reliefLimit) = _limits(p, ctx, fee);
        if (cashLimit == 0 && reliefLimit == 0) {
            return;
        }

        _dispatch(ctx, cashLimit, reliefLimit, p.paidThrough);
    }

    /// @dev Splits the fee for this claim. Cascade mode (a second liquidation inside
    ///      `CASCADE_WINDOW`) sends everything to relief and nothing to cash, because the next
    ///      loan is the one in danger.
    function _limits(Policy storage p, ClaimContext memory ctx, uint256 fee)
        private
        view
        returns (uint256 cashLimit, uint256 reliefLimit)
    {
        uint256 reliefAvail = p.reliefCeiling - reliefUsed[ctx.policyId] - reliefReserved[ctx.policyId];
        uint256 cashAvail = p.cashCeiling - cashPaid[ctx.policyId] - cashReserved[ctx.policyId];

        bool cascade = lastClaimAt[ctx.borrower] != 0 && ctx.decidedAt - lastClaimAt[ctx.borrower] <= CASCADE_WINDOW;
        if (cascade) {
            return (0, fee < reliefAvail ? fee : reliefAvail);
        }

        (uint256 cashShare, uint256 reliefShare) = FeeMath.split(fee, p.reliefShareBps);
        cashLimit = cashShare < cashAvail ? cashShare : cashAvail;
        reliefLimit = reliefShare < reliefAvail ? reliefShare : reliefAvail;
    }

    /// @dev Marks the run dispatched, reserves both limits, then requests the callbacks. Reservations
    ///      happen before any request so a claim in the same block cannot over-commit a ceiling.
    function _dispatch(ClaimContext memory ctx, uint256 cashLimit, uint256 reliefLimit, uint64 paidThrough) private {
        dispatched[ctx.runId] = true;
        lastClaimAt[ctx.borrower] = ctx.decidedAt;

        if (reliefLimit > 0 && reliefRecipient != address(0)) {
            reliefReserved[ctx.policyId] += reliefLimit;
            reservedReliefByRun[ctx.runId] = reliefLimit;
            _requestRelief(ctx.runId, ctx.policyId, reliefLimit, ctx.decidedAt, ctx.liquidateBlock);
        }

        if (cashLimit > 0 && cashRecipient != address(0)) {
            cashReserved[ctx.policyId] += cashLimit;
            reservedCashByRun[ctx.runId] = cashLimit;
            _requestCash(ctx.runId, ctx.policyId, cashLimit, paidThrough, ctx.decidedAt);
        }
    }

    function _onPolicyCreated(IReactive.LogRecord calldata log_) internal {
        if (log_.chainId != baseChainId || log_.contractAddress != policyRegistry) {
            return;
        }
        if (log_.opCode != 4 || log_.data.length < 9 * 32) {
            return;
        }

        uint256 policyId = log_.topic1;
        address borrower = address(uint160(log_.topic2));
        bytes32 marketId = bytes32(log_.topic3);

        (
            uint256 coverageCap,
            uint256 cashCeiling,
            uint256 reliefCeiling,,
            uint64 paidThrough,
            uint16 reliefShareBps,
            uint256 targetHealthWad,
            address cashDestination,
            uint256 lltv
        ) = abi.decode(log_.data, (uint256, uint256, uint256, uint256, uint64, uint16, uint256, address, uint256));

        Policy storage p = policies[policyId];
        p.borrower = borrower;
        p.marketId = marketId;
        p.lltv = lltv;
        p.coverageCap = coverageCap;
        p.cashCeiling = cashCeiling;
        p.reliefCeiling = reliefCeiling;
        p.paidThrough = paidThrough;
        p.reliefShareBps = reliefShareBps;
        p.targetHealthWad = targetHealthWad;
        p.cashDestination = cashDestination;
        p.status = STATUS_ACTIVE;

        policyOfLoan[keccak256(abi.encode(marketId, borrower))] = policyId;
        policiesOf[borrower].push(policyId);

        if (cashCeiling > 0 && cashRecipient != address(0)) {
            _requestRegistration(policyId, cashCeiling, paidThrough, cashDestination);
        }
    }

    function _onPremiumPaid(IReactive.LogRecord calldata log_) internal {
        if (log_.chainId != baseChainId || log_.contractAddress != policyRegistry) {
            return;
        }
        if (log_.opCode != 2 || log_.data.length < 32) {
            return;
        }

        uint256 policyId = log_.topic1;
        Policy storage p = policies[policyId];
        if (p.borrower == address(0)) {
            return;
        }

        (uint64 paidThrough) = abi.decode(log_.data, (uint64));
        p.paidThrough = paidThrough;
    }

    function _onStatusChanged(IReactive.LogRecord calldata log_) internal {
        if (log_.chainId != baseChainId || log_.contractAddress != policyRegistry) {
            return;
        }
        if (log_.opCode != 2 || log_.data.length < 2 * 32) {
            return;
        }

        uint256 policyId = log_.topic1;
        Policy storage p = policies[policyId];
        if (p.borrower == address(0)) {
            return;
        }

        (uint8 status,) = abi.decode(log_.data, (uint8, uint64));
        p.status = status;
    }

    /// @dev Reconciliation: release exactly this run's reservation, then record what was actually
    ///      spent. Without this the mirror could over-issue relief after a claim that stopped at
    ///      the target health.
    function _onReliefApplied(IReactive.LogRecord calldata log_) internal {
        if (coveragePoolWitness == address(0) || log_.contractAddress != coveragePoolWitness) {
            return;
        }
        if (log_.opCode != 4 || log_.data.length < 4 * 32) {
            return;
        }

        bytes32 runId = bytes32(log_.topic1);
        uint256 policyId = log_.topic2;
        (uint256 reliefSpent,,,) = abi.decode(log_.data, (uint256, uint256, uint256, uint64));

        uint256 reserved = reservedReliefByRun[runId];
        if (reserved > 0) {
            uint256 current = reliefReserved[policyId];
            reliefReserved[policyId] = current > reserved ? current - reserved : 0;
            delete reservedReliefByRun[runId];
        }
        reliefUsed[policyId] += reliefSpent;
    }

    function _onClaimPaid(IReactive.LogRecord calldata log_) internal {
        if (claimVaultWitness == address(0) || log_.contractAddress != claimVaultWitness) {
            return;
        }
        if (log_.opCode != 4 || log_.data.length < 2 * 32) {
            return;
        }

        bytes32 runId = bytes32(log_.topic1);
        uint256 policyId = log_.topic2;
        (uint256 amount,) = abi.decode(log_.data, (uint256, uint64));

        uint256 reserved = reservedCashByRun[runId];
        if (reserved > 0) {
            uint256 current = cashReserved[policyId];
            cashReserved[policyId] = current > reserved ? current - reserved : 0;
            delete reservedCashByRun[runId];
        }
        cashPaid[policyId] += amount;
    }

    // ---------------------------------------------------------------------------------------
    // Callback requests
    // ---------------------------------------------------------------------------------------

    function _requestRelief(
        bytes32 runId,
        uint256 policyId,
        uint256 reliefLimit,
        uint64 decidedAt,
        uint64 liquidateBlock
    ) private {
        bytes memory payload = abi.encodeWithSignature(
            "settleCascade(address,bytes32,uint256,uint256,uint64,uint64)",
            address(0),
            runId,
            policyId,
            reliefLimit,
            decidedAt,
            liquidateBlock
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: baseChainId, recipient: reliefRecipient, gasLimit: RELIEF_GAS_LIMIT, payload: payload
            })
        );
    }

    function _requestCash(bytes32 runId, uint256 policyId, uint256 cashLimit, uint64 paidThrough, uint64 decidedAt)
        private
    {
        bytes memory payload = abi.encodeWithSignature(
            "payClaim(address,bytes32,uint256,uint256,uint64,uint64)",
            address(0),
            runId,
            policyId,
            cashLimit,
            paidThrough,
            decidedAt
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: unichainChainId, recipient: cashRecipient, gasLimit: CASH_GAS_LIMIT, payload: payload
            })
        );
    }

    function _requestRegistration(uint256 policyId, uint256 cashCeiling, uint64 paidThrough, address cashDestination)
        private
    {
        bytes memory payload = abi.encodeWithSignature(
            "registerPolicy(address,uint256,uint256,uint64,address)",
            address(0),
            policyId,
            cashCeiling,
            paidThrough,
            cashDestination
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: unichainChainId, recipient: cashRecipient, gasLimit: REGISTRATION_GAS_LIMIT, payload: payload
            })
        );
    }
}
