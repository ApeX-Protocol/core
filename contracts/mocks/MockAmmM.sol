// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../core/interfaces/IVault.sol";

contract MockAmmOfMargin is ERC20 {
    address public baseToken;
    address public quoteToken;
    address public margin;
    uint112 private baseReserve;
    uint112 private quoteReserve;
    uint32 private blockTimestampLast;
    uint256 public price = 2e9;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function initialize(address baseToken_, address quoteToken_) external {
        baseToken = baseToken_;
        quoteToken = quoteToken_;
    }

    function setMargin(address margin_) external {
        margin = margin_;
    }

    //2000usdc/eth -> 2000*(1e6/1e18)*1e18
    function setPrice(uint256 _price) external {
        price = _price;
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

    function deposit(address to, uint256 amount) external {
        IVault(margin).deposit(to, amount);
    }

    function withdraw(
        address user,
        address receiver,
        uint256 amount
    ) external {
        IVault(margin).withdraw(user, receiver, amount);
    }

    function estimateSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256[2] memory amounts) {
        inputToken = inputToken;
        outputToken = outputToken;
        if (inputToken == baseToken) {
            if (inputAmount != 0) {
                amounts = [0, (inputAmount * price) / 1e18];
            } else {
                amounts = [(outputAmount * 1e18) / price, 0];
            }
        } else {
            if (inputAmount != 0) {
                amounts = [0, (inputAmount * 1e18) / price];
            } else {
                amounts = [(outputAmount * price) / 1e18, 0];
            }
        }
    }

    function swap(
        address trader,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256[2] memory amounts) {
        inputToken = inputToken;
        outputToken = outputToken;

        if (inputToken == baseToken) {
            if (inputAmount != 0) {
                amounts = [0, (inputAmount * price) / 1e18];
            } else {
                amounts = [(outputAmount * 1e18) / price, 0];
            }
        } else {
            if (inputAmount != 0) {
                amounts = [0, (inputAmount * 1e18) / price];
            } else {
                amounts = [(outputAmount * price) / 1e18, 0];
            }
        }
    }

    function forceSwap(
        address trader,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external {
        if (inputToken == baseToken) {
            baseReserve += uint112(inputAmount);
            quoteReserve -= uint112(outputAmount);
        } else {
            baseReserve -= uint112(outputAmount);
            quoteReserve += uint112(inputAmount);
        }
    }
}
