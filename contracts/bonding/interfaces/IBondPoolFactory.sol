// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title The interface for a bond pool factory
/// @notice For create bond pool
interface IBondPoolFactory {
    event BondPoolCreated(address indexed amm, address indexed pool);
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);

    function setPriceOracle(address newOracle) external;

    function updateParams(
        uint256 maxPayout_,
        uint256 discount_,
        uint256 vestingTerm_
    ) external;

    function createPool(address amm) external returns (address);

    function WETH() external view returns (address);

    function apeXToken() external view returns (address);

    function treasury() external view returns (address);

    function priceOracle() external view returns (address);

    function maxPayout() external view returns (uint256);

    function discount() external view returns (uint256);

    function vestingTerm() external view returns (uint256);

    function getPool(address amm) external view returns (address);

    function allPools(uint256) external view returns (address);

    function allPoolsLength() external view returns (uint256);
}
