// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { console2 } from "forge-std/console2.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { Json } from "./helpers/Json.s.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { ClaimVault } from "../src/unichain/ClaimVault.sol";

/// @notice Step 4 of the deploy order: the cash reserve and claim vault on Unichain Sepolia.
contract DeployUnichain is Json {
    function run() external returns (address usdc, address vaultAddress) {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address callbackProxy = vm.envAddress("UNICHAIN_CALLBACK_PROXY");
        address reactiveContract = requireAddress("lasna.SecondWindReactive");

        vm.startBroadcast(deployerKey);
        usdc = address(new MockERC20("Mock USDC", "mUSDC"));
        vaultAddress = address(new ClaimVault(IPayable(payable(callbackProxy)), reactiveContract, usdc));
        vm.stopBroadcast();

        ClaimVault vault = ClaimVault(payable(vaultAddress));
        require(address(vault.coverAsset()) == usdc, "DeployUnichain: cover asset mismatch");
        require(vault._CALLBACK_SENDER() == reactiveContract, "DeployUnichain: reactive mismatch");

        writeAddress("unichain.mUSDC", usdc);
        writeAddress("unichain.ClaimVault", vaultAddress);

        console2.log("deploy 4/5 claim vault", vaultAddress);
    }
}
