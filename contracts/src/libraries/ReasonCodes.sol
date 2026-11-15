// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title ReasonCodes
/// @notice Stable rejection codes carried in custom-error arguments so the indexer can store a
///         reason without parsing strings (FR-016). The API's reason catalog mirrors these names.
/// @dev Values are short ASCII strings as `bytes32` for cheap calldata and easy comparison.
library ReasonCodes {
    bytes32 internal constant DUPLICATE_DELIVERY = "DUPLICATE_DELIVERY";
    bytes32 internal constant POLICY_CANCELLED = "POLICY_CANCELLED";
    bytes32 internal constant POLICY_PAUSED = "POLICY_PAUSED";
    bytes32 internal constant PREMIUM_LAPSED = "PREMIUM_LAPSED";
    bytes32 internal constant COVERAGE_EXHAUSTED = "COVERAGE_EXHAUSTED";
    bytes32 internal constant UNKNOWN_LOAN = "UNKNOWN_LOAN";
    bytes32 internal constant DESTINATION_UNDERFUNDED = "DESTINATION_UNDERFUNDED";
    bytes32 internal constant ZERO_FEE = "ZERO_FEE";
    bytes32 internal constant TERMS_MISMATCH = "TERMS_MISMATCH";
}
