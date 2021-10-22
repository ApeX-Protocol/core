pragma solidity ^0.8.0;



contract MockPriceOracle   {
    
    constructor() {
    }

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) external view  returns (uint256 quoteAmount) {
        quoteAmount = 100000 * 10**6;
    }
}
