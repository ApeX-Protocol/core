// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IStakingPool {
    struct Deposit {
        uint256 amount;
        uint256 weight;
        uint256 lockFrom;
        uint256 lockUntil;
    }

    struct Yield {
        uint256 amount;
        uint256 lockFrom;
        uint256 lockUntil;
    }

    struct User {
        uint256 tokenAmount;
        uint256 totalWeight;
        uint256 subYieldRewards;
        Deposit[] deposits;
        Yield[] yields;
    }

    event BatchWithdraw(
        address indexed by,
        uint256[] _depositIds,
        uint256[] _amounts,
        uint256[] _yieldIds,
        uint256[] _yieldAmounts
    );

    event ForceWithdraw(address indexed by, uint256[] yieldIds);

    event Staked(address indexed to, uint256 depositId, uint256 amount, uint256 lockFrom, uint256 lockUntil);

    event YieldClaimed(address indexed by, uint256 depositId, uint256 amount, uint256 lockFrom, uint256 lockUntil);

    event StakeAsPool(
        address indexed by,
        address indexed to,
        uint256 depositId,
        uint256 amountStakedAsPool,
        uint256 yieldAmount,
        uint256 lockFrom,
        uint256 lockUntil
    );

    event Synchronized(address indexed by, uint256 yieldRewardsPerWeight, uint256 lastYieldDistribution);

    event UpdateStakeLock(address indexed by, uint256 depositId, uint256 lockFrom, uint256 lockUntil);

    /// @notice Get pool token of this core pool
    function poolToken() external view returns (address);

    function getStakeInfo(address _user)
        external
        view
        returns (
            uint256 tokenAmount,
            uint256 totalWeight,
            uint256 subYieldRewards
        );

    function getDeposit(address _user, uint256 _depositId) external view returns (Deposit memory);

    function getDepositsLength(address _user) external view returns (uint256);

    function getYield(address _user, uint256 _yieldId) external view returns (Yield memory);

    function getYieldsLength(address _user) external view returns (uint256);

    /// @notice Process yield reward (apex) of msg.sender
    function processRewards() external;

    /// @notice Stake poolToken
    /// @param amount poolToken's amount to stake.
    /// @param lockUntil time to lock.
    function stake(uint256 amount, uint256 lockUntil) external;

    /// @notice BatchWithdraw poolToken
    /// @param depositIds the deposit index.
    /// @param depositAmounts poolToken's amount to unstake.
    function batchWithdraw(
        uint256[] memory depositIds,
        uint256[] memory depositAmounts,
        uint256[] memory yieldIds,
        uint256[] memory yieldAmounts
    ) external;

    /// @notice force withdraw locked reward and new reward
    /// @param depositIds the deposit index of locked reward.
    function forceWithdraw(uint256[] memory depositIds) external;

    /// @notice Not-apex stakingPool to stake their users' yield to apex stakingPool
    /// @param staker add yield to this staker in apex stakingPool.
    /// @param amount yield apex amount to stake.
    function stakeAsPool(address staker, uint256 amount) external;

    /// @notice enlarge lock time of this deposit `depositId` to `lockUntil`
    /// @param depositId the deposit index.
    /// @param lockUntil new lock time.
    function updateStakeLock(uint256 depositId, uint256 lockUntil) external;
}
