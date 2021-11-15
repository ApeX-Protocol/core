// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface ICorePool {
    struct Deposit {
        uint256 amount;
        uint256 weight;
        uint256 lockFrom;
        uint256 lockUntil;
        bool isYield;
    }

    struct User {
        uint256 tokenAmount;
        uint256 totalWeight;
        uint256 subYieldRewards;
        Deposit[] deposits;
    }

    event Staked(address indexed by, address indexed from, uint256 amount);

    event YieldClaimed(address indexed by, address indexed to, uint256 amount);

    event Synchronized(address indexed by, uint256 yieldRewardsPerWeight, uint256 lastYieldDistribution);

    event UpdateStakeLock(address indexed by, uint256 depositId, uint256 lockFrom, uint256 lockUntil);

    function poolToken() external view returns (address);

    function processRewards() external;

    function stake(uint256 amount, uint256 lockUntil) external;

    function unstake(uint256 depositId, uint256 amount) external;

    function stakeAsPool(address staker, uint256 amount) external;

    function updateStakeLock(uint256 depositId, uint256 lockUntil) external;
}
