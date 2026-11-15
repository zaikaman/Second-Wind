// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMorpho } from "../interfaces/IMorpho.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { HealthMath } from "../libraries/HealthMath.sol";

/// @title PolicyRegistry
/// @notice The borrower's side of Second Wind: creates policies, collects premium, records relief
///         usage, and publishes the events the reactive contract mirrors on Lasna.
/// @dev There is no function that changes the terms, cap, split, target or destination of an
///      existing policy. That is the contract-level proof of FR-018: cover cannot be rewritten
///      after the borrower has paid for it.
contract PolicyRegistry is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Terminal state machine for a policy.
    enum Status {
        None,
        Active,
        Paused,
        Cancelled
    }

    /// @notice Everything the borrower bought, frozen at creation.
    struct Policy {
        uint256 policyId;
        address borrower;
        bytes32 marketId;
        bytes32 loanKey;
        uint256 coverageCap;
        uint256 cashCeiling;
        uint256 reliefCeiling;
        uint256 premiumPerSecond;
        uint64 paidThrough;
        uint16 reliefShareBps;
        uint256 targetHealthWad;
        address cashDestination;
        Status status;
        uint256 reliefUsed;
        uint64 cancelledAtBlock;
        uint64 createdAt;
    }

    event PolicyCreated(
        uint256 indexed policyId,
        address indexed borrower,
        bytes32 indexed marketId,
        uint256 coverageCap,
        uint256 cashCeiling,
        uint256 reliefCeiling,
        uint256 premiumPerSecond,
        uint64 paidThrough,
        uint16 reliefShareBps,
        uint256 targetHealthWad,
        address cashDestination,
        uint256 lltv
    );

    event PremiumPaid(uint256 indexed policyId, uint64 paidThrough);

    event PolicyStatusChanged(uint256 indexed policyId, uint8 status, uint64 cancelledAtBlock);

    event CoveragePoolSet(address indexed pool);

    error MarketNotSupported(bytes32 marketId);
    error LoanNotOpen(bytes32 marketId, address borrower);
    error LoanUnhealthy(bytes32 marketId, address borrower, uint256 health);
    error PolicyExists(bytes32 loanKey, uint256 policyId);
    error TooManyPolicies(address borrower, uint256 count);
    error CapOutOfRange(uint256 cap);
    error ShareOutOfRange(uint16 reliefShareBps);
    error TargetOutOfRange(uint256 targetHealthWad);
    error ZeroDestination();
    error TermOutOfRange(uint32 premiumTermSeconds);
    error UnknownPolicy(uint256 policyId);
    error NotBorrower(uint256 policyId, address caller);
    error PolicyNotLive(uint256 policyId, uint8 status);
    error AmountTooSmall(uint256 amount, uint256 minimum);
    error CapExceeded(uint256 requested, uint256 remaining);
    error OnlyCoveragePool(address caller);
    error PoolNotSet();
    error AlreadySet();
    error ZeroAddress();

    /// @notice Premium APR in basis points: 3% a year.
    uint16 public constant APR_BPS = 300;
    /// @notice Maximum number of policies one borrower can hold, which bounds the relief loop.
    uint256 public constant MAX_POLICIES = 8;
    /// @notice Smallest policy the product sells.
    uint256 public constant MIN_CAP = 100e18;
    /// @notice Largest policy the product sells.
    uint256 public constant MAX_CAP = 5_000e18;
    /// @notice Lower bound on the relief target health.
    uint256 public constant MIN_TARGET_HEALTH = 1.05e18;
    /// @notice Upper bound on the relief target health.
    uint256 public constant MAX_TARGET_HEALTH = 1.5e18;
    /// @notice Shortest prepaid term.
    uint32 public constant MIN_TERM = 1 days;
    /// @notice Longest prepaid term, also the premium horizon.
    uint32 public constant MAX_TERM = 365 days;

    uint16 internal constant BPS = 10_000;
    uint256 internal constant WAD = 1e18;

    /// @notice Cover asset (mUSDC). Immutable: terms are denominated in it.
    IERC20 public immutable coverAsset;
    /// @notice Morpho Blue on this chain.
    IMorpho public immutable morpho;

    /// @notice Set once by the owner, then renounced. Receives premium and records relief.
    address public coveragePool;

    mapping(uint256 => Policy) private _policies;
    mapping(bytes32 => uint256) private _policyOfLoan;
    mapping(address => uint256[]) private _policiesOf;
    uint256 private _policyCount;

    constructor(address coverAsset_, address morpho_) Ownable(msg.sender) {
        if (coverAsset_ == address(0) || morpho_ == address(0)) {
            revert ZeroAddress();
        }
        coverAsset = IERC20(coverAsset_);
        morpho = IMorpho(morpho_);
    }

    modifier onlyCoveragePool() {
        if (msg.sender != coveragePool) {
            revert OnlyCoveragePool(msg.sender);
        }
        _;
    }

    /// @notice Creates a policy for the caller's position in `marketId` and collects the first
    ///         premium period in the same transaction, so no policy is born already lapsed.
    /// @param marketId Morpho market the loan sits in.
    /// @param coverageCap Maximum total payout, in loan-asset units (18 decimals).
    /// @param reliefShareBps Relief share in basis points; the remainder is paid as cash.
    /// @param targetHealthWad Health the relief aims to restore.
    /// @param cashDestination Address that receives the cash share on Unichain.
    /// @param premiumTermSeconds Prepaid premium period, in seconds.
    function createPolicy(
        bytes32 marketId,
        uint256 coverageCap,
        uint16 reliefShareBps,
        uint256 targetHealthWad,
        address cashDestination,
        uint32 premiumTermSeconds
    ) external returns (uint256 policyId) {
        if (coveragePool == address(0)) {
            revert PoolNotSet();
        }
        _validateTerms(coverageCap, reliefShareBps, targetHealthWad, cashDestination, premiumTermSeconds);
        uint256 lltv = _validateLoan(marketId, msg.sender);

        policyId = ++_policyCount;
        Policy storage p = _policies[policyId];
        p.policyId = policyId;
        p.borrower = msg.sender;
        p.marketId = marketId;
        p.loanKey = loanKey(marketId, msg.sender);
        p.coverageCap = coverageCap;
        p.cashCeiling = (coverageCap * (BPS - reliefShareBps)) / BPS;
        p.reliefCeiling = coverageCap - p.cashCeiling;
        p.premiumPerSecond = (coverageCap * APR_BPS) / (uint256(BPS) * MAX_TERM);
        p.paidThrough = uint64(block.timestamp) + premiumTermSeconds;
        p.reliefShareBps = reliefShareBps;
        p.targetHealthWad = targetHealthWad;
        p.cashDestination = cashDestination;
        p.status = Status.Active;
        p.createdAt = uint64(block.timestamp);

        _policyOfLoan[p.loanKey] = policyId;
        _policiesOf[msg.sender].push(policyId);

        if (p.premiumPerSecond > 0) {
            coverAsset.safeTransferFrom(msg.sender, coveragePool, p.premiumPerSecond * premiumTermSeconds);
        }

        emit PolicyCreated(
            policyId,
            msg.sender,
            marketId,
            coverageCap,
            p.cashCeiling,
            p.reliefCeiling,
            p.premiumPerSecond,
            p.paidThrough,
            reliefShareBps,
            targetHealthWad,
            cashDestination,
            lltv
        );
    }

    /// @dev Term and range validation, kept out of `createPolicy` so the function stays under the
    ///      EVM stack limit without enabling the IR pipeline.
    function _validateTerms(
        uint256 coverageCap,
        uint16 reliefShareBps,
        uint256 targetHealthWad,
        address cashDestination,
        uint32 premiumTermSeconds
    ) private pure {
        if (coverageCap < MIN_CAP || coverageCap > MAX_CAP) {
            revert CapOutOfRange(coverageCap);
        }
        if (reliefShareBps > BPS) {
            revert ShareOutOfRange(reliefShareBps);
        }
        if (targetHealthWad < MIN_TARGET_HEALTH || targetHealthWad > MAX_TARGET_HEALTH) {
            revert TargetOutOfRange(targetHealthWad);
        }
        if (cashDestination == address(0)) {
            revert ZeroDestination();
        }
        if (premiumTermSeconds < MIN_TERM || premiumTermSeconds > MAX_TERM) {
            revert TermOutOfRange(premiumTermSeconds);
        }
    }

    /// @dev Market, position and duplicate-policy validation. Returns the market's LLTV because the
    ///      `PolicyCreated` event carries it for the reactive contract, which cannot read Morpho.
    function _validateLoan(bytes32 marketId, address borrower) private view returns (uint256 lltv) {
        IMorpho.MarketParams memory params = morpho.idToMarketParams(marketId);
        if (params.loanToken == address(0) || params.oracle == address(0) || params.loanToken != address(coverAsset)) {
            revert MarketNotSupported(marketId);
        }

        IMorpho.Position memory position = morpho.position(marketId, borrower);
        if (position.collateral == 0 || position.borrowShares == 0) {
            revert LoanNotOpen(marketId, borrower);
        }

        uint256 debt = _debtOf(marketId, position.borrowShares);
        uint256 health = HealthMath.health(position.collateral, IOracle(params.oracle).price(), params.lltv, debt);
        if (health <= WAD) {
            revert LoanUnhealthy(marketId, borrower, health);
        }

        bytes32 key = loanKey(marketId, borrower);
        uint256 existing = _policyOfLoan[key];
        if (existing != 0 && _policies[existing].status != Status.Cancelled) {
            revert PolicyExists(key, existing);
        }
        if (_policiesOf[borrower].length >= MAX_POLICIES) {
            revert TooManyPolicies(borrower, _policiesOf[borrower].length);
        }

        return params.lltv;
    }

    /// @notice Buys more time. Allowed while Active or Paused: paying ahead is never blocked.
    /// @param policyId Policy to extend.
    /// @param amount Cover asset to pay; it buys `amount / premiumPerSecond` seconds.
    function payPremium(uint256 policyId, uint256 amount) external {
        Policy storage p = _policies[policyId];
        if (p.status == Status.None) {
            revert UnknownPolicy(policyId);
        }
        if (p.borrower != msg.sender) {
            revert NotBorrower(policyId, msg.sender);
        }
        if (p.status != Status.Active && p.status != Status.Paused) {
            revert PolicyNotLive(policyId, uint8(p.status));
        }
        if (amount < p.premiumPerSecond) {
            revert AmountTooSmall(amount, p.premiumPerSecond);
        }

        uint64 secondsBought = uint64(amount / p.premiumPerSecond);
        uint64 latestAllowed = uint64(block.timestamp) + MAX_TERM;
        uint64 paidThrough = p.paidThrough + secondsBought;
        if (paidThrough > latestAllowed) {
            paidThrough = latestAllowed;
        }
        p.paidThrough = paidThrough;

        coverAsset.safeTransferFrom(msg.sender, coveragePool, amount);
        emit PremiumPaid(policyId, paidThrough);
    }

    /// @notice Stops claims without refunding premium. Time keeps running while paused.
    function pausePolicy(uint256 policyId) external {
        Policy storage p = _ownedPolicy(policyId);
        if (p.status != Status.Active) {
            revert PolicyNotLive(policyId, uint8(p.status));
        }
        p.status = Status.Paused;
        emit PolicyStatusChanged(policyId, uint8(Status.Paused), 0);
    }

    /// @notice Restores claims on a paused policy.
    function resumePolicy(uint256 policyId) external {
        Policy storage p = _ownedPolicy(policyId);
        if (p.status != Status.Paused) {
            revert PolicyNotLive(policyId, uint8(p.status));
        }
        p.status = Status.Active;
        emit PolicyStatusChanged(policyId, uint8(Status.Active), 0);
    }

    /// @notice Ends cover permanently. Claims whose liquidation preceded this block are still
    ///         honoured by `CoveragePool`, which compares `cancelledAtBlock` with `liquidateBlock`.
    function cancelPolicy(uint256 policyId) external {
        Policy storage p = _ownedPolicy(policyId);
        if (p.status == Status.Cancelled) {
            revert PolicyNotLive(policyId, uint8(Status.Cancelled));
        }
        p.status = Status.Cancelled;
        p.cancelledAtBlock = uint64(block.number);
        emit PolicyStatusChanged(policyId, uint8(Status.Cancelled), uint64(block.number));
    }

    /// @notice Records relief applied by the pool. Only the pool may write here.
    function recordRelief(uint256 policyId, uint256 amount) external onlyCoveragePool {
        Policy storage p = _policies[policyId];
        if (p.status == Status.None) {
            revert UnknownPolicy(policyId);
        }
        uint256 remaining = p.reliefCeiling - p.reliefUsed;
        if (amount > remaining) {
            revert CapExceeded(amount, remaining);
        }
        p.reliefUsed += amount;
    }

    /// @notice Points the registry at the pool exactly once. The deploy script then renounces
    ///         ownership, so this cannot be used to redirect anything later.
    function setCoveragePool(address pool) external onlyOwner {
        if (pool == address(0)) {
            revert ZeroAddress();
        }
        if (coveragePool != address(0)) {
            revert AlreadySet();
        }
        coveragePool = pool;
        emit CoveragePoolSet(pool);
    }

    /// @notice The key a loan is known by: one position per market per borrower in Morpho.
    function loanKey(bytes32 marketId, address borrower) public pure returns (bytes32) {
        return keccak256(abi.encode(marketId, borrower));
    }

    /// @notice Full policy record.
    function getPolicy(uint256 policyId) external view returns (Policy memory) {
        if (_policies[policyId].status == Status.None) {
            revert UnknownPolicy(policyId);
        }
        return _policies[policyId];
    }

    /// @notice Policy id currently bound to a loan, or 0.
    function policyOfLoan(bytes32 loanKey_) external view returns (uint256) {
        return _policyOfLoan[loanKey_];
    }

    /// @notice Every policy id for a borrower, oldest first (at most `MAX_POLICIES`).
    function policiesOf(address borrower) external view returns (uint256[] memory) {
        return _policiesOf[borrower];
    }

    /// @notice Relief capacity left on a policy.
    function reliefRemaining(uint256 policyId) external view returns (uint256) {
        Policy storage p = _policies[policyId];
        if (p.status == Status.None) {
            return 0;
        }
        return p.reliefCeiling - p.reliefUsed;
    }

    /// @notice Number of policies that can still claim (Active or Paused).
    function activePolicyCount(address borrower) external view returns (uint256 count) {
        uint256[] storage ids = _policiesOf[borrower];
        for (uint256 i = 0; i < ids.length; ++i) {
            Status status = _policies[ids[i]].status;
            if (status == Status.Active || status == Status.Paused) {
                ++count;
            }
        }
    }

    /// @notice True when a claim could be honoured right now.
    function isCoverable(uint256 policyId) external view returns (bool) {
        Policy storage p = _policies[policyId];
        return p.status == Status.Active && p.paidThrough >= block.timestamp && p.reliefCeiling > p.reliefUsed;
    }

    function _ownedPolicy(uint256 policyId) private view returns (Policy storage p) {
        p = _policies[policyId];
        if (p.status == Status.None) {
            revert UnknownPolicy(policyId);
        }
        if (p.borrower != msg.sender) {
            revert NotBorrower(policyId, msg.sender);
        }
    }

    function _debtOf(bytes32 marketId, uint128 borrowShares) private view returns (uint256) {
        IMorpho.Market memory m = morpho.market(marketId);
        if (m.totalBorrowShares == 0) {
            return 0;
        }
        return HealthMath.toAssetsUp(borrowShares, m.totalBorrowAssets, m.totalBorrowShares);
    }
}
