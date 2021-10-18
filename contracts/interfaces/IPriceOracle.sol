// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IPriceOracle {
    function getSpotPrice(address baseToken, address quoteToken) external view returns (uint256 price);

    function getMarkPrice(address baseToken, address quoteToken) external view returns (uint256 price);
}
