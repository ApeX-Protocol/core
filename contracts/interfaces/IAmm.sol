// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IAmm {
    event Mint(address indexed sender, address indexed to, uint256 baseAmount, uint256 quoteAmount, uint256 liquidity);
    event Burn(address indexed sender, address indexed to, uint256 baseAmount, uint256 quoteAmount);
    event Swap(address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 outputAmount);
    event ForceSwap(address indexed inputToken, address indexed outputToken, uint256 inputAmount, uint256 outputAmount);
    event Rebase(uint256 quoteAmountBefore, uint256 quoteAmountAfter, uint256 baseAmount);
    event Sync(uint112 reserveBase, uint112 reserveQuote);

    function baseToken() external view returns (address);

    function quoteToken() external view returns (address);

    function factory() external view returns (address);

    function config() external view returns (address);

    function margin() external view returns (address);

    function vault() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserveBase,
            uint112 reserveQuote,
            uint32 blockTimestamp
        );

    // only factory can call this function
    function initialize(
        address _baseToken,
        address _quoteToken,
        address _config,
        address _margin,
        address _vault
    ) external;

    function mint(address to) external returns (uint256 quoteAmount, uint256 liquidity);

    function burn(address to) external returns (uint256 baseAmount, uint256 quoteAmount);

    // only binding margin can call this function
    function swap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external returns (uint256[2] memory amounts);

    // only binding margin can call this function
    function forceSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external;

    function rebase() external returns (int256 amount);

    function swapQuery(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256[2] memory amounts);

    function swapQueryWithAcctSpecMarkPrice(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view returns (uint256[2] memory amounts);
}
