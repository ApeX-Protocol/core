// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

contract MockPriceOracleOfMargin {
    int256 public pf = 0;
    uint256 public p;
    uint256 public markPriceInRatio;
    bool public isIndex;

    constructor() {
        p = 2e9;
    }

    //premiumFraction is (markPrice - indexPrice) * fundingRatePrecision / 8h / indexPrice
    function getPremiumFraction(address amm) external view returns (int256) {
        return pf;
    }

    function setPf(int256 _pf) external {
        pf = _pf;
    }

    //2000usdc = 2000*(1e-12)*1e18
    function setMarkPriceInRatio(uint256 _markPriceInRatio) external {
        markPriceInRatio = _markPriceInRatio;
    }

    function setIsIndex(bool value) external {
        isIndex = value;
    }

    function getMarkPriceAcc(
        address amm,
        uint8 beta,
        uint256 quoteAmount,
        bool negative
    ) public view returns (uint256 price) {
        return (quoteAmount * 1e18) / p;
    }

    function setMarkPrice(uint256 _p) external {
        p = _p;
    }

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) external view returns (uint256 quoteAmount, uint8 source) {
        quoteAmount = 100000 * 10**6;
        source = 0;
    }

    function updateAmmTwap(address pair) external {}

    function setupTwap(address amm) external {}

    function getMarkPriceInRatio(address amm) external view returns (uint256, bool) {
        return (markPriceInRatio, isIndex);
    }
}
