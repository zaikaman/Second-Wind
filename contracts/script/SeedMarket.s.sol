// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { console2 } from "forge-std/console2.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Json } from "./helpers/Json.s.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MorphoV3Oracle } from "../src/base/MorphoV3Oracle.sol";
import { IMorpho } from "../src/interfaces/IMorpho.sol";
import { IUniswapV3Factory, INonfungiblePositionManager } from "../src/interfaces/IUniswapV3.sol";
import { IUniswapV3Pool } from "../src/interfaces/IUniswapV3Pool.sol";
import { HealthMath } from "../src/libraries/HealthMath.sol";

/// @notice Seeds the whole demo on Base Sepolia: the mock-token Uniswap pool at 2500, the Morpho
///         market, the three loans, and the relief reserve.
/// @dev Run after `DeployBase`, `DeployReactive` and `DeployPool`. The Unichain reserve is funded by
///      `FundClaimVault` in this file, because a forge script broadcasts to only one chain.
contract SeedMarket is Json {
    uint24 internal constant FEE_TIER = 3000;
    int24 internal constant MIN_TICK = -887_220;
    int24 internal constant MAX_TICK = 887_220;
    uint256 internal constant LLTV = 0.86e18;
    uint256 internal constant RESERVE = 250_000e18;
    uint256 internal constant MARKET_LIQUIDITY = 600_000e18;

    struct Config {
        uint256 deployerKey;
        address morpho;
        address factory;
        address npm;
        address irm;
        address weth;
        address usdc;
        address coveragePool;
        uint256 targetPrice;
        uint256 seedLiquidity;
    }

    struct Loan {
        uint256 key;
        uint128 collateral;
        uint128 debt;
        string label;
    }

    function run() external {
        Config memory config = _config();
        address pool = _pool(config);
        (address oracle, bytes32 marketId) = _market(config, pool);

        _openLoan(
            config, marketId, oracle, Loan({ key: _borrowerKey(), collateral: 100e18, debt: 180_000e18, label: "A" })
        );
        _openLoan(
            config, marketId, oracle, Loan({ key: _borrowerKey(), collateral: 20e18, debt: 34_000e18, label: "B" })
        );
        _openLoan(config, marketId, oracle, Loan({ key: _twinKey(), collateral: 20e18, debt: 34_000e18, label: "B'" }));

        console2.log("seed: pool", pool);
        console2.log("seed: oracle", oracle);
        console2.log("seed: market id", vm.toString(marketId));
    }

    function _config() private view returns (Config memory config) {
        config = Config({
            deployerKey: vm.envUint("DEPLOYER_KEY"),
            morpho: vm.envAddress("MORPHO"),
            factory: vm.envAddress("UNISWAP_V3_FACTORY"),
            npm: vm.envAddress("UNISWAP_V3_NPM"),
            irm: vm.envOr("IRM", address(0x46415998764C29aB2a25CbeA6254146D50D22687)),
            weth: requireAddress("base.mWETH"),
            usdc: requireAddress("base.mUSDC"),
            coveragePool: requireAddress("base.CoveragePool"),
            targetPrice: vm.envOr("SEED_PRICE", uint256(2500e36)),
            seedLiquidity: vm.envOr("SEED_LIQUIDITY", uint256(1_000e18))
        });
    }

    function _borrowerKey() private view returns (uint256) {
        return vm.envUint("BORROWER_KEY");
    }

    function _twinKey() private view returns (uint256) {
        return vm.envUint("LIQUIDATOR_KEY");
    }

    /// @dev Creates the pool once and initialises it at the demo price, then records its address.
    function _pool(Config memory config) private returns (address pool) {
        pool = IUniswapV3Factory(config.factory).getPool(config.weth, config.usdc, FEE_TIER);

        vm.startBroadcast(config.deployerKey);
        if (pool == address(0)) {
            pool = IUniswapV3Factory(config.factory).createPool(config.weth, config.usdc, FEE_TIER);
        }
        address token0 = IUniswapV3Pool(pool).token0();
        (uint160 sqrtPrice,,,,,,) = IUniswapV3Pool(pool).slot0();
        if (sqrtPrice == 0) {
            IUniswapV3Pool(pool).initialize(_sqrtPriceX96(token0, config.weth, config.targetPrice));
        }
        vm.stopBroadcast();

        (sqrtPrice,,,,,,) = IUniswapV3Pool(pool).slot0();
        require(sqrtPrice != 0, "SeedMarket: pool not initialised");

        writeAddress("base.UniswapPool", pool);
    }

    /// @dev Deploys the oracle, adds liquidity, creates the market, lends into it and funds the pool.
    function _market(Config memory config, address pool) private returns (address oracle, bytes32 marketId) {
        address deployer = vm.addr(config.deployerKey);
        vm.startBroadcast(config.deployerKey);

        oracle = address(new MorphoV3Oracle(pool, config.usdc, config.weth, config.targetPrice));
        _provideLiquidity(config, IUniswapV3Pool(pool).token0());

        IMorpho.MarketParams memory params = IMorpho.MarketParams({
            loanToken: config.usdc, collateralToken: config.weth, oracle: oracle, irm: config.irm, lltv: LLTV
        });
        IMorpho(config.morpho).createMarket(params);

        MockERC20(config.usdc).mint(deployer, MARKET_LIQUIDITY + RESERVE);
        MockERC20(config.usdc).approve(config.morpho, type(uint256).max);
        IMorpho(config.morpho).supply(params, MARKET_LIQUIDITY, 0, deployer, "");
        MockERC20(config.usdc).transfer(config.coveragePool, RESERVE);
        vm.stopBroadcast();

        marketId = keccak256(abi.encode(params));
        writeAddress("base.MorphoOracle", oracle);
        writeString("base.MarketId", vm.toString(marketId));

        console2.log("seed: relief reserve funded", RESERVE);
    }

    /// @dev Mints both assets and adds a full-range position so swaps have somewhere to move.
    function _provideLiquidity(Config memory config, address token0) private {
        address deployer = vm.addr(config.deployerKey);
        MockERC20(config.weth).mint(deployer, config.seedLiquidity);
        MockERC20(config.usdc).mint(deployer, config.seedLiquidity);
        MockERC20(config.weth).approve(config.npm, type(uint256).max);
        MockERC20(config.usdc).approve(config.npm, type(uint256).max);

        INonfungiblePositionManager(config.npm)
            .mint(
                INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token0 == config.weth ? config.usdc : config.weth,
                fee: FEE_TIER,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: config.seedLiquidity,
                amount1Desired: config.seedLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer,
                deadline: block.timestamp + 1 hours
            })
            );
    }

    /// @dev Supplies collateral and borrows, signed by the account that owns the loan, then asserts
    ///      the position is healthy before the demo starts.
    function _openLoan(Config memory config, bytes32 marketId, address oracle, Loan memory loan) private {
        address account = vm.addr(loan.key);
        IMorpho.MarketParams memory params = IMorpho(config.morpho).idToMarketParams(marketId);

        vm.startBroadcast(config.deployerKey);
        MockERC20(config.weth).mint(account, loan.collateral);
        vm.stopBroadcast();

        vm.startBroadcast(loan.key);
        MockERC20(config.weth).approve(config.morpho, type(uint256).max);
        IMorpho(config.morpho).supplyCollateral(params, loan.collateral, account, "");
        IMorpho(config.morpho).borrow(params, loan.debt, 0, account, account);
        vm.stopBroadcast();

        uint256 health = _health(config.morpho, marketId, account, oracle);
        console2.log(string.concat("loan ", loan.label, " health x1e18"), health);
        require(health > 1e18, "SeedMarket: a seeded loan is already liquidatable");
    }

    /// @dev `price` is loan units per collateral, scaled by 1e36. Uniswap encodes
    ///      sqrt(token1 per token0) in Q96, and both assets have 18 decimals, so the human ratio is
    ///      the raw ratio. `sqrt(price)` is that ratio's square root scaled by 1e18.
    function _sqrtPriceX96(address token0, address collateral, uint256 price) internal pure returns (uint160) {
        uint256 root = Math.sqrt(price);
        require(root > 0, "SeedMarket: price too small");
        if (token0 == collateral) {
            return uint160((root * 2 ** 96) / 1e18);
        }
        return uint160((uint256(2 ** 96) * 1e18) / root);
    }

    function _health(address morpho, bytes32 marketId, address account, address oracle)
        internal
        view
        returns (uint256)
    {
        IMorpho.Position memory position = IMorpho(morpho).position(marketId, account);
        IMorpho.Market memory market = IMorpho(morpho).market(marketId);
        uint256 debt = HealthMath.toAssetsUp(position.borrowShares, market.totalBorrowAssets, market.totalBorrowShares);
        return HealthMath.health(position.collateral, MorphoV3Oracle(oracle).price(), LLTV, debt);
    }
}

/// @notice Funds the Unichain reserve. Run with `--rpc-url $UNICHAIN_SEPOLIA_RPC`, because a forge
///         script broadcasts to exactly one chain.
contract FundClaimVault is Json {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address usdc = requireAddress("unichain.mUSDC");
        address vault = requireAddress("unichain.ClaimVault");
        uint256 reserve = vm.envOr("RESERVE_SEED", uint256(250_000e18));

        vm.startBroadcast(deployerKey);
        MockERC20(usdc).mint(vault, reserve);
        vm.stopBroadcast();

        require(MockERC20(usdc).balanceOf(vault) >= reserve, "FundClaimVault: reserve not funded");
        console2.log("seed: unichain cash reserve funded", reserve);
    }
}
