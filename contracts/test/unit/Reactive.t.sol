// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { TestBase } from "../utils/TestBase.sol";
import { Fixtures } from "../utils/Fixtures.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { MockSystemContract } from "../../src/mocks/MockSystemContract.sol";
import { SecondWindReactive } from "../../src/reactive/SecondWindReactive.sol";
import { Topics } from "../../src/libraries/Topics.sol";

/// @notice Subscriptions, the revert-free router, and the mirrors the reactive contract keeps.
contract ReactiveTest is TestBase {
    uint256 internal constant POLICY_ID = 1;
    uint256 internal constant LOG_INDEX = 7;

    // -------------------------------------------------------------------------------------
    // Subscriptions
    // -------------------------------------------------------------------------------------

    function test_ExactlySixSubscriptions() public view {
        assertEq(system.subscriptionCount(), 6);
    }

    function test_SubscriptionCriteria() public view {
        MockSystemContract.Subscription memory s;

        s = system.subscriptionAt(0);
        assertEq(s.chainId, BASE_CHAIN_ID);
        assertEq(s.contractAddress, address(registry));
        assertEq(s.topic0, uint256(Topics.POLICY_CREATED));

        s = system.subscriptionAt(1);
        assertEq(s.chainId, BASE_CHAIN_ID);
        assertEq(s.contractAddress, address(registry));
        assertEq(s.topic0, uint256(Topics.PREMIUM_PAID));

        s = system.subscriptionAt(2);
        assertEq(s.chainId, BASE_CHAIN_ID);
        assertEq(s.contractAddress, address(registry));
        assertEq(s.topic0, uint256(Topics.STATUS_CHANGED));

        s = system.subscriptionAt(3);
        assertEq(s.chainId, BASE_CHAIN_ID);
        assertEq(s.contractAddress, address(morpho));
        assertEq(s.topic0, uint256(Topics.LIQUIDATE));

        s = system.subscriptionAt(4);
        assertEq(s.chainId, BASE_CHAIN_ID);
        assertEq(s.contractAddress, address(0));
        assertEq(s.topic0, uint256(Topics.RELIEF_APPLIED));

        s = system.subscriptionAt(5);
        assertEq(s.chainId, UNICHAIN_CHAIN_ID);
        assertEq(s.contractAddress, address(0));
        assertEq(s.topic0, uint256(Topics.CLAIM_PAID));
    }

    // -------------------------------------------------------------------------------------
    // Router
    // -------------------------------------------------------------------------------------

    function test_React_RejectsEOA() public {
        IReactive.LogRecord memory record = _record(
            address(registry),
            Topics.POLICY_CREATED,
            POLICY_ID,
            uint256(uint160(borrower)),
            uint256(marketA),
            _policyCreatedData(),
            4
        );

        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, borrower, SYSTEM_ADDRESS));
        vm.prank(borrower);
        reactive.react(record);
    }

    function test_React_UnknownTopic_ReturnsWithoutRevert() public {
        IReactive.LogRecord memory record =
            _record(address(registry), keccak256("Unknown(uint256)"), 1, 0, 0, abi.encode(uint256(1)), 2);

        vm.prank(SYSTEM_ADDRESS);
        reactive.react(record);

        assertEq(system.callbackCount(), 0);
        assertEq(reactive.getPolicy(POLICY_ID).borrower, address(0));
    }

    function test_React_WrongOpCode_ReturnsWithoutRevert() public {
        IReactive.LogRecord memory record = _record(
            address(registry),
            Topics.POLICY_CREATED,
            POLICY_ID,
            uint256(uint160(borrower)),
            uint256(marketA),
            _policyCreatedData(),
            3
        );

        vm.prank(SYSTEM_ADDRESS);
        reactive.react(record);

        assertEq(reactive.getPolicy(POLICY_ID).borrower, address(0));
        assertEq(system.callbackCount(), 0);
    }

    // -------------------------------------------------------------------------------------
    // Mirrors
    // -------------------------------------------------------------------------------------

    function test_PolicyCreated_MirrorsTermsAndRequestsRegistration() public {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            _record(
                address(registry),
                Topics.POLICY_CREATED,
                POLICY_ID,
                uint256(uint160(borrower)),
                uint256(marketA),
                _policyCreatedData(),
                4
            )
        );

        SecondWindReactive.Policy memory p = reactive.getPolicy(POLICY_ID);
        assertEq(p.borrower, borrower);
        assertEq(p.marketId, marketA);
        assertEq(p.lltv, Fixtures.LLTV);
        assertEq(p.coverageCap, Fixtures.COVERAGE_CAP);
        assertEq(p.cashCeiling, 2_000e18);
        assertEq(p.reliefCeiling, 3_000e18);
        assertEq(p.reliefShareBps, Fixtures.RELIEF_SHARE_BPS);
        assertEq(p.targetHealthWad, Fixtures.TARGET_HEALTH);
        assertEq(p.cashDestination, cashDestination);
        assertEq(p.status, 1);
        assertEq(reactive.policyOfLoan(keccak256(abi.encode(marketA, borrower))), POLICY_ID);
        assertEq(reactive.policiesOf(borrower, 0), POLICY_ID);

        // Cash cover is registered on Unichain through one callback issued from this reactive
        // transaction, not by the borrower.
        assertEq(system.callbackCount(), 1);
        MockSystemContract.CallbackRecord memory cb = system.callbackAt(0);
        assertEq(cb.chainId, UNICHAIN_CHAIN_ID);
        assertEq(cb.recipient, address(vault));
        assertEq(cb.gasLimit, 200_000);
    }

    function test_PolicyCreated_FromUnrelatedContract_IsIgnored() public {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            _record(
                address(borrower),
                Topics.POLICY_CREATED,
                POLICY_ID,
                uint256(uint160(borrower)),
                uint256(marketA),
                _policyCreatedData(),
                4
            )
        );

        assertEq(reactive.getPolicy(POLICY_ID).borrower, address(0));
        assertEq(system.callbackCount(), 0);
    }

    function test_PremiumPaid_AdvancesPaidThrough() public {
        _mirrorPolicy();
        uint64 newPaidThrough = uint64(block.timestamp + 60 days);

        vm.prank(SYSTEM_ADDRESS);
        reactive.react(_record(address(registry), Topics.PREMIUM_PAID, POLICY_ID, 0, 0, abi.encode(newPaidThrough), 2));

        assertEq(reactive.getPolicy(POLICY_ID).paidThrough, newPaidThrough);
    }

    function test_StatusChanged_PauseAndCancel() public {
        _mirrorPolicy();

        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            _record(address(registry), Topics.STATUS_CHANGED, POLICY_ID, 0, 0, abi.encode(uint8(2), uint64(0)), 2)
        );
        assertEq(reactive.getPolicy(POLICY_ID).status, 2);

        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            _record(address(registry), Topics.STATUS_CHANGED, POLICY_ID, 0, 0, abi.encode(uint8(3), uint64(500)), 2)
        );
        assertEq(reactive.getPolicy(POLICY_ID).status, 3);
    }

    function test_StatusChanged_UnknownPolicy_IsIgnored() public {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            _record(address(registry), Topics.STATUS_CHANGED, POLICY_ID, 0, 0, abi.encode(uint8(2), uint64(0)), 2)
        );

        assertEq(reactive.getPolicy(POLICY_ID).status, 0);
    }

    // -------------------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------------------

    function _mirrorPolicy() internal {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(
            _record(
                address(registry),
                Topics.POLICY_CREATED,
                POLICY_ID,
                uint256(uint160(borrower)),
                uint256(marketA),
                _policyCreatedData(),
                4
            )
        );
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

    function _record(
        address emitter,
        bytes32 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3,
        bytes memory data,
        uint256 opCode
    ) internal pure returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chainId: BASE_CHAIN_ID,
            contractAddress: emitter,
            topic0: uint256(topic0),
            topic1: topic1,
            topic2: topic2,
            topic3: topic3,
            data: data,
            blockNumber: 100,
            opCode: opCode,
            blockHash: uint256(keccak256("block")),
            txHash: uint256(keccak256("tx")),
            logIndex: LOG_INDEX
        });
    }
}
