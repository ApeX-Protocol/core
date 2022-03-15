// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./Ownable.sol";

abstract contract Whitelist is Ownable {
    mapping(address => bool) public whitelist;

    function _addWhitelist(address account) internal onlyOwner {
        whitelist[account] = true;
    }

    function addManyWhitelist(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelist[accounts[i]] = true;
        }
    }

    function removeManyWhitelist(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelist[accounts[i]] = false;
        }
    }

    modifier onlyWhitelist() {
        require(whitelist[msg.sender], "whitelist: NOT_IN_WHITELIST");
        _;
    }
}
