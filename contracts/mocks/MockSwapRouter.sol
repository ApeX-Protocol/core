// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../interfaces/uniswapV3/ISwapRouter.sol";

contract MockSwapRouter is ISwapRouter {
    address public override WETH9;
    address public override factory;

    constructor(address WETH9_, address factory_) {
        WETH9 = WETH9_;
        factory = factory_;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256 amountOut) {
        
    }
}