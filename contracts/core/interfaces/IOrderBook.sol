// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IOrderBook {
    struct OpenPositionOrder {
        address trader;
        address baseToken;
        address quoteToken;
        uint8 side;
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 baseAmountLimit;
        uint256 limitPrice;
        uint256 deadline;
        bytes nonce;
    }

    struct ClosePositionOrder {
        address trader;
        address baseToken;
        address quoteToken;
        uint8 side;
        uint256 quoteAmount;
        uint256 limitPrice;
        uint256 deadline;
        bool autoWithdraw;
        bytes nonce;
    }

    event SetRouterForKeeper(address newRouterForKeeper);

    event ExecuteOpenPositionOrder(address trader, address feeReceiver, uint256 index);

    event ExecuteClosePositionOrder(address trader, address feeReceiver, uint256 index);

    function setRouterForKeeper(address routerForKeeper) external;

    // function executeOpenPositionOrder(
    //     address _trader,
    //     address payable _feeReceiver,
    //     uint256 _orderIndex,
    //     bytes calldata data
    // ) external;
}
