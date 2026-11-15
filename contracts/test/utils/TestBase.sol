// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { MockOracle } from "../../src/mocks/MockOracle.sol";
import { MockMorpho } from "../../src/mocks/MockMorpho.sol";
import { MockSystemContract } from "../../src/mocks/MockSystemContract.sol";
import { PolicyRegistry } from "../../src/base/PolicyRegistry.sol";
import { CoveragePool } from "../../src/base/CoveragePool.sol";
import { ClaimVault } from "../../src/unichain/ClaimVault.sol";
import { SecondWindReactive } from "../../src/reactive/SecondWindReactive.sol";
import { IMorpho } from "../../src/interfaces/IMorpho.sol";
import { Fixtures } from "./Fixtures.sol";

/// @title TestBase
/// @notice Deploys the whole product on a local EVM: the mock system contract etched at the
///         canonical Lasna address, both mock assets, the oracle, a Morpho double, the registry,
///         the reactive contract, and both settlement contracts, all wired and funded.
/// @dev The callback proxies are plain addresses with no code on a local EVM; tests impersonate
///      them with `vm.prank`, which is exactly how the real proxy calls in.
abstract contract TestBase is Test {
    address internal constant SYSTEM_ADDRESS = 0x8888888888888888888888888888888888888888;
    address internal constant BASE_CALLBACK_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    address internal constant UNICHAIN_CALLBACK_PROXY = 0x775c9B990ADe401060B78D0e98684eEf8d2466C1;

    uint256 internal constant BASE_CHAIN_ID = 84532;
    uint256 internal constant UNICHAIN_CHAIN_ID = 1301;

    uint256 internal constant RESERVE_SEED = 250_000e18;

    MockSystemContract internal system;
    MockERC20 internal weth;
    MockERC20 internal usdc;
    MockOracle internal oracle;
    MockMorpho internal morpho;
    PolicyRegistry internal registry;
    SecondWindReactive internal reactive;
    CoveragePool internal pool;
    ClaimVault internal vault;

    address internal borrower = makeAddr("borrower");
    address internal twin = makeAddr("twin");
    address internal liquidator = makeAddr("liquidator");
    address internal cashDestination = makeAddr("cashDestination");

    bytes32 internal marketA;
    bytes32 internal marketB;
    bytes32 internal marketTwin;

    function setUp() public virtual {
        MockSystemContract systemImplementation = new MockSystemContract();
        vm.etch(SYSTEM_ADDRESS, address(systemImplementation).code);
        system = MockSystemContract(payable(SYSTEM_ADDRESS));

        weth = new MockERC20("Mock WETH", "mWETH");
        usdc = new MockERC20("Mock USDC", "mUSDC");

        oracle = new MockOracle(Fixtures.PRICE);
        morpho = new MockMorpho();

        registry = new PolicyRegistry(address(usdc), address(morpho));
        reactive = new SecondWindReactive(address(registry), address(morpho), BASE_CHAIN_ID, UNICHAIN_CHAIN_ID);

        pool = new CoveragePool(
            IPayable(payable(BASE_CALLBACK_PROXY)), address(reactive), address(registry), address(morpho), address(usdc)
        );
        vault = new ClaimVault(IPayable(payable(UNICHAIN_CALLBACK_PROXY)), address(reactive), address(usdc));

        registry.setCoveragePool(address(pool));
        reactive.setReliefRecipient(address(pool));
        reactive.setCashRecipient(address(vault));
        reactive.setSettlementWitnesses(address(pool), address(vault));

        _openDemoLoans();
        _fund();

        vm.prank(borrower);
        usdc.approve(address(registry), type(uint256).max);
        usdc.mint(borrower, 1_000_000e18);
        usdc.mint(twin, 1_000_000e18);
        vm.prank(twin);
        usdc.approve(address(registry), type(uint256).max);
    }

    /// @notice Creates a market. `salt` distinguishes markets that share every other parameter,
    ///         because a Morpho market id is the hash of its parameters.
    function _newMarket(uint256 lltv, uint256 salt) internal returns (bytes32 id) {
        IMorpho.MarketParams memory params = IMorpho.MarketParams({
            loanToken: address(usdc),
            collateralToken: address(weth),
            oracle: address(oracle),
            irm: address(uint160(10_000 + salt)),
            lltv: lltv
        });
        morpho.createMarket(params);
        id = morpho.marketIdOf(params);
    }

    /// @notice Opens or extends a position, keeping the market totals consistent with it.
    function _openLoan(bytes32 id, address account, uint128 collateral, uint128 debt) internal {
        IMorpho.Market memory m = morpho.market(id);
        morpho.setTotals(id, uint128(uint256(m.totalBorrowAssets) + debt), uint128(uint256(m.totalBorrowShares) + debt));
        IMorpho.Position memory p = morpho.position(id, account);
        morpho.setPosition(
            id, account, uint128(uint256(p.collateral) + collateral), uint128(uint256(p.borrowShares) + debt)
        );
    }

    /// @notice The three demo loans: A and B belong to one borrower, B' to a twin account.
    function _openDemoLoans() internal {
        marketA = _newMarket(Fixtures.LLTV, 1);
        marketB = _newMarket(Fixtures.LLTV, 2);
        marketTwin = _newMarket(Fixtures.LLTV, 3);

        _openLoan(marketA, borrower, Fixtures.LOAN_A_COLLATERAL, Fixtures.LOAN_A_DEBT);
        _openLoan(marketB, borrower, Fixtures.LOAN_B_COLLATERAL, Fixtures.LOAN_B_DEBT);
        _openLoan(marketTwin, twin, Fixtures.TWIN_COLLATERAL, Fixtures.TWIN_DEBT);
    }

    /// @notice Funds both settlement contracts the way the deploy script does.
    function _fund() internal {
        usdc.mint(address(pool), RESERVE_SEED);
        usdc.mint(address(vault), RESERVE_SEED);
        vm.deal(address(pool), 1 ether);
        vm.deal(address(vault), 1 ether);
        vm.deal(address(reactive), 1 ether);
        vm.deal(SYSTEM_ADDRESS, 1 ether);
    }

    /// @notice Creates a policy on `marketA` with the canonical demo terms.
    function _createPolicyOnA() internal returns (uint256 policyId) {
        vm.prank(borrower);
        policyId = registry.createPolicy(
            marketA,
            Fixtures.COVERAGE_CAP,
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.PREMIUM_TERM
        );
    }
}
