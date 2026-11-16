// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { TestBase } from "../utils/TestBase.sol";
import { Fixtures } from "../utils/Fixtures.sol";
import { Callbacks } from "../utils/Callbacks.sol";
import { FeeMath } from "../../src/libraries/FeeMath.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { MockSystemContract } from "../../src/mocks/MockSystemContract.sol";
import { Topics } from "../../src/libraries/Topics.sol";

/// @notice The dispatch decision: which liquidations produce callbacks, and what those callbacks
///         carry. The reactive contract is the only place the split is computed.
contract ReactiveDispatchTest is TestBase {
    using Callbacks for bytes;

    uint256 internal constant POLICY_ID = 1;
    uint256 internal constant LOG_INDEX = 7;
    uint256 internal constant REPAID = Fixtures.DEMO_REPAID;

    // -------------------------------------------------------------------------------------
    // T094: one liquidation, two callbacks, one runId
    // -------------------------------------------------------------------------------------

    function test_Liquidate_DispatchesReliefAndCash() public {
        _mirrorPolicy();
        _liquidate(marketA, borrower, REPAID, LOG_INDEX);

        assertEq(system.callbackCount(), 3, "registration plus two branches");

        MockSystemContract.CallbackRecord memory relief = system.callbackAt(1);
        MockSystemContract.CallbackRecord memory cash = system.callbackAt(2);

        assertEq(relief.chainId, BASE_CHAIN_ID);
        assertEq(relief.recipient, address(pool));
        assertEq(relief.gasLimit, 900_000);

        assertEq(cash.chainId, UNICHAIN_CHAIN_ID);
        assertEq(cash.recipient, address(vault));
        assertEq(cash.gasLimit, 700_000);

        // Both destination proxies withhold `_extraGas()` (80,000) plus `_maxChargeGas()` (50,000)
        // before forwarding, so a limit has to clear that 130,000 on top of the recipient's work.
        assertGt(relief.gasLimit - 130_000, 400_000, "relief headroom too thin");
        assertGt(cash.gasLimit - 130_000, 300_000, "cash headroom too thin");

        Callbacks.Relief memory r = Callbacks.relief(relief.payload);
        Callbacks.Cash memory c = Callbacks.cash(cash.payload);

        assertEq(r.runId, c.runId, "both branches must share one runId");
        assertEq(r.runId, _runId(LOG_INDEX));
        assertEq(r.sender, address(0), "the proxy injects the sender; the payload says zero");
        assertEq(c.sender, address(0));
        assertEq(r.policyId, POLICY_ID);
        assertEq(c.policyId, POLICY_ID);
        (uint256 cashShare, uint256 reliefShare) = FeeMath.split(_fee(), Fixtures.RELIEF_SHARE_BPS);
        assertEq(r.reliefLimit, reliefShare);
        assertEq(c.cashLimit, cashShare);
        assertEq(r.decidedAt, uint64(block.timestamp));
        assertEq(c.decidedAt, uint64(block.timestamp));
        assertEq(r.liquidateBlock, 100, "the origin block, not the Lasna block");
        assertEq(c.paidThrough, uint64(block.timestamp + 30 days));
        assertTrue(reactive.dispatched(r.runId));
        assertEq(reactive.lastClaimAt(borrower), uint64(block.timestamp));
    }

    function test_Liquidate_ReservesBeforeDispatching() public {
        _mirrorPolicy();
        _liquidate(marketA, borrower, REPAID, LOG_INDEX);

        (uint256 cashShare, uint256 reliefShare) = FeeMath.split(_fee(), Fixtures.RELIEF_SHARE_BPS);
        assertEq(reactive.reliefReserved(POLICY_ID), reliefShare);
        assertEq(reactive.cashReserved(POLICY_ID), cashShare);

        bytes32 runId = _runId(LOG_INDEX);
        assertEq(reactive.reservedReliefByRun(runId), reliefShare);
        assertEq(reactive.reservedCashByRun(runId), cashShare);
    }

    // -------------------------------------------------------------------------------------
    // T095: every guard produces zero callbacks
    // -------------------------------------------------------------------------------------

    function test_Liquidate_LapsedPremium_Ignores() public {
        _mirrorPolicy();
        vm.warp(block.timestamp + 31 days);

        _liquidate(marketA, borrower, REPAID, LOG_INDEX);
        assertEq(system.callbackCount(), 1, "registration only");
    }

    function test_Liquidate_UnknownLoan_Ignores() public {
        _mirrorPolicy();

        _liquidate(marketB, borrower, REPAID, LOG_INDEX);
        assertEq(system.callbackCount(), 1);
        assertFalse(reactive.dispatched(_runId(LOG_INDEX)));
    }

    function test_Liquidate_UnknownBorrower_Ignores() public {
        _mirrorPolicy();

        _liquidate(marketA, twin, REPAID, LOG_INDEX);
        assertEq(system.callbackCount(), 1);
    }

    function test_Liquidate_ZeroFee_Ignores() public {
        _mirrorPolicy();

        // One wei of repaid debt rounds the penalty to zero.
        _liquidate(marketA, borrower, 1, LOG_INDEX);
        assertEq(system.callbackCount(), 1);
        assertFalse(reactive.dispatched(_runId(LOG_INDEX)));
    }

    function test_Liquidate_PausedPolicy_Ignores() public {
        _mirrorPolicy();
        _setStatus(POLICY_ID, 2);

        _liquidate(marketA, borrower, REPAID, LOG_INDEX);
        assertEq(system.callbackCount(), 1);
    }

    function test_Liquidate_CancelledPolicy_Ignores() public {
        _mirrorPolicy();
        _setStatus(POLICY_ID, 3);

        _liquidate(marketA, borrower, REPAID, LOG_INDEX);
        assertEq(system.callbackCount(), 1);
    }

    function test_Liquidate_UnsubscribedEmitter_Ignores() public {
        _mirrorPolicy();

        IReactive.LogRecord memory record = _liquidateRecord(marketA, borrower, REPAID, LOG_INDEX);
        record.contractAddress = address(0xBAD);

        vm.prank(SYSTEM_ADDRESS);
        reactive.react(record);

        assertEq(system.callbackCount(), 1);
    }

    // -------------------------------------------------------------------------------------
    // T096: replay and distinct logs
    // -------------------------------------------------------------------------------------

    function test_Liquidate_SameRunTwice_OneDispatch() public {
        _mirrorPolicy();
        _liquidate(marketA, borrower, REPAID, LOG_INDEX);
        uint256 afterFirst = system.callbackCount();

        _liquidate(marketA, borrower, REPAID, LOG_INDEX);
        assertEq(system.callbackCount(), afterFirst);
    }

    function test_Liquidate_DifferentLogIndex_SecondDispatch() public {
        _mirrorPolicy();
        _liquidate(marketA, borrower, REPAID, LOG_INDEX);
        // Past the 60-second cascade window, so the second claim takes the standard split again.
        vm.warp(block.timestamp + 61);
        _liquidate(marketA, borrower, REPAID, LOG_INDEX + 1);

        assertEq(system.callbackCount(), 5, "two branches for each distinct liquidation");
        assertTrue(reactive.dispatched(_runId(LOG_INDEX)));
        assertTrue(reactive.dispatched(_runId(LOG_INDEX + 1)));
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    function _mirrorPolicy() internal {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            IReactive.LogRecord({
                chainId: BASE_CHAIN_ID,
                contractAddress: address(registry),
                topic0: uint256(Topics.POLICY_CREATED),
                topic1: POLICY_ID,
                topic2: uint256(uint160(borrower)),
                topic3: uint256(marketA),
                data: _policyCreatedData(),
                blockNumber: 90,
                opCode: 4,
                blockHash: uint256(keccak256("block")),
                txHash: uint256(keccak256("create-tx")),
                logIndex: 0
            })
        );
    }

    function _setStatus(uint256 policyId, uint8 status) internal {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            IReactive.LogRecord({
                chainId: BASE_CHAIN_ID,
                contractAddress: address(registry),
                topic0: uint256(Topics.STATUS_CHANGED),
                topic1: policyId,
                topic2: 0,
                topic3: 0,
                data: abi.encode(status, uint64(0)),
                blockNumber: 91,
                opCode: 2,
                blockHash: uint256(keccak256("block")),
                txHash: uint256(keccak256("status-tx")),
                logIndex: 1
            })
        );
    }

    function _liquidate(bytes32 marketId, address account, uint256 repaidAssets, uint256 logIndex) internal {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(_liquidateRecord(marketId, account, repaidAssets, logIndex));
    }

    function _liquidateRecord(bytes32 marketId, address account, uint256 repaidAssets, uint256 logIndex)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord({
            chainId: BASE_CHAIN_ID,
            contractAddress: address(morpho),
            topic0: uint256(Topics.LIQUIDATE),
            topic1: uint256(marketId),
            topic2: uint256(uint160(liquidator)),
            topic3: uint256(uint160(account)),
            data: abi.encode(repaidAssets, uint256(0), uint256(0), uint256(0), uint256(0)),
            blockNumber: 100,
            opCode: 4,
            blockHash: uint256(keccak256("block")),
            txHash: uint256(keccak256("tx")),
            logIndex: logIndex
        });
    }

    function _fee() internal pure returns (uint256) {
        return FeeMath.penalty(REPAID, Fixtures.LLTV);
    }

    function _runId(uint256 logIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(BASE_CHAIN_ID, bytes32(uint256(keccak256("tx"))), logIndex));
    }

    function _policyCreatedData() internal view returns (bytes memory) {
        uint256 premiumPerSecond = (Fixtures.COVERAGE_CAP * Fixtures.APR_BPS) / (10_000 * 365 days);
        return abi.encode(
            Fixtures.COVERAGE_CAP,
            uint256(2_000e18),
            uint256(3_000e18),
            premiumPerSecond,
            uint64(block.timestamp + 30 days),
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.LLTV
        );
    }
}
