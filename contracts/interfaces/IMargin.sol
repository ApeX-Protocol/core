// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IMargin {
    event AddMargin(address indexed trader, uint256 depositAmount);
    event RemoveMargin(address indexed trader, uint256 withdrawAmount);
    event OpenPosition(address indexed trader, uint8 side, uint256 baseAmount, uint256 quoteAmount);
    event ClosePosition(address indexed trader, uint256 quoteAmount, uint256 baseAmount);
    event Liquidate(
        address indexed liquidator,
        address indexed trader,
        uint256 quoteAmount,
        uint256 baseAmount,
        uint256 bonus
    );

    function baseToken() external view returns (address);

    function quoteToken() external view returns (address);

    function factory() external view returns (address);

    function config() external view returns (address);

    function amm() external view returns (address);

    function vault() external view returns (address);

    function getPosition(address trader)
        external
        view
        returns (
            int256 baseSize,
            int256 quoteSize,
            uint256 tradeSize
        );

    function getWithdrawable(address trader) external view returns (uint256 amount);

    function canLiquidate(address trader) external view returns (bool);

    function queryMaxOpenPosition(uint8 side, uint256 baseAmount) external view returns (uint256 quoteAmount);

    // only factory can call this function
    function initialize(
        address _baseToken,
        address _quoteToken,
        address _config,
        address _amm,
        address _vault
    ) external;

    function addMargin(address trader, uint256 depositAmount) external;

    function removeMargin(uint256 withdrawAmount) external;

    function openPosition(uint8 side, uint256 baseAmount) external returns (uint256 quoteAmount);

    function closePosition(uint256 quoteAmount) external returns (uint256 baseAmount);

    function liquidate(address trader)
        external
        returns (
            uint256 quoteAmount,
            uint256 baseAmount,
            uint256 bonus
        );
}
