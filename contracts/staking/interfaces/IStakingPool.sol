// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IStakingPool {
    struct Deposit {
        uint256 amount;
        uint256 weight;
        uint256 lockFrom;
        uint256 lockDuration;
    }

    struct User {
        uint256 tokenAmount; //vest + stake
        uint256 totalWeight; //stake
        uint256 subYieldRewards;
        Deposit[] deposits; //stake slp/alp
    }

    event BatchWithdraw(address indexed by, uint256[] _depositIds, uint256[] _depositAmounts);

    event Staked(address indexed to, uint256 depositId, uint256 amount, uint256 lockFrom, uint256 lockUntil);

    event Synchronized(address indexed by, uint256 yieldRewardsPerWeight);

    event UpdateStakeLock(address indexed by, uint256 depositId, uint256 lockFrom, uint256 lockUntil);

    event MintEsApeX(address to, uint256 amount);

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

    function initialize(address _factory, address _poolToken) external;

    /// @notice Process yield reward (esApeX) of msg.sender
    function processRewards() external;

    /// @notice Stake poolToken
    /// @param amount poolToken's amount to stake.
    /// @param _lockDuration time to lock.
    function stake(uint256 amount, uint256 _lockDuration) external;

    /// @notice BatchWithdraw poolToken
    /// @param depositIds the deposit index.
    /// @param depositAmounts poolToken's amount to unstake.
    function batchWithdraw(uint256[] memory depositIds, uint256[] memory depositAmounts) external;

    /// @notice enlarge lock time of this deposit `depositId` to `lockDuration`
    /// @param depositId the deposit index.
    /// @param _lockDuration new lock time.
    function updateStakeLock(uint256 depositId, uint256 _lockDuration) external;
}
