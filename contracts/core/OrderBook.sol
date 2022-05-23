// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../utils/Ownable.sol";
import "../utils/Reentrant.sol";
import "../libraries/TransferHelper.sol";
import "../interfaces/IOrderBook.sol";
import "../interfaces/IRouterForKeeper.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OrderBook is IOrderBook, Ownable, Reentrant {
    using ECDSA for bytes32;

    address public routerForKeeper;
    address public bot;
    mapping(bytes => bool) public usedNonce;

    modifier onlyBot() {
        require(msg.sender == bot, "OB:only bot");
        _;
    }

    constructor(address _routerForKeeper, address _bot) {
        require(_routerForKeeper != address(0), "OB: ZERO_ADDRESS");
        owner = msg.sender;
        routerForKeeper = _routerForKeeper;
        bot = _bot;
    }

    function setBot(address newBot) external override onlyOwner {
        require(newBot != address(0), "OB.ST: ZERO_ADDRESS");
        bot = newBot;
    }

    function batchExecuteOpen(
        OpenPositionOrder[] memory orders,
        bytes[] memory signatures,
        bool requireSuccess
    ) external override nonReentrant onlyBot returns (RespData[] memory respData) {
        require(orders.length == signatures.length, "OB.BE: LENGTH_NOT_MATCH");
        respData = new RespData[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            respData[i] = _executeOpen(orders[i], signatures[i], requireSuccess);
        }
        emit BatchExecuteOpen(orders, signatures, requireSuccess);
    }

    function batchExecuteClose(
        ClosePositionOrder[] memory orders,
        bytes[] memory signatures,
        bool requireSuccess
    ) external override nonReentrant onlyBot returns (RespData[] memory respData) {
        require(orders.length == signatures.length, "OB.BE: LENGTH_NOT_MATCH");
        respData = new RespData[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            respData[i] = _executeClose(orders[i], signatures[i], requireSuccess);
        }

        emit BatchExecuteClose(orders, signatures, requireSuccess);
    }

    function executeOpen(OpenPositionOrder memory order, bytes memory signature) external override nonReentrant onlyBot {
        _executeOpen(order, signature, true);

        emit ExecuteOpen(order, signature);
    }

    function executeClose(ClosePositionOrder memory order, bytes memory signature) external override nonReentrant onlyBot {
        _executeClose(order, signature, true);

        emit ExecuteClose(order, signature);
    }

    function verifyOpen(OpenPositionOrder memory order, bytes memory signature) public view override returns (bool) {
        address recover = keccak256(abi.encode(order)).toEthSignedMessageHash().recover(signature);
        require(order.trader == recover, "OB.VO: NOT_SIGNER");
        require(!usedNonce[order.nonce], "OB.VO: NONCE_USED");
        require(block.timestamp < order.deadline, "OB.VO: EXPIRED");
        return true;
    }

    function verifyClose(ClosePositionOrder memory order, bytes memory signature) public view override returns (bool) {
        address recover = keccak256(abi.encode(order)).toEthSignedMessageHash().recover(signature);
        require(order.trader == recover, "OB.VC: NOT_SIGNER");
        require(!usedNonce[order.nonce], "OB.VC: NONCE_USED");
        require(block.timestamp < order.deadline, "OB.VC: EXPIRED");
        return true;
    }

    function setRouterForKeeper(address _routerForKeeper) external override onlyOwner {
        require(_routerForKeeper != address(0), "OB.SRK: ZERO_ADDRESS");

        routerForKeeper = _routerForKeeper;
        emit SetRouterForKeeper(_routerForKeeper);
    }

    function _executeOpen(
        OpenPositionOrder memory order,
        bytes memory signature,
        bool requireSuccess
    ) internal returns (RespData memory) {
        require(verifyOpen(order, signature));
        require(order.routerToExecute == routerForKeeper, "OB.EO: WRONG_ROUTER");
        require(order.baseToken != address(0), "OB.EO: ORDER_NOT_FOUND");
        require(order.side == 0 || order.side == 1, "OB.EO: INVALID_SIDE");

        (uint256 currentPrice, uint256 baseDecimals, uint256 quoteDecimals) = IRouterForKeeper(routerForKeeper)
        .getSpotPriceWithMultiplier(order.baseToken, order.quoteToken);

        // long 0 : price <= limitPrice * (1 + slippage)
        // short 1 : price >= limitPrice * (1 - slippage)
        uint256 slippagePrice = (order.side == 0) ? (order.limitPrice * (10000 + order.slippage)) / 10000 : (order.limitPrice * (10000 - order.slippage)) / 10000;
        require(order.side == 0 ? currentPrice <= slippagePrice : currentPrice >= slippagePrice, "OB.EO: SLIPPAGE_NOT_FUIFILL");

        bool success;
        bytes memory ret;

        if (order.withWallet) {
            (success, ret) = routerForKeeper.call(
                abi.encodeWithSelector(
                    IRouterForKeeper.openPositionWithWallet.selector,
                    order
                )
            );
        } else {
            (success, ret) = routerForKeeper.call(
                abi.encodeWithSelector(
                    IRouterForKeeper.openPositionWithMargin.selector,
                    order
                )
            );
        }
        emit ExecuteLog(order.nonce, success);
        if (requireSuccess) {
            require(success, "OB.EO: call failed");
        }

        usedNonce[order.nonce] = true;
        return RespData({success : success, result : ret});
    }

    function _executeClose(
        ClosePositionOrder memory order,
        bytes memory signature,
        bool requireSuccess
    ) internal returns (RespData memory) {
        require(verifyClose(order, signature));
        require(order.routerToExecute == routerForKeeper, "OB.EC: WRONG_ROUTER");
        require(order.baseToken != address(0), "OB.EC: ORDER_NOT_FOUND");
        require(order.side == 0 || order.side == 1, "OB.EC: INVALID_SIDE");

        (uint256 currentPrice, ,) = IRouterForKeeper(routerForKeeper).getSpotPriceWithMultiplier(
            order.baseToken,
            order.quoteToken
        );

        require(
            order.side == 0 ? currentPrice >= order.limitPrice : currentPrice <= order.limitPrice,
            "OB.EC: WRONG_PRICE"
        );

        (bool success, bytes memory ret) = routerForKeeper.call(
            abi.encodeWithSelector(IRouterForKeeper.closePosition.selector, order)
        );
        emit ExecuteLog(order.nonce, success);

        if (requireSuccess) {
            require(success, "OB.EC: call failed");
        }

        usedNonce[order.nonce] = true;
        return RespData({success : success, result : ret});
    }
}
