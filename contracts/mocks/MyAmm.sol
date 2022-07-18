// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IAmm.sol";
import "../core/LiquidityERC20.sol";
import "../interfaces/IERC20.sol";

contract MyAmm is IAmm, LiquidityERC20  {
    uint256 public constant override MINIMUM_LIQUIDITY = 10**3;

    address public override factory;
    address public override config;
    address public override baseToken;
    address public override quoteToken;
    address public override margin;

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;

    uint256 public override lastPrice;

    uint112 private baseReserve;
    uint112 private quoteReserve;
    uint32 private blockTimestampLast;

    constructor() {
        factory = msg.sender;
    }

    // only factory can call this function
    function initialize(
        address baseToken_,
        address quoteToken_,
        address margin_
    ) external override {
        baseToken = baseToken_;
        quoteToken = quoteToken_;
        margin = margin_;
    }

    function setReserves(uint112 reserveBase, uint112 reserveQuote) external {
        baseReserve = reserveBase;
        quoteReserve = reserveQuote;
    }

    function mint(address to)
        external override
        returns (
            uint256 baseAmount,
            uint256 quoteAmount,
            uint256 liquidity
        ) {
            _mint(to, 10000);
        }

    function burn(address to)
        external override
        returns (
            uint256 baseAmount,
            uint256 quoteAmount,
            uint256 liquidity
        ) {
            IERC20(baseToken).transfer(to, 100);
        }

    // only binding margin can call this function
    function swap(
        address trader,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external override returns (uint256[2] memory amounts) {

    }

    // only binding margin can call this function
    function forceSwap(
        address trader,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external override {

    }

    function rebase() external override returns (uint256 quoteReserveAfter) {

    }

    function collectFee() external override returns (bool) {
        
    }

    function getReserves()
        external
        view override
        returns (
            uint112 reserveBase,
            uint112 reserveQuote,
            uint32 blockTimestamp
        ) 
    {
        reserveBase = baseReserve;
        reserveQuote = quoteReserve;
        blockTimestamp = blockTimestampLast;
    }

    function estimateSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view override returns (uint256[2] memory amounts) {

    }

    function getFeeLiquidity() external  override view returns (uint256) {

    }

    function getTheMaxBurnLiquidity() external override view returns (uint256 maxLiquidity) {

    }
}