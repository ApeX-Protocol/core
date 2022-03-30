// SPDX-License-Identifier: GPL-3.0-or-later
import "../bonding/interfaces/IBondPriceOracle.sol";

contract MockBondPriceOracle is IBondPriceOracle {
    function setupTwap(address baseToken) external override {

    }

    function quote(address baseToken, uint256 baseAmount) external view override returns (uint256 apeXAmount) {
        return baseAmount * 100;
    }
}