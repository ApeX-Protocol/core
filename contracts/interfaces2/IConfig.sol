pragma solidity ^0.8.0;

interface IConfig {
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
    event NewAdmin(address oldAdmin, address newAdmin);
    event PriceOracleChanged(address indexed oldOracle, address indexed newOracle);
    event LiquidateIncentiveChanged(uint oldIncentive, uint newIncentive);
    event RebasePriceGapChanged(uint oldGap, uint newGap);

    function pendingAdmin() external view returns (address);
    function admin() external view returns (address);
    function priceOracle() external view returns (address);
    function liquidateIncentive() external view returns (uint);
    function rebasePriceGap() external view returns (uint);

    function setPendingAdmin(address newPendingAdmin) external;
    function acceptAdmin() external;
    function setPriceOracle(address newOracle) external;
    function setLiquidateIncentive(uint newIncentive) external;
    function setRebasePriceGap(uint newGap) external;
}