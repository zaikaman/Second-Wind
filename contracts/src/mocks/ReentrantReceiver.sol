// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title ReentrantReceiver
/// @notice A payout destination that re-enters both settlement entry points from `receive()`.
/// @dev Used by the reentrancy tests: a claim paid to this address immediately tries to claim
///      again with the same `runId`, which `nonReentrant` and the replay guard must stop.
contract ReentrantReceiver {
    address public immutable coveragePool;
    address public immutable claimVault;

    bytes32 public runId;
    uint256 public policyId;
    uint256 public amount;

    bool public attempted;
    bool public reliefReentrySucceeded;
    bool public cashReentrySucceeded;

    constructor(address coveragePool_, address claimVault_) {
        coveragePool = coveragePool_;
        claimVault = claimVault_;
    }

    /// @notice Arms the receiver with the claim it should replay when it is paid.
    function configure(bytes32 runId_, uint256 policyId_, uint256 amount_) external {
        runId = runId_;
        policyId = policyId_;
        amount = amount_;
        attempted = false;
    }

    receive() external payable {
        if (attempted) {
            return;
        }
        attempted = true;
        _reenter();
    }

    function _reenter() private {
        if (coveragePool != address(0)) {
            (bool ok,) = coveragePool.call(
                abi.encodeWithSignature(
                    "settleCascade(address,bytes32,uint256,uint256,uint64,uint64)",
                    address(this),
                    runId,
                    policyId,
                    amount,
                    uint64(0),
                    uint64(0)
                )
            );
            reliefReentrySucceeded = ok;
        }
        if (claimVault != address(0)) {
            (bool ok,) = claimVault.call(
                abi.encodeWithSignature(
                    "payClaim(address,bytes32,uint256,uint256,uint64,uint64)",
                    address(this),
                    runId,
                    policyId,
                    amount,
                    uint64(0),
                    uint64(0)
                )
            );
            cashReentrySucceeded = ok;
        }
    }
}
