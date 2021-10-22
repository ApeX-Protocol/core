// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IRouter {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function addLiquidity(
        address baseToken,
        address quoteToken,
        uint256 baseAmount,
        uint256 quoteAmountMin,
        uint256 deadline,
        bool autoStake
    ) external returns (uint256 quoteAmount, uint256 liquidity);

    function removeLiquidity(
        address baseToken,
        address quoteToken,
        uint256 liquidity,
        uint256 baseAmountMin,
        uint256 deadline
    ) external returns (uint256 baseAmount, uint256 quoteAmount);

    function deposit(
        address baseToken,
        address quoteToken,
        address holder,
        uint256 amount
    ) external;

    function withdraw(
        address baseToken,
        address quoteToken,
        uint256 amount
    ) external;

    function openPositionWithWallet(
        address baseToken,
        address quoteToken,
        uint8 side,
        uint256 marginAmount,
        uint256 baseAmount,
        uint256 quoteAmountLimit,
        uint256 deadline
    ) external returns (uint256 quoteAmount);

    function openPositionWithMargin(
        address baseToken,
        address quoteToken,
        uint8 side,
        uint256 baseAmount,
        uint256 quoteAmountLimit,
        uint256 deadline
    ) external returns (uint256 quoteAmount);

    function closePosition(
        address baseToken,
        address quoteToken,
        uint256 quoteAmount,
        uint256 deadline,
        bool autoWithdraw
    ) external returns (uint256 baseAmount, uint256 withdrawAmount);

    function getReserves(address baseToken, address quoteToken)
        external
        view
        returns (uint256 reserveBase, uint256 reserveQuote);

    function getQuoteAmount(
        address baseToken,
        address quoteToken,
        uint8 side,
        uint256 baseAmount
    ) external view returns (uint256 quoteAmount);

    function getWithdrawable(
        address baseToken,
        address quoteToken,
        address holder
    ) external view returns (uint256 amount);

    function getPosition(
        address baseToken,
        address quoteToken,
        address holder
    )
        external
        view
        returns (
            int256 baseSize,
            int256 quoteSize,
            uint256 tradeSize
        );
}
