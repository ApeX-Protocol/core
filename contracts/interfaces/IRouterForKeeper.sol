// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
import "./IOrderBook.sol";

interface IRouterForKeeper {
    event CollectFee(address indexed trader, address indexed margin, uint256 fee);

    function pairFactory() external view returns (address);

    function WETH() external view returns (address);

    function openPositionWithWallet(IOrderBook.OpenPositionOrder memory order)
        external
        returns (uint256 baseAmount);

    function openPositionWithMargin(IOrderBook.OpenPositionOrder memory order)
        external
        returns (uint256 baseAmount);

    function closePosition(IOrderBook.ClosePositionOrder memory order)
        external
        returns (uint256 baseAmount, uint256 withdrawAmount);

    function getSpotPriceWithMultiplier(address baseToken, address quoteToken)
        external
        view
        returns (
            uint256 spotPriceWithMultiplier,
            uint256 baseDecimal,
            uint256 quoteDecimal
        );

    function setOrderBook(address newOrderBook) external;
}
