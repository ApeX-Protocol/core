// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IVAmm {
    // get base with quote
    function getBaseWithMarkPrice(uint256 quoteAmount)
        external
        view
        returns (uint256);

    //
    function getAccountSpecificMarkPrice() external view returns (uint256);
}
