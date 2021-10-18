// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockVAmm is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function getBaseWithMarkPrice(uint256 quoteAmount) public returns (uint256) {
        return quoteAmount;
    }

    function swapQuery(
        address input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256) {
        if (inputAmount != 0) {
            return inputAmount;
        }
        return outputAmount;
    }

    function swap(
        address input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount
    ) external returns (uint256) {
        if (inputAmount != 0) {
            return inputAmount;
        }
        return outputAmount;
    }

    function forceSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external {}

    function getAccountSpecificMarkPrice() external view returns (uint256) {
        return 10; //bad for long
    }
}
