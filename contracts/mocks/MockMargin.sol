// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../core/interfaces/IAmm.sol";
import "../libraries/SignedMath.sol";

contract MockMargin  {

     using SignedMath for int256;
    address public config;
    address public amm;
    address public baseToken;
    address public quoteToken;
    uint256 public reserve;
    int256 public netpostion ;
    uint256 public totalpostion ;
    constructor() {
    }

    function initialize(
        address baseToken_,
        address quoteToken_,
        address amm_,
        address config_
    ) external  {
        baseToken = baseToken_;
        quoteToken = quoteToken_;
        amm = amm_;
        config = config_ ;
    }


    function totalPosition() external view returns (uint256 ){
        return netpostion.abs()*7;
    }
    function netPosition() external view returns (int256 ){
        return netpostion;
    }
    function setNetPosition(int256 newNetpositon ) external  returns (int256 ){
      
       netpostion = newNetpositon;
       return netpostion; 
    }


    function deposit(address user, uint256 amount) external  {
        require(msg.sender == amm, "Margin.deposit: REQUIRE_AMM");
        require(amount > 0, "Margin.deposit: AMOUNT_IS_ZERO");
        uint256 balance = IERC20(baseToken).balanceOf(address(this));
        require(amount <= balance - reserve, "Margin.deposit: INSUFFICIENT_AMOUNT");

        reserve = reserve + amount;
    }

    // need for testing
    function swapProxy(
        address trader,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external returns (uint256[2] memory amounts) {
      IAmm(amm).swap(trader, inputToken, outputToken, inputAmount, outputAmount);
    }

       function withdraw(
        address user,
        address receiver,
        uint256 amount
    ) external   {
        require(msg.sender == amm, "Margin.withdraw: REQUIRE_AMM");
    }
}
