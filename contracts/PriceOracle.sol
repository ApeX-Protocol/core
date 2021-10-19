pragma solidity ^0.8.0;

contract PriceOracle is IPriceOracle {
    address uniswapV2Factory;

    function getSpotPrice(address baseToken, address quoteToken) external view returns (uint256 price) {
        
    }
}