// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IStakingPoolFactory {
    
    struct PoolWeight {
        uint256 weight;
        uint256 lastYieldPriceOfWeight; //multiplied by 10000
        uint256 exitYieldPriceOfWeight;
    }

    event WeightUpdated(address indexed by, address indexed pool, uint256 weight);

    event PoolRegistered(address indexed by, address indexed poolToken, address indexed pool, uint256 weight);

    event PoolUnRegistered(address indexed by, address indexed pool);

    event SetYieldLockTime(uint256 yieldLockTime);

    event UpdateApeXPerSec(uint256 apeXPerSec);

    event TransferYieldTo(address by, address to, uint256 amount);

    event TransferYieldToTreasury(address by, address to, uint256 amount);

    event TransferEsApeXTo(address by, address to, uint256 amount);

    event TransferEsApeXFrom(address from, address to, uint256 amount);

    event SetEsApeX(address esApeX);

    event SetVeApeX(address veApeX);

    event SetStakingPoolTemplate(address oldTemplate, address newTemplate);

    event SyncYieldPriceOfWeight(uint256 oldYieldPriceOfWeight, uint256 newYieldPriceOfWeight);

    event WithdrawApeX(address to, uint256 amount);

    event SetRemainForOtherVest(uint256);

    event SetMinRemainRatioAfterBurn(uint256);

    function apeX() external view returns (address);

    function esApeX() external view returns (address);

    function veApeX() external view returns (address);

    function treasury() external view returns (address);

    function lastUpdateTimestamp() external view returns (uint256);

    function secSpanPerUpdate() external view returns (uint256);

    function apeXPerSec() external view returns (uint256);

    function totalWeight() external view returns (uint256);

    function stakingPoolTemplate() external view returns (address);

    /// @notice get the end timestamp to yield, after this, no yield reward
    function endTimestamp() external view returns (uint256);

    function lockTime() external view returns (uint256);

    /// @notice get minimum remain ratio after force withdraw
    function minRemainRatioAfterBurn() external view returns (uint256);

    function remainForOtherVest() external view returns (uint256);

    /// @notice check if can update reward ratio
    function shouldUpdateRatio() external view returns (bool);

    /// @notice calculate yield reward of poolToken since lastYieldPriceOfWeight
    function calStakingPoolApeXReward(address token) external view returns (uint256 reward, uint256 newPriceOfWeight);

    function calPendingFactoryReward() external view returns (uint256 reward);

    function calLatestPriceOfWeight() external view returns (uint256);

    function syncYieldPriceOfWeight() external returns (uint256 reward);

    /// @notice update yield reward rate
    function updateApeXPerSec() external;

    function setStakingPoolTemplate(address _template) external;

    /// @notice create a new stakingPool
    /// @param poolToken stakingPool staked token.
    /// @param weight new pool's weight between all other stakingPools.
    function createPool(address poolToken, uint256 weight) external;

    /// @notice register apeX pool to factory
    /// @param pool the exist pool.
    /// @param weight pool's weight between all other stakingPools.
    function registerApeXPool(address pool, uint256 weight) external;

    /// @notice unregister an exist pool
    function unregisterPool(address pool) external;

    /// @notice mint apex to staker
    /// @param to the staker.
    /// @param amount apex amount.
    function transferYieldTo(address to, uint256 amount) external;

    function transferYieldToTreasury(uint256 amount) external;

    function withdrawApeX(address to, uint256 amount) external;

    /// @notice change a pool's weight
    /// @param poolAddr the pool.
    /// @param weight new weight.
    function changePoolWeight(address poolAddr, uint256 weight) external;

    /// @notice set minimum reward ratio when force withdraw locked rewards
    function setMinRemainRatioAfterBurn(uint256 _minRemainRatioAfterBurn) external;

    function setRemainForOtherVest(uint256 _remainForOtherVest) external;

    function mintEsApeX(address to, uint256 amount) external;

    function burnEsApeX(address from, uint256 amount) external;

    function transferEsApeXTo(address to, uint256 amount) external;

    function transferEsApeXFrom(
        address from,
        address to,
        uint256 amount
    ) external;

    function mintVeApeX(address to, uint256 amount) external;

    function burnVeApeX(address from, uint256 amount) external;

    function setEsApeX(address _esApeX) external;

    function setVeApeX(address _veApeX) external;
}
