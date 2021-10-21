// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Ownable {
    address public _admin;
    address public _pendingAdmin;

    event OwnershipTransfer(address indexed previousAdmin, address indexed pendingAdmin);
    event OwnershipAccept(address indexed currentAdmin);

    constructor() {
        _admin = msg.sender;
    }

    function _setPendingAdmin(address newAdmin) public onlyAdmin {
        require(newAdmin != address(0), "Ownable: new admin is the zero address");
        require(newAdmin != _pendingAdmin, "Ownable: already set");
        _pendingAdmin = newAdmin;
        emit OwnershipTransfer(_admin, newAdmin);
    }

    function _acceptAdmin() public {
        require(msg.sender == _pendingAdmin, "Ownable: not pendingAdmin");
        _admin = _pendingAdmin;
        _pendingAdmin = address(0);
        emit OwnershipAccept(_pendingAdmin);
    }

    modifier onlyAdmin() {
        require(_admin == msg.sender, "Ownable: caller is not the admin");
        _;
    }
}
