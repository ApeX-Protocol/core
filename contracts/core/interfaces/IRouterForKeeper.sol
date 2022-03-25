// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

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

    function openPositionWithWallet(
        address baseToken,
        address quoteToken,
        address from,
        address holder,
        uint8 side,
        uint256 marginAmount,
        uint256 quoteAmount,
        uint256 baseAmountLimit,
        uint256 deadline
    ) external returns (uint256 baseAmount);

    function openPositionWithMargin(
        address baseToken,
        address quoteToken,
        address holder,
        uint8 side,
        uint256 quoteAmount,
        uint256 baseAmountLimit,
        uint256 deadline
    ) external returns (uint256 baseAmount);

    function closePosition(
        address baseToken,
        address quoteToken,
        address holder,
        address to,
        uint256 quoteAmount,
        uint256 deadline,
        bool autoWithdraw
    ) external returns (uint256 baseAmount, uint256 withdrawAmount);

    function getSpotPriceWithMultiplier(address baseToken, address quoteToken)
        external
        view
        returns (uint256 spotPriceWithMultiplier);
}
