// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./Ownable.sol";

abstract contract Whitelist is Ownable {
    mapping(address => bool) public whitelist;
    mapping(address => bool) public operator; //have access to mint/burn

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

    function addOperator(address account) external onlyOwner {
        _addOperator(account);
    }

    function removeOperator(address account) external onlyOwner {
        require(operator[account], "whitelist.removeOperator: NOT_OPERATOR");
        operator[account] = false;
    }

    function _addOperator(address account) internal {
        require(!operator[account], "whitelist.addOperator: ALREADY_OPERATOR");
        operator[account] = true;
    }

    modifier onlyOperator() {
        require(operator[msg.sender], "whitelist: NOT_IN_OPERATOR");
        _;
    }

    modifier operatorOrWhitelist() {
        require(operator[msg.sender] || whitelist[msg.sender], "whitelist: NOT_IN_OPERATOR_OR_WHITELIST");
        _;
    }
}
