// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IStakingPoolFactory {
    struct PoolInfo {
        address pool;
        uint256 weight;
    }

    event WeightUpdated(address indexed by, address indexed pool, uint256 weight);

    event PoolRegistered(address indexed by, address indexed poolToken, address indexed pool, uint256 weight);

    event SetYieldLockTime(uint256 yieldLockTime);

    event UpdateApeXPerBlock(uint256 apeXPerBlock);

    event TransferYieldTo(address by, address to, uint256 amount);

    /// @notice get the endBlock number to yield, after this, no yield reward
    function endBlock() external view returns (uint256);

    function yieldLockTime() external view returns (uint256);

    /// @notice get stakingPool's poolToken
    function poolTokenMap(address pool) external view returns (address);

    /// @notice get stakingPool's address of poolToken
    /// @param poolToken staked token.
    function getPoolAddress(address poolToken) external view returns (address);

    function shouldUpdateRatio() external view returns (bool);

    /// @notice calculate yield reward of poolToken since lastYieldDistribution
    /// @param poolToken staked token.
    function calStakingPoolApeXReward(uint256 lastYieldDistribution, address poolToken)
        external
        view
        returns (uint256 reward);

    /// @notice update yield reward rate
    function updateApeXPerBlock() external;

    /// @notice create a new stakingPool
    /// @param poolToken stakingPool staked token.
    /// @param initBlock when to yield reward.
    /// @param weight new pool's weight between all other stakingPools.
    function createPool(
        address poolToken,
        uint256 initBlock,
        uint256 weight
    ) external;

    /// @notice register an exist pool to factory
    /// @param pool the exist pool.
    /// @param weight pool's weight between all other stakingPools.
    function registerPool(address pool, uint256 weight) external;

    /// @notice mint apex to staker
    /// @param _to the staker.
    /// @param _amount apex amount.
    function transferYieldTo(address _to, uint256 _amount) external;

    /// @notice change a pool's weight
    /// @param poolAddr the pool.
    /// @param weight new weight.
    function changePoolWeight(address poolAddr, uint256 weight) external;
}
