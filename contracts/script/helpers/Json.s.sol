// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Script } from "forge-std/Script.sol";

/// @title Json
/// @notice Merges deployed addresses into `ops/addresses.json` without rewriting the file, so a
///         later deploy on another chain cannot erase an earlier one.
/// @dev Keys are dot paths: `writeAddress("base.PolicyRegistry", addr)`. `ops/lib/addresses.ts`
///      reads the same file.
abstract contract Json is Script {
    string internal constant ADDRESSES_PATH = "../ops/addresses.json";

    /// @notice Writes `addr` at `key`, creating the file and any parent objects as needed.
    function writeAddress(string memory key, address addr) internal {
        require(addr != address(0), "Json: refusing to write the zero address");
        if (!vm.exists(ADDRESSES_PATH)) {
            vm.writeFile(ADDRESSES_PATH, "{}");
        }
        string memory value = string.concat("\"", vm.toString(addr), "\"");
        vm.writeJson(value, ADDRESSES_PATH, string.concat(".", key));
    }

    /// @notice Reads `key` from the address book, or zero when it is absent.
    function readAddress(string memory key) internal view returns (address) {
        if (!vm.exists(ADDRESSES_PATH)) {
            return address(0);
        }
        string memory json = vm.readFile(ADDRESSES_PATH);
        bytes memory raw = vm.parseJson(json, string.concat(".", key));
        return abi.decode(raw, (address));
    }

    /// @notice Writes a non-address value (a market id, a pool address recorded as text) at `key`.
    function writeString(string memory key, string memory value) internal {
        if (!vm.exists(ADDRESSES_PATH)) {
            vm.writeFile(ADDRESSES_PATH, "{}");
        }
        vm.writeJson(string.concat("\"", value, "\""), ADDRESSES_PATH, string.concat(".", key));
    }

    /// @notice Reads a string written by `writeString`.
    function readString(string memory key) internal view returns (string memory) {
        return vm.parseJsonString(vm.readFile(ADDRESSES_PATH), string.concat(".", key));
    }

    /// @notice Reads `key` and fails loudly when it is missing, which means the deploy order was
    ///         broken: every step depends on the address written by the step before it.
    function requireAddress(string memory key) internal view returns (address addr) {
        addr = readAddress(key);
        require(addr != address(0), string.concat("Json: missing address for ", key));
    }
}
