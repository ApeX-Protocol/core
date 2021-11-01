pragma solidity  0.8.0;
import "../libraries/FullMath.sol";
contract MathTest {

     function swapQueryWithAcctSpecMarkPrice(
        uint256 inputAmount,
        uint256 outputAmount
    ) external view  returns (uint256 amounts) {
        uint112 _baseReserve =100201086702639423047683153;
        uint112 _quoteReserve= 200402267246802328553949887628;

        uint256 quoteAmount;
        uint256 baseAmount;
        if (inputAmount != 0) {
            quoteAmount = inputAmount;
        } else {
            quoteAmount = outputAmount;
        }

        uint256 inputSquare = quoteAmount * quoteAmount;
        // price = (sqrt(y/x)+ betal * deltaY/L).**2;
        // deltaX = deltaY/price
        // deltaX = (deltaY * L)/(y + betal * deltaY)**2
        uint256 L = uint256(_baseReserve) * uint256(_quoteReserve);
        uint8 beta = 100;
        require(beta >= 50 && beta <= 100, "beta error");
        //112
        uint256 denominator = _quoteReserve + beta * quoteAmount/100;
        //224
        denominator = denominator * denominator;

       // baseAmount = quoteAmount*L/denominator;
        baseAmount = FullMath.mulDiv(quoteAmount, L, denominator);

        return baseAmount;
    }
}

