// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../utils/Ownable.sol";
import "../utils/Reentrant.sol";
import "./interfaces/IOrderBook.sol";
import "./interfaces/IRouterForKeeper.sol";
import "../libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    function executeOpenPositionOrder(OpenPositionOrder memory order, bytes memory signature) external nonReentrant {
        require(verify(order, signature));
        require(order.baseToken != address(0), "OrderBook.executeOpenPositionOrder: ORDER_NOT_FOUND");
        require(order.side == 0 || order.side == 1, "OrderBook.executeOpenPositionOrder: INVALID_SIDE");

        uint256 currentPrice = IRouterForKeeper(routerForKeeper).getSpotPriceWithMultiplier(
            order.baseToken,
            order.quoteToken
        );
        //check price
        if (order.side == 0) {
            require(currentPrice <= order.limitPrice, "OrderBook.executeOpenPositionOrder: WRONG_PRICE");
        } else {
            require(currentPrice >= order.limitPrice, "OrderBook.executeOpenPositionOrder: WRONG_PRICE");
        }

        //execute
        IRouterForKeeper(routerForKeeper).openPositionWithWallet(
            order.baseToken,
            order.quoteToken,
            order.trader,
            order.trader,
            order.side,
            order.baseAmount,
            order.quoteAmount,
            order.baseAmountLimit,
            order.deadline
        );

        usedNonce[order.nonce] = true;
    }

    function verify(OpenPositionOrder memory order, bytes memory signature) public view returns (bool) {
        address recover = keccak256(abi.encode(order)).toEthSignedMessageHash().recover(signature);
        require(order.trader == recover, "OrderBook.verify: NOT_SIGNER");
        require(!usedNonce[order.nonce], "OrderBook.verify: NONCE_USED");
        require(block.timestamp < order.deadline, "OrderBook.verify: EXPIRED");
        return true;
    }

    function setRouterForKeeper(address _routerForKeeper) external override onlyOwner {
        require(_routerForKeeper != address(0), "OrderBook.setRouterKeeper: ZERO_ADDRESS");

        routerForKeeper = _routerForKeeper;
        emit SetRouterForKeeper(_routerForKeeper);
    }
}
