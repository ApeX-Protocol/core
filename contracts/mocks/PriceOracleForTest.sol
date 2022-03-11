//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../core/interfaces/IERC20.sol";
import "../core/interfaces/IAmm.sol";
import "../core/interfaces/IConfig.sol";
import "../core/interfaces/IPriceOracle.sol";
import "../libraries/FullMath.sol";

contract PriceOracleForTest is IPriceOracle {
    using FullMath for uint256;
    struct Reserves {
        uint256 base;
        uint256 quote;
    }
    mapping(address => mapping(address => Reserves)) public getReserves;

    function setReserve(
        address baseToken,
        address quoteToken,
        uint256 reserveBase,
        uint256 reserveQuote
    ) external {
        getReserves[baseToken][quoteToken] = Reserves(reserveBase, reserveQuote);
    }

    function setupTwap(address amm) external override {
        return;
    }

    function updateAmmTwap(address pair) external override {}

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view override returns (uint256 quoteAmount, uint8 source) {
        Reserves memory reserves = getReserves[baseToken][quoteToken];
        require(baseAmount > 0, "INSUFFICIENT_AMOUNT");
        require(reserves.base > 0 && reserves.quote > 0, "INSUFFICIENT_LIQUIDITY");
        quoteAmount = (baseAmount * reserves.quote) / reserves.base;
    }

    function quoteFromAmmTwap(address amm, uint256 baseAmount) public view override returns (uint256 quoteAmount) {
        quoteAmount = 0;
    }

    function getIndexPrice(address amm) public view override returns (uint256) {
        address baseToken = IAmm(amm).baseToken();
        address quoteToken = IAmm(amm).quoteToken();
        uint256 baseDecimals = IERC20(baseToken).decimals();
        uint256 quoteDecimals = IERC20(quoteToken).decimals();
        (uint256 quoteAmount, ) = quote(baseToken, quoteToken, 10**baseDecimals);
        return quoteAmount * (10**(18 - quoteDecimals));
    }

    function getMarkPrice(address amm) public view override returns (uint256 price) {
        (uint256 baseReserve, uint256 quoteReserve, ) = IAmm(amm).getReserves();
        uint8 baseDecimals = IERC20(IAmm(amm).baseToken()).decimals();
        uint8 quoteDecimals = IERC20(IAmm(amm).quoteToken()).decimals();
        uint256 exponent = uint256(10**(18 + baseDecimals - quoteDecimals));
        price = FullMath.mulDiv(exponent, quoteReserve, baseReserve);
    }

    function getMarkPriceAcc(
        address amm,
        uint8 beta,
        uint256 quoteAmount,
        bool negative
    ) external view override returns (uint256 baseAmount) {
        (uint112 baseReserve, uint112 quoteReserve, ) = IAmm(amm).getReserves();
        uint256 rvalue = (quoteAmount * beta) / 100;
        uint256 denominator;
        if (negative) {
            denominator = quoteReserve - rvalue;
        } else {
            denominator = quoteReserve + rvalue;
        }
        denominator = denominator * denominator;
        baseAmount = quoteAmount.mulDiv(uint256(baseReserve) * quoteReserve, denominator);
    }

    //premiumFraction is (markPrice - indexPrice) / 24h / indexPrice
    function getPremiumFraction(address amm) public view override returns (int256) {
        int256 markPrice = int256(getMarkPrice(amm));
        int256 indexPrice = int256(getIndexPrice(amm));
        require(markPrice > 0 && indexPrice > 0, "PriceOracle.getPremiumFraction: INVALID_PRICE");
        return ((markPrice - indexPrice) * 1e18) / (24 * 3600) / indexPrice;
    }
}
