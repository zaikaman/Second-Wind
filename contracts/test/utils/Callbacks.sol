// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Callbacks
/// @notice Decodes the payloads `SecondWindReactive` hands to the system contract, so tests can
///         assert what each destination would receive rather than trusting the dispatch count.
library Callbacks {
    /// @notice The injected sender and the shared run id of a relief callback.
    struct Relief {
        address sender;
        bytes32 runId;
        uint256 policyId;
        uint256 reliefLimit;
        uint64 decidedAt;
        uint64 liquidateBlock;
    }

    /// @notice The injected sender and the shared run id of a cash callback.
    struct Cash {
        address sender;
        bytes32 runId;
        uint256 policyId;
        uint256 cashLimit;
        uint64 paidThrough;
        uint64 decidedAt;
    }

    /// @notice The injected sender and terms of a registration callback.
    struct Registration {
        address sender;
        uint256 policyId;
        uint256 cashCeiling;
        uint64 paidThrough;
        address destination;
    }

    /// @dev Drops the 4-byte selector so the arguments can be decoded generically.
    function args(bytes memory payload) internal pure returns (bytes memory out) {
        require(payload.length > 4, "Callbacks: payload too short");
        out = new bytes(payload.length - 4);
        for (uint256 i = 4; i < payload.length; ++i) {
            out[i - 4] = payload[i];
        }
    }

    function relief(bytes memory payload) internal pure returns (Relief memory) {
        (address sender, bytes32 runId, uint256 policyId, uint256 limit, uint64 decidedAt, uint64 liquidateBlock) =
            abi.decode(args(payload), (address, bytes32, uint256, uint256, uint64, uint64));
        return Relief(sender, runId, policyId, limit, decidedAt, liquidateBlock);
    }

    function cash(bytes memory payload) internal pure returns (Cash memory) {
        (address sender, bytes32 runId, uint256 policyId, uint256 limit, uint64 paidThrough, uint64 decidedAt) =
            abi.decode(args(payload), (address, bytes32, uint256, uint256, uint64, uint64));
        return Cash(sender, runId, policyId, limit, paidThrough, decidedAt);
    }

    function registration(bytes memory payload) internal pure returns (Registration memory) {
        (address sender, uint256 policyId, uint256 ceiling, uint64 paidThrough, address destination) =
            abi.decode(args(payload), (address, uint256, uint256, uint64, address));
        return Registration(sender, policyId, ceiling, paidThrough, destination);
    }
}
