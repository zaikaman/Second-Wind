// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title FeeMath
/// @notice The only place the liquidation penalty and the cash/relief split are computed.
/// @dev All values are 18-decimal fixed point. Every division rounds **down**, because a
///      payout must never exceed the penalty the borrower actually paid: rounding up would
///      let the pool pay more than the fee, which breaks the coverage-cap invariant.
library FeeMath {
    /// @notice 1.0 in 18-decimal fixed point.
    uint256 internal constant WAD = 1e18;
    /// @notice Basis-point denominator (10000 = 100%).
    uint256 internal constant BPS = 10_000;
    /// @notice Morpho's liquidation incentive factor cap: 1.15.
    uint256 internal constant LIF_CAP = 1.15e18;
    /// @notice Morpho's liquidation penalty factor: 0.3.
    uint256 internal constant LIF_PENALTY_FACTOR = 0.3e18;

    /// @notice Morpho Blue's liquidation incentive factor for a given LLTV.
    /// @dev `LIF = min(1.15, 1 / (1 - 0.3 * (1 - lltv)))`, evaluated in WAD with floor division.
    /// @param lltv Market's liquidation loan-to-value, 18 decimals.
    /// @return The LIF, 18 decimals (1.0438…e18 at lltv = 0.86e18).
    function lif(uint256 lltv) internal pure returns (uint256) {
        uint256 penaltyFactor = (LIF_PENALTY_FACTOR * (WAD - lltv)) / WAD;
        uint256 denominator = WAD - penaltyFactor;
        uint256 computed = (WAD * WAD) / denominator;
        return computed > LIF_CAP ? LIF_CAP : computed;
    }

    /// @notice The penalty a liquidator paid on top of the repaid debt.
    /// @dev `fee = repaidAssets * (LIF - 1)`, floored.
    /// @param repaidAssets Debt the liquidator repaid, in loan-asset units.
    /// @param lltv Market's LLTV, 18 decimals.
    function penalty(uint256 repaidAssets, uint256 lltv) internal pure returns (uint256) {
        uint256 incentive = lif(lltv);
        if (incentive <= WAD) {
            return 0;
        }
        return (repaidAssets * (incentive - WAD)) / WAD;
    }

    /// @notice Splits a fee into the cash share and the relief share.
    /// @dev Both shares are floored independently, so `cash + relief <= fee` always holds and a
    ///      remainder of at most one wei stays in the pool rather than being paid twice.
    /// @param fee Penalty to split.
    /// @param reliefShareBps Relief share in basis points (10000 = all relief, 0 = all cash).
    function split(uint256 fee, uint16 reliefShareBps) internal pure returns (uint256 cash, uint256 relief) {
        relief = (fee * reliefShareBps) / BPS;
        cash = (fee * (BPS - reliefShareBps)) / BPS;
    }
}
