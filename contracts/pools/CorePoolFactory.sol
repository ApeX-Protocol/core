// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/ICorePool.sol";
import "../interfaces/ICorePoolFactory.sol";
import "../libraries/ApexAware.sol";
import "../utils/Initializable.sol";
import "../utils/Ownable.sol";
import "./CorePool.sol";

contract CorePoolFactory is ICorePoolFactory, Ownable, ApexAware, Initializable {
    uint256 public blocksPerUpdate;

    uint256 public apexPerBlock;

    uint256 public totalWeight;

    uint256 public override endBlock;

    uint256 public lastRatioUpdate;

    mapping(address => PoolInfo) public pools;

    mapping(address => address) public override poolTokenMap;

    function initialize(
        address _apex,
        uint256 _apexPerBlock,
        uint256 _blocksPerUpdate,
        uint256 _initBlock,
        uint256 _endBlock
    ) public initializer {
        require(_apex != address(0), "apex address not set");
        require(_apexPerBlock > 0, "APEX/block not set");
        require(_blocksPerUpdate > 0, "blocks/update not set");
        require(_initBlock > 0, "init block not set");
        require(_endBlock > _initBlock, "invalid end block: must be greater than init block");

        admin = msg.sender;
        entered = false;
        apex = _apex;
        apexPerBlock = _apexPerBlock;
        blocksPerUpdate = _blocksPerUpdate;
        lastRatioUpdate = _initBlock;
        endBlock = _endBlock;
    }

    function createPool(
        address _poolToken,
        uint256 _initBlock,
        uint256 _weight
    ) external virtual override onlyAdmin {
        ICorePool pool = new CorePool(address(this), _poolToken, apex, _initBlock);
        registerPool(address(pool), _weight);
    }

    function registerPool(address _pool, uint256 _weight) public override onlyAdmin {
        require(poolTokenMap[_pool] == address(0), "this pool is already registered");
        address poolToken = ICorePool(_pool).poolToken();
        require(poolToken != address(0), "address is 0");

        pools[poolToken] = PoolInfo({pool: _pool, weight: _weight});
        poolTokenMap[_pool] = poolToken;
        totalWeight += _weight;

        emit PoolRegistered(msg.sender, poolToken, _pool, _weight);
    }

    function updateApexPerBlock() external override {
        require(shouldUpdateRatio(), "too frequent");

        apexPerBlock = (apexPerBlock * 97) / 100;
        lastRatioUpdate = block.number;
    }

    function mintYieldTo(address _to, uint256 _amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "access denied");

        mintApex(_to, _amount);
    }

    function changePoolWeight(address _pool, uint256 _weight) external override {
        require(msg.sender == admin || poolTokenMap[msg.sender] != address(0));
        address poolToken = poolTokenMap[_pool];
        require(poolToken != address(0), "pool not exist");

        totalWeight = totalWeight + _weight - pools[poolToken].weight;
        pools[poolToken].weight = _weight;

        emit WeightUpdated(msg.sender, _pool, _weight);
    }

    function calCorePoolApexReward(uint256 _lastYieldDistribution, address _poolToken)
        external
        view
        override
        returns (uint256 reward)
    {
        uint256 blockNumber = block.number;
        uint256 blocksPassed = blockNumber > endBlock
            ? endBlock - _lastYieldDistribution
            : blockNumber - _lastYieldDistribution;

        reward = (blocksPassed * apexPerBlock * pools[_poolToken].weight) / totalWeight;
    }

    function shouldUpdateRatio() public view override returns (bool) {
        uint256 blockNumber = block.number;
        return blockNumber > endBlock ? false : blockNumber >= lastRatioUpdate + blocksPerUpdate;
    }

    function getPoolAddress(address _poolToken) external view override returns (address) {
        return pools[_poolToken].pool;
    }
}
