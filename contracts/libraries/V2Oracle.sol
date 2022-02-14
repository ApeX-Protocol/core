// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../core/interfaces/uniswapV2/IUniswapV2Pair.sol";
import "./FixedPoint.sol";

library V2Oracle {
    struct Observation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint256 timestamp, uint256 periodSize, uint16 granularity) internal pure returns (uint16 index) {
        uint256 epochPeriod = timestamp / periodSize;
        return uint16(epochPeriod % granularity);
    }

    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getFirstObservationInWindow(Observation[] storage self, uint256 periodSize, uint16 granularity) internal view returns (Observation storage firstObservation) {
        uint16 observationIndex = observationIndexOf(block.timestamp, periodSize, granularity);
        // no overflow issue. if observationIndex + 1 overflows, result is still zero.
        uint16 firstObservationIndex = (observationIndex + 1) % granularity;
        firstObservation = self[firstObservationIndex];
    }


    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update(Observation[] storage self, address pair, uint256 periodSize, uint16 granularity) internal {
        // populate the array with empty observations (first call only)
        for (uint256 i = self.length; i < granularity; i++) {
            self.push();
        }

        // get the observation for the current period
        uint16 observationIndex = observationIndexOf(block.timestamp, periodSize, granularity);
        Observation memory observation = self[observationIndex];

        // we only want to commit updates once per period (i.e. windowSize / granularity)
        uint timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed > periodSize) {
            (uint256 price0Cumulative, uint256 price1Cumulative,) = currentCumulativePrices(pair);
            observation.timestamp = block.timestamp;
            observation.price0Cumulative = price0Cumulative;
            observation.price1Cumulative = price1Cumulative;
            self[observationIndex] = observation;
        }
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function computeAmountOut(
        uint256 priceCumulativeStart, uint256 priceCumulativeEnd,
        uint256 timeElapsed, uint256 amountIn
    ) private pure returns (uint256 amountOut) {
        // overflow is desired.
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
        );
        FixedPoint.uq144x112 memory amountOut144x112 = FixedPoint.mul(priceAverage, amountIn);
        amountOut = FixedPoint.decode144(amountOut144x112);
    }

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - [windowSize, windowSize - periodSize * 2], now]
    // update must have been called for the bucket corresponding to timestamp `now - windowSize`
    function consult(
        Observation[] storage self, 
        address pair, 
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn, 
        uint256 windowSize, 
        uint256 periodSize, 
        uint16 granularity
    ) internal view returns (uint256 amountOut) {
        Observation memory firstObservation = getFirstObservationInWindow(self, periodSize, granularity);

        uint timeElapsed = block.timestamp - firstObservation.timestamp;
        require(timeElapsed <= windowSize, 'V2Oracle: MISSING_HISTORICAL_OBSERVATION');
        // should never happen.
        require(timeElapsed >= windowSize - periodSize * 2, 'V2Oracle: UNEXPECTED_TIME_ELAPSED');

        (uint256 price0Cumulative, uint256 price1Cumulative,) = currentCumulativePrices(pair);
        (address token0,) = sortTokens(tokenIn, tokenOut);

        if (token0 == tokenIn) {
            return computeAmountOut(firstObservation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
        } else {
            return computeAmountOut(firstObservation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
        }
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = uint32(block.timestamp % 2 ** 32);
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'V2Oracle: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'V2Oracle: ZERO_ADDRESS');
    }
}