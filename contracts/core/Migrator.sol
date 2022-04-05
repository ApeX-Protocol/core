// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IAmm.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IPairFactory.sol";

contract Migrator {
    address public oldRouter;
    address public newRouter;

    function migrate(address baseToken, address quoteToken) external {
        
    }
}