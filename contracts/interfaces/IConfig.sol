// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IConfig {
    event PriceOracleChanged(address indexed oldOracle, address indexed newOracle);
    event RebasePriceGapChanged(uint256 oldGap, uint256 newGap);
    event RouterRegistered(address indexed router);
    event RouterUnregistered(address indexed router);

    function priceOracle() external view returns (address);

    function beta() external view returns (uint8);

    function initMarginRatio() external view returns (uint256);

    function liquidateThreshold() external view returns (uint256);

    function liquidateFeeRatio() external view returns (uint256);

    function rebasePriceGap() external view returns (uint256);

    function routerMap(address) external view returns (bool);

    function setPriceOracle(address newOracle) external;

    function setBeta(uint8 newBeta) external;

    function setRebasePriceGap(uint256 priceGap) external;

    function setInitMarginRatio(uint256 marginRatio) external;

    function setLiquidateThreshold(uint256 threshold) external;

    function setLiquidateFeeRatio(uint256 feeRatio) external;

    function registerRouter(address router) external;

    function unregisterRouter(address router) external;
}
