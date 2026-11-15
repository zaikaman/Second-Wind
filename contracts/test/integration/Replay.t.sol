// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { TestBase } from "../utils/TestBase.sol";
import { Fixtures } from "../utils/Fixtures.sol";
import { Callbacks } from "../utils/Callbacks.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { Topics } from "../../src/libraries/Topics.sol";

/// @notice One thousand deliveries per branch must produce exactly one state change each. This is
///         the on-chain half of SC-003: a duplicated callback cannot pay twice.
contract ReplayTest is TestBase {
    uint256 internal constant POLICY_ID = 1;
    uint256 internal constant LOG_INDEX = 3;
    uint256 internal constant DELIVERIES = 1_000;
    bytes32 internal constant RUN_ID = keccak256(abi.encode(84532, bytes32(uint256(keccak256("tx"))), 3));

    function test_1000Replays_PayOnce() public {
        _createPolicyOnA();
        _mirrorPolicy();
        Callbacks.Registration memory reg = Callbacks.registration(system.callbackAt(0).payload);
        _applyRegistration(reg);

        oracle.setPrice(2200e36);
        _liquidate();

        Callbacks.Relief memory relief = Callbacks.relief(system.callbackAt(1).payload);
        Callbacks.Cash memory cash = Callbacks.cash(system.callbackAt(2).payload);

        uint256 reserveBefore = pool.reserveBalance();
        uint256 vaultBefore = vault.reserveBalance();

        for (uint256 i = 0; i < DELIVERIES; ++i) {
            vm.prank(BASE_CALLBACK_PROXY);
            try pool.settleCascade(
                address(reactive),
                relief.runId,
                relief.policyId,
                relief.reliefLimit,
                relief.decidedAt,
                relief.liquidateBlock
            ) { }
                catch { }
        }

        for (uint256 i = 0; i < DELIVERIES; ++i) {
            vm.prank(UNICHAIN_CALLBACK_PROXY);
            try vault.payClaim(
                address(reactive), cash.runId, cash.policyId, cash.cashLimit, cash.paidThrough, cash.decidedAt
            ) { }
                catch { }
        }

        assertEq(reserveBefore - pool.reserveBalance(), relief.reliefLimit, "relief paid once");
        assertEq(vaultBefore - vault.reserveBalance(), cash.cashLimit, "cash paid once");
        assertEq(usdc.balanceOf(cashDestination), cash.cashLimit);
        assertEq(registry.getPolicy(POLICY_ID).reliefUsed, relief.reliefLimit);
        assertTrue(pool.usedRun(RUN_ID));
        assertTrue(vault.usedRun(RUN_ID));
    }

    function test_Reactive_ReplayIsFree() public {
        // The reactive side must also ignore a redelivered log before requesting anything.
        _mirrorPolicy();
        _liquidate();
        uint256 afterFirst = system.callbackCount();

        for (uint256 i = 0; i < 50; ++i) {
            _liquidate();
        }
        assertEq(system.callbackCount(), afterFirst);
    }

    // -------------------------------------------------------------------------------------
    // Helpers
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
        vm.prank(UNICHAIN_CALLBACK_PROXY);
        vault.registerPolicy(address(reactive), reg.policyId, reg.cashCeiling, reg.paidThrough, reg.destination);
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
