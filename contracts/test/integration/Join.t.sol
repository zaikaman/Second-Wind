// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { TestBase } from "../utils/TestBase.sol";
import { Fixtures } from "../utils/Fixtures.sol";
import { Callbacks } from "../utils/Callbacks.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { MockSystemContract } from "../../src/mocks/MockSystemContract.sol";
import { Topics } from "../../src/libraries/Topics.sol";

/// @notice One liquidation, two chains. Both destination calls are driven from the same runId and
///         both succeed, which is the product's core claim (FR-010).
contract JoinTest is TestBase {
    uint256 internal constant POLICY_ID = 1;
    uint256 internal constant LOG_INDEX = 3;
    bytes32 internal constant RUN_ID = keccak256(abi.encode(84532, bytes32(uint256(keccak256("tx"))), 3));

    function test_BothBranches_SameRunId() public {
        uint256 policyId = _createPolicyOnA();
        assertEq(policyId, POLICY_ID);
        _mirrorPolicy();
        Callbacks.Registration memory reg = Callbacks.registration(system.callbackAt(0).payload);
        _applyRegistration(reg);

        oracle.setPrice(2200e36);
        _liquidate();

        Callbacks.Relief memory relief = Callbacks.relief(system.callbackAt(1).payload);
        Callbacks.Cash memory cash = Callbacks.cash(system.callbackAt(2).payload);

        assertEq(relief.runId, cash.runId, "the join key must be identical");
        assertEq(relief.runId, RUN_ID);

        _applyRelief(relief);
        _applyCash(cash);

        assertTrue(pool.usedRun(RUN_ID), "relief branch settled");
        assertTrue(vault.usedRun(RUN_ID), "cash branch settled");
        assertEq(usdc.balanceOf(cashDestination), cash.cashLimit, "cash reached the registered destination");
        assertGt(registry.getPolicy(POLICY_ID).reliefUsed, 0, "relief was recorded on the policy");
    }

    // -------------------------------------------------------------------------------------
    // Helpers: exactly what the callback proxies would do
    // -------------------------------------------------------------------------------------

    function _mirrorPolicy() internal {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            IReactive.LogRecord({
                chainId: BASE_CHAIN_ID,
                contractAddress: address(registry),
                topic0: uint256(Topics.POLICY_CREATED),
                topic1: POLICY_ID,
                topic2: uint256(uint160(borrower)),
                topic3: uint256(marketA),
                data: _policyCreatedData(),
                blockNumber: 90,
                opCode: 4,
                blockHash: uint256(keccak256("block")),
                txHash: uint256(keccak256("create-tx")),
                logIndex: 0
            })
        );
    }

    function _liquidate() internal {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            IReactive.LogRecord({
                chainId: BASE_CHAIN_ID,
                contractAddress: address(morpho),
                topic0: uint256(Topics.LIQUIDATE),
                topic1: uint256(marketA),
                topic2: uint256(uint160(liquidator)),
                topic3: uint256(uint160(borrower)),
                data: abi.encode(Fixtures.DEMO_REPAID, uint256(0), uint256(0), uint256(0), uint256(0)),
                blockNumber: 100,
                opCode: 4,
                blockHash: uint256(keccak256("block")),
                txHash: uint256(keccak256("tx")),
                logIndex: LOG_INDEX
            })
        );
    }

    function _applyRegistration(Callbacks.Registration memory reg) internal {
        assertEq(reg.sender, address(0));
        vm.prank(UNICHAIN_CALLBACK_PROXY);
        vault.registerPolicy(address(reactive), reg.policyId, reg.cashCeiling, reg.paidThrough, reg.destination);
        assertEq(vault.destinationOf(reg.policyId), cashDestination);
    }

    function _applyRelief(Callbacks.Relief memory relief) internal {
        assertEq(relief.sender, address(0));
        vm.prank(BASE_CALLBACK_PROXY);
        pool.settleCascade(
            address(reactive),
            relief.runId,
            relief.policyId,
            relief.reliefLimit,
            relief.decidedAt,
            relief.liquidateBlock
        );
    }

    function _applyCash(Callbacks.Cash memory cash) internal {
        assertEq(cash.sender, address(0));
        vm.prank(UNICHAIN_CALLBACK_PROXY);
        vault.payClaim(address(reactive), cash.runId, cash.policyId, cash.cashLimit, cash.paidThrough, cash.decidedAt);
    }

    function _policyCreatedData() internal view returns (bytes memory) {
        uint256 premiumPerSecond = (Fixtures.COVERAGE_CAP * Fixtures.APR_BPS) / (10_000 * 365 days);
        return abi.encode(
            Fixtures.COVERAGE_CAP,
            uint256(2_000e18),
            uint256(3_000e18),
            premiumPerSecond,
            uint64(block.timestamp + 30 days),
            Fixtures.RELIEF_SHARE_BPS,
            Fixtures.TARGET_HEALTH,
            cashDestination,
            Fixtures.LLTV
        );
    }
}
