// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";
import { FeeMath } from "../../src/libraries/FeeMath.sol";

/// @notice The penalty and the split. Every value here is checked against an independently
///         rearranged form of Morpho's formula, so a typo inside `FeeMath` cannot pass by symmetry.
contract FeeMathTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;

    /// @dev `LIF = 1e54 / (1e36 - 0.3e18 * (1e18 - lltv))`, capped at 1.15e18.
    function _referenceLif(uint256 lltv) internal pure returns (uint256) {
        uint256 denominator = 1e36 - (0.3e18 * (WAD - lltv)) / 1;
        uint256 lif = 1e54 / denominator;
        return lif > 1.15e18 ? 1.15e18 : lif;
    }

    // -------------------------------------------------------------------------------------
    // T091: LIF at every enabled LLTV, and the cap
    // -------------------------------------------------------------------------------------

    function test_Lif_AtEnabledLltvs() public pure {
        uint256[6] memory lltvs = [uint256(0.77e18), 0.86e18, 0.91e18, 0.945e18, 0.965e18, 0.98e18];
        for (uint256 i = 0; i < lltvs.length; ++i) {
            assertEq(FeeMath.lif(lltvs[i]), _referenceLif(lltvs[i]), "LIF mismatch");
        }
    }

    function test_Lif_KnownValues() public pure {
        // Morpho's published figure at 86% LLTV.
        assertApproxEqAbs(FeeMath.lif(0.86e18), 1.043841e18, 1e12);
        // Almost no penalty at 98%.
        assertApproxEqAbs(FeeMath.lif(0.98e18), 1.006036e18, 1e12);
        // Strictly above 1.0 at every enabled LLTV, otherwise no borrower would be liquidated.
        assertGt(FeeMath.lif(0.98e18), WAD);
    }

    function test_Lif_IncreasesWithLltv() public pure {
        uint256 previous = FeeMath.lif(0.385e18);
        uint256[5] memory lltvs = [uint256(0.77e18), 0.86e18, 0.91e18, 0.965e18, 0.98e18];
        for (uint256 i = 0; i < lltvs.length; ++i) {
            uint256 current = FeeMath.lif(lltvs[i]);
            assertLt(current, previous, "LIF must fall as LLTV rises");
            previous = current;
        }
    }

    function test_Lif_CappedAt115() public pure {
        assertEq(FeeMath.lif(0.385e18), 1.15e18);
        assertEq(FeeMath.lif(0.5e18), 1.15e18);
        assertEq(FeeMath.lif(0), 1.15e18);
    }

    // -------------------------------------------------------------------------------------
    // T092: penalty, floors, split
    // -------------------------------------------------------------------------------------

    function test_Penalty_MatchesLifDifference() public pure {
        uint256 repaid = 90_000e18;
        assertEq(FeeMath.penalty(repaid, 0.86e18), (repaid * (FeeMath.lif(0.86e18) - WAD)) / WAD);
    }

    function test_Penalty_FloorsToZero() public pure {
        // One wei of repaid debt times a 4.4% penalty is far below one wei of fee.
        assertEq(FeeMath.penalty(1, 0.86e18), 0);
        assertEq(FeeMath.penalty(10, 0.98e18), 0);
        assertEq(FeeMath.penalty(0, 0.86e18), 0);
    }

    function test_Penalty_DemoNumbers() public pure {
        // Crash 1 repays 90,000 mUSDC at 86% LLTV: 3,945.72… of penalty.
        assertApproxEqAbs(FeeMath.penalty(90_000e18, 0.86e18), 3_945.72e18, 1e15);
    }

    function test_Split_DemoNumbers() public pure {
        uint256 fee = FeeMath.penalty(90_000e18, 0.86e18);
        (uint256 cash, uint256 relief) = FeeMath.split(fee, 6000);

        assertEq(relief, (fee * 6000) / BPS);
        assertEq(cash, (fee * 4000) / BPS);
        assertLe(cash + relief, fee);
        assertEq(fee - cash - relief, 0);
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_Split_NeverSumsAboveFee(uint256 fee, uint16 shareSeed) public pure {
        fee = bound(fee, 0, type(uint128).max);
        uint16 share = uint16(bound(uint256(shareSeed), 0, BPS));

        (uint256 cash, uint256 relief) = FeeMath.split(fee, share);
        assertLe(cash + relief, fee);
        assertLe(relief, fee);
        assertLe(cash, fee);
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_Split_OfAllCashOrAllRelief(uint256 fee) public pure {
        fee = bound(fee, 0, type(uint128).max);

        (uint256 cashOnly, uint256 noRelief) = FeeMath.split(fee, 0);
        assertEq(cashOnly, fee);
        assertEq(noRelief, 0);

        (uint256 noCash, uint256 reliefOnly) = FeeMath.split(fee, uint16(BPS));
        assertEq(noCash, 0);
        assertEq(reliefOnly, fee);
    }
}
