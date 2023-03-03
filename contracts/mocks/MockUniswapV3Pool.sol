// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../libraries/Math.sol";
import "../libraries/FullMath.sol";
import "../interfaces/uniswapV3/IUniswapV3Pool.sol";
import "../libraries/TickMath.sol";
import "../libraries/V3Oracle.sol";
import "../interfaces/IERC20.sol";

contract MockUniswapV3Pool is IUniswapV3Pool {
    using Math for uint256;
    using FullMath for uint256;

    struct Observation {
        // the block timestamp of the observation
        uint32 blockTimestamp;
        // the tick accumulator, i.e. tick * time elapsed since the pool was first initialized
        int56 tickCumulative;
        // the seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
        uint160 secondsPerLiquidityCumulativeX128;
        // whether or not the observation is initialized
        bool initialized;
    }

    address public immutable override token0;
    address public immutable override token1;
    uint24 public immutable override fee;
    uint128 public override liquidity;
    Observation[65535] public override observations;

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }
    Slot0 public override slot0;

    constructor(
        address token0_,
        address token1_,
        uint24 fee_
    ) {
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
    }

    function initialize(uint112 baseReserve, uint112 quoteReserve) external {
        uint160 sqrtPriceX96 = _getSqrtPriceX96(baseReserve, quoteReserve);
        require(slot0.sqrtPriceX96 == 0, 'AI');

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        observations[0] = Observation({
            blockTimestamp: _blockTimestamp(),
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: 1,
            observationCardinalityNext: 1,
            feeProtocol: 0,
            unlocked: true
        });
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override returns (int256 amount0, int256 amount1) {
        if (zeroForOne) {
            IERC20(token1).transfer(recipient, 100);
        } else {
            IERC20(token0).transfer(recipient, 100);
        }
    }

    function setLiquidity(uint128 liquidity_) external {
        liquidity = liquidity_;
    }

    function setSqrtPriceX96(uint112 baseReserve, uint112 quoteReserve) external {
        slot0.sqrtPriceX96 = _getSqrtPriceX96(baseReserve, quoteReserve);
    }

    function writeObservation() external {
        Observation memory last = observations[slot0.observationIndex];

        // early return if we've already written an observation this block
        if (last.blockTimestamp == _blockTimestamp()) return;

        uint16 indexUpdated; 
        uint16 cardinalityUpdated;
        // if the conditions are right, we can bump the cardinality
        if (slot0.observationCardinalityNext > slot0.observationCardinality && slot0.observationIndex == (slot0.observationCardinality - 1)) {
            cardinalityUpdated = slot0.observationCardinalityNext;
        } else {
            cardinalityUpdated = slot0.observationCardinality;
        }

        indexUpdated = (slot0.observationIndex + 1) % cardinalityUpdated;
        observations[indexUpdated] = transform(last, _blockTimestamp(), slot0.tick, liquidity);
        slot0.observationIndex = indexUpdated;
        slot0.observationCardinality = cardinalityUpdated;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        override
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {

        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            (tickCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = observeSingle(
                observations,
                _blockTimestamp(),
                secondsAgos[i],
                slot0.tick,
                slot0.observationIndex,
                liquidity,
                slot0.observationCardinality
            );
        }
    }

    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint128 liquidity_,
        uint16 cardinality
    ) internal view returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) {
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.blockTimestamp != time) last = transform(last, time, tick, liquidity_);
            return (last.tickCumulative, last.secondsPerLiquidityCumulativeX128);
        }

        uint32 target = time - secondsAgo;

        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(self, time, target, tick, index, liquidity_, cardinality);

        if (target == beforeOrAt.blockTimestamp) {
            // we're at the left boundary
            return (beforeOrAt.tickCumulative, beforeOrAt.secondsPerLiquidityCumulativeX128);
        } else if (target == atOrAfter.blockTimestamp) {
            // we're at the right boundary
            return (atOrAfter.tickCumulative, atOrAfter.secondsPerLiquidityCumulativeX128);
        } else {
            // we're in the middle
            uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
            uint32 targetDelta = target - beforeOrAt.blockTimestamp;
            return (
                beforeOrAt.tickCumulative +
                    ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / int56(uint56(observationTimeDelta))) *
                    int56(uint56(targetDelta)),
                beforeOrAt.secondsPerLiquidityCumulativeX128 +
                    uint160(
                        (uint256(
                            atOrAfter.secondsPerLiquidityCumulativeX128 - beforeOrAt.secondsPerLiquidityCumulativeX128
                        ) * targetDelta) / observationTimeDelta
                    )
            );
        }
    }

    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint128 liquidity_,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // optimistically set before to the newest observation
        beforeOrAt = self[index];

        // if the target is chronologically at or after the newest observation, we can early return
        if (lte(time, beforeOrAt.blockTimestamp, target)) {
            if (beforeOrAt.blockTimestamp == target) {
                // if newest observation equals target, we're in the same block, so we can ignore atOrAfter
                return (beforeOrAt, atOrAfter);
            } else {
                // otherwise, we need to transform
                return (beforeOrAt, transform(beforeOrAt, target, tick, liquidity_));
            }
        }

        // now, set before to the oldest observation
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // ensure that the target is chronologically at or after the oldest observation
        require(lte(time, beforeOrAt.blockTimestamp, target), 'OLD');

        // if we've reached this point, we have to binary search
        return binarySearch(self, time, target, index, cardinality);
    }

    function binarySearch(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // oldest observation
        uint256 r = l + cardinality - 1; // newest observation
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // we've landed on an uninitialized tick, keep searching higher (more recently)
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);

            // check if we've found the answer!
            if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp)) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity_
    ) private pure returns (Observation memory) {
        uint32 delta = blockTimestamp - last.blockTimestamp;
        return
            Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: last.tickCumulative + int56(tick) * int56(uint56(delta)),
                secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128 +
                    ((uint160(delta) << 128) / (liquidity_ > 0 ? liquidity_ : 1)),
                initialized: true
            });
    }

    function lte(
        uint32 time,
        uint32 a,
        uint32 b
    ) private pure returns (bool) {
        // if there hasn't been overflow, no need to adjust
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2**32;
        uint256 bAdjusted = b > time ? b : b + 2**32;

        return aAdjusted <= bAdjusted;
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external override {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext; // for the event
        for (uint16 i = observationCardinalityNextOld; i < observationCardinalityNext; i++) observations[i].blockTimestamp = 1;
        slot0.observationCardinalityNext = observationCardinalityNext;
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }

    function _getSqrtPriceX96(uint112 baseReserve, uint112 quoteReserve) internal pure returns (uint160) {
        uint256 priceX192 = uint256(quoteReserve).mulDiv(2**192, baseReserve);
        return uint160(priceX192.sqrt());
    }
}
