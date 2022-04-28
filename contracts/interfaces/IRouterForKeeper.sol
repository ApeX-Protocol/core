// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
import "./IOrderBook.sol";

interface IRouterForKeeper {
    event Deposit(address, address, address, uint256);
    event DepositETH(address, address, uint256);
    event Withdraw(address, address, address, uint256);
    event WithdrawETH(address, address, uint256);

    function pairFactory() external view returns (address);

    function WETH() external view returns (address);

    function deposit(
        address baseToken,
        address to,
        uint256 amount
    ) external;

    function depositETH(address to) external payable;

    function withdraw(
        address baseToken,
        address to,
        uint256 amount
    ) external;

    function withdrawETH(address to, uint256 amount) external;

    function openPositionWithWallet(IOrderBook.OpenPositionOrder memory order, uint256 deadline)
        external
        returns (uint256 baseAmount);

    function openPositionWithMargin(IOrderBook.OpenPositionOrder memory order, uint256 deadline)
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
}
