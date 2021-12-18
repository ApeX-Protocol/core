// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "../core/interfaces/uniswapV3/IUniswapV3Pool.sol";

contract MockUniswapV3Pool is IUniswapV3Pool {
    address public immutable override token0;
    address public immutable override token1;
    uint24 public immutable fee;
    uint128 public override liquidity;

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

    function setLiquidity(uint128 liquidity_) external {
        liquidity = liquidity_;
    }

    function setSqrtPriceX96(uint160 sqrtPriceX96) external {
        slot0.sqrtPriceX96 = sqrtPriceX96;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        override
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {}
}
