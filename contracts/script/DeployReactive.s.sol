// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { console2 } from "forge-std/console2.sol";
import { Json } from "./helpers/Json.s.sol";
import { SecondWindReactive } from "../src/reactive/SecondWindReactive.sol";

/// @notice Step 2 of the deploy order: the reactive contract on Lasna. It must exist before either
///         settlement contract, because both store its address immutably.
contract DeployReactive is Json {
    function run() external returns (address reactiveAddress) {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address registry = requireAddress("base.PolicyRegistry");
        address morpho = vm.envAddress("MORPHO");
        uint256 baseChainId = vm.envOr("BASE_SEPOLIA_CHAIN_ID", uint256(84532));
        uint256 unichainChainId = vm.envOr("UNICHAIN_SEPOLIA_CHAIN_ID", uint256(1301));
        uint256 deposit = vm.envOr("REACTIVE_DEPOSIT_WEI", uint256(0));

        vm.startBroadcast(deployerKey);
        reactiveAddress =
            address(new SecondWindReactive{ value: deposit }(registry, morpho, baseChainId, unichainChainId));
        vm.stopBroadcast();

        SecondWindReactive reactive = SecondWindReactive(payable(reactiveAddress));
        require(reactive.policyRegistry() == registry, "DeployReactive: registry mismatch");
        require(reactive.morpho() == morpho, "DeployReactive: morpho mismatch");
        require(reactive.baseChainId() == baseChainId, "DeployReactive: base chain id mismatch");
        require(reactive.unichainChainId() == unichainChainId, "DeployReactive: unichain chain id mismatch");

        writeAddress("lasna.SecondWindReactive", reactiveAddress);

        console2.log("deploy 2/5 reactive", reactiveAddress);
    }
}
