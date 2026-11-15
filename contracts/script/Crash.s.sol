// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { console2 } from "forge-std/console2.sol";
import { Vm } from "forge-std/Vm.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Json } from "./helpers/Json.s.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MorphoV3Oracle } from "../src/base/MorphoV3Oracle.sol";
import { IMorpho } from "../src/interfaces/IMorpho.sol";
import { ISwapRouter02 } from "../src/interfaces/IUniswapV3.sol";
import { HealthMath } from "../src/libraries/HealthMath.sol";

/// @notice Crash 1: push the Uniswap price down, prove the oracle sees it, then liquidate loan A.
///         The liquidation is the only trigger the product needs; from here the reactive contract
///         does the rest on its own.
contract Crash is Json {
    uint24 internal constant FEE_TIER = 3000;
    bytes32 internal constant LIQUIDATE_TOPIC =
        keccak256("Liquidate(bytes32,address,address,uint256,uint256,uint256,uint256,uint256)");

    struct Config {
        uint256 deployerKey;
        uint256 liquidatorKey;
        address borrower;
        address router;
        address morpho;
        address usdc;
        address weth;
        address oracle;
        bytes32 marketId;
        uint256 swapIn;
        uint256 targetPrice;
        uint256 repaidAssets;
    }

    function run() external {
        Config memory config = _config();
        _pushPriceDown(config);

        uint256 healthBefore = _health(config, config.borrower);
        _liquidate(config, healthBefore);
    }

    function _config() private view returns (Config memory config) {
        config = Config({
            deployerKey: vm.envUint("DEPLOYER_KEY"),
            liquidatorKey: vm.envUint("LIQUIDATOR_KEY"),
            borrower: vm.addr(vm.envUint("BORROWER_KEY")),
            router: vm.envAddress("UNISWAP_SWAP_ROUTER"),
            morpho: vm.envAddress("MORPHO"),
            usdc: requireAddress("base.mUSDC"),
            weth: requireAddress("base.mWETH"),
            oracle: requireAddress("base.MorphoOracle"),
            marketId: _toBytes32(readString("base.MarketId")),
            swapIn: vm.envOr("CRASH_WETH_IN", uint256(200e18)),
            targetPrice: vm.envOr("CRASH1_TARGET_PRICE", uint256(2050e36)),
            repaidAssets: vm.envOr("CRASH_REPAID_ASSETS", uint256(90_000e18))
        });
    }

    /// @dev Sells collateral into the pool. The oracle reads spot, so the price moves with the pool.
    function _pushPriceDown(Config memory config) private {
        vm.startBroadcast(config.deployerKey);
        MockERC20(config.weth).mint(address(this), config.swapIn);
        MockERC20(config.weth).approve(config.router, config.swapIn);
        ISwapRouter02(config.router)
            .exactInputSingle(
                ISwapRouter02.ExactInputSingleParams({
                    tokenIn: config.weth,
                    tokenOut: config.usdc,
                    fee: FEE_TIER,
                    recipient: address(this),
                    amountIn: config.swapIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        vm.stopBroadcast();

        uint256 price = MorphoV3Oracle(config.oracle).price();
        console2.log("crash: oracle price x1e36", price);
        require(price <= (config.targetPrice * 1005) / 1000, "Crash: price is above the 1% band around target");
        require(price >= (config.targetPrice * 995) / 1000, "Crash: price is below the 1% band around target");
    }

    /// @dev Liquidates loan A on behalf of the liquidator, and proves the log the reactive contract
    ///      subscribes to was emitted.
    function _liquidate(Config memory config, uint256 healthBefore) private {
        console2.log("crash: loan A health before x1e18", healthBefore);

        IMorpho morpho = IMorpho(config.morpho);
        uint256 repaidShares = _sharesFor(morpho, config.marketId, config.repaidAssets);

        vm.startBroadcast(config.liquidatorKey);
        MockERC20(config.usdc).mint(vm.addr(config.liquidatorKey), config.repaidAssets);
        MockERC20(config.usdc).approve(config.morpho, config.repaidAssets);
        vm.recordLogs();
        morpho.liquidate(morpho.idToMarketParams(config.marketId), config.borrower, 0, repaidShares, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopBroadcast();

        require(_sawLiquidate(logs), "Crash: no Liquidate log was emitted");

        uint256 healthAfter = _health(config, config.borrower);
        require(healthAfter > healthBefore, "Crash: liquidation left health unchanged");
        console2.log("crash: liquidated assets", config.repaidAssets);
        console2.log("crash: loan A health after x1e18", healthAfter);
    }

    /// @dev Converts the debt to repay into borrow shares, rounding up like Morpho does.
    function _sharesFor(IMorpho morpho, bytes32 marketId, uint256 assets) private view returns (uint256) {
        IMorpho.Market memory market = morpho.market(marketId);
        return Math.mulDiv(
            assets, uint256(market.totalBorrowShares) + 1e6, uint256(market.totalBorrowAssets) + 1, Math.Rounding.Ceil
        );
    }

    function _sawLiquidate(Vm.Log[] memory logs) internal pure returns (bool) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == LIQUIDATE_TOPIC) {
                return true;
            }
        }
        return false;
    }

    function _health(Config memory config, address account) internal view returns (uint256) {
        IMorpho morpho = IMorpho(config.morpho);
        IMorpho.Position memory position = morpho.position(config.marketId, account);
        IMorpho.Market memory market = morpho.market(config.marketId);
        IMorpho.MarketParams memory params = morpho.idToMarketParams(config.marketId);
        uint256 debt = HealthMath.toAssetsUp(position.borrowShares, market.totalBorrowAssets, market.totalBorrowShares);
        uint256 price = MorphoV3Oracle(params.oracle).price();
        return HealthMath.health(position.collateral, price, params.lltv, debt);
    }

    /// @dev Converts a `0x`-prefixed hex string back into the bytes32 market id stored by the seed.
    function _toBytes32(string memory hexString) internal pure returns (bytes32 result) {
        bytes memory characters = bytes(hexString);
        require(characters.length == 66 && characters[0] == "0" && characters[1] == "x", "Crash: bad market id");
        for (uint256 i = 2; i < 66; ++i) {
            result = bytes32((uint256(result) << 4) | uint256(_nibble(characters[i])));
        }
    }

    function _nibble(bytes1 character) internal pure returns (uint8) {
        uint8 value = uint8(character);
        if (value >= 48 && value <= 57) {
            return value - 48;
        }
        if (value >= 65 && value <= 70) {
            return value - 55;
        }
        if (value >= 97 && value <= 102) {
            return value - 87;
        }
        revert("Crash: non-hex character");
    }
}
