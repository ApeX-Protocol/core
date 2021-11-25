// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAmm is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function estimateSwap(
        address input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount
    ) external pure returns (uint256[2] memory) {
        input = input;
        output = output;
        if (inputAmount != 0) {
            return [0, inputAmount];
        }
        return [outputAmount, 0];
    }

    function swap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external pure returns (uint256[2] memory amounts) {
        inputToken = inputToken;
        outputToken = outputToken;

        if (inputAmount != 0) {
            amounts = [0, inputAmount];
        } else {
            amounts = [outputAmount, 0];
        }
    }

    function forceSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external {}

    function estimateSwapWithMarkPrice(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external pure returns (uint256[2] memory amounts) {
        inputToken = inputToken;
        outputToken = outputToken;
        if (inputAmount != 0) {
            return [0, inputAmount];
        }
        return [outputAmount, 0];
    }
}
