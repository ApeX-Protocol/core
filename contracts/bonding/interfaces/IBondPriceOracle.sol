// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IBondPriceOracle {
    function setupTwap(address baseToken) external;

    function quote(address baseToken, uint256 baseAmount) external view returns (uint256 apeXAmount);
}
