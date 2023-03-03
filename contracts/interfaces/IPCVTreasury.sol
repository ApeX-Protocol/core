// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IPCVTreasury {
    event NewLiquidityToken(address indexed lpToken);
    event NewBondPool(address indexed pool);
    event Deposit(address indexed pool, address indexed lpToken, uint256 amountIn, uint256 payout);
    event Withdraw(address indexed lpToken, address indexed policy, uint256 amount);
    event ApeXGranted(address indexed to, uint256 amount);

    function apeXToken() external view returns (address);

    function isLiquidityToken(address) external view returns (bool);

    function isBondPool(address) external view returns (bool);

    function addLiquidityToken(address lpToken) external;

    function addBondPool(address pool) external;

    function deposit(
        address lpToken,
        uint256 amountIn,
        uint256 payout
    ) external;

    function withdraw(
        address lpToken,
        address policy,
        uint256 amount,
        bytes calldata data
    ) external;

    function grantApeX(address to, uint256 amount) external;
}
