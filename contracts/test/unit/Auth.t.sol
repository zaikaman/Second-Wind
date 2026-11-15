// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { TestBase } from "../utils/TestBase.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { ClaimVault } from "../../src/unichain/ClaimVault.sol";
import { ReasonCodes } from "../../src/libraries/ReasonCodes.sol";

/// @notice Both settlement contracts accept calls only from their callback proxy and only from the
///         recorded reactive contract. Either check alone would be bypassable; together they are
///         the whole access-control story.
contract AuthTest is TestBase {
    bytes32 internal constant RUN_ID = keccak256("run-1");

    function test_Pool_RejectsDirectEOA() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, borrower, BASE_CALLBACK_PROXY));
        vm.prank(borrower);
        pool.settleCascade(borrower, RUN_ID, 1, 0, 0, 0);
    }

    function test_Pool_RejectsWrongInjectedSender() public {
        vm.expectRevert(
            abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, borrower, address(reactive))
        );
        vm.prank(BASE_CALLBACK_PROXY);
        pool.settleCascade(borrower, RUN_ID, 1, 0, 0, 0);
    }

    function test_Vault_RejectsDirectEOA() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, borrower, UNICHAIN_CALLBACK_PROXY));
        vm.prank(borrower);
        vault.payClaim(borrower, RUN_ID, 1, 1e18, 0, 0);
    }

    function test_Vault_RejectsWrongInjectedSender() public {
        vm.expectRevert(
            abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, borrower, address(reactive))
        );
        vm.prank(UNICHAIN_CALLBACK_PROXY);
        vault.payClaim(borrower, RUN_ID, 1, 1e18, 0, 0);
    }

    function test_Vault_RegisterPolicy_RejectsDirectEOA() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, borrower, UNICHAIN_CALLBACK_PROXY));
        vm.prank(borrower);
        vault.registerPolicy(borrower, 1, 2_000e18, 0, cashDestination);
    }

    function test_Vault_PayClaim_UnknownPolicy_RevertsAndChangesNothing() public {
        uint256 balanceBefore = vault.reserveBalance();

        vm.expectRevert(abi.encodeWithSelector(ClaimVault.UnknownPolicy.selector, 42, ReasonCodes.UNKNOWN_LOAN));
        vm.prank(UNICHAIN_CALLBACK_PROXY);
        vault.payClaim(address(reactive), RUN_ID, 42, 1e18, uint64(block.timestamp), uint64(block.timestamp));

        assertFalse(vault.usedRun(RUN_ID));
        assertEq(vault.cashPaidOf(42), 0);
        assertEq(vault.destinationOf(42), address(0));
        assertEq(vault.reserveBalance(), balanceBefore);
    }
}
