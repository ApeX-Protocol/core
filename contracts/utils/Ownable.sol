// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Ownable {
    address private _owner;
    address private _pendingOwner;

    event OwnershipTransfer(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipAccept(address indexed currentOwner);

    constructor() {
        _owner = msg.sender;
    }

    function renounceOwnership() public onlyOwner {
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        require(newOwner != _pendingOwner, "Ownable: already set");
        _pendingOwner = newOwner;
        emit OwnershipTransfer(_owner, newOwner);
    }

    function acceptOwnership() public {
        require(msg.sender == _pendingOwner, "Ownable: not pendingOwner");
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit OwnershipAccept(_pendingOwner);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
}
