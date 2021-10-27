// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IConfig {
    event PriceOracleChanged(address indexed oldOracle, address indexed newOracle);
    event RebasePriceGapChanged(uint256 oldGap, uint256 newGap);

    function priceOracle() external view returns (address);

    function beta() external view returns (uint8);

    function initMarginRatio() external view returns (uint256);

    function liquidateThreshold() external view returns (uint256);

    function liquidateFeeRatio() external view returns (uint256);

    function rebasePriceGap() external view returns (uint256);

    function setPriceOracle(address newOracle) external;

    function setBeta(uint8 _beta) external;

    function setRebasePriceGap(uint256 newGap) external;

    function setInitMarginRatio(uint256 _initMarginRatio) external;

    function setLiquidateThreshold(uint256 _liquidateThreshold) external;

    function setLiquidateFeeRatio(uint256 _liquidateFeeRatio) external;
}
