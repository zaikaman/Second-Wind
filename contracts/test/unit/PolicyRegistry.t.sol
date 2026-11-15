// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { TestBase } from "../utils/TestBase.sol";
import { Fixtures } from "../utils/Fixtures.sol";
import { PolicyRegistry } from "../../src/base/PolicyRegistry.sol";
import { IMorpho } from "../../src/interfaces/IMorpho.sol";

/// @notice Policy lifecycle: every revert path from the interface contract, the premium formula,
///         status transitions, and the ceiling arithmetic.
contract PolicyRegistryTest is TestBase {
    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    function _policyOn(bytes32 marketId) internal returns (uint256 policyId) {
        vm.prank(borrower);
        policyId = registry.createPolicy(
            marketId,
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.PREMIUM_TERM
        );
    }

    function _createPolicyOnMarket(bytes32 marketId, uint256 cap) internal returns (uint256 policyId) {
        vm.prank(borrower);
        policyId = registry.createPolicy(
            marketId, cap, Fixtures.RELIEF_SHARE_BPS, Fixtures.TARGET_HEALTH, cashDestination, Fixtures.PREMIUM_TERM
        );
    }

    // -------------------------------------------------------------------------------------
    // Creation: happy path and stored terms
    // -------------------------------------------------------------------------------------

    function test_CreatePolicy_StoresTerms() public {
        uint256 policyId = _createPolicyOnA();
        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);

        assertEq(policyId, 1);
        assertEq(p.borrower, borrower);
        assertEq(p.marketId, marketA);
        assertEq(p.coverageCap, Fixtures.COVERAGE_CAP);
        assertEq(p.cashCeiling, 2_000e18);
        assertEq(p.reliefCeiling, 3_000e18);
        assertEq(p.reliefShareBps, Fixtures.RELIEF_SHARE_BPS);
        assertEq(p.targetHealthWad, Fixtures.TARGET_HEALTH);
        assertEq(p.cashDestination, cashDestination);
        assertEq(uint8(p.status), uint8(PolicyRegistry.Status.Active));
        assertEq(p.paidThrough, uint64(block.timestamp) + Fixtures.PREMIUM_TERM);
        assertEq(registry.policyOfLoan(registry.loanKey(marketA, borrower)), policyId);
        assertEq(registry.policiesOf(borrower).length, 1);
        assertTrue(registry.isCoverable(policyId));
    }

    // -------------------------------------------------------------------------------------
    // Creation: every revert path
    // -------------------------------------------------------------------------------------

    function test_RevertWhen_MarketNotSupported() public {
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.MarketNotSupported.selector, bytes32(0)));
        registry.createPolicy(
            bytes32(0),
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_LoanTokenNotCoverAsset() public {
        IMorpho.MarketParams memory params = IMorpho.MarketParams({
            loanToken: address(weth),
            collateralToken: address(usdc),
            oracle: address(oracle),
            irm: address(uint160(99_999)),
            lltv: Fixtures.LLTV
        });
        morpho.createMarket(params);
        bytes32 id = morpho.marketIdOf(params);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.MarketNotSupported.selector, id));
        registry.createPolicy(
            id,
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_LoanNotOpen() public {
        bytes32 emptyMarket = _newMarket(Fixtures.LLTV, 42);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.LoanNotOpen.selector, emptyMarket, borrower));
        registry.createPolicy(
            emptyMarket,
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_LoanUnhealthy() public {
        // At 2000 the loan A health factor is 0.955: cover for an already-liquidatable loan is out
        // of scope.
        oracle.setPrice(2000e36);

        vm.prank(borrower);
        vm.expectRevert();
        registry.createPolicy(
            marketA,
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_PolicyExists() public {
        uint256 policyId = _createPolicyOnA();

        vm.expectRevert(
            abi.encodeWithSelector(PolicyRegistry.PolicyExists.selector, registry.loanKey(marketA, borrower), policyId)
        );
        vm.prank(borrower);
        registry.createPolicy(
            marketA,
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.PREMIUM_TERM
        );
    }

    function test_CancelledPolicy_FreesTheLoan() public {
        uint256 policyId = _createPolicyOnA();
        vm.prank(borrower);
        registry.cancelPolicy(policyId);

        uint256 second = _policyOn(marketA);
        assertEq(second, 2);
    }

    function test_RevertWhen_TooManyPolicies() public {
        // A borrower can hold at most MAX_POLICIES; the cap bounds the relief loop.
        _policyOn(marketA);
        _policyOn(marketB);
        for (uint256 i = 0; i < 6; ++i) {
            bytes32 id = _newMarket(Fixtures.LLTV, 100 + i);
            _openLoan(id, borrower, Fixtures.LOAN_B_COLLATERAL, Fixtures.LOAN_B_DEBT);
            _policyOn(id);
        }

        bytes32 ninth = _newMarket(Fixtures.LLTV, 200);
        _openLoan(ninth, borrower, Fixtures.LOAN_B_COLLATERAL, Fixtures.LOAN_B_DEBT);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.TooManyPolicies.selector, borrower, 8));
        registry.createPolicy(
            ninth,
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_CapOutOfRange() public {
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.CapOutOfRange.selector, 99e18));
        registry.createPolicy(
            marketA, 99e18, Fixtures.RELIEF_SHARE_BPS, Fixtures.TARGET_HEALTH, cashDestination, Fixtures.PREMIUM_TERM
        );

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.CapOutOfRange.selector, 5_001e18));
        registry.createPolicy(
            marketA, 5_001e18, Fixtures.RELIEF_SHARE_BPS, Fixtures.TARGET_HEALTH, cashDestination, Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_ShareOutOfRange() public {
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.ShareOutOfRange.selector, uint16(10_001)));
        registry.createPolicy(
            marketA, Fixtures.COVERAGE_CAP, 10_001, Fixtures.TARGET_HEALTH, cashDestination, Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_TargetOutOfRange() public {
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.TargetOutOfRange.selector, 1.04e18));
        registry.createPolicy(
            marketA, Fixtures.COVERAGE_CAP, Fixtures.RELIEF_SHARE_BPS, 1.04e18, cashDestination, Fixtures.PREMIUM_TERM
        );

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.TargetOutOfRange.selector, 1.51e18));
        registry.createPolicy(
            marketA, Fixtures.COVERAGE_CAP, Fixtures.RELIEF_SHARE_BPS, 1.51e18, cashDestination, Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_ZeroDestination() public {
        vm.prank(borrower);
        vm.expectRevert(PolicyRegistry.ZeroDestination.selector);
        registry.createPolicy(
            marketA,
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            address(0),
            Fixtures.PREMIUM_TERM
        );
    }

    function test_RevertWhen_TermOutOfRange() public {
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.TermOutOfRange.selector, uint32(1 hours)));
        registry.createPolicy(
            marketA, Fixtures.COVERAGE_CAP, Fixtures.RELIEF_SHARE_BPS, Fixtures.TARGET_HEALTH, cashDestination, 1 hours
        );

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.TermOutOfRange.selector, uint32(366 days)));
        registry.createPolicy(
            marketA, Fixtures.COVERAGE_CAP, Fixtures.RELIEF_SHARE_BPS, Fixtures.TARGET_HEALTH, cashDestination, 366 days
        );
    }

    // -------------------------------------------------------------------------------------
    // Premium
    // -------------------------------------------------------------------------------------

    function test_Premium_Formula() public {
        uint256 expectedPerSecond = (Fixtures.COVERAGE_CAP * Fixtures.APR_BPS) / (10_000 * 365 days);
        uint256 policyId = _createPolicyOnA();
        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);

        assertEq(p.premiumPerSecond, expectedPerSecond);
        assertEq(usdc.balanceOf(address(pool)), RESERVE_SEED + expectedPerSecond * Fixtures.PREMIUM_TERM);
    }

    function test_Premium_TruncatesDown() public {
        // 3% APR on a cap that does not divide evenly: the per-second rate is floored, so the pool
        // never collects more than the advertised APR.
        uint256 cap = 123.456789e18;
        uint256 policyId = _createPolicyOnMarket(marketA, cap);
        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);

        assertEq(p.premiumPerSecond, (cap * Fixtures.APR_BPS) / (10_000 * 365 days));
        assertLe(
            p.premiumPerSecond * Fixtures.PREMIUM_TERM,
            (cap * Fixtures.APR_BPS * Fixtures.PREMIUM_TERM) / (10_000 * 365 days)
        );
    }

    function test_PayPremium_AdvancesPaidThrough() public {
        uint256 policyId = _createPolicyOnA();
        PolicyRegistry.Policy memory before = registry.getPolicy(policyId);

        uint256 amount = before.premiumPerSecond * 10 days;
        vm.prank(borrower);
        registry.payPremium(policyId, amount);

        PolicyRegistry.Policy memory afterPay = registry.getPolicy(policyId);
        assertEq(afterPay.paidThrough, before.paidThrough + 10 days);
    }

    function test_PayPremium_CappedAtOneYear() public {
        uint256 policyId = _createPolicyOnA();

        vm.prank(borrower);
        registry.payPremium(policyId, 100_000e18);

        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(p.paidThrough, uint64(block.timestamp) + 365 days);
    }

    function test_PayPremium_AmountTooSmall() public {
        uint256 policyId = _createPolicyOnA();
        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.AmountTooSmall.selector, 1, p.premiumPerSecond));
        registry.payPremium(policyId, 1);
    }

    function test_PayPremium_OnlyBorrower() public {
        uint256 policyId = _createPolicyOnA();

        vm.prank(twin);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.NotBorrower.selector, policyId, twin));
        registry.payPremium(policyId, 1_000e18);
    }

    // -------------------------------------------------------------------------------------
    // Status
    // -------------------------------------------------------------------------------------

    function test_Pause_BlocksIsCoverable() public {
        uint256 policyId = _createPolicyOnA();
        assertTrue(registry.isCoverable(policyId));

        vm.prank(borrower);
        registry.pausePolicy(policyId);

        assertFalse(registry.isCoverable(policyId));
        assertEq(uint8(registry.getPolicy(policyId).status), uint8(PolicyRegistry.Status.Paused));
    }

    function test_Resume_RestoresCoverable() public {
        uint256 policyId = _createPolicyOnA();

        vm.prank(borrower);
        registry.pausePolicy(policyId);
        vm.prank(borrower);
        registry.resumePolicy(policyId);

        assertTrue(registry.isCoverable(policyId));
        assertEq(uint8(registry.getPolicy(policyId).status), uint8(PolicyRegistry.Status.Active));
    }

    function test_Cancel_IsTerminalAndSetsBlock() public {
        uint256 policyId = _createPolicyOnA();

        vm.prank(borrower);
        registry.cancelPolicy(policyId);

        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(uint8(p.status), uint8(PolicyRegistry.Status.Cancelled));
        assertEq(p.cancelledAtBlock, uint64(block.number));
        assertFalse(registry.isCoverable(policyId));

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyRegistry.PolicyNotLive.selector, policyId, uint8(PolicyRegistry.Status.Cancelled)
            )
        );
        registry.resumePolicy(policyId);
    }

    function test_NonBorrower_CannotPauseOrCancel() public {
        uint256 policyId = _createPolicyOnA();

        vm.prank(twin);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.NotBorrower.selector, policyId, twin));
        registry.pausePolicy(policyId);

        vm.prank(twin);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.NotBorrower.selector, policyId, twin));
        registry.cancelPolicy(policyId);
    }

    // -------------------------------------------------------------------------------------
    // Caps
    // -------------------------------------------------------------------------------------

    function test_RecordRelief_OnlyPool() public {
        uint256 policyId = _createPolicyOnA();

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.OnlyCoveragePool.selector, borrower));
        registry.recordRelief(policyId, 1e18);
    }

    function test_RecordRelief_CapsAtReliefCeiling() public {
        uint256 policyId = _createPolicyOnA();

        vm.prank(address(pool));
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.CapExceeded.selector, 3_001e18, 3_000e18));
        registry.recordRelief(policyId, 3_001e18);

        vm.prank(address(pool));
        registry.recordRelief(policyId, 3_000e18);
        assertEq(registry.reliefRemaining(policyId), 0);
        assertFalse(registry.isCoverable(policyId));
    }

    function test_SetCoveragePool_OneTimeOnly() public {
        vm.expectRevert(PolicyRegistry.AlreadySet.selector);
        registry.setCoveragePool(address(0xBEEF));
    }

    function testFuzz_CeilingsSumToCap(uint256 capSeed, uint16 shareSeed) public {
        uint256 cap = bound(capSeed, registry.MIN_CAP(), registry.MAX_CAP());
        uint16 share = uint16(bound(uint256(shareSeed), 0, 10_000));

        vm.prank(borrower);
        uint256 policyId = registry.createPolicy(
            marketA, cap, share, Fixtures.TARGET_HEALTH, cashDestination, Fixtures.PREMIUM_TERM
        );

        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(p.cashCeiling + p.reliefCeiling, cap);
        assertEq(p.cashCeiling, (cap * (10_000 - share)) / 10_000);
        assertEq(p.reliefCeiling, cap - p.cashCeiling);
    }
}
