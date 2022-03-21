// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IOrderBook {
    struct OpenPositionOrder {
        address baseToken;
        address quoteToken;
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 baseAmountLimit;
        uint256 deadline;
        uint256 executionFee;
        uint8 isLong;
        bool filled;
    }

    event SetRouterForKeeper(address newRouterForKeeper);

    event ExecuteOpenPositionOrder(address trader, address feeReceiver, uint256 index);

    event ExecuteClosePositionOrder(address trader, address feeReceiver, uint256 index);

    function setRouterForKeeper(address routerForKeeper) external;

    function executeOpenPositionOrder(
        address _trader,
        address payable _feeReceiver,
        uint256 _orderIndex,
        bytes calldata data
    ) external;
}
