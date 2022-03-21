// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../utils/Ownable.sol";
import "../utils/Reentrant.sol";
import "./interfaces/IOrderBook.sol";
import "../libraries/TransferHelper.sol";

contract OrderBook is IOrderBook, Ownable, Reentrant {
    address public routerForKeeper;

    mapping(address => mapping(uint256 => bool)) public traderNonces;

    constructor(address _routerForKeeper) {
        require(_routerForKeeper != address(0), "OrderBook: ZERO_ADDRESS");
        owner = msg.sender;
        routerForKeeper = _routerForKeeper;
    }

    function executeOpenPositionOrder(
        address _trader,
        address payable _feeReceiver,
        uint256 _orderIndex,
        bytes calldata data
    ) external override nonReentrant {
        (OpenPositionOrder memory order, uint256 t) = abi.decode(data, (OpenPositionOrder, uint256));
        //check
        require(order.baseToken != address(0), "OrderBook.executeOpenPositionOrder: ORDER_NOT_FOUND");

        TransferHelper.safeTransferETH(_feeReceiver, order.executionFee);

        emit ExecuteOpenPositionOrder(_trader, _feeReceiver, _orderIndex);
    }

    function setRouterForKeeper(address _routerForKeeper) external override onlyOwner {
        require(_routerForKeeper != address(0), "OrderBook.setRouterKeeper: ZERO_ADDRESS");

        routerForKeeper = _routerForKeeper;
        emit SetRouterForKeeper(_routerForKeeper);
    }
}
