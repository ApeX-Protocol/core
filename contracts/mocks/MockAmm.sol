// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAmm is ERC20 {
    address public baseToken;
    address public quoteToken;
    uint112 private baseReserve;
    uint112 private quoteReserve;
    uint32 private blockTimestampLast;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function initialize(address baseToken_, address quoteToken_) external {
        baseToken = baseToken_;
        quoteToken = quoteToken_;
    }

    function setReserves(uint112 reserveBase, uint112 reserveQuote) external {
        baseReserve = reserveBase;
        quoteReserve = reserveQuote;
    }

    function getReserves()
        public
        view
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

    function mint(address to)
        external
        returns (
            uint256 baseAmount,
            uint256 quoteAmount,
            uint256 liquidity
        )
    {
        baseAmount = 1000;
        quoteAmount = 1000;
        liquidity = 1000;
        _mint(to, liquidity);
    }

    function estimateSwap(
        address input,
        address output,
        uint256 inputAmount,
        uint256 outputAmount
    ) external pure returns (uint256[2] memory) {
        input = input;
        output = output;
        if (inputAmount != 0) {
            return [0, inputAmount];
        }
        return [outputAmount, 0];
    }

    function swap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external pure returns (uint256[2] memory amounts) {
        inputToken = inputToken;
        outputToken = outputToken;

        if (inputAmount != 0) {
            amounts = [0, inputAmount];
        } else {
            amounts = [outputAmount, 0];
        }
    }

    function forceSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external {}

    function estimateSwapWithMarkPrice(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external pure returns (uint256[2] memory amounts) {
        inputToken = inputToken;
        outputToken = outputToken;
        if (inputAmount != 0) {
            return [0, inputAmount];
        }
        return [outputAmount, 0];
    }
}
