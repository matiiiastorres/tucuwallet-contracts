// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";

/// @title TucuToken
/// @notice Upgradeable ERC-20 reward token for the Tucu ecosystem on World Chain.
/// @custom:oz-upgrades
contract TucuToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public maxSupply;

    error ZeroAddress();
    error MaxSupplyBelowCurrentSupply(uint256 requested, uint256 currentSupply);
    error MaxSupplyExceeded(uint256 requestedSupply, uint256 maximumSupply);

    event MaxSupplyChanged(uint256 previousMaximum, uint256 newMaximum);

    /// @dev Locks the implementation contract. State is initialized through the proxy.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy once and grants all initial roles to `admin`.
    /// @param admin Initial administrator, minter, pauser and upgrader.
    function initialize(address admin) public initializer {
        if (admin == address(0)) revert ZeroAddress();

        __ERC20_init("Tucu", "TUCU");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        maxSupply = 100_000_000 ether;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    /// @notice Issues rewards. `amount` uses 18-decimal base units.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        uint256 requestedSupply = totalSupply() + amount;
        if (requestedSupply > maxSupply) {
            revert MaxSupplyExceeded(requestedSupply, maxSupply);
        }
        _mint(to, amount);
    }

    /// @notice Changes the emission ceiling without deploying a new implementation.
    /// @dev It can never be set below the already issued supply.
    function setMaxSupply(uint256 newMaximum) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 currentSupply = totalSupply();
        if (newMaximum < currentSupply) {
            revert MaxSupplyBelowCurrentSupply(newMaximum, currentSupply);
        }

        uint256 previousMaximum = maxSupply;
        maxSupply = newMaximum;
        emit MaxSupplyChanged(previousMaximum, newMaximum);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Only the upgrader role can replace the implementation behind the proxy.
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);
    }
}
