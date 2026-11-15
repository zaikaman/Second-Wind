// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { TestBase } from "../utils/TestBase.sol";
import { ClaimVault } from "../../src/unichain/ClaimVault.sol";
import { ReasonCodes } from "../../src/libraries/ReasonCodes.sol";

/// @notice The cash branch: write-once terms, one payout per run, and no partial effects on failure.
contract ClaimVaultTest is TestBase {
    uint256 internal constant POLICY_ID = 7;
    bytes32 internal constant RUN_ID = keccak256("run-cash");

    function _register(uint256 policyId, uint256 ceiling, address destination) internal {
        vm.prank(UNICHAIN_CALLBACK_PROXY);
        vault.registerPolicy(address(reactive), policyId, ceiling, uint64(block.timestamp + 30 days), destination);
    }

    function _pay(bytes32 runId, uint256 policyId, uint256 amount, uint64 paidThrough, uint64 decidedAt) internal {
        vm.prank(UNICHAIN_CALLBACK_PROXY);
        vault.payClaim(address(reactive), runId, policyId, amount, paidThrough, decidedAt);
    }

    // -------------------------------------------------------------------------------------
    // T093: registration
    // -------------------------------------------------------------------------------------

    function test_RegisterPolicy_StoresWriteOnceTerms() public {
        _register(POLICY_ID, 2_000e18, cashDestination);

        assertEq(vault.cashCeilingOf(POLICY_ID), 2_000e18);
        assertEq(vault.destinationOf(POLICY_ID), cashDestination);
        assertEq(vault.cashPaidOf(POLICY_ID), 0);
        assertEq(vault.lastPaidThroughOf(POLICY_ID), uint64(block.timestamp + 30 days));
    }

    function test_RegisterPolicy_IsIdempotent() public {
        _register(POLICY_ID, 2_000e18, cashDestination);

        // A second identical registration emits nothing and changes nothing.
        vm.recordLogs();
        _register(POLICY_ID, 2_000e18, cashDestination);
        assertEq(vm.getRecordedLogs().length, 0, "idempotent registration must not emit");
        assertEq(vault.cashCeilingOf(POLICY_ID), 2_000e18);
    }

    function test_RegisterPolicy_TermsMismatch() public {
        _register(POLICY_ID, 2_000e18, cashDestination);

        vm.expectRevert(abi.encodeWithSelector(ClaimVault.TermsMismatch.selector, POLICY_ID));
        _register(POLICY_ID, 2_100e18, cashDestination);

        vm.expectRevert(abi.encodeWithSelector(ClaimVault.TermsMismatch.selector, POLICY_ID));
        _register(POLICY_ID, 2_000e18, makeAddr("otherDestination"));
    }

    function test_RegisterPolicy_ZeroDestination() public {
        vm.expectRevert(ClaimVault.ZeroDestination.selector);
        _register(POLICY_ID, 2_000e18, address(0));
    }

    function test_RegisterPolicy_CeilingTooLarge() public {
        vm.expectRevert(abi.encodeWithSelector(ClaimVault.CeilingTooLarge.selector, 10_001e18));
        _register(POLICY_ID, 10_001e18, cashDestination);
    }

    // -------------------------------------------------------------------------------------
    // T093/T109: payment
    // -------------------------------------------------------------------------------------

    function test_PayClaim_TransfersToRegisteredDestination() public {
        _register(POLICY_ID, 2_000e18, cashDestination);
        uint64 paidThrough = uint64(block.timestamp + 30 days);
        uint64 decidedAt = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true, address(vault));
        emit ClaimVault.ClaimPaid(RUN_ID, POLICY_ID, cashDestination, 1_578.281e18, paidThrough);
        _pay(RUN_ID, POLICY_ID, 1_578.281e18, paidThrough, decidedAt);

        assertEq(usdc.balanceOf(cashDestination), 1_578.281e18);
        assertEq(vault.cashPaidOf(POLICY_ID), 1_578.281e18);
        assertEq(vault.lastPaidThroughOf(POLICY_ID), paidThrough);
        assertTrue(vault.usedRun(RUN_ID));
        assertEq(vault.reserveBalance(), RESERVE_SEED - 1_578.281e18);
    }

    function test_PayClaim_DuplicateRun_Reverts() public {
        _register(POLICY_ID, 2_000e18, cashDestination);
        uint64 paidThrough = uint64(block.timestamp + 30 days);
        _pay(RUN_ID, POLICY_ID, 1_000e18, paidThrough, uint64(block.timestamp));

        vm.expectRevert(
            abi.encodeWithSelector(ClaimVault.DuplicateRun.selector, RUN_ID, ReasonCodes.DUPLICATE_DELIVERY)
        );
        _pay(RUN_ID, POLICY_ID, 1_000e18, paidThrough, uint64(block.timestamp));

        assertEq(usdc.balanceOf(cashDestination), 1_000e18);
        assertEq(vault.cashPaidOf(POLICY_ID), 1_000e18);
    }

    function test_PayClaim_CappedByCeiling() public {
        _register(POLICY_ID, 500e18, cashDestination);
        uint64 paidThrough = uint64(block.timestamp + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(ClaimVault.CapExceeded.selector, 501e18, 500e18, ReasonCodes.COVERAGE_EXHAUSTED)
        );
        _pay(RUN_ID, POLICY_ID, 501e18, paidThrough, uint64(block.timestamp));

        _pay(RUN_ID, POLICY_ID, 500e18, paidThrough, uint64(block.timestamp));
        assertEq(vault.cashPaidOf(POLICY_ID), 500e18);
    }

    function test_PayClaim_ReserveShortfall_LeavesNoEffects() public {
        _register(POLICY_ID, 2_000e18, cashDestination);
        // Leave half a token in the reserve, less than the claim needs.
        vm.prank(address(vault));
        usdc.transfer(address(0xdEaD), RESERVE_SEED - 0.5e18);

        bytes32 shortRun = keccak256("short");
        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimVault.ReserveInsufficient.selector, 1e18, 0.5e18, ReasonCodes.DESTINATION_UNDERFUNDED
            )
        );
        _pay(shortRun, POLICY_ID, 1e18, uint64(block.timestamp + 30 days), uint64(block.timestamp));

        assertFalse(vault.usedRun(shortRun));
        assertEq(vault.cashPaidOf(POLICY_ID), 0);
        assertEq(vault.reserveBalance(), 0.5e18);
    }

    function test_PayClaim_ZeroAmount() public {
        _register(POLICY_ID, 2_000e18, cashDestination);

        vm.expectRevert(abi.encodeWithSelector(ClaimVault.ZeroFee.selector, ReasonCodes.ZERO_FEE));
        _pay(RUN_ID, POLICY_ID, 0, uint64(block.timestamp + 30 days), uint64(block.timestamp));
    }

    function test_PayClaim_StaleWindow() public {
        _register(POLICY_ID, 2_000e18, cashDestination);
        uint64 paidThrough = uint64(block.timestamp + 30 days);
        _pay(keccak256("first"), POLICY_ID, 1e18, paidThrough, uint64(block.timestamp));

        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimVault.StaleWindow.selector, paidThrough - 1 days, paidThrough, ReasonCodes.PREMIUM_LAPSED
            )
        );
        _pay(keccak256("second"), POLICY_ID, 1e18, paidThrough - 1 days, uint64(block.timestamp));
    }

    function test_PayClaim_PremiumLapsed() public {
        _register(POLICY_ID, 2_000e18, cashDestination);

        uint64 paidThrough = uint64(block.timestamp + 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                ClaimVault.PremiumLapsed.selector, paidThrough, paidThrough + 1, ReasonCodes.PREMIUM_LAPSED
            )
        );
        _pay(RUN_ID, POLICY_ID, 1e18, paidThrough, paidThrough + 1);
    }

    function test_PayClaim_UnknownPolicy() public {
        vm.expectRevert(abi.encodeWithSelector(ClaimVault.UnknownPolicy.selector, 99, ReasonCodes.UNKNOWN_LOAN));
        _pay(RUN_ID, 99, 1e18, uint64(block.timestamp), uint64(block.timestamp));
    }
}

