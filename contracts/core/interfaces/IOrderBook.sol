// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IOrderBook {
    struct OpenPositionOrder {
        address routerToExecute;
        address trader;
        address baseToken;
        address quoteToken;
        uint8 side;
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 baseAmountLimit;
        uint256 limitPrice;
        uint256 deadline;
        bool withWallet;
        bytes nonce;
    }

    struct ClosePositionOrder {
        address routerToExecute;
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

    event ExecuteOpen(address trader, address feeReceiver, uint256 index);

    event ExecuteClose(address trader, address feeReceiver, uint256 index);

    function setRouterForKeeper(address routerForKeeper) external;
}
