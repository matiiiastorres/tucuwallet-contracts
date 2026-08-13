// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

interface ITucuRewardsToken {
    function mint(address to, uint256 amount) external;
}

/// @title RewardsDistributorV2
/// @notice Mints fixed TUCU rewards after a trusted backend signs a short-lived
/// EIP-712 authorization. Mission amounts and limits are enforced on-chain.
/// @dev The distributor must receive TUCU's MINTER_ROLE after deployment.
contract RewardsDistributorV2 is AccessControl, EIP712, Pausable {
    bytes32 public constant REWARD_SIGNER_ROLE = keccak256("REWARD_SIGNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "RewardClaim(address recipient,bytes32 missionId,bytes32 claimId,uint256 amount,uint256 deadline)"
    );
    uint256 private constant SECP256K1N_DIV_2 =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;
    uint256 public constant WINDOW_DURATION = 30 days;
    uint256 public constant MAX_REWARD_PER_WINDOW = 100 ether;

    ITucuRewardsToken public immutable token;

    struct MissionConfig {
        uint256 amount;
        uint64 cooldown;
        uint32 maxLifetimeClaims;
        uint32 maxClaimsPerWindow;
        bool enabled;
    }

    struct MissionAccount {
        uint64 lastClaimAt;
        uint64 windowStartedAt;
        uint32 lifetimeClaims;
        uint32 windowClaims;
    }

    struct RewardWindow {
        uint64 startedAt;
        uint192 amount;
    }

    mapping(bytes32 missionId => MissionConfig config) public missions;
    mapping(address recipient => mapping(bytes32 missionId => MissionAccount account))
        public missionAccounts;
    mapping(address recipient => RewardWindow window) public rewardWindows;
    mapping(bytes32 claimId => bool used) public usedClaimIds;

    error ClaimAlreadyUsed(bytes32 claimId);
    error ClaimExpired(uint256 deadline);
    error CooldownActive(uint256 availableAt);
    error InvalidSignature();
    error LifetimeLimitReached();
    error MissionDisabled(bytes32 missionId);
    error InvalidMissionId();
    error RewardAmountTooHigh(uint256 amount, uint256 maximum);
    error RewardAmountChanged(uint256 authorizedAmount, uint256 currentAmount);
    error MissionWindowLimitReached();
    error MonthlyRewardLimitReached();
    error NotRecipient();
    error ZeroAddress();
    error ZeroAmount();

    event MissionConfigured(
        bytes32 indexed missionId,
        uint256 amount,
        uint64 cooldown,
        uint32 maxLifetimeClaims,
        uint32 maxClaimsPerWindow,
        bool enabled
    );
    event RewardClaimed(
        address indexed recipient,
        bytes32 indexed missionId,
        bytes32 indexed claimId,
        uint256 amount,
        address signer
    );

    constructor(address tokenAddress, address admin, address rewardSigner)
        EIP712("TucuRewardsDistributor", "2")
    {
        if (
            tokenAddress == address(0) ||
            admin == address(0) ||
            rewardSigner == address(0)
        ) revert ZeroAddress();

        token = ITucuRewardsToken(tokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(REWARD_SIGNER_ROLE, rewardSigner);
    }

    /// @notice Creates or updates an on-chain mission policy.
    function configureMission(
        bytes32 missionId,
        uint256 amount,
        uint64 cooldown,
        uint32 maxLifetimeClaims,
        uint32 maxClaimsPerWindow,
        bool enabled
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (missionId == bytes32(0)) revert InvalidMissionId();
        if (amount == 0) revert ZeroAmount();
        if (amount > MAX_REWARD_PER_WINDOW) {
            revert RewardAmountTooHigh(amount, MAX_REWARD_PER_WINDOW);
        }

        missions[missionId] = MissionConfig({
            amount: amount,
            cooldown: cooldown,
            maxLifetimeClaims: maxLifetimeClaims,
            maxClaimsPerWindow: maxClaimsPerWindow,
            enabled: enabled
        });

        emit MissionConfigured(
            missionId,
            amount,
            cooldown,
            maxLifetimeClaims,
            maxClaimsPerWindow,
            enabled
        );
    }

    /// @notice Claims a reward authorized by a REWARD_SIGNER_ROLE account.
    /// @param missionId keccak256 hash of the canonical mission name.
    /// @param claimId Unique backend-generated identifier; it can never be reused.
    /// @param recipient World wallet that completed the verified mission.
    /// @param amount Reward amount authorized by the backend.
    /// @param deadline Last timestamp at which the authorization is valid.
    /// @param signature EIP-712 signature over the other four parameters.
    function claim(
        bytes32 missionId,
        bytes32 claimId,
        address recipient,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external whenNotPaused {
        if (msg.sender != recipient) revert NotRecipient();
        if (block.timestamp > deadline) revert ClaimExpired(deadline);
        if (usedClaimIds[claimId]) revert ClaimAlreadyUsed(claimId);

        MissionConfig memory mission = missions[missionId];
        if (!mission.enabled) revert MissionDisabled(missionId);
        if (amount != mission.amount) {
            revert RewardAmountChanged(amount, mission.amount);
        }

        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                recipient,
                missionId,
                claimId,
                amount,
                deadline
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = _recover(digest, signature);
        if (!hasRole(REWARD_SIGNER_ROLE, signer)) revert InvalidSignature();

        MissionAccount storage account = missionAccounts[recipient][missionId];
        if (
            mission.maxLifetimeClaims != 0 &&
            account.lifetimeClaims >= mission.maxLifetimeClaims
        ) revert LifetimeLimitReached();
        if (
            mission.cooldown != 0 &&
            account.lastClaimAt != 0 &&
            block.timestamp < uint256(account.lastClaimAt) + mission.cooldown
        ) {
            revert CooldownActive(uint256(account.lastClaimAt) + mission.cooldown);
        }

        if (
            account.windowStartedAt == 0 ||
            block.timestamp >= uint256(account.windowStartedAt) + WINDOW_DURATION
        ) {
            account.windowStartedAt = uint64(block.timestamp);
            account.windowClaims = 0;
        }
        if (
            mission.maxClaimsPerWindow != 0 &&
            account.windowClaims >= mission.maxClaimsPerWindow
        ) revert MissionWindowLimitReached();

        RewardWindow storage rewardWindow = rewardWindows[recipient];
        if (
            rewardWindow.startedAt == 0 ||
            block.timestamp >= uint256(rewardWindow.startedAt) + WINDOW_DURATION
        ) {
            rewardWindow.startedAt = uint64(block.timestamp);
            rewardWindow.amount = 0;
        }
        if (
            uint256(rewardWindow.amount) + mission.amount >
            MAX_REWARD_PER_WINDOW
        ) revert MonthlyRewardLimitReached();

        usedClaimIds[claimId] = true;
        account.lastClaimAt = uint64(block.timestamp);
        account.lifetimeClaims += 1;
        account.windowClaims += 1;
        rewardWindow.amount += uint192(mission.amount);

        token.mint(recipient, mission.amount);

        emit RewardClaimed(
            recipient,
            missionId,
            claimId,
            mission.amount,
            signer
        );
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _recover(bytes32 digest, bytes calldata signature)
        private
        pure
        returns (address signer)
    {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (uint256(s) > SECP256K1N_DIV_2 || (v != 27 && v != 28)) {
            revert InvalidSignature();
        }
        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }

}
