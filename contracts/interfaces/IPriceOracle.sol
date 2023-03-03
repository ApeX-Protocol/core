// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IPriceOracle {
    function setupTwap(address amm) external;

    function quoteFromAmmTwap(address amm, uint256 baseAmount) external view returns (uint256 quoteAmount);

    function updateAmmTwap(address pair) external;

    // index price maybe get from different oracle, like UniswapV3 TWAP,Chainklink, or others
    // source represents which oracle used. 0 = UniswapV3 TWAP
    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) external view returns (uint256 quoteAmount, uint8 source);

    function getIndexPrice(address amm) external view returns (uint256);

    function getMarketPrice(address amm) external view returns (uint256);

    function getMarkPrice(address amm) external view returns (uint256 price, bool isIndexPrice);

    function getMarkPriceAfterSwap(
        address amm,
        uint256 quoteAmount,
        uint256 baseAmount
    ) external view returns (uint256 price, bool isIndexPrice);

    function getMarkPriceInRatio(
        address amm,
        uint256 quoteAmount,
        uint256 baseAmount
    )
        external
        view
        returns (
            uint256 resultBaseAmount,
            uint256 resultQuoteAmount,
            bool isIndexPrice
        );

    function getMarkPriceAcc(
        address amm,
        uint8 beta,
        uint256 quoteAmount,
        bool negative
    ) external view returns (uint256 baseAmount);

    function getPremiumFraction(address amm) external view returns (int256);
}
