// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";
import { MorphoV3Oracle } from "../../src/base/MorphoV3Oracle.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";

/// @notice The demo oracle: fallback mode serves the fixed price and discloses itself, and pool mode
///         refuses anything it cannot price correctly.
contract MorphoV3OracleTest is Test {
    uint256 internal constant PRICE = 2500e36;

    function test_FallbackMode_ServesFixedPrice() public {
        MockERC20 weth = new MockERC20("Mock WETH", "mWETH");
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC");

        MorphoV3Oracle oracle = new MorphoV3Oracle(address(0), address(usdc), address(weth), PRICE);

        assertEq(oracle.price(), PRICE);
        assertTrue(oracle.isDemoHarness());
    }

    function test_FallbackMode_RequiresPrice() public {
        MockERC20 weth = new MockERC20("Mock WETH", "mWETH");
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC");

        vm.expectRevert(MorphoV3Oracle.ZeroPrice.selector);
        new MorphoV3Oracle(address(0), address(usdc), address(weth), 0);
    }

    function test_ZeroTokens_Rejected() public {
        vm.expectRevert(MorphoV3Oracle.ZeroToken.selector);
        new MorphoV3Oracle(address(0), address(0), address(0), PRICE);
    }
}
