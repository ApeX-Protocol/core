// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IFactory {
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
    event NewAdmin(address oldAdmin, address newAdmin);
    event NewPair(address indexed baseToken, address indexed quoteToken, address amm, address margin, address vault);
    event NewStaking(address indexed baseToken, address indexed quoteToken, address staking);

    function pendingAdmin() external view returns (address);

    function admin() external view returns (address);

    function config() external view returns (address);

    function getAmm(address baseToken, address quoteToken) external view returns (address amm);

    function getMargin(address baseToken, address quoteToken) external view returns (address margin);

    function getVault(address baseToken, address quoteToken) external view returns (address vault);

    // function getStaking(address amm) external view returns (address staking);

    function setPendingAdmin(address newPendingAdmin) external;

    function acceptAdmin() external;

    function createPair(address baseToken, address quotoToken)
        external
        returns (
            address amm,
            address margin,
            address vault
        );

    // function createStaking(address baseToken, address quoteToken) external returns (address staking);
}
