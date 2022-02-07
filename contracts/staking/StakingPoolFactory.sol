// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IStakingPool.sol";
import "./interfaces/IStakingPoolFactory.sol";
import "../utils/Initializable.sol";
import "../utils/Ownable.sol";
import "./StakingPool.sol";
import "./interfaces/IERC20Extend.sol";

//this is a stakingPool factory to create and register stakingPool, distribute ApeX token according to pools' weight
contract StakingPoolFactory is IStakingPoolFactory, Ownable, Initializable {
    address public override apeX;
    address public esApeX;
    uint256 public override lastUpdateTimestamp;
    uint256 public override secSpanPerUpdate;
    uint256 public override apeXPerSec;
    uint256 public override totalWeight;
    uint256 public override endTimestamp;
    uint256 public override lockTime;
    uint256 public override minRemainRatioAfterBurn; //10k-based
    mapping(address => PoolInfo) public pools;
    mapping(address => address) public override poolTokenMap;

    //upgradableProxy StakingPoolFactory only initialized once
    function initialize(
        address _apeX,
        address _esApeX,
        uint256 _apeXPerSec,
        uint256 _secSpanPerUpdate,
        uint256 _initTimestamp,
        uint256 _endTimestamp,
        uint256 _lockTime
    ) public initializer {
        require(_apeX != address(0), "cpf.initialize: INVALID_APEX");
        require(_esApeX != address(0), "cpf.initialize: INVALID_ESAPEX");
        require(_apeXPerSec > 0, "cpf.initialize: INVALID_PER_SEC");
        require(_secSpanPerUpdate > 0, "cpf.initialize: INVALID_UPDATE_SPAN");
        require(_initTimestamp > 0, "cpf.initialize: INVALID_INIT_TIMESTAMP");
        require(_endTimestamp > _initTimestamp, "cpf.initialize: INVALID_END_TIMESTAMP");
        require(_lockTime > 0, "cpf.initialize: INVALID_LOCK_TIME");

        owner = msg.sender;
        apeX = _apeX;
        esApeX = _esApeX;
        apeXPerSec = _apeXPerSec;
        secSpanPerUpdate = _secSpanPerUpdate;
        lastUpdateTimestamp = _initTimestamp;
        endTimestamp = _endTimestamp;
        lockTime = _lockTime;
    }

    function createPool(
        address _poolToken,
        uint256 _initTimestamp,
        uint256 _weight
    ) external override onlyOwner {
        IStakingPool pool = new StakingPool(address(this), _poolToken, apeX, _initTimestamp);
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

    function unregisterPool(address _pool) external override onlyOwner {
        require(poolTokenMap[_pool] != address(0), "cpf.unregisterPool: POOL_NOT_REGISTERED");
        address poolToken = IStakingPool(_pool).poolToken();

        totalWeight -= pools[poolToken].weight;
        delete pools[poolToken];
        delete poolTokenMap[_pool];

        emit PoolUnRegistered(msg.sender, poolToken, _pool);
    }

    function updateApeXPerSec() external override {
        uint256 currentTimestamp = block.timestamp;

        require(currentTimestamp >= lastUpdateTimestamp + secSpanPerUpdate, "cpf.updateApeXPerSec: TOO_FREQUENT");
        require(currentTimestamp <= endTimestamp, "cpf.updateApeXPerSec: END");

        apeXPerSec = (apeXPerSec * 97) / 100;
        lastUpdateTimestamp = currentTimestamp;

        emit UpdateApeXPerSec(apeXPerSec);
    }

    function transferYieldTo(address _to, uint256 _amount) external override {
        require(pools[apeX].pool != msg.sender, "cpf.transferYieldTo: ACCESS_DENIED");

        emit TransferYieldTo(msg.sender, _to, _amount);
        IERC20(apeX).transfer(_to, _amount);
    }

    function transferEsApeXTo(address _to, uint256 _amount) external override {
        require(pools[apeX].pool != msg.sender, "cpf.transferEsApeXTo: ACCESS_DENIED");

        emit TransferEsApeXTo(msg.sender, _to, _amount);
        IERC20(esApeX).transfer(_to, _amount);
    }

    function transferEsApeXFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external override {
        require(pools[apeX].pool != msg.sender, "cpf.transferEsApeXFrom: ACCESS_DENIED");

        emit TransferEsApeXFrom(_from, _to, _amount);
        IERC20(esApeX).transferFrom(_from, _to, _amount);
    }

    function burnEsApeX(address from, uint256 amount) external override {
        require(pools[apeX].pool != msg.sender, "cpf.burnEsApeX: ACCESS_DENIED");
        IERC20Extend(esApeX).burn(from, amount);
    }

    function mintEsApeX(address to, uint256 amount) external override {
        require(pools[apeX].pool != msg.sender, "cpf.mintEsApeX: ACCESS_DENIED");
        IERC20Extend(esApeX).mint(to, amount);
    }

    function changePoolWeight(address _pool, uint256 _weight) external override onlyOwner {
        address poolToken = poolTokenMap[_pool];
        require(poolToken != address(0), "cpf.changePoolWeight: POOL_NOT_EXIST");

        totalWeight = totalWeight + _weight - pools[poolToken].weight;
        pools[poolToken].weight = _weight;

        emit WeightUpdated(msg.sender, _pool, _weight);
    }

    function setLockTime(uint256 _lockTime) external onlyOwner {
        require(_lockTime > lockTime, "cpf.setLockTime: INVALID_LOCK_TIME");
        lockTime = _lockTime;

        emit SetYieldLockTime(_lockTime);
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
        uint256 currentTimestamp = block.timestamp;
        uint256 secPassed = currentTimestamp > endTimestamp
            ? endTimestamp - _lastYieldDistribution
            : currentTimestamp - _lastYieldDistribution;

        reward = (secPassed * apeXPerSec * pools[_poolToken].weight) / totalWeight;
    }

    function shouldUpdateRatio() external view override returns (bool) {
        uint256 currentTimestamp = block.timestamp;
        return currentTimestamp > endTimestamp ? false : currentTimestamp >= lastUpdateTimestamp + secSpanPerUpdate;
    }

    function getPoolAddress(address _poolToken) external view override returns (address) {
        return pools[_poolToken].pool;
    }

    //just for dev use
    function setApeXPerSec(uint256 _apeXPerSec) external onlyOwner {
        apeXPerSec = _apeXPerSec;
    }
}
