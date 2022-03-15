// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./Ownable.sol";

abstract contract Whitelist is Ownable {
    mapping(address => bool) public whitelist;

    function addWhitelist(address account) public onlyOwner {
        whitelist[account] = true;
    }

    function removeWhitelist(address account) external onlyOwner {
        whitelist[account] = false;
    }

    modifier onlyWhitelist() {
        require(whitelist[msg.sender], "whitelist: NOT_IN_WHITELIST");
        _;
    }
}
