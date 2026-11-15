// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IOracle } from "../interfaces/IOracle.sol";

/// @title MockOracle
/// @notice Deterministic `IOracle` for unit tests and for the `pool == address(0)` fallback mode.
/// @dev The price is 18-decimal loan-asset units per collateral unit scaled by 1e36, matching
///      Morpho's ORACLE_PRICE_SCALE. Owner-settable; unit tests own it.
contract MockOracle is IOracle, Ownable {
    uint256 private _price;

    event PriceSet(uint256 price);

    error ZeroPrice();

    constructor(uint256 initialPrice) Ownable(msg.sender) {
        if (initialPrice == 0) {
            revert ZeroPrice();
        }
        _price = initialPrice;
    }

    /// @inheritdoc IOracle
    function price() external view returns (uint256) {
        return _price;
    }

    /// @notice Sets the price. Emits `PriceSet` so tests and the indexer can follow changes.
    function setPrice(uint256 newPrice) external onlyOwner {
        if (newPrice == 0) {
            revert ZeroPrice();
        }
        _price = newPrice;
        emit PriceSet(newPrice);
    }
}
