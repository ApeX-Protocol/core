// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface ICorePoolFactory {
    struct PoolInfo {
        address pool;
        uint256 weight;
    }

    event WeightUpdated(address indexed _by, address indexed pool, uint256 weight);

    event PoolRegistered(address indexed _by, address indexed poolToken, address indexed pool, uint256 weight);

    function endBlock() external view returns (uint256);

    function shouldUpdateRatio() external view returns (bool);

    function poolTokenMap(address pool) external view returns (address);

    function getPoolAddress(address poolToken) external view returns (address);

    function calCorePoolApexReward(uint256 lastYieldDistribution, address poolToken)
        external
        view
        returns (uint256 reward);

    function updateApexPerBlock() external;

    function createPool(
        address poolToken,
        uint256 initBlock,
        uint256 weight
    ) external;

    function registerPool(address pool, uint256 weight) external;

    function mintYieldTo(address _to, uint256 _amount) external;

    function changePoolWeight(address poolAddr, uint256 weight) external;
}
