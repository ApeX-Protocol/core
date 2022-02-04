// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAlpPool {
    struct VestItem {
        uint256 amount;
        uint256 lockUntil;
    }

    struct User {
        uint256 total;
        VestItem[] vests;
    }

    event Stake(address indexed staker, uint256 amount);

    event Unstake(address indexed unstaker, uint256 amount);

    event Claim(address indexed receiver, uint256 amount);

    event Vest(address indexed vester, uint256 amount);

    event WithdrawApeX(address indexed withdrawer, uint256[] vestIds, uint256[] vestAmounts);

    function stakedAmounts(address _account) external view returns (uint256);

    function claimable(address _account) external view returns (uint256);

    function stake(uint256 _amount) external;

    function unstake(uint256 _amount) external;

    function claim() external returns (uint256);

    function vest(uint256 amount) external;

    function withdrawApeX(uint256[] memory vestIds, uint256[] memory vestAmounts) external;
}
