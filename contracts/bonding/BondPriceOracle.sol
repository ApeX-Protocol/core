// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IBondPriceOracle.sol";
import "./interfaces/IBondPool.sol";
import "../core/interfaces/uniswapV3/IUniswapV3Factory.sol";
import "../core/interfaces/uniswapV3/IUniswapV3Pool.sol";
import "../libraries/FullMath.sol";
import "../libraries/UniswapV3TwapGetter.sol";
import "../libraries/FixedPoint96.sol";
import "../utils/Initializable.sol";

contract BondPriceOracle is IBondPriceOracle, Initializable {
    using FullMath for uint256;

    address public apeX;
    address public WETH;
    address public v3Factory;
    uint24[3] public v3Fees;

    uint16 public constant cardinality = 24;
    uint32 public constant twapInterval = 86400; // 24 hour
    
    // baseToken => v3Pool
    mapping(address => address) public v3Pools; // baseToken-WETH Pool in UniswapV3

    function initialize(address apeX_, address WETH_, address v3Factory_) public initializer {
        apeX = apeX_;
        WETH = WETH_;
        v3Factory = v3Factory_;
        v3Fees[0] = 500;
        v3Fees[1] = 3000;
        v3Fees[2] = 10000;
        setupTwap(apeX);
    }

    function setupTwap(address baseToken) public override {
        require(baseToken != address(0), "BondPriceOracle.setupTwap: ZERO_ADDRESS");
        if (baseToken == WETH) return;
        if (v3Pools[baseToken] != address(0)) return;
        // find out the pool with best liquidity as target pool
        address pool;
        address tempPool;
        uint256 poolLiquidity;
        uint256 tempLiquidity;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            tempPool = IUniswapV3Factory(v3Factory).getPool(baseToken, WETH, v3Fees[i]);
            if (tempPool == address(0)) continue;
            tempLiquidity = uint256(IUniswapV3Pool(tempPool).liquidity());
            // use the max liquidity pool as index price source
            if (tempLiquidity > poolLiquidity) {
                poolLiquidity = tempLiquidity;
                pool = tempPool;
            }
        }
        require(pool != address(0), "PriceOracle.setupTwap: POOL_NOT_FOUND");
        v3Pools[baseToken] = pool;

        IUniswapV3Pool v3Pool = IUniswapV3Pool(pool);
        (, , , , uint16 cardinalityNext, , ) = v3Pool.slot0();
        if (cardinalityNext < cardinality) {
            IUniswapV3Pool(pool).increaseObservationCardinalityNext(cardinality);
        }
    }

    function quote(
        address baseToken,
        uint256 baseAmount
    ) public view override returns (uint256 apeXAmount) {
        if (baseToken == WETH) {
            address pool = v3Pools[apeX];
            uint160 sqrtPriceX96 = UniswapV3TwapGetter.getSqrtTwapX96(pool, twapInterval);
            // priceX96 = token1/token0, this price is scaled by 2^96
            uint256 priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
            if (baseToken == IUniswapV3Pool(pool).token0()) {
                apeXAmount = baseAmount.mulDiv(priceX96, FixedPoint96.Q96);
            } else {
                apeXAmount = baseAmount.mulDiv(FixedPoint96.Q96, priceX96);
            }
        } else {
            address pool = v3Pools[baseToken];
            require(pool != address(0), "PriceOracle.quote: POOL_NOT_FOUND");
            uint160 sqrtPriceX96 = UniswapV3TwapGetter.getSqrtTwapX96(pool, twapInterval);
            // priceX96 = token1/token0, this price is scaled by 2^96
            uint256 priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
            uint256 wethAmount;
            if (baseToken == IUniswapV3Pool(pool).token0()) {
                wethAmount = baseAmount.mulDiv(priceX96, FixedPoint96.Q96);
            } else {
                wethAmount = baseAmount.mulDiv(FixedPoint96.Q96, priceX96);
            }

            pool = v3Pools[apeX];
            sqrtPriceX96 = UniswapV3TwapGetter.getSqrtTwapX96(pool, twapInterval);
            // priceX96 = token1/token0, this price is scaled by 2^96
            priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
            if (WETH == IUniswapV3Pool(pool).token0()) {
                apeXAmount = wethAmount.mulDiv(priceX96, FixedPoint96.Q96);
            } else {
                apeXAmount = wethAmount.mulDiv(FixedPoint96.Q96, priceX96);
            }
        }
    }
}
