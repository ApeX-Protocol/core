pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IUniswapV3Factory.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./libraries/FullMath.sol";

contract PriceOracle is IPriceOracle {
    address public immutable uniswapV3Factory;
    uint24[3] public fees;

    constructor(address uniswapV3Factory_) {
        uniswapV3Factory = uniswapV3Factory_;
        fees[0] = 500;
        fees[1] = 3000;
        fees[2] = 10000;
    }

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view override returns (uint256 quoteAmount) {
        uint128 maxLiquidity;
        uint160 sqrtPriceX96;
        address pool;
        uint128 liquidity;
        for (uint256 i = 0; i < fees.length; i++) {
            pool = IUniswapV3Factory(uniswapV3Factory).getPool(baseToken, quoteToken, fees[i]);
            if (pool == address(0)) continue;
            liquidity = IUniswapV3Pool(pool).liquidity();
            if (liquidity > maxLiquidity) {
                maxLiquidity = liquidity;
                (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
            }
        }
        require(sqrtPriceX96 > 0, "PriceOracle.quote: NO_PRICE");
        uint256 price = uint256(sqrtPriceX96) * sqrtPriceX96; // price = token1/token0
        if (baseToken == IUniswapV3Pool(pool).token0()) {
            quoteAmount = baseAmount * price;
        } else {
            quoteAmount = baseAmount / price;
        }
    }

    function getIndexPrice(address amm) public view override returns (uint256) {
        address baseToken = IAmm(amm).baseToken();
        address quoteToken = IAmm(amm).quoteToken();
        uint256 baseDecimals = IERC20(baseToken).decimals();
        uint256 quoteDecimals = IERC20(quoteToken).decimals();
        uint256 quoteAmount = quote(baseToken, quoteToken, 10**baseDecimals);
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
    ) public view override returns (uint256 price) {
        (, uint256 quoteReserve, ) = IAmm(amm).getReserves();
        uint256 markPrice = getMarkPrice(amm);
        uint256 rvalue = FullMath.mulDiv(markPrice, (2 * quoteAmount * beta) / 100, quoteReserve);
        if (negative) {
            price = markPrice - rvalue;
        } else {
            price = markPrice + rvalue;
        }
    }

    //premiumFraction is (markPrice - indexPrice) / 8h / indexPrice
    function getPremiumFraction(address amm) public view override returns (int256) {
        int256 markPrice = int256(getMarkPrice(amm));
        int256 indexPrice = int256(getIndexPrice(amm));
        return ((markPrice - indexPrice) * 1e18) / (8 * 3600) / indexPrice;
    }
}
