// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { console2 } from "forge-std/console2.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { Json } from "./helpers/Json.s.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { PolicyRegistry } from "../src/base/PolicyRegistry.sol";
import { CoveragePool } from "../src/base/CoveragePool.sol";

/// @notice Step 1 of the deploy order: the two mock assets and the policy registry on Base Sepolia.
contract DeployBase is Json {
    function run() external returns (address weth, address usdc, address registry) {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address morpho = vm.envAddress("MORPHO");

        vm.startBroadcast(deployerKey);
        weth = address(new MockERC20("Mock WETH", "mWETH"));
        usdc = address(new MockERC20("Mock USDC", "mUSDC"));
        registry = address(new PolicyRegistry(usdc, morpho));
        vm.stopBroadcast();

        require(address(PolicyRegistry(registry).coverAsset()) == usdc, "DeployBase: cover asset mismatch");
        require(address(PolicyRegistry(registry).morpho()) == morpho, "DeployBase: morpho mismatch");

        writeAddress("base.mWETH", weth);
        writeAddress("base.mUSDC", usdc);
        writeAddress("base.PolicyRegistry", registry);

        console2.log("deploy 1/5 registry", registry);
    }
}

/// @notice Step 3 of the deploy order: the coverage pool on Base Sepolia. Runs after the reactive
///         contract, because the pool stores the reactive address immutably.
contract DeployPool is Json {
    function run() external returns (address poolAddress) {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address callbackProxy = vm.envAddress("BASE_CALLBACK_PROXY");
        address morpho = vm.envAddress("MORPHO");
        address reactiveContract = requireAddress("lasna.SecondWindReactive");
        address registry = requireAddress("base.PolicyRegistry");
        address coverAsset = requireAddress("base.mUSDC");

        vm.startBroadcast(deployerKey);
        poolAddress = address(
            new CoveragePool(IPayable(payable(callbackProxy)), reactiveContract, registry, morpho, coverAsset)
        );
        vm.stopBroadcast();

        CoveragePool pool = CoveragePool(payable(poolAddress));
        require(address(pool.coverAsset()) == coverAsset, "DeployPool: cover asset mismatch");
        require(pool.registry() == registry, "DeployPool: registry mismatch");
        require(pool._CALLBACK_SENDER() == reactiveContract, "DeployPool: reactive mismatch");

        writeAddress("base.CoveragePool", poolAddress);

        console2.log("deploy 3/5 coverage pool", poolAddress);
    }
}
