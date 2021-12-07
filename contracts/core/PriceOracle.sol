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
    ) public view returns (uint256 quoteAmount) {
        uint128 maxLiquidity;
        uint160 sqrtPriceX96;
        address pool;
        uint128 liquidity;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            pool = IUniswapV3Factory(v3Factory).getPool(baseToken, quoteToken, v3Fees[i]);
            if (pool == address(0)) continue;
            liquidity = IUniswapV3Pool(pool).liquidity();
            // use the max liquidity pool as oracle price source
            if (liquidity > maxLiquidity) {
                maxLiquidity = liquidity;
                sqrtPriceX96 = UniswapV3TwapGetter.getSqrtTwapX96(pool, 60);
            }
        }
        if (sqrtPriceX96 == 0) return 0;
        // priceX96 = token1/token0, this price is scaled by 2^96
        uint256 priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        if (baseToken == IUniswapV3Pool(pool).token0()) {
            quoteAmount = FullMath.mulDiv(baseAmount, priceX96, FixedPoint96.Q96);
        } else {
            quoteAmount = FullMath.mulDiv(baseAmount, FixedPoint96.Q96, priceX96);
        }
    }

    function quoteFromV2(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view returns (uint256 quoteAmount) {
        address pair = IUniswapV2Factory(v2Factory).getPair(baseToken, quoteToken);
        if (pair == address(0)) return 0;
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
        uint256 wethAmount = quoteFromV3(baseToken, WETH, baseAmount);
        if (wethAmount == 0) {
            wethAmount = quoteFromV2(baseToken, WETH, baseAmount);
        }
        quoteAmount = quoteFromV3(WETH, quoteToken, wethAmount);
        if (quoteAmount == 0) {
            quoteAmount = quoteFromV2(WETH, quoteToken, wethAmount);
        }
    }

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view override returns (uint256 quoteAmount) {
        quoteAmount = quoteFromV3(baseToken, quoteToken, baseAmount);
        if (quoteAmount == 0) {
            quoteAmount = quoteFromV2(baseToken, quoteToken, baseAmount);
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
        uint8 baseDecimals = IERC20(IAmm(amm).baseToken()).decimals();
        uint8 quoteDecimals = IERC20(IAmm(amm).quoteToken()).decimals();
        uint256 exponent = uint256(10**(18 + baseDecimals - quoteDecimals));
        uint256 lastPriceX112 = IAmm(amm).lastPrice();
        price = FullMath.mulDiv(exponent, lastPriceX112, 2**112);
    }

    // get user's mark price, it's for checking if user's position can be liquidated.
    // markPriceAcc = markPrice * (1 +/- (2 * beta * quoteAmount)/quoteReserve)
    // the result price is scaled by 1e18.
    function getMarkPriceAcc(
        address amm,
        uint8 beta,
        uint256 quoteAmount,
        bool negative
    ) public view override returns (uint256 price) {
        (, uint112 quoteReserve, ) = IAmm(amm).getReserves();
        uint256 markPrice = getMarkPrice(amm);
        uint256 delta = FullMath.mulDiv(markPrice, (2 * quoteAmount * beta) / 100, quoteReserve);
        if (negative) {
            price = markPrice - delta;
        } else {
            price = markPrice + delta;
        }
    }

    //premiumFraction is (markPrice - indexPrice) / 8h / indexPrice, scale by 1e18
    function getPremiumFraction(address amm) external view override returns (int256) {
        int256 markPrice = int256(getMarkPrice(amm));
        int256 indexPrice = int256(getIndexPrice(amm));
        require(markPrice > 0 && indexPrice > 0, "PriceOracle.getPremiumFraction: INVALID_PRICE");
        return ((markPrice - indexPrice) * 1e18) / (8 * 3600) / indexPrice;
    }
}
