// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IPriceOracle {
    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) external view returns (uint256 quoteAmount);

   // todo
   // function markPrice(address baseToken, address quoteToken) external view returns (uint256);

    function estimateSwapWithMarkPrice(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256[2] memory amounts);
}
