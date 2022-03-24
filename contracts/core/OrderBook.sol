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

    struct RespData {
        bool success;
        bytes result;
    }

    address public routerForKeeper;
    mapping(bytes => bool) public usedNonce;

    constructor(address _routerForKeeper) {
        require(_routerForKeeper != address(0), "OrderBook: ZERO_ADDRESS");
        owner = msg.sender;
        routerForKeeper = _routerForKeeper;
    }

    function batchExecuteOpen(
        OpenPositionOrder[] memory orders,
        bytes[] memory signatures,
        bool requireSuccess
    ) external nonReentrant returns (RespData[] memory respData) {
        require(orders.length == signatures.length, "OrderBook.batchExecuteOpen: LENGTH_NOT_MATCH");
        respData = new RespData[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            respData[i] = _executeOpen(orders[i], signatures[i], requireSuccess);
        }
    }

    function batchExecuteClose(
        ClosePositionOrder[] memory orders,
        bytes[] memory signatures,
        bool requireSuccess
    ) external nonReentrant returns (RespData[] memory respData) {
        require(orders.length == signatures.length, "OrderBook.batchExecuteClose: LENGTH_NOT_MATCH");
        respData = new RespData[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            respData[i] = _executeClose(orders[i], signatures[i], requireSuccess);
        }
    }

    function executeOpen(OpenPositionOrder memory order, bytes memory signature) external nonReentrant {
        _executeOpen(order, signature, true);
    }

    function executeClose(ClosePositionOrder memory order, bytes memory signature) external nonReentrant {
        _executeClose(order, signature, true);
    }

    function _executeOpen(
        OpenPositionOrder memory order,
        bytes memory signature,
        bool requireSuccess
    ) internal returns (RespData memory) {
        require(verifyOpen(order, signature));
        require(order.routerToExecute == routerForKeeper, "OrderBook.executeOpen: WRONG_ROUTER");
        require(order.baseToken != address(0), "OrderBook.executeOpen: ORDER_NOT_FOUND");
        require(order.side == 0 || order.side == 1, "OrderBook.executeOpen: INVALID_SIDE");

        uint256 currentPrice = IRouterForKeeper(routerForKeeper).getSpotPriceWithMultiplier(
            order.baseToken,
            order.quoteToken
        );
        //check price
        if (order.side == 0) {
            require(currentPrice <= order.limitPrice, "OrderBook.executeOpen: WRONG_PRICE");
        } else {
            require(currentPrice >= order.limitPrice, "OrderBook.executeOpen: WRONG_PRICE");
        }

        bool success;
        bytes memory ret;
        if (order.withWallet) {
            (success, ret) = routerForKeeper.call(
                abi.encodeWithSignature(
                    "openPositionWithWallet(address,address,address,address,uint8,uint256,uint256,uint256,uint256)",
                    order.baseToken,
                    order.quoteToken,
                    order.trader,
                    order.trader,
                    order.side,
                    order.baseAmount,
                    order.quoteAmount,
                    order.baseAmountLimit,
                    order.deadline
                )
            );
        } else {
            (success, ret) = routerForKeeper.call(
                abi.encodeWithSignature(
                    "openPositionWithMargin(address,address,address,uint8,uint256,uint256,uint256)",
                    order.baseToken,
                    order.quoteToken,
                    order.trader,
                    order.side,
                    order.quoteAmount,
                    order.baseAmountLimit,
                    order.deadline
                )
            );
        }
        if (requireSuccess) {
            require(success, "_executeOpen: call failed");
        }

        usedNonce[order.nonce] = true;
        return RespData({success: success, result: ret});
    }

    function _executeClose(
        ClosePositionOrder memory order,
        bytes memory signature,
        bool requireSuccess
    ) internal returns (RespData memory) {
        require(verifyClose(order, signature));
        require(order.routerToExecute == routerForKeeper, "OrderBook.executeClose: WRONG_ROUTER");
        require(order.baseToken != address(0), "OrderBook.executeClose: ORDER_NOT_FOUND");
        require(order.side == 0 || order.side == 1, "OrderBook.executeClose: INVALID_SIDE");

        uint256 currentPrice = IRouterForKeeper(routerForKeeper).getSpotPriceWithMultiplier(
            order.baseToken,
            order.quoteToken
        );

        //check price
        if (order.side == 0) {
            require(currentPrice >= order.limitPrice, "OrderBook.executeClose: WRONG_PRICE");
        } else {
            require(currentPrice <= order.limitPrice, "OrderBook.executeClose: WRONG_PRICE");
        }

        (bool success, bytes memory ret) = routerForKeeper.call(
            abi.encodeWithSignature(
                "closePosition(address,address,address,address,uint256,uint256,bool)",
                order.baseToken,
                order.quoteToken,
                order.trader,
                order.trader,
                order.quoteAmount,
                order.deadline,
                order.autoWithdraw
            )
        );

        if (requireSuccess) {
            require(success, "_executeClose: call failed");
        }

        usedNonce[order.nonce] = true;
        return RespData({success: success, result: ret});
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
