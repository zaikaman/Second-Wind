// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { console2 } from "forge-std/console2.sol";
import { Json } from "./helpers/Json.s.sol";
import { PolicyRegistry } from "../src/base/PolicyRegistry.sol";
import { SecondWindReactive } from "../src/reactive/SecondWindReactive.sol";

/// @notice Step 5 on Lasna: point the reactive contract at both settlement contracts, then renounce
///         ownership so no privileged caller exists afterwards.
contract Wire is Json {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address reactiveAddress = requireAddress("lasna.SecondWindReactive");
        address pool = requireAddress("base.CoveragePool");
        address vault = requireAddress("unichain.ClaimVault");

        SecondWindReactive reactive = SecondWindReactive(payable(reactiveAddress));

        vm.startBroadcast(deployerKey);
        reactive.setReliefRecipient(pool);
        reactive.setCashRecipient(vault);
        reactive.setSettlementWitnesses(pool, vault);
        reactive.renounceOwnership();
        vm.stopBroadcast();

        require(reactive.owner() == address(0), "Wire: reactive owner not renounced");
        require(reactive.reliefRecipient() == pool, "Wire: relief recipient mismatch");
        require(reactive.cashRecipient() == vault, "Wire: cash recipient mismatch");
        require(reactive.coveragePoolWitness() == pool, "Wire: relief witness mismatch");
        require(reactive.claimVaultWitness() == vault, "Wire: cash witness mismatch");

        console2.log("wire 5/5 reactive wired and renounced", reactiveAddress);
    }
}

/// @notice Step 5 on Base Sepolia: point the registry at the pool, then renounce ownership. This is
///         last because the registry's only privileged action is that one-time pointer.
contract WireRegistry is Json {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address registryAddress = requireAddress("base.PolicyRegistry");
        address pool = requireAddress("base.CoveragePool");

        PolicyRegistry registry = PolicyRegistry(registryAddress);

        vm.startBroadcast(deployerKey);
        registry.setCoveragePool(pool);
        registry.renounceOwnership();
        vm.stopBroadcast();

        require(registry.owner() == address(0), "WireRegistry: owner not renounced");
        require(registry.coveragePool() == pool, "WireRegistry: pool mismatch");

        console2.log("wire 5/5 registry wired and renounced", registryAddress);
    }
}
