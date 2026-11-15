// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title HealthMath
/// @notice Health factor, weakest-loan selection and repay targeting for a Morpho position.
/// @dev 18-decimal fixed point. Morpho prices collateral as `loan per collateral * 1e36`, so
///      `collateralValue = collateral * price / 1e36`.
library HealthMath {
    /// @notice 1.0 in 18-decimal fixed point.
    uint256 internal constant WAD = 1e18;
    /// @notice Morpho's oracle price scale.
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;
    /// @notice Morpho's virtual shares, used when converting borrow shares to assets.
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    /// @notice Morpho's virtual assets, used when converting borrow shares to assets.
    uint256 internal constant VIRTUAL_ASSETS = 1;

    /// @notice A candidate loan for weakest-position selection.
    struct Candidate {
        bytes32 marketId;
        uint256 healthWad;
        uint256 debt;
    }

    /// @notice Value of the collateral in loan-asset units.
    /// @dev Floor division: undervaluing collateral by at most one wei is the safe direction.
    function collateralValue(uint256 collateral, uint256 price) internal pure returns (uint256) {
        return Math.mulDiv(collateral, price, ORACLE_PRICE_SCALE);
    }

    /// @notice Health factor of one position, 18 decimals.
    /// @dev Returns `type(uint256).max` for a zero-debt position, meaning "nothing to liquidate";
    ///      callers must treat that as a skip, not as an extremely healthy loan.
    function health(uint256 collateral, uint256 price, uint256 lltv, uint256 debt) internal pure returns (uint256) {
        if (debt == 0) {
            return type(uint256).max;
        }
        uint256 value = collateralValue(collateral, price);
        return Math.mulDiv(value, lltv, debt);
    }

    /// @notice Picks the weakest candidate: lowest health, ties broken by the lower market id.
    /// @dev Candidates with zero debt are skipped. Fuzzing over three positions is bounded by the
    ///      registry's eight-policy limit, so this loop is cheap and cannot be gas-griefed.
    /// @return index Index of the chosen candidate in `candidates`.
    /// @return found False when no candidate had debt.
    function weakest(Candidate[] memory candidates) internal pure returns (uint256 index, bool found) {
        uint256 bestHealth = type(uint256).max;
        bytes32 bestMarket;
        for (uint256 i = 0; i < candidates.length; ++i) {
            Candidate memory candidate = candidates[i];
            if (candidate.debt == 0) {
                continue;
            }
            if (
                !found || candidate.healthWad < bestHealth
                    || (candidate.healthWad == bestHealth && candidate.marketId < bestMarket)
            ) {
                found = true;
                bestHealth = candidate.healthWad;
                bestMarket = candidate.marketId;
                index = i;
            }
        }
    }

    /// @notice Debt that must be repaid to raise a position to `targetHealthWad`.
    /// @dev Clamped to `[0, debt]`: a position already above target needs nothing, and repaying
    ///      more than the debt is impossible.
    function repayForTarget(uint256 debt, uint256 collateralValue_, uint256 lltv, uint256 targetHealthWad)
        internal
        pure
        returns (uint256)
    {
        if (debt == 0 || targetHealthWad == 0) {
            return 0;
        }
        uint256 valueAtTarget = Math.mulDiv(collateralValue_, lltv, targetHealthWad);
        if (valueAtTarget >= debt) {
            return 0;
        }
        return debt - valueAtTarget;
    }

    /// @notice Converts borrow shares to debt, matching Morpho's rounding up.
    /// @dev `ceil(shares * (totalAssets + 1) / (totalShares + 1e6))`, Morpho's virtual-share formula.
    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return Math.mulDiv(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES, Math.Rounding.Ceil);
    }
}
