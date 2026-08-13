// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TucuToken} from "./TucuToken.sol";

/// @notice Permanent proxy address for TUCU. The constructor initializes all roles atomically.
contract TucuProxy is ERC1967Proxy {
    constructor(address implementation, address admin)
        ERC1967Proxy(implementation, abi.encodeCall(TucuToken.initialize, (admin)))
    {}
}
