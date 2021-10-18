pragma solidity ^0.8.0;

interface IAmm {
    event Mint(address indexed sender, address indexed to, uint baseAmount, uint quoteAmount, uint liquidity);
    event Burn(address indexed sender, address indexed to, uint baseAmount, uint quoteAmount);
    event Swap(address indexed inputToken, address indexed outputToken, uint inputAmount, uint outputAmount);
    event ForceSwap(address indexed inputToken, address indexed outputToken, uint inputAmount, uint outputAmount);
    event Rebase(uint priceBefore, uint priceAfter, uint modifyAmount);
    event Sync(uint112 reserveBase, uint112 reserveQuote);

    function baseToken() external view returns (address);
    function quoteToken() external view returns (address);
    function factory() external view returns (address);
    function config() external view returns (address);
    function margin() external view returns (address);
    function vault() external view returns (address);
    function getReserves() external view returns (uint reserveBase, uint reserveQuote);
    
    // only factory can call this function
    function initialize(address baseToken, address quoteToken, address config, address margin, address vault) external;
    function mint(address to) external returns (uint quoteAmount, uint liquidity);
    function burn(address to) external returns (uint baseAmount, uint quoteAmount);
    // only binding margin can call this functiion
    function swap(address inputToken, address outputToken, uint inputAmount, uint outputAmount) external returns (uint[2] memory amounts);
    // only binding margin can call this functiion
    function forceSwap(address inputToken, address outputToken, uint inputAmount, uint outputAmount) external;
    function rebase() external returns (int amount);
}