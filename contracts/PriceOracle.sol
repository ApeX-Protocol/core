pragma solidity ^0.8.0;

import "./interfaces/IPriceOracle.sol";
import "./libraries/UniswapV2Library.sol";

contract PriceOracle is IPriceOracle {
    address public uniswapV2Factory;

    constructor(address _uniswapV2Facroty) public {
        uniswapV2Factory = _uniswapV2Facroty;
    }

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) external view returns (uint256 quoteAmount) {
        (uint256 reserveBase, uint256 reserveQuote) = UniswapV2Library.getReserves(
            uniswapV2Factory,
            baseToken,
            quoteToken
        );
        quoteAmount = UniswapV2Library.quote(baseAmount, reserveBase, reserveQuote);
    }
}
