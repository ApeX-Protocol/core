// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../utils/Ownable.sol";
import "../utils/Reentrant.sol";
import "./interfaces/IOrderBook.sol";
import "../libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "hardhat/console.sol";

contract OrderBook is IOrderBook, Ownable, Reentrant {
    using ECDSA for bytes32;

    address public routerForKeeper;

    mapping(bytes => bool) public usedNonce;

    constructor(address _routerForKeeper) {
        require(_routerForKeeper != address(0), "OrderBook: ZERO_ADDRESS");
        owner = msg.sender;
        routerForKeeper = _routerForKeeper;
    }

    function executeOpenPositionOrder(
        OpenPositionOrder memory order,
        bytes memory signature,
        uint256[] memory c
    ) external nonReentrant {
        require(verify(order, signature, c));
        require(order.baseToken != address(0), "OrderBook.executeOpenPositionOrder: ORDER_NOT_FOUND");
        //execute

        usedNonce[order.nonce] = true;
    }

    function verify(
        OpenPositionOrder memory order,
        bytes memory signature,
        uint256[] memory c
    ) public view returns (bool) {
        uint256 a = 1234;
        string memory b = "hello";
        address recover = keccak256(abi.encode(a, b, c)).toEthSignedMessageHash().recover(signature);
        require(order.trader == recover, "NOT_SIGNER");
        require(!usedNonce[order.nonce], "NONCE_USED");
        require(block.timestamp < order.deadline, "EXPIRED");
        return true;
    }

    function setRouterForKeeper(address _routerForKeeper) external override onlyOwner {
        require(_routerForKeeper != address(0), "OrderBook.setRouterKeeper: ZERO_ADDRESS");

        routerForKeeper = _routerForKeeper;
        emit SetRouterForKeeper(_routerForKeeper);
    }
}
