// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IUniswapV3Pool
/// @notice The pool surface the demo oracle and the crash script read.
interface IUniswapV3Pool {
    /// @return sqrtPriceX96 Current price as a square root, 96-bit fixed point.
    /// @return tick Current tick.
    /// @return observationIndex Index of the last written oracle observation.
    /// @return observationCardinality Number of written oracle observations.
    /// @return observationCardinalityNext Next maximum number of oracle observations.
    /// @return feeProtocol Protocol fee split, packed.
    /// @return unlocked Whether the pool is unlocked.
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function token0() external view returns (address);

    function token1() external view returns (address);

    function liquidity() external view returns (uint128);
}
