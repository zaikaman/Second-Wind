// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Fixtures
/// @notice The canonical demo numbers, in one place, so contracts and tests cannot drift apart.
/// @dev Price is scaled by 1e36, Morpho's ORACLE_PRICE_SCALE. Health values in the spec
///      (A 1.1944, B 1.2647 at price 2500) follow from these numbers exactly.
library Fixtures {
    /// @notice Demo price: 2500 mUSDC per mWETH, scaled by 1e36.
    uint256 internal constant PRICE = 2500e36;
    /// @notice Demo market LLTV: 86%.
    uint256 internal constant LLTV = 0.86e18;

    /// @notice Loan A: 100 mWETH collateral against 180,000 mUSDC debt.
    uint128 internal constant LOAN_A_COLLATERAL = 100e18;
    uint128 internal constant LOAN_A_DEBT = 180_000e18;
    /// @notice Loan B: 20 mWETH collateral against 34,000 mUSDC debt.
    uint128 internal constant LOAN_B_COLLATERAL = 20e18;
    uint128 internal constant LOAN_B_DEBT = 34_000e18;
    /// @notice Twin B': identical to B, left uncovered as the control.
    uint128 internal constant TWIN_COLLATERAL = 20e18;
    uint128 internal constant TWIN_DEBT = 34_000e18;

    /// @notice Demo coverage cap: 5,000 mUSDC.
    uint256 internal constant COVERAGE_CAP = 5_000e18;
    /// @notice Demo relief share: 60% of the fee, so 40% is cash.
    uint16 internal constant RELIEF_SHARE_BPS = 6000;
    /// @notice Demo relief target health.
    uint256 internal constant TARGET_HEALTH = 1.15e18;
    /// @notice Demo prepaid premium term: 30 days.
    uint32 internal constant PREMIUM_TERM = 30 days;
    /// @notice Demo premium APR in basis points: 3%.
    uint16 internal constant APR_BPS = 300;

    /// @notice A liquidation repaying 90,000 mUSDC, the demo's crash 1.
    uint256 internal constant DEMO_REPAID = 90_000e18;
}
