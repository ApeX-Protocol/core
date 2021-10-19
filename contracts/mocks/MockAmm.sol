// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockVAmm is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function swapQuery(
        address input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256[2] memory) {
        if (inputAmount != 0) {
            return [0, inputAmount];
        }
        return [0, outputAmount];
    }

    function swap(
        address input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount
    ) external returns (uint256[2] memory) {
        if (inputAmount != 0) {
            return [0, inputAmount];
        }
        return [0, outputAmount];
    }

    function forceSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external {}

    function swapQueryWithAcctSpecMarkPrice(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256[2] memory amounts) {
        if (inputAmount != 0) {
            return [0, inputAmount];
        }
        return [0, outputAmount];
    }
}
