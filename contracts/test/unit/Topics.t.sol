// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";
import { Topics } from "../../src/libraries/Topics.sol";

/// @notice Every subscription key equals `keccak256` of its signature string, so a typo in a
///         parameter type cannot ship and silently break the whole loop.
contract TopicsTest is Test {
    function test_Topic_PolicyCreated() public pure {
        assertEq(
            Topics.POLICY_CREATED,
            keccak256(
                "PolicyCreated(uint256,address,bytes32,uint256,uint256,uint256,uint256,uint64,uint16,uint256,address,uint256)"
            )
        );
    }

    function test_Topic_PremiumPaid() public pure {
        assertEq(Topics.PREMIUM_PAID, keccak256("PremiumPaid(uint256,uint64)"));
    }

    function test_Topic_StatusChanged() public pure {
        assertEq(Topics.STATUS_CHANGED, keccak256("PolicyStatusChanged(uint256,uint8,uint64)"));
    }

    function test_Topic_Liquidate() public pure {
        assertEq(
            Topics.LIQUIDATE, keccak256("Liquidate(bytes32,address,address,uint256,uint256,uint256,uint256,uint256)")
        );
    }

    function test_Topic_ReliefApplied() public pure {
        assertEq(
            Topics.RELIEF_APPLIED, keccak256("ReliefApplied(bytes32,uint256,bytes32,uint256,uint256,uint256,uint64)")
        );
    }

    function test_Topic_ClaimPaid() public pure {
        assertEq(Topics.CLAIM_PAID, keccak256("ClaimPaid(bytes32,uint256,address,uint256,uint64)"));
    }

    function test_Topics_AreDistinct() public pure {
        bytes32[6] memory topics = [
            Topics.POLICY_CREATED,
            Topics.PREMIUM_PAID,
            Topics.STATUS_CHANGED,
            Topics.LIQUIDATE,
            Topics.RELIEF_APPLIED,
            Topics.CLAIM_PAID
        ];
        for (uint256 i = 0; i < topics.length; ++i) {
            for (uint256 j = i + 1; j < topics.length; ++j) {
                assertTrue(topics[i] != topics[j]);
            }
        }
    }
}
