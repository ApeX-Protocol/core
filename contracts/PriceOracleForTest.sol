//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./interfaces/IPriceOracle.sol";

contract PriceOracleForTest is IPriceOracle {
    struct Reserves {
        uint256 base;
        uint256 quote;
    }
    mapping(address => mapping(address => Reserves)) public getReserves;

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) external view override returns (uint256 quoteAmount) {
        Reserves memory reserves = getReserves[baseToken][quoteToken];
        require(baseAmount > 0, "INSUFFICIENT_AMOUNT");
        require(reserves.base > 0 && reserves.quote > 0, "INSUFFICIENT_LIQUIDITY");
        quoteAmount = (baseAmount * reserves.quote) / reserves.base;
    }

    function setReserve(
        address baseToken,
        address quoteToken,
        uint256 reserveBase,
        uint256 reserveQuote
    ) external {
        getReserves[baseToken][quoteToken] = Reserves(reserveBase, reserveQuote);
    }

     function estimateSwapWithMarkPrice(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view override returns (uint256[2] memory amounts) {
        // (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        // uint256 quoteAmount;
        // uint256 baseAmount;
        // if (inputAmount != 0) {
        //     quoteAmount = inputAmount;
        // } else {
        //     quoteAmount = outputAmount;
        // }
        // uint256 inputSquare = quoteAmount * quoteAmount;
        // // price = (sqrt(y/x)+ betal * deltaY/L).**2;
        // // deltaX = deltaY/price
        // // deltaX = (deltaY * L)/(y + betal * deltaY)**2
        // uint256 L = uint256(_baseReserve) * uint256(_quoteReserve);
        // uint8 beta = IConfig(IPairFactory(factory).config()).beta();
        // require(beta >= 50 && beta <= 100, "beta error");
        // //112
        // uint256 denominator = (_quoteReserve + (beta * quoteAmount) / 100);
        // //224
        // denominator = denominator * denominator;
        // baseAmount = FullMath.mulDiv(quoteAmount, L, denominator);
        // return inputAmount == 0 ? [baseAmount, quoteAmount] : [quoteAmount, baseAmount];
    }
}
