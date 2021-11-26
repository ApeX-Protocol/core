// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IAmm {
    function mint(address to)
        external
        returns (
            uint256 baseAmount,
            uint256 quoteAmount,
            uint256 liquidity
        );

    function baseToken() external view returns (address);
}
