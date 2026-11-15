// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { ISubscriptionService } from "@reactive/src/interfaces/ISubscriptionService.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";

/// @title MockSystemContract
/// @notice Stands in at `0x8888…` for the Reactive system contract, so `react()` and the
///         subscriptions can be exercised locally without a Lasna node.
/// @dev Deployed in tests and `vm.etch`ed at the canonical address. It records every
///      subscription and every requested callback, and emits `CallbackRequest` with the same
///      shape the network uses, so assertions read like the real thing.
contract MockSystemContract is ISystemContract {
    struct Subscription {
        uint256 chainId;
        address contractAddress;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    struct CallbackRecord {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    event Subscribed(uint256 indexed chainId, address indexed contractAddress, uint256 topic0);
    event Unsubscribed(uint256 indexed chainId, address indexed contractAddress, uint256 topic0);
    event CallbackRequest(uint256 indexed chainId, address indexed recipient, uint64 indexed gasLimit, bytes payload);

    Subscription[] private _subscriptions;
    CallbackRecord[] private _callbacks;

    /// @notice Reserves reported to callback contracts. Always zero in this mock.
    mapping(address => uint256) public reserves;

    /// @inheritdoc ISubscriptionService
    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        _subscriptions.push(Subscription(chainId_, contract_, topic0_, topic1_, topic2_, topic3_));
        emit Subscribed(chainId_, contract_, topic0_);
    }

    /// @inheritdoc ISubscriptionService
    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        for (uint256 i = 0; i < _subscriptions.length; ++i) {
            Subscription memory s = _subscriptions[i];
            if (
                s.chainId == chainId_ && s.contractAddress == contract_ && s.topic0 == topic0_ && s.topic1 == topic1_
                    && s.topic2 == topic2_ && s.topic3 == topic3_
            ) {
                _subscriptions[i] = _subscriptions[_subscriptions.length - 1];
                _subscriptions.pop();
                emit Unsubscribed(chainId_, contract_, topic0_);
                return;
            }
        }
    }

    /// @inheritdoc ISystemContract
    function requestCallback(CallbackVersion version, bytes memory config) external {
        // The V_1_0 config is the only version this project uses; decode it so the mock rejects
        // malformed configurations the same way the real system contract would.
        version;
        CallbackConfiguration_V_1_0 memory decoded = abi.decode(config, (CallbackConfiguration_V_1_0));
        _record(decoded);
    }

    /// @inheritdoc ISystemContract
    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config) external {
        _record(config);
    }

    /// @inheritdoc IPayable
    function debt(address) external pure returns (uint256) {
        return 0;
    }

    /// @notice Sets the reserves a callback contract is told it has. Test helper.
    function setReserves(address contract_, uint256 amount) external {
        reserves[contract_] = amount;
    }

    /// @notice Number of recorded subscriptions.
    function subscriptionCount() external view returns (uint256) {
        return _subscriptions.length;
    }

    /// @notice Recorded subscription at `index`.
    function subscriptionAt(uint256 index) external view returns (Subscription memory) {
        return _subscriptions[index];
    }

    /// @notice Number of recorded callback requests.
    function callbackCount() external view returns (uint256) {
        return _callbacks.length;
    }

    /// @notice Recorded callback request at `index`.
    function callbackAt(uint256 index) external view returns (CallbackRecord memory) {
        return _callbacks[index];
    }

    function _record(CallbackConfiguration_V_1_0 memory config) private {
        _callbacks.push(
            CallbackRecord({
                chainId: config.chainId, recipient: config.recipient, gasLimit: config.gasLimit, payload: config.payload
            })
        );
        emit CallbackRequest(config.chainId, config.recipient, config.gasLimit, config.payload);
    }

    receive() external payable override { }
}
