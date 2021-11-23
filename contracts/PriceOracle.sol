pragma solidity ^0.8.0;

import "./interfaces/IPriceOracle.sol";
import "./libraries/UniswapV2Library.sol";

contract PriceOracle is IPriceOracle {
    address public uniswapV2Factory;
    IAmmFactory public ammFactory;
    IConfig public config;

    constructor(address _uniswapV2Facroty) {
        uniswapV2Factory = _uniswapV2Facroty;
    }

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) external view override returns (uint256 quoteAmount) {
        (uint256 reserveBase, uint256 reserveQuote) = UniswapV2Library.getReserves(
            uniswapV2Factory,
            baseToken,
            quoteToken
        );
        quoteAmount = UniswapV2Library.quote(baseAmount, reserveBase, reserveQuote);
    }

    function markPrice(address baseToken, address quoteToken) external view returns (uint256) {
        IAmm amm = IAmm(ammFactory.getAmm(baseToken, quoteToken));

    }

    function markPriceAcc(int256 quoteAmount, int256 quoteReserve) external view returns (uint256) {
        2 * config.beta() * quoteAmount / quoteReserve
    }

    function estimateSwapWithMarkPrice(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view override returns (uint256[2] memory amounts) {
        // (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        // uint256 quoteAmount;
        // uint256 baseAmount;
        // if (inputAmount != 0) {
        //     quoteAmount = inputAmount;
        // } else {
        //     quoteAmount = outputAmount;
        // }
        // uint256 inputSquare = quoteAmount * quoteAmount;
        // // price = (sqrt(y/x)+ betal * deltaY/L).**2;
        // // deltaX = deltaY/price
        // // deltaX = (deltaY * L)/(y + betal * deltaY)**2
        // uint256 L = uint256(_baseReserve) * uint256(_quoteReserve);
        // uint8 beta = IConfig(IPairFactory(factory).config()).beta();
        // require(beta >= 50 && beta <= 100, "beta error");
        // //112
        // uint256 denominator = (_quoteReserve + (beta * quoteAmount) / 100);
        // //224
        // denominator = denominator * denominator;
        // baseAmount = FullMath.mulDiv(quoteAmount, L, denominator);
        // return inputAmount == 0 ? [baseAmount, quoteAmount] : [quoteAmount, baseAmount];
    }

    function getPremiumFraction(address amm) external view override returns (int256) {}
}
