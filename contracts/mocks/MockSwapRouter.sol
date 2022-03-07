// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../core/interfaces/uniswapV3/ISwapRouter.sol";

contract MockSwapRouter is ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256 amountOut) {
        
    }
}