// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Ownable {
    address public admin;
    address public pendingAdmin;

    event NewAdmin(address indexed oldAdmin, address indexed newAdmin);
    event NewPendingAdmin(address indexed oldPendingAdmin, address indexed newPendingAdmin);
    ///@notice there is no constructor, need to set admin from child contract

    modifier onlyAdmin() {
        require(msg.sender == admin, "Ownable: REQUIRE_ADMIN");
        _;
    }

    function setPendingAdmin(address newPendingAdmin) external onlyAdmin {
        require(pendingAdmin != newPendingAdmin, "Ownable: ALREADY_SET");
        emit NewPendingAdmin(pendingAdmin, newPendingAdmin);
        pendingAdmin = newPendingAdmin;
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "Ownable: REQUIRE_PENDING_ADMIN");
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;
        admin = pendingAdmin;
        pendingAdmin = address(0);
        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }
}
