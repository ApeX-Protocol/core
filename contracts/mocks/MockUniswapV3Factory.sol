// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../interfaces/uniswapV3/IUniswapV3Factory.sol";

contract MockUniswapV3Factory is IUniswapV3Factory {
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    function setPool(
        address tokenA,
        address tokenB,
        uint24 fee,
        address pool
    ) external {
        getPool[tokenA][tokenB][fee] = pool;
        getPool[tokenB][tokenA][fee] = pool;
    }
}
