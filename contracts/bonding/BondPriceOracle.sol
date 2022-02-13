// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IBondPriceOracle.sol";
import "./interfaces/IBondPool.sol";
import "../core/interfaces/IAmm.sol";
import "../core/interfaces/uniswapV3/IUniswapV3Factory.sol";
import "../core/interfaces/uniswapV3/IUniswapV3Pool.sol";
import "../core/interfaces/uniswapV2/IUniswapV2Factory.sol";
import "../libraries/FullMath.sol";
import "../libraries/TickMath.sol";
import "../libraries/UniswapV3TwapGetter.sol";
import "../libraries/FixedPoint96.sol";
import "../libraries/V3Oracle.sol";
import "../libraries/V2Oracle.sol";
import "../utils/Initializable.sol";

contract BondPriceOracle is IBondPriceOracle, Initializable {
    using FullMath for uint256;
    using V3Oracle for V3Oracle.Observation[65535];
    using V2Oracle for V2Oracle.Observation[];

    address public apeX;
    address public WETH;
    address public v2Pair; // apeX-WETH pair in UniswapV2/SushiSwap
    address public v3Factory;
    address public v2Factory;
    uint24[3] public v3Fees;

    uint16 public constant cardinality = 12;
    uint32 public constant twapInterval = 3600; // 1 hour
    uint256 public constant periodSize = 300; // 5 min
    
    V2Oracle.Observation[] public v2Observations;
    // baseToken => v3Pool
    mapping(address => address) public v3Pools; // baseToken-WETH Pool in UniswapV3

    function initialize(address apeX_, address WETH_, address v3Factory_, address v2Factory_) public initializer {
        apeX = apeX_;
        WETH = WETH_;
        v3Factory = v3Factory_;
        v2Factory = v2Factory_;
        v3Fees[0] = 500;
        v3Fees[1] = 3000;
        v3Fees[2] = 10000;
        v2Pair = IUniswapV2Factory(v2Factory).getPair(apeX, WETH);
        v2Observations.update(v2Pair, periodSize, cardinality);
    }

    function setupTwap(address bondPool) external override {
        address baseToken = IAmm(IBondPool(bondPool).amm()).baseToken();
        require(baseToken != address(0) && baseToken != apeX, "BondPriceOracle.setupTwap: FORBIDDEN");
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

    function updateV2() external override {
        v2Observations.update(v2Pair, periodSize, cardinality);
    }

    function quoteFromV3(
        address baseToken,
        uint256 baseAmount
    ) public view returns (uint256 quoteAmount) {
        address pool = v3Pools[baseToken];
        if (pool == address(0)) return 0;
        uint160 sqrtPriceX96 = UniswapV3TwapGetter.getSqrtTwapX96(pool, twapInterval);
        // priceX96 = token1/token0, this price is scaled by 2^96
        uint256 priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        if (baseToken == IUniswapV3Pool(pool).token0()) {
            quoteAmount = baseAmount.mulDiv(priceX96, FixedPoint96.Q96);
        } else {
            quoteAmount = baseAmount.mulDiv(FixedPoint96.Q96, priceX96);
        }
    }

    function quote(
        address baseToken,
        uint256 baseAmount
    ) public view override returns (uint256 apeXAmount) {
        if (baseToken == WETH) {
            apeXAmount = v2Observations.consult(
                v2Pair, 
                baseToken, 
                apeX, 
                baseAmount, 
                twapInterval, 
                periodSize, 
                cardinality
            );
        } else {
            uint256 wethAmount = quoteFromV3(baseToken, baseAmount);
            apeXAmount = v2Observations.consult(
                v2Pair, 
                WETH, 
                apeX, 
                wethAmount, 
                twapInterval, 
                periodSize, 
                cardinality
            );
        }
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }
}
