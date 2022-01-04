// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IStakingPool.sol";
import "./interfaces/IStakingPoolFactory.sol";
import "../utils/Initializable.sol";
import "../utils/Ownable.sol";
import "./StakingPool.sol";

//this is a stakingPool factory to create and register stakingPool, distribute ApeX token according to pools' weight
contract StakingPoolFactory is IStakingPoolFactory, Ownable, Initializable {
    address public apeX;
    uint256 public blocksPerUpdate;
    uint256 public apeXPerBlock;
    uint256 public totalWeight;
    uint256 public override endBlock;
    uint256 public lastUpdateBlock;
    uint256 public override lockTime; //tocheck if can hardcode, will optimise gas
    uint256 public override minRemainRatioAfterBurn; //10k-based
    mapping(address => PoolInfo) public pools;
    mapping(address => address) public override poolTokenMap;

    //upgradableProxy StakingPoolFactory only initialized once
    function initialize(
        address _apeX,
        uint256 _apeXPerBlock,
        uint256 _blocksPerUpdate,
        uint256 _initBlock,
        uint256 _endBlock
    ) public initializer {
        require(_apeX != address(0), "cpf.initialize: INVALID_APEX");
        require(_apeXPerBlock > 0, "cpf.initialize: INVALID_PER_BLOCK");
        require(_blocksPerUpdate > 0, "cpf.initialize: INVALID_UPDATE_SPAN");
        require(_initBlock > 0, "cpf.initialize: INVALID_INIT_BLOCK");
        require(_endBlock > _initBlock, "cpf.initialize: INVALID_ENDBLOCK");

        owner = msg.sender;
        apeX = _apeX;
        apeXPerBlock = _apeXPerBlock;
        blocksPerUpdate = _blocksPerUpdate;
        lastUpdateBlock = _initBlock;
        endBlock = _endBlock;
    }

    function createPool(
        address _poolToken,
        uint256 _initBlock,
        uint256 _weight
    ) external override onlyOwner {
        IStakingPool pool = new StakingPool(address(this), _poolToken, apeX, _initBlock);
        registerPool(address(pool), _weight);
    }

    function registerPool(address _pool, uint256 _weight) public override onlyOwner {
        require(poolTokenMap[_pool] == address(0), "cpf.registerPool: POOL_REGISTERED");
        address poolToken = IStakingPool(_pool).poolToken();
        require(poolToken != address(0), "cpf.registerPool: ZERO_ADDRESS");

        pools[poolToken] = PoolInfo({pool: _pool, weight: _weight});
        poolTokenMap[_pool] = poolToken;
        totalWeight += _weight;

        emit PoolRegistered(msg.sender, poolToken, _pool, _weight);
    }

    function updateApeXPerBlock() external override {
        uint256 blockNumber = block.number;

        require(
            blockNumber <= endBlock && blockNumber >= lastUpdateBlock + blocksPerUpdate,
            "cpf.updateApeXPerBlock: TOO_FREQUENT"
        );

        apeXPerBlock = (apeXPerBlock * 97) / 100;
        lastUpdateBlock = block.number;

        emit UpdateApeXPerBlock(apeXPerBlock);
    }

    function transferYieldTo(address _to, uint256 _amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "cpf.transferYieldTo: ACCESS_DENIED");

        IERC20(apeX).transfer(_to, _amount);
        emit TransferYieldTo(msg.sender, _to, _amount);
    }

    function changePoolWeight(address _pool, uint256 _weight) external override onlyOwner {
        address poolToken = poolTokenMap[_pool];
        require(poolToken != address(0), "cpf.changePoolWeight: POOL_NOT_EXIST");

        totalWeight = totalWeight + _weight - pools[poolToken].weight;
        pools[poolToken].weight = _weight;

        emit WeightUpdated(msg.sender, _pool, _weight);
    }

    function setYieldLockTime(uint256 _yieldLockTime) external onlyOwner {
        require(_yieldLockTime > yieldLockTime, "cpf.setYieldLockTime: INVALID_YIELDLOCKTIME");
        yieldLockTime = _yieldLockTime;

        emit SetYieldLockTime(_yieldLockTime);
    }

    function setMinRemainRatioAfterBurn(uint256 _minRemainRatioAfterBurn) external override onlyOwner {
        require(_minRemainRatioAfterBurn <= 10000, "cpf.setMinRemainRatioAfterBurn: INVALID_VALUE");
        minRemainRatioAfterBurn = _minRemainRatioAfterBurn;
    }

    function calStakingPoolApeXReward(uint256 _lastYieldDistribution, address _poolToken)
        external
        view
        override
        returns (uint256 reward)
    {
        uint256 blockNumber = block.number;
        uint256 blocksPassed = blockNumber > endBlock
            ? endBlock - _lastYieldDistribution
            : blockNumber - _lastYieldDistribution;
        //@audit - if no claim, shrinking reward make sense?
        reward = (blocksPassed * apeXPerBlock * pools[_poolToken].weight) / totalWeight;
    }

    function shouldUpdateRatio() external view override returns (bool) {
        uint256 blockNumber = block.number;
        return blockNumber > endBlock ? false : blockNumber >= lastUpdateBlock + blocksPerUpdate;
    }

    function getPoolAddress(address _poolToken) external view override returns (address) {
        return pools[_poolToken].pool;
    }
}
