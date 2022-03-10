// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.2;

import "../bonding/interfaces/IBondPriceOracle.sol";

contract MockBondPriceOracle is IBondPriceOracle {
    function setupTwap(address baseToken) external override {

    }

    function updateV2() external override {

    }

    function quote(address baseToken, uint256 baseAmount) external view override returns (uint256 apeXAmount) {
        return baseAmount * 100;
    }
}
