pragma solidity ^0.8.0;

contract MockPriceOracle {
    constructor() {}

    int256 public pf = 0;

    //premiumFraction is (markPrice - indexPrice) * fundingRatePrecision / 8h / indexPrice
    function getPremiumFraction(address amm) external view returns (int256) {
        return pf;
    }

    function setPf(int256 _pf) external {
        pf = _pf;
    }
}
