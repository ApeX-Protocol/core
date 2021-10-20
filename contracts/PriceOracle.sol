pragma solidity ^0.8.0;

contract PriceOracle is IPriceOracle {
    using SafeMath for uint256;

    address public uniswapV2Factory;
    uint8 public decimals;

    function getSpotPrice(address baseToken, address quoteToken) external view returns (uint256 price) {
        (uint256 reserveBase, uint256 reserveQuote) = UniswapV2Library.getReserves(uniswapV2Factory, baseToken, quoteToken);
        price = reserveBase.mul(1e18).div(reserveQuote); 
    }

}