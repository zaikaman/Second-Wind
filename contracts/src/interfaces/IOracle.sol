// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IOracle
/// @notice Morpho's price oracle surface.
/// @dev Prices are loan-asset units per collateral unit, scaled by 1e36 (MORPHO_ORACLE_PRICE_SCALE).
interface IOracle {
    function price() external view returns (uint256);
}
