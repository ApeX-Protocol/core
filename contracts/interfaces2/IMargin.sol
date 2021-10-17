pragma solidity ^0.8.0;

interface IMargin {
    event AddMargin(address indexed trader, uint depositAmount);
    event RemoveMargin(address indexed trader, uint withdrawAmount);
    event OpenPosition(address indexed trader, uint8 side, uint baseAmount, uint quoteAmount);
    event ClosePosition(address indexed trader, uint quoteAmount, uint baseAmount);
    event Liquidate(address indexed liquidator, address indexed trader, uint quoteAmount, uint baseAmount, uint bonus);

    function baseToken() external view returns (address);
    function quoteToken() external view returns (address);
    function factory() external view returns (address);
    function config() external view returns (address);
    function amm() external view returns (address);
    function vault() external view returns (address);
    function getPosition(address trader) external view returns (uint baseSize, uint quoteSize, uint tradeSize);
    function getWithdrawable(address trader) external view returns (uint amount);
    function canLiquidate(address trade) external view returns (bool);

    // only factory can call this function
    function initialize(address baseToken, address quoteToken, address config, address amm, address vault) external;
    function addMargin(address trader, uint depositAmount) external;
    function removeMargin(uint withdrawAmount) external;
    function openPosition(uint8 side, uint baseAmount) external returns (uint quoteAmount);
    function closePosition(uint quoteAmount) external returns (uint baseAmount);
    function liquidate(address trader) external returns (uint quoteAmount, uint baseAmount, uint bonus);
}