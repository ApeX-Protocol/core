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
import "../libraries/Math.sol";
import "../libraries/TickMath.sol";
import "../libraries/UniswapV3TwapGetter.sol";
import "../libraries/FixedPoint96.sol";
import "../libraries/Oracle.sol";

contract PriceOracle is IPriceOracle {
    using Math for uint256;
    using FullMath for uint256;
    using Oracle for Oracle.Observation[65535];

    address public immutable config;
    address public immutable v3Factory;
    address public immutable v2Factory;
    address public immutable WETH;
    uint24[3] public v3Fees;

    uint16 cardinality = 120;
    mapping(address => address) v3Pools;
    mapping(address => uint16) ammObservationIndex;
    mapping(address => Oracle.Observation[65535]) ammObservations;
    
    constructor(address config_, address v3Factory_, address v2Factory_, address WETH_) {
        config = config_;
        v3Factory = v3Factory_;
        v2Factory = v2Factory_;
        WETH = WETH_;
        v3Fees[0] = 500;
        v3Fees[1] = 3000;
        v3Fees[2] = 10000;
    }

    function setupTwap(address amm) external override {
        require(v3Pools[amm] == address(0), "PriceOracle.setupTwap: ALREADY_SETUP");
        address baseToken = IAmm(amm).baseToken();
        address quoteToken = IAmm(amm).quoteToken();

        // find out the pool with best liquidity as target pool
        address pool;
        address tempPool;
        uint256 poolLiquidity;
        uint256 tempLiquidity;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            tempPool = IUniswapV3Factory(v3Factory).getPool(baseToken, quoteToken, v3Fees[i]);
            if (tempPool == address(0)) continue;
            tempLiquidity = uint256(IUniswapV3Pool(tempPool).liquidity());
            // use the max liquidity pool as index price source
            if (tempLiquidity > poolLiquidity) {
                poolLiquidity = tempLiquidity;
                pool = tempPool;
            }
        }
        require(pool != address(0), "PriceOracle.setupTwap: POOL_NOT_FOUND");
        v3Pools[amm] = pool;

        IUniswapV3Pool v3Pool = IUniswapV3Pool(pool);
        (, , , , uint16 cardinalityNext, , ) = v3Pool.slot0();
        if (cardinalityNext < cardinality) {
            IUniswapV3Pool(pool).increaseObservationCardinalityNext(cardinality);
        }

        ammObservationIndex[amm] = 0;
        ammObservations[amm][0] = Oracle.Observation({
            blockTimestamp: _blockTimestamp(),
            tickCumulative: 0,
            initialized: true
        });
        for (uint16 i = 1; i < cardinality; i++) ammObservations[amm][i].blockTimestamp = 1;
    }

    function updateAmmTwap(address amm) external override {
        uint160 sqrtPriceX96 = uint160(getMarkPrice(amm).sqrt() * 2**96 / 1e9);
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        uint16 index = ammObservationIndex[amm];
        Oracle.Observation memory last = ammObservations[amm][index];
        if (last.blockTimestamp < _blockTimestamp()) {
            uint16 indexUpdated = (index + 1) % cardinality;
            uint32 delta = _blockTimestamp() - last.blockTimestamp;
            ammObservations[amm][indexUpdated] = Oracle.Observation({
                blockTimestamp: _blockTimestamp(),
                tickCumulative: last.tickCumulative + int56(tick) * int32(delta),
                initialized: true
            });
            ammObservationIndex[amm] = indexUpdated;
        }
    }

    function getAmmTwap(address amm) external view override returns (uint256) {
        uint32[] memory secondsAgos = new uint32[](2);
        uint16 twapInterval = IConfig(config).twapInterval();
        secondsAgos[0] = twapInterval; // from (before)
        secondsAgos[1] = 0; // to (now)

        uint160 sqrtPriceX96 = uint160(getMarkPrice(amm).sqrt() * 2**96 / 1e9);
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        int56[] memory tickCumulatives = ammObservations[amm].observe(
            _blockTimestamp(),
            secondsAgos,
            tick,
            ammObservationIndex[amm],
            cardinality
        );
        // tick(imprecise as it's an integer) to price
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(twapInterval)))
        );
        return uint256(sqrtPriceX96) * sqrtPriceX96 * 1e18 >> (96 * 2);
    }

    function quoteFromV3(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view returns (uint256 quoteAmount, uint256 poolLiquidity) {
        address pool;
        uint160 sqrtPriceX96;
        address tempPool;
        uint256 tempLiquidity;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            tempPool = IUniswapV3Factory(v3Factory).getPool(baseToken, quoteToken, v3Fees[i]);
            if (tempPool == address(0)) continue;
            tempLiquidity = uint256(IUniswapV3Pool(tempPool).liquidity());
            // use the max liquidity pool as index price source
            if (tempLiquidity > poolLiquidity) {
                poolLiquidity = tempLiquidity;
                pool = tempPool;
                // get sqrt twap in 30*60 seconds
                sqrtPriceX96 = UniswapV3TwapGetter.getSqrtTwapX96(pool, 30*60);
            }
        }
        if (pool == address(0)) return (0, 0);
        // priceX96 = token1/token0, this price is scaled by 2^96
        uint256 priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        if (baseToken == IUniswapV3Pool(pool).token0()) {
            quoteAmount = baseAmount.mulDiv(priceX96, FixedPoint96.Q96);
        } else {
            quoteAmount = baseAmount.mulDiv(FixedPoint96.Q96, priceX96);
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
            quoteAmount = baseAmount.mulDiv(reserve1, reserve0);
        } else {
            quoteAmount = baseAmount.mulDiv(reserve0, reserve1);
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
        price = exponent.mulDiv(quoteReserve, baseReserve);
    }

    // get user's mark price, return base amount, it's for checking if user's position can be liquidated.
    // price = ( sqrt(y/x) +/- beta * quoteAmount / sqrt(x*y) )**2 = (y +/- beta * quoteAmount)**2 / x*y
    // baseAmount = quoteAmount / price = quoteAmount * x * y / (y +/- beta * quoteAmount)**2
    function getMarkPriceAcc(
        address amm,
        uint8 beta,
        uint256 quoteAmount,
        bool negative
    ) external view override returns (uint256 baseAmount) {
        (uint112 baseReserve, uint112 quoteReserve, ) = IAmm(amm).getReserves();
        uint256 rvalue = quoteAmount * beta / 100;
        uint256 denominator;
        if (negative) {
            denominator = quoteReserve - rvalue;
        } else {
            denominator = quoteReserve + rvalue;
        }
        denominator = denominator * denominator;
        baseAmount = quoteAmount.mulDiv(uint256(baseReserve) * quoteReserve, denominator);
    }

    //premiumFraction is (markPrice - indexPrice) / 8h / indexPrice, scale by 1e18
    function getPremiumFraction(address amm) external view override returns (int256) {
        int256 markPrice = int256(getMarkPrice(amm));
        int256 indexPrice = int256(getIndexPrice(amm));
        require(markPrice > 0 && indexPrice > 0, "PriceOracle.getPremiumFraction: INVALID_PRICE");
        return ((markPrice - indexPrice) * 1e18) / (8 * 3600) / indexPrice;
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }
}
