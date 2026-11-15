// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Vm } from "forge-std/Vm.sol";
import { TestBase } from "../utils/TestBase.sol";
import { Fixtures } from "../utils/Fixtures.sol";
import { CoveragePool } from "../../src/base/CoveragePool.sol";
import { PolicyRegistry } from "../../src/base/PolicyRegistry.sol";
import { IMorpho } from "../../src/interfaces/IMorpho.sol";
import { ReasonCodes } from "../../src/libraries/ReasonCodes.sol";
import { HealthMath } from "../../src/libraries/HealthMath.sol";

/// @notice The relief branch: it re-reads the policy, picks the weakest loan and repays exactly the
///         amount needed, never more than the limit, the debt, or the remaining ceiling.
contract CoveragePoolTest is TestBase {
    bytes32 internal constant RUN_ID = keccak256("run-relief");
    uint256 internal constant RELIEF_LIMIT = 2_367.422e18;

    function _settle(bytes32 runId, uint256 policyId, uint256 limit, uint64 decidedAt, uint64 liquidateBlock) internal {
        vm.prank(BASE_CALLBACK_PROXY);
        pool.settleCascade(address(reactive), runId, policyId, limit, decidedAt, liquidateBlock);
    }

    // -------------------------------------------------------------------------------------
    // T097: a valid claim repays, consumes the run, emits, and reduces the reserve
    // -------------------------------------------------------------------------------------

    function test_Settle_RepaysWeakestLoan() public {
        uint256 policyId = _createPolicyOnA();
        // Crash the price after the policy exists: A falls to 1.0511, B to 1.1129, so A is weakest.
        oracle.setPrice(2200e36);

        uint256 debtBefore = _positionDebt(marketA, borrower);
        uint256 reserveBefore = pool.reserveBalance();
        uint64 decidedAt = uint64(block.timestamp);

        vm.expectEmit(true, true, true, false, address(pool));
        emit CoveragePool.ReliefApplied(RUN_ID, policyId, marketA, RELIEF_LIMIT, 0, 0, decidedAt);
        _settle(RUN_ID, policyId, RELIEF_LIMIT, decidedAt, uint64(block.number));

        assertTrue(pool.usedRun(RUN_ID));
        assertEq(pool.reserveBalance(), reserveBefore - RELIEF_LIMIT);
        assertEq(_positionDebt(marketA, borrower), debtBefore - RELIEF_LIMIT);
        assertEq(registry.getPolicy(policyId).reliefUsed, RELIEF_LIMIT);
        assertEq(registry.reliefRemaining(policyId), 3_000e18 - RELIEF_LIMIT);
    }

    function test_Settle_EventCarriesDebtAndHealthAfter() public {
        uint256 policyId = _createPolicyOnA();
        oracle.setPrice(2200e36);

        uint64 decidedAt = uint64(block.timestamp);
        vm.recordLogs();
        _settle(RUN_ID, policyId, RELIEF_LIMIT, decidedAt, uint64(block.number));

        (uint256 spent, uint256 debtAfter, uint256 healthAfter,) = _lastReliefData();
        assertEq(spent, RELIEF_LIMIT);
        assertEq(debtAfter, _positionDebt(marketA, borrower));
        assertGt(healthAfter, 1.0511e18, "health must improve");
    }

    function test_Settle_ConsumesRunId() public {
        uint256 policyId = _createPolicyOnA();
        oracle.setPrice(2200e36);

        uint64 decidedAt = uint64(block.timestamp);
        _settle(RUN_ID, policyId, RELIEF_LIMIT, decidedAt, uint64(block.number));

        vm.expectRevert(
            abi.encodeWithSelector(CoveragePool.DuplicateRun.selector, RUN_ID, ReasonCodes.DUPLICATE_DELIVERY)
        );
        vm.prank(BASE_CALLBACK_PROXY);
        pool.settleCascade(address(reactive), RUN_ID, policyId, RELIEF_LIMIT, decidedAt, uint64(block.number));
    }

    function test_Settle_StopsAtTargetHealth() public {
        uint256 policyId = _createPolicyOnA();
        // A is at 1.1498 at 2400: the relief needed to reach 1.15 is small, far below the limit.
        oracle.setPrice(2400e36);

        uint64 decidedAt = uint64(block.timestamp);
        vm.recordLogs();
        _settle(RUN_ID, policyId, RELIEF_LIMIT, decidedAt, uint64(block.number));

        (uint256 spent,, uint256 healthAfter,) = _lastReliefData();
        assertLt(spent, RELIEF_LIMIT, "must not spend more than the target needs");
        assertApproxEqAbs(healthAfter, Fixtures.TARGET_HEALTH, 1e15);

        // The unspent remainder stays as relief capacity for the next claim (FR-009).
        assertEq(registry.reliefRemaining(policyId), 3_000e18 - spent);
    }

    function test_Settle_AlreadyAboveTarget_EmitsZero() public {
        uint256 policyId = _createPolicyOnA();
        uint256 reserveBefore = pool.reserveBalance();

        uint64 decidedAt = uint64(block.timestamp);
        vm.expectEmit(true, true, true, false, address(pool));
        emit CoveragePool.ReliefApplied(RUN_ID, policyId, marketA, 0, 0, 0, decidedAt);
        _settle(RUN_ID, policyId, RELIEF_LIMIT, decidedAt, uint64(block.number));

        assertTrue(pool.usedRun(RUN_ID), "a zero claim still consumes the run");
        assertEq(pool.reserveBalance(), reserveBefore, "no relief was spent");
    }

    // -------------------------------------------------------------------------------------
    // Rejections carry reason codes
    // -------------------------------------------------------------------------------------

    function test_Settle_PremiumLapsed_Reverts() public {
        uint256 policyId = _createPolicyOnA();
        uint64 decidedAt = uint64(block.timestamp + 31 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                CoveragePool.PremiumLapsed.selector,
                registry.getPolicy(policyId).paidThrough,
                decidedAt,
                ReasonCodes.PREMIUM_LAPSED
            )
        );
        _settle(RUN_ID, policyId, RELIEF_LIMIT, decidedAt, uint64(block.number));
    }

    function test_Settle_Paused_Reverts() public {
        uint256 policyId = _createPolicyOnA();
        vm.prank(borrower);
        registry.pausePolicy(policyId);

        vm.expectRevert(
            abi.encodeWithSelector(CoveragePool.PolicyNotLive.selector, policyId, uint8(2), ReasonCodes.POLICY_PAUSED)
        );
        _settle(RUN_ID, policyId, RELIEF_LIMIT, uint64(block.timestamp), uint64(block.number));
    }

    function test_Settle_CancelledBeforeLiquidation_Reverts() public {
        uint256 policyId = _createPolicyOnA();
        vm.prank(borrower);
        registry.cancelPolicy(policyId);
        uint64 cancelledAt = registry.getPolicy(policyId).cancelledAtBlock;

        vm.expectRevert(
            abi.encodeWithSelector(
                CoveragePool.PolicyCancelled.selector, policyId, cancelledAt, ReasonCodes.POLICY_CANCELLED
            )
        );
        _settle(RUN_ID, policyId, RELIEF_LIMIT, uint64(block.timestamp), cancelledAt);
    }

    function test_Settle_CancelledAfterLiquidation_IsHonoured() public {
        uint256 policyId = _createPolicyOnA();
        oracle.setPrice(2200e36);
        uint64 liquidateBlock = uint64(block.number);

        // Cancellation lands in a later block than the liquidation it must not erase.
        vm.roll(block.number + 1);
        vm.prank(borrower);
        registry.cancelPolicy(policyId);

        _settle(RUN_ID, policyId, RELIEF_LIMIT, uint64(block.timestamp), liquidateBlock);
        assertTrue(pool.usedRun(RUN_ID));
    }

    function test_Settle_ExceedsRemainingCap_Reverts() public {
        uint256 policyId = _createPolicyOnA();
        oracle.setPrice(2200e36);

        vm.expectRevert(
            abi.encodeWithSelector(
                CoveragePool.CapExceeded.selector, 3_001e18, 3_000e18, ReasonCodes.COVERAGE_EXHAUSTED
            )
        );
        _settle(RUN_ID, policyId, 3_001e18, uint64(block.timestamp), uint64(block.number));
    }

    function test_Settle_ReserveInsufficient_Reverts() public {
        uint256 policyId = _createPolicyOnA();
        oracle.setPrice(2200e36);

        vm.prank(address(pool));
        usdc.transfer(address(0xdEaD), RESERVE_SEED);
        uint256 available = pool.reserveBalance();

        vm.expectRevert(
            abi.encodeWithSelector(
                CoveragePool.ReserveInsufficient.selector, RELIEF_LIMIT, available, ReasonCodes.DESTINATION_UNDERFUNDED
            )
        );
        _settle(RUN_ID, policyId, RELIEF_LIMIT, uint64(block.timestamp), uint64(block.number));

        assertFalse(pool.usedRun(RUN_ID), "a rejected claim must not consume the run");
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    function _positionDebt(bytes32 marketId, address account) internal view returns (uint256) {
        IMorpho.Market memory m = morpho.market(marketId);
        return HealthMath.toAssetsUp(
            morpho.position(marketId, account).borrowShares, m.totalBorrowAssets, m.totalBorrowShares
        );
    }

    function _lastReliefData()
        internal
        returns (uint256 spent, uint256 debtAfter, uint256 healthAfter, uint64 appliedAt)
    {
        // `vm.recordLogs` was called by the test; read the most recent ReliefApplied.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            Vm.Log memory entry = logs[i - 1];
            if (
                entry.topics.length == 4
                    && entry.topics[0]
                        == keccak256("ReliefApplied(bytes32,uint256,bytes32,uint256,uint256,uint256,uint64)")
            ) {
                (spent, debtAfter, healthAfter, appliedAt) = abi.decode(entry.data, (uint256, uint256, uint256, uint64));
                return (spent, debtAfter, healthAfter, appliedAt);
            }
        }
        revert("no ReliefApplied log");
    }
}
