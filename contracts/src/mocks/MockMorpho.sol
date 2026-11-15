// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IMorpho } from "../interfaces/IMorpho.sol";

/// @title MockMorpho
/// @notice In-memory Morpho Blue for unit tests: same structs, same share conversion, same token
///         movement, without a full market deployment. Fork tests use the real contract on Base
///         Sepolia instead, so this double never becomes the product's dependency.
/// @dev Markets are keyed exactly as Morpho keys them: `keccak256(abi.encode(MarketParams))`.
contract MockMorpho is IMorpho {
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    mapping(bytes32 => MarketParams) private _params;
    mapping(bytes32 => Market) private _markets;
    mapping(bytes32 => mapping(address => Position)) private _positions;

    error UnknownMarket(bytes32 id);

    /// @notice Registers a market and returns its id.
    function createMarket(MarketParams memory marketParams) external {
        _params[marketIdOf(marketParams)] = marketParams;
    }

    /// @notice Test helper: seeds a market's aggregate totals.
    function setTotals(bytes32 id, uint128 borrowAssets, uint128 borrowShares) external {
        Market storage m = _markets[id];
        m.totalBorrowAssets = borrowAssets;
        m.totalBorrowShares = borrowShares;
        m.lastUpdate = uint128(block.timestamp);
    }

    /// @notice Test helper: seeds a borrower's position.
    function setPosition(bytes32 id, address user, uint128 collateral, uint128 borrowShares) external {
        _positions[id][user] = Position({ supplyShares: 0, borrowShares: borrowShares, collateral: collateral });
    }

    /// @notice The id Morpho derives from market parameters.
    function marketIdOf(MarketParams memory marketParams) public pure returns (bytes32) {
        return keccak256(abi.encode(marketParams));
    }

    /// @inheritdoc IMorpho
    function position(bytes32 id, address user) external view returns (Position memory) {
        return _positions[id][user];
    }

    /// @inheritdoc IMorpho
    function idToMarketParams(bytes32 id) external view returns (MarketParams memory) {
        return _params[id];
    }

    /// @inheritdoc IMorpho
    function market(bytes32 id) external view returns (Market memory) {
        return _markets[id];
    }

    /// @inheritdoc IMorpho
    function supply(MarketParams memory marketParams, uint256 assets, uint256 shares, address onBehalf, bytes memory)
        external
        returns (uint256 assetsSupplied, uint256 sharesSupplied)
    {
        assetsSupplied = shares == 0 ? assets : assets;
        sharesSupplied = shares;
        if (assetsSupplied > 0) {
            IERC20(marketParams.loanToken).transferFrom(msg.sender, address(this), assetsSupplied);
        }
        Market storage m = _markets[marketIdOf(marketParams)];
        m.totalSupplyAssets = uint128(uint256(m.totalSupplyAssets) + assetsSupplied);
        m.totalSupplyShares = uint128(uint256(m.totalSupplyShares) + sharesSupplied);
        _positions[marketIdOf(marketParams)][onBehalf].supplyShares += sharesSupplied;
    }

    /// @inheritdoc IMorpho
    function supplyCollateral(MarketParams memory marketParams, uint256 assets, address onBehalf, bytes memory)
        external
    {
        bytes32 id = marketIdOf(marketParams);
        if (assets > 0) {
            IERC20(marketParams.collateralToken).transferFrom(msg.sender, address(this), assets);
        }
        _positions[id][onBehalf].collateral = uint128(uint256(_positions[id][onBehalf].collateral) + assets);
    }

    /// @inheritdoc IMorpho
    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed) {
        bytes32 id = marketIdOf(marketParams);
        Market storage m = _markets[id];
        if (shares == 0) {
            sharesBorrowed = m.totalBorrowAssets == 0
                ? assets
                : Math.mulDiv(
                    assets,
                    uint256(m.totalBorrowShares) + VIRTUAL_SHARES,
                    uint256(m.totalBorrowAssets) + VIRTUAL_ASSETS,
                    Math.Rounding.Ceil
                );
            assetsBorrowed = assets;
        } else {
            sharesBorrowed = shares;
            assetsBorrowed = Math.mulDiv(
                shares, uint256(m.totalBorrowAssets) + VIRTUAL_ASSETS, uint256(m.totalBorrowShares) + VIRTUAL_SHARES
            );
        }
        m.totalBorrowAssets = uint128(uint256(m.totalBorrowAssets) + assetsBorrowed);
        m.totalBorrowShares = uint128(uint256(m.totalBorrowShares) + sharesBorrowed);
        _positions[id][onBehalf].borrowShares = uint128(uint256(_positions[id][onBehalf].borrowShares) + sharesBorrowed);
        if (assetsBorrowed > 0) {
            IERC20(marketParams.loanToken).transfer(receiver, assetsBorrowed);
        }
    }

    /// @inheritdoc IMorpho
    function repay(MarketParams memory marketParams, uint256 assets, uint256 shares, address onBehalf, bytes memory)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        bytes32 id = marketIdOf(marketParams);
        Market storage m = _markets[id];
        Position storage pos = _positions[id][onBehalf];

        uint256 totalAssets = m.totalBorrowAssets;
        uint256 totalShares = m.totalBorrowShares;

        if (shares == 0) {
            sharesRepaid = totalAssets == 0
                ? 0
                : Math.mulDiv(assets, totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS, Math.Rounding.Ceil);
            assetsRepaid = assets;
        } else {
            sharesRepaid = shares;
            assetsRepaid =
                Math.mulDiv(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES, Math.Rounding.Ceil);
        }

        if (sharesRepaid > pos.borrowShares) {
            sharesRepaid = pos.borrowShares;
            assetsRepaid = Math.mulDiv(
                sharesRepaid, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES, Math.Rounding.Ceil
            );
        }
        if (assetsRepaid > totalAssets) {
            assetsRepaid = totalAssets;
        }

        pos.borrowShares = uint128(uint256(pos.borrowShares) - sharesRepaid);
        m.totalBorrowShares = uint128(totalShares - sharesRepaid);
        m.totalBorrowAssets = uint128(totalAssets - assetsRepaid);

        if (assetsRepaid > 0) {
            IERC20(marketParams.loanToken).transferFrom(msg.sender, address(this), assetsRepaid);
        }
    }

    /// @inheritdoc IMorpho
    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes memory
    ) external returns (uint256 seizedAssetsLiquidated, uint256 repaidAssets) {
        bytes32 id = marketIdOf(marketParams);
        Market storage m = _markets[id];
        Position storage pos = _positions[id][borrower];

        uint256 totalAssets = m.totalBorrowAssets;
        uint256 totalShares = m.totalBorrowShares;

        repaidAssets = repaidShares == 0
            ? 0
            : Math.mulDiv(repaidShares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES, Math.Rounding.Ceil);
        seizedAssetsLiquidated = seizedAssets > pos.collateral ? pos.collateral : seizedAssets;

        pos.borrowShares = uint128(uint256(pos.borrowShares) - repaidShares);
        pos.collateral = uint128(uint256(pos.collateral) - seizedAssetsLiquidated);
        m.totalBorrowShares = uint128(totalShares - repaidShares);
        m.totalBorrowAssets = uint128(totalAssets - repaidAssets);

        if (repaidAssets > 0) {
            IERC20(marketParams.loanToken).transferFrom(msg.sender, address(this), repaidAssets);
        }
        if (seizedAssetsLiquidated > 0) {
            IERC20(marketParams.collateralToken).transfer(msg.sender, seizedAssetsLiquidated);
        }
    }
}
