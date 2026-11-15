// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";

/// @title MorphoV3Oracle
/// @notice Morpho oracle that reports the Uniswap V3 spot price of the collateral in loan-asset
///         units, scaled by 1e36. Twice in the demo the pool is manipulated, and this is what makes
///         the loans liquidatable.
/// @dev Spot price, not a TWAP: the demo needs a price that moves in a single block, and the spec
///      discloses this. With `pool == address(0)` the contract serves a fixed price and reports
///      `isDemoHarness() == true`, which the proof page discloses.
/// @dev Both demo assets have 18 decimals, enforced here, so no decimal scaling is needed.
contract MorphoV3Oracle is IOracle {
    uint256 internal constant Q192 = 1 << 192;
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    error ZeroPrice();
    error ZeroToken();
    error UnsupportedDecimals();
    error TokensNotInPool();
    error PoolNotInitialised();

    /// @notice Uniswap V3 pool whose spot price is reported. Zero selects fallback mode.
    IUniswapV3Pool public immutable pool;
    /// @notice Loan asset of the Morpho market.
    address public immutable loanToken;
    /// @notice Collateral asset of the Morpho market.
    address public immutable collateralToken;
    /// @notice Price served when `pool` is zero, scaled by 1e36.
    uint256 public immutable fallbackPrice;

    bool internal immutable _loanIsToken0;

    /// @param pool_ Pool to read, or `address(0)` for fallback mode.
    /// @param loanToken_ Loan asset; must be one of the pool's tokens in pool mode.
    /// @param collateralToken_ Collateral asset; must be the other one.
    /// @param fallbackPrice_ Price used in fallback mode, scaled by 1e36.
    constructor(address pool_, address loanToken_, address collateralToken_, uint256 fallbackPrice_) {
        if (loanToken_ == address(0) || collateralToken_ == address(0)) {
            revert ZeroToken();
        }
        pool = IUniswapV3Pool(pool_);
        loanToken = loanToken_;
        collateralToken = collateralToken_;
        fallbackPrice = fallbackPrice_;

        if (pool_ == address(0)) {
            if (fallbackPrice_ == 0) {
                revert ZeroPrice();
            }
            return;
        }
        if (fallbackPrice_ == 0) {
            revert ZeroPrice();
        }
        if (IERC20Metadata(loanToken_).decimals() != 18 || IERC20Metadata(collateralToken_).decimals() != 18) {
            revert UnsupportedDecimals();
        }

        address token0 = IUniswapV3Pool(pool_).token0();
        address token1 = IUniswapV3Pool(pool_).token1();
        bool loanIsToken0 = token0 == loanToken_ && token1 == collateralToken_;
        bool loanIsToken1 = token0 == collateralToken_ && token1 == loanToken_;
        if (!loanIsToken0 && !loanIsToken1) {
            revert TokensNotInPool();
        }
        _loanIsToken0 = loanIsToken0;
    }

    /// @inheritdoc IOracle
    /// @return Loan-asset units per collateral unit, scaled by 1e36.
    function price() external view returns (uint256) {
        if (address(pool) == address(0)) {
            return fallbackPrice;
        }

        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        if (sqrtPriceX96 == 0) {
            revert PoolNotInitialised();
        }

        // `sqrtPriceX96` encodes sqrt(token1 per token0) in Q96. With both assets at 18 decimals the
        // raw ratio is already the human ratio; scaling by 1e18 keeps the division precise.
        uint256 priceScaled = Math.mulDiv(sqrtPriceX96, uint256(sqrtPriceX96) * 1e18, Q192);
        if (priceScaled == 0) {
            revert ZeroPrice();
        }

        if (_loanIsToken0) {
            // Collateral is token1: the loan price is the inverse of token1 per token0.
            return Math.mulDiv(1e54, 1, priceScaled);
        }
        return priceScaled * 1e18;
    }

    /// @notice True when this oracle serves a fixed price instead of a pool, which the proof page
    ///         must disclose (FR-020).
    function isDemoHarness() external view returns (bool) {
        return address(pool) == address(0);
    }

    /// @notice The scale Morpho expects from `price()`.
    function ORACLE_PRICE_SCALE_() external pure returns (uint256) {
        return ORACLE_PRICE_SCALE;
    }
}
