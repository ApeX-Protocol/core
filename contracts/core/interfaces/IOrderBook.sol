// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IOrderBook {
    struct RespData {
        bool success;
        bytes result;
    }

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

    event BatchExecuteOpen(OpenPositionOrder[] orders, bytes[] signatures, bool requireSuccess);

    event BatchExecuteClose(ClosePositionOrder[] orders, bytes[] signatures, bool requireSuccess);

    event SetRouterForKeeper(address newRouterForKeeper);

    event ExecuteOpen(OpenPositionOrder order, bytes signature);

    event ExecuteClose(ClosePositionOrder order, bytes signature);

    function batchExecuteOpen(
        OpenPositionOrder[] memory orders,
        bytes[] memory signatures,
        bool requireSuccess
    ) external returns (RespData[] memory respData);

    function batchExecuteClose(
        ClosePositionOrder[] memory orders,
        bytes[] memory signatures,
        bool requireSuccess
    ) external returns (RespData[] memory respData);

    function executeOpen(OpenPositionOrder memory order, bytes memory signature) external;

    function executeClose(ClosePositionOrder memory order, bytes memory signature) external;

    function verifyOpen(OpenPositionOrder memory order, bytes memory signature) external view returns (bool);

    function verifyClose(ClosePositionOrder memory order, bytes memory signature) external view returns (bool);

    function setRouterForKeeper(address routerForKeeper) external;
}
