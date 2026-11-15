// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice The demo asset: 18 decimals for both `mWETH` and `mUSDC`, mintable by the deploy
///         scripts only. Worth nothing; see SECURITY.md.
/// @dev 18 decimals on both sides keeps the oracle conversion free of decimal scaling.
contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /// @notice Mints demo tokens. Open on testnets by design; there is no ownership gate to bypass.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burns demo tokens from any holder, so a script can reset the demo.
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
