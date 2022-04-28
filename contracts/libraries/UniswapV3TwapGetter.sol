// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/uniswapV3/IUniswapV3Pool.sol";
import "./FixedPoint96.sol";
import "./TickMath.sol";
import "./FullMath.sol";

library UniswapV3TwapGetter {
    function getSqrtTwapX96(address uniswapV3Pool, uint32 twapInterval) internal view returns (uint160 sqrtPriceX96) {
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Pool);
        if (twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = pool.slot0();
        } else {
            (, , uint16 index, uint16 cardinality, , , ) = pool.slot0();
            (uint32 targetElementTime, , , bool initialized) = pool.observations((index + 1) % cardinality);
            if (!initialized) {
                (targetElementTime, , , ) = pool.observations(0);
            }
            uint32 delta = uint32(block.timestamp) - targetElementTime;
            if (delta == 0) {
                (sqrtPriceX96, , , , , , ) = pool.slot0();
            } else {
                if (delta < twapInterval) twapInterval = delta;
                uint32[] memory secondsAgos = new uint32[](2);
                secondsAgos[0] = twapInterval; // from (before)
                secondsAgos[1] = 0; // to (now)
                (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
                // tick(imprecise as it's an integer) to price
                sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                    int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(twapInterval)))
                );
            }
        }
    }

    function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256 priceX96) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }
}
