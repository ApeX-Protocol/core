// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IConfig {
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
    event NewAdmin(address oldAdmin, address newAdmin);
    event PriceOracleChanged(address indexed oldOracle, address indexed newOracle);
    event LiquidateIncentiveChanged(uint256 oldIncentive, uint256 newIncentive);
    event RebasePriceGapChanged(uint256 oldGap, uint256 newGap);

    function pendingAdmin() external view returns (address);

    function admin() external view returns (address);

    function priceOracle() external view returns (address);

    function liquidateIncentive() external view returns (uint256);

    function rebasePriceGap() external view returns (uint256);

    function onlyPCV() external view returns (bool);

    function setPendingAdmin(address newPendingAdmin) external;

    function acceptAdmin() external;

    function setPriceOracle(address newOracle) external;

    function setLiquidateIncentive(uint256 newIncentive) external;

    function setRebasePriceGap(uint256 newGap) external;
}
