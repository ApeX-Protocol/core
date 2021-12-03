// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IStakingPool {
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

    /// @notice Get pool token of this core pool
    function poolToken() external view returns (address);

    /// @notice Process yield reward (apex) of msg.sender
    function processRewards() external;

    /// @notice Stake poolToken
    /// @param amount poolToken's amount to stake.
    /// @param lockUntil time to lock.
    function stake(uint256 amount, uint256 lockUntil) external;

    /// @notice UnstakeBatch poolToken
    /// @param depositIds the deposit index.
    /// @param amounts poolToken's amount to unstake.
    function unstakeBatch(uint256[] memory depositIds, uint256[] memory amounts) external;

    /// @notice Not-apex stakingPool to stake their users' yield to apex stakingPool
    /// @param staker add yield to this staker in apex stakingPool.
    /// @param amount yield apex amount to stake.
    function stakeAsPool(address staker, uint256 amount) external;

    /// @notice enlarge lock time of this deposit `depositId` to `lockUntil`
    /// @param depositId the deposit index.
    /// @param lockUntil new lock time.
    function updateStakeLock(uint256 depositId, uint256 lockUntil) external;
}
