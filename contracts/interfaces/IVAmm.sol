// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IVAmm {
    //input or output is weth or usdt address
    function swap(
        address input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount
    ) external returns (uint256);

    function swapQuery(
        address input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256);

    function forceSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external;

    // get base with quote
    function getBaseWithMarkPrice(uint256 quoteAmount) external view returns (uint256);

    function getAccountSpecificMarkPrice() external view returns (uint256);
}
