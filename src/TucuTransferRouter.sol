// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IERC20TransferFrom {
    function transferFrom(address from, address to, uint256 amount)
        external
        returns (bool);
}

/// @title TucuTransferRouter
/// @notice Non-custodial ERC-20 transfer router with a transparent platform fee.
/// @dev The sender approves only the selected token amount. The complete amount
/// is distributed to the recipient and treasury in the same transaction.
contract TucuTransferRouter is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint16 public constant MAX_FEE_BPS = 100; // Hard cap: 1%.

    address public treasury;
    uint16 public feeBps;
    mapping(address token => bool allowed) public allowedTokens;

    error FeeTooHigh(uint16 feeBps);
    error InvalidAmount();
    error TokenNotAllowed(address token);
    error TokenTransferFailed(address token);
    error ZeroAddress();

    event FeeUpdated(uint16 previousFeeBps, uint16 newFeeBps);
    event TokenPermissionUpdated(address indexed token, bool allowed);
    event TransferRouted(
        address indexed sender,
        address indexed recipient,
        address indexed token,
        uint256 totalAmount,
        uint256 recipientAmount,
        uint256 feeAmount
    );
    event TreasuryUpdated(
        address indexed previousTreasury,
        address indexed newTreasury
    );

    constructor(address admin, address initialTreasury, uint16 initialFeeBps) {
        if (admin == address(0) || initialTreasury == address(0)) {
            revert ZeroAddress();
        }
        if (initialFeeBps > MAX_FEE_BPS) revert FeeTooHigh(initialFeeBps);

        treasury = initialTreasury;
        feeBps = initialFeeBps;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /// @notice Routes an approved token amount without retaining custody.
    /// @param token Allowlisted ERC-20 token.
    /// @param recipient Address receiving the amount after the platform fee.
    /// @param totalAmount Total amount debited from the caller.
    function routeToken(
        address token,
        address recipient,
        uint256 totalAmount
    ) external whenNotPaused nonReentrant {
        if (!allowedTokens[token]) revert TokenNotAllowed(token);
        if (recipient == address(0)) revert ZeroAddress();
        if (totalAmount == 0) revert InvalidAmount();

        uint256 feeAmount = (totalAmount * feeBps) / 10_000;
        uint256 recipientAmount = totalAmount - feeAmount;
        _safeTransferFrom(token, msg.sender, recipient, recipientAmount);
        if (feeAmount != 0) {
            _safeTransferFrom(token, msg.sender, treasury, feeAmount);
        }

        emit TransferRouted(
            msg.sender,
            recipient,
            token,
            totalAmount,
            recipientAmount,
            feeAmount
        );
    }

    /// @notice Adds or removes a token from the explicit transfer allowlist.
    function setTokenAllowed(address token, bool allowed)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (token == address(0)) revert ZeroAddress();
        allowedTokens[token] = allowed;
        emit TokenPermissionUpdated(token, allowed);
    }

    /// @notice Sets the platform fee, permanently capped by MAX_FEE_BPS.
    function setFeeBps(uint16 newFeeBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh(newFeeBps);
        uint16 previous = feeBps;
        feeBps = newFeeBps;
        emit FeeUpdated(previous, newFeeBps);
    }

    /// @notice Updates the address that receives separately accounted fees.
    function setTreasury(address newTreasury)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newTreasury == address(0)) revert ZeroAddress();
        address previous = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(previous, newTreasury);
    }

    /// @notice Stops new routed transfers in an emergency.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Restores routed transfers after an emergency is resolved.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) private {
        bool success = IERC20TransferFrom(token).transferFrom(
            from,
            to,
            amount
        );
        if (!success) {
            revert TokenTransferFailed(token);
        }
    }
}
