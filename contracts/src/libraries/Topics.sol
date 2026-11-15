// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Topics
/// @notice `topic0` constants for every event the reactive contract subscribes to.
/// @dev `Topics.t.sol` asserts each constant against `keccak256` of its signature string, so a
///      typo in a parameter type cannot silently ship and break the whole loop.
library Topics {
    /// @notice `PolicyRegistry.PolicyCreated(uint256,address,bytes32,uint256,uint256,uint256,uint256,uint64,uint16,uint256,address,uint256)`
    bytes32 internal constant POLICY_CREATED = keccak256(
        "PolicyCreated(uint256,address,bytes32,uint256,uint256,uint256,uint256,uint64,uint16,uint256,address,uint256)"
    );

    /// @notice `PolicyRegistry.PremiumPaid(uint256,uint64)`
    bytes32 internal constant PREMIUM_PAID = keccak256("PremiumPaid(uint256,uint64)");

    /// @notice `PolicyRegistry.PolicyStatusChanged(uint256,uint8,uint64)`
    bytes32 internal constant STATUS_CHANGED = keccak256("PolicyStatusChanged(uint256,uint8,uint64)");

    /// @notice `IMorpho.Liquidate(bytes32,address,address,uint256,uint256,uint256,uint256,uint256)`
    bytes32 internal constant LIQUIDATE =
        keccak256("Liquidate(bytes32,address,address,uint256,uint256,uint256,uint256,uint256)");

    /// @notice `CoveragePool.ReliefApplied(bytes32,uint256,bytes32,uint256,uint256,uint256,uint64)`
    bytes32 internal constant RELIEF_APPLIED =
        keccak256("ReliefApplied(bytes32,uint256,bytes32,uint256,uint256,uint256,uint64)");

    /// @notice `ClaimVault.ClaimPaid(bytes32,uint256,address,uint256,uint64)`
    bytes32 internal constant CLAIM_PAID = keccak256("ClaimPaid(bytes32,uint256,address,uint256,uint64)");
}
