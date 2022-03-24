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
        require(verifyOpen(order, signature));
        require(order.routerToExecute == routerForKeeper, "OrderBook.executeOpenPositionOrder: WRONG_ROUTER");
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
        if (order.withWallet) {
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
        } else {
            IRouterForKeeper(routerForKeeper).openPositionWithMargin(
                order.baseToken,
                order.quoteToken,
                order.trader,
                order.side,
                order.quoteAmount,
                order.baseAmountLimit,
                order.deadline
            );
        }

        usedNonce[order.nonce] = true;
    }

    function executeClosePositionOrder(ClosePositionOrder memory order, bytes memory signature) external nonReentrant {
        require(verifyClose(order, signature));
        require(order.routerToExecute == routerForKeeper, "OrderBook.executeClosePositionOrder: WRONG_ROUTER");
        require(order.baseToken != address(0), "OrderBook.executeClosePositionOrder: ORDER_NOT_FOUND");
        require(order.side == 0 || order.side == 1, "OrderBook.executeClosePositionOrder: INVALID_SIDE");

        uint256 currentPrice = IRouterForKeeper(routerForKeeper).getSpotPriceWithMultiplier(
            order.baseToken,
            order.quoteToken
        );

        //check price
        if (order.side == 0) {
            require(currentPrice >= order.limitPrice, "OrderBook.executeClosePositionOrder: WRONG_PRICE");
        } else {
            require(currentPrice <= order.limitPrice, "OrderBook.executeClosePositionOrder: WRONG_PRICE");
        }

        //execute
        IRouterForKeeper(routerForKeeper).closePosition(
            order.baseToken,
            order.quoteToken,
            order.trader,
            order.trader,
            order.quoteAmount,
            order.deadline,
            order.autoWithdraw
        );

        usedNonce[order.nonce] = true;
    }

    function verifyOpen(OpenPositionOrder memory order, bytes memory signature) public view returns (bool) {
        address recover = keccak256(abi.encode(order)).toEthSignedMessageHash().recover(signature);
        require(order.trader == recover, "OrderBook.verifyOpen: NOT_SIGNER");
        require(!usedNonce[order.nonce], "OrderBook.verifyOpen: NONCE_USED");
        require(block.timestamp < order.deadline, "OrderBook.verifyOpen: EXPIRED");
        return true;
    }

    function verifyClose(ClosePositionOrder memory order, bytes memory signature) public view returns (bool) {
        address recover = keccak256(abi.encode(order)).toEthSignedMessageHash().recover(signature);
        require(order.trader == recover, "OrderBook.verifyClose: NOT_SIGNER");
        require(!usedNonce[order.nonce], "OrderBook.verifyClose: NONCE_USED");
        require(block.timestamp < order.deadline, "OrderBook.verifyClose: EXPIRED");
        return true;
    }

    function setRouterForKeeper(address _routerForKeeper) external override onlyOwner {
        require(_routerForKeeper != address(0), "OrderBook.setRouterKeeper: ZERO_ADDRESS");

        routerForKeeper = _routerForKeeper;
        emit SetRouterForKeeper(_routerForKeeper);
    }
}
