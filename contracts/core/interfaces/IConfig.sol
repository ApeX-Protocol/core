// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IConfig {
    event PriceOracleChanged(address indexed oldOracle, address indexed newOracle);
    event RebasePriceGapChanged(uint256 oldGap, uint256 newGap);
    event RouterRegistered(address indexed router);
    event RouterUnregistered(address indexed router);

    /// @notice get price oracle address.
    function priceOracle() external view returns (address);

    /// @notice get beta of amm.
    function beta() external view returns (uint8);

    /// @notice get init margin ratio of margin.
    function initMarginRatio() external view returns (uint256);

    /// @notice get liquidate threshold of margin.
    function liquidateThreshold() external view returns (uint256);

    /// @notice get liquidate fee ratio of margin.
    function liquidateFeeRatio() external view returns (uint256);

    /// @notice get rebase gap of amm.
    function rebasePriceGap() external view returns (uint256);

    function routerMap(address) external view returns (bool);

    function registerRouter(address router) external;

    function unregisterRouter(address router) external;

    /// @notice Set a new oracle
    /// @param newOracle new oracle address.
    function setPriceOracle(address newOracle) external;

    /// @notice Set a new beta of amm
    /// @param newBeta new beta.
    function setBeta(uint8 newBeta) external;

    /// @notice Set a new rebase gap of amm
    /// @param newGap new gap.
    function setRebasePriceGap(uint256 newGap) external;

    /// @notice Set a new init margin ratio of margin
    /// @param marginRatio new init margin ratio.
    function setInitMarginRatio(uint256 marginRatio) external;

    /// @notice Set a new liquidate threshold of margin
    /// @param threshold new liquidate threshold of margin.
    function setLiquidateThreshold(uint256 threshold) external;

    /// @notice Set a new liquidate fee of margin
    /// @param feeRatio new liquidate fee of margin.
    function setLiquidateFeeRatio(uint256 feeRatio) external;
}
