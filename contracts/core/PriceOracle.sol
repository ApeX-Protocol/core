// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/uniswapV3/IUniswapV3Factory.sol";
import "./interfaces/uniswapV3/IUniswapV3Pool.sol";
import "./interfaces/uniswapV2/IUniswapV2Factory.sol";
import "./interfaces/uniswapV2/IUniswapV2Pair.sol";
import "../libraries/FullMath.sol";
import "../libraries/UniswapV3TwapGetter.sol";
import "../libraries/FixedPoint96.sol";

contract PriceOracle is IPriceOracle {
    address public immutable v3Factory;
    address public immutable v2Factory;
    address public immutable WETH;
    uint24[3] public v3Fees;

    constructor(address v3Factory_, address v2Factory_, address WETH_) {
        v3Factory = v3Factory_;
        v2Factory = v2Factory_;
        WETH = WETH_;
        v3Fees[0] = 500;
        v3Fees[1] = 3000;
        v3Fees[2] = 10000;
    }

    function quoteFromV3(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view returns (uint256 quoteAmount, uint256 poolLiquidity) {
        address pool;
        uint160 sqrtPriceX96;
        address tempPool;
        uint128 tempLiquidity;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            tempPool = IUniswapV3Factory(v3Factory).getPool(baseToken, quoteToken, v3Fees[i]);
            if (tempPool == address(0)) continue;
            tempLiquidity = IUniswapV3Pool(tempPool).liquidity();
            // use the max liquidity pool as index price source
            if (tempLiquidity > poolLiquidity) {
                poolLiquidity = tempLiquidity;
                pool = tempPool;
                // get sqrt twap in 60 seconds
                sqrtPriceX96 = UniswapV3TwapGetter.getSqrtTwapX96(pool, 60);
            }
        }
        if (pool == address(0)) return (0, 0);
        // priceX96 = token1/token0, this price is scaled by 2^96
        uint256 priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        if (baseToken == IUniswapV3Pool(pool).token0()) {
            quoteAmount = FullMath.mulDiv(baseAmount, priceX96, FixedPoint96.Q96);
        } else {
            quoteAmount = FullMath.mulDiv(baseAmount, FixedPoint96.Q96, priceX96);
        }
    }

    // this mainly for ApeX Bonding to get APEX-XXX price
    function quoteFromV2(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view returns (uint256 quoteAmount, uint256 poolLiquidity) {
        if (v2Factory == address(0)) {
            return (0, 0);
        }
        address pair = IUniswapV2Factory(v2Factory).getPair(baseToken, quoteToken);
        if (pair == address(0)) return (0, 0);
        poolLiquidity = IUniswapV2Pair(pair).totalSupply();
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        if (baseToken == IUniswapV2Pair(pair).token0()) {
            quoteAmount = FullMath.mulDiv(baseAmount, reserve1, reserve0);
        } else {
            quoteAmount = FullMath.mulDiv(baseAmount, reserve0, reserve1);
        }
    }

    function quoteFromHybrid(
        address baseToken, 
        address quoteToken,
        uint256 baseAmount
    ) public view returns (uint256 quoteAmount) {
        uint256 wethAmount;
        uint256 wethAmountV3;
        uint256 wethAmountV2;
        uint256 liquidityV3;
        uint256 liquidityV2;
        (wethAmountV3, liquidityV3) = quoteFromV3(baseToken, WETH, baseAmount);
        (wethAmountV2, liquidityV2) = quoteFromV2(baseToken, WETH, baseAmount);
        if (liquidityV3 >= liquidityV2) {
            wethAmount = wethAmountV3;
        } else {
            wethAmount = wethAmountV2;
        }
        uint256 quoteAmountV3;
        uint256 quoteAmountV2;
        (quoteAmountV3, liquidityV3) = quoteFromV3(WETH, quoteToken, wethAmount);
        (quoteAmountV2, liquidityV2) = quoteFromV2(WETH, quoteToken, wethAmount);
        if (liquidityV3 >= liquidityV2) {
            quoteAmount = quoteAmountV3;
        } else {
            quoteAmount = quoteAmountV2;
        }
    }

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view override returns (uint256 quoteAmount) {
        (uint256 quoteAmountV3, uint256 liquidityV3) = quoteFromV3(baseToken, quoteToken, baseAmount);
        (uint256 quoteAmountV2, uint256 liquidityV2) = quoteFromV2(baseToken, quoteToken, baseAmount);
        if (liquidityV3 >= liquidityV2) {
            quoteAmount = quoteAmountV3;
        } else {
            quoteAmount = quoteAmountV2;
        }
        if (quoteAmount == 0) {
            quoteAmount = quoteFromHybrid(baseToken, quoteToken, baseAmount);
        }
    }

    // the result price is scaled by 1e18
    function getIndexPrice(address amm) public view override returns (uint256) {
        address baseToken = IAmm(amm).baseToken();
        address quoteToken = IAmm(amm).quoteToken();
        uint256 baseDecimals = IERC20(baseToken).decimals();
        uint256 quoteDecimals = IERC20(quoteToken).decimals();
        uint256 quoteAmount = quote(baseToken, quoteToken, 10**baseDecimals);
        return quoteAmount * (10**(18 - quoteDecimals));
    }

    //@notice the price is transformed. example: 1eth = 2000usdt, price = 2000*1e18
    function getMarkPrice(address amm) public view override returns (uint256 price) {
        (uint112 baseReserve, uint112 quoteReserve, ) = IAmm(amm).getReserves();
        uint8 baseDecimals = IERC20(IAmm(amm).baseToken()).decimals();
        uint8 quoteDecimals = IERC20(IAmm(amm).quoteToken()).decimals();
        uint256 exponent = uint256(10**(18 + baseDecimals - quoteDecimals));
        price = FullMath.mulDiv(exponent, quoteReserve, baseReserve);
    }

    // get user's mark price, return base amount, it's for checking if user's position can be liquidated.
    // price = ( sqrt(y/x) +/- beta * quoteAmount / sqrt(x*y) )**2 = (y +/- beta * quoteAmount)**2 / x*y
    // baseAmount = quoteAmount / price = quoteAmount * x * y / (y +/- beta * quoteAmount)**2
    function getMarkPriceAcc(
        address amm,
        uint8 beta,
        uint256 quoteAmount,
        bool negative
    ) public view override returns (uint256 baseAmount) {
        (uint112 baseReserve, uint112 quoteReserve, ) = IAmm(amm).getReserves();
        uint256 rvalue = quoteAmount * beta / 100;
        uint256 denominator;
        if (negative) {
            denominator = quoteReserve - rvalue;
        } else {
            denominator = quoteReserve + rvalue;
        }
        denominator = denominator * denominator;
        baseAmount = FullMath.mulDiv(quoteAmount, uint256(baseReserve) * quoteReserve, denominator);
    }

    //premiumFraction is (markPrice - indexPrice) / 8h / indexPrice, scale by 1e18
    function getPremiumFraction(address amm) external view override returns (int256) {
        int256 markPrice = int256(getMarkPrice(amm));
        int256 indexPrice = int256(getIndexPrice(amm));
        require(markPrice > 0 && indexPrice > 0, "PriceOracle.getPremiumFraction: INVALID_PRICE");
        return ((markPrice - indexPrice) * 1e18) / (8 * 3600) / indexPrice;
    }
}
