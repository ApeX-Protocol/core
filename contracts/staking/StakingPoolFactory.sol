// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IStakingPool.sol";
import "./interfaces/IApeXPool.sol";
import "./interfaces/IStakingPoolFactory.sol";
import "../utils/Initializable.sol";
import "../utils/Ownable.sol";
import "./StakingPool.sol";
import "./interfaces/IERC20Extend.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

//this is a stakingPool factory to create and register stakingPool, distribute esApeX token according to pools' weight
contract StakingPoolFactory is IStakingPoolFactory, Ownable, Initializable {
    uint256 constant tenK = 10000;
    address public override apeX;
    address public override esApeX;
    address public override veApeX;
    address public override treasury;
    uint256 public override lastUpdateTimestamp;
    uint256 public override secSpanPerUpdate;
    uint256 public override apeXPerSec;
    uint256 public override totalWeight;
    uint256 public override endTimestamp;
    uint256 public override lockTime;
    uint256 public override minRemainRatioAfterBurn; //10k-based
    uint256 public override remainForOtherVest; //100-based
    uint256 public priceOfWeight; //multiplied by 10k
    uint256 public lastTimeUpdatePriceOfWeight;
    address public override stakingPoolTemplate;
    mapping(address => PoolInfo) public pools;
    mapping(address => address) public override poolTokenMap;

    function initialize(
        address _apeX,
        address _treasury,
        uint256 _apeXPerSec,
        uint256 _secSpanPerUpdate,
        uint256 _initTimestamp,
        uint256 _endTimestamp,
        uint256 _lockTime
    ) public initializer {
        require(_apeX != address(0), "spf.initialize: INVALID_APEX");
        require(_treasury != address(0), "spf.initialize: INVALID_TREASURY");
        require(_apeXPerSec > 0, "spf.initialize: INVALID_PER_SEC");
        require(_secSpanPerUpdate > 0, "spf.initialize: INVALID_UPDATE_SPAN");
        require(_initTimestamp > 0, "spf.initialize: INVALID_INIT_TIMESTAMP");
        require(_endTimestamp > _initTimestamp, "spf.initialize: INVALID_END_TIMESTAMP");
        require(_lockTime > 0, "spf.initialize: INVALID_LOCK_TIME");

        owner = msg.sender;
        apeX = _apeX;
        treasury = _treasury;
        apeXPerSec = _apeXPerSec;
        secSpanPerUpdate = _secSpanPerUpdate;
        lastUpdateTimestamp = _initTimestamp;
        endTimestamp = _endTimestamp;
        lockTime = _lockTime;
        lastTimeUpdatePriceOfWeight = _initTimestamp;
    }

    function setStakingPoolTemplate(address _template) external onlyOwner {
        require(_template != address(0), "spf.setStakingPoolTemplate: ZERO_ADDRESS");

        emit SetStakingPoolTemplate(stakingPoolTemplate, _template);
        stakingPoolTemplate = _template;
    }

    function createPool(
        address _poolToken,
        uint256 _initPriceOfWeight,
        uint256 _weight
    ) external override onlyOwner {
        require(_poolToken != apeX, "spf.createPool: CANT_APEX");
        require(stakingPoolTemplate != address(0), "spf.createPool: ZERO_TEMPLATE");
        require(_poolToken != address(0), "spf.createPool: ZERO_ADDRESS");

        address pool = Clones.clone(stakingPoolTemplate);
        uint256 initPriceOfWeight = priceOfWeight + ((calPendingFactoryReward() * tenK) / totalWeight);
        if (_initPriceOfWeight == 0) {
            _initPriceOfWeight = initPriceOfWeight;
        } else {
            require(initPriceOfWeight <= _initPriceOfWeight, "spf.createPool: CANT_MINE_EARLIER");
        }

        IStakingPool(pool).initialize(address(this), _poolToken, initPriceOfWeight);

        _registerPool(pool, _weight, _poolToken);
    }

    function registerApeXPool(address _pool, uint256 _weight) external override onlyOwner {
        address poolToken = IApeXPool(_pool).poolToken();
        require(poolToken == apeX, "spf.registerApeXPool: MUST_APEX");
        uint256 initPriceOfWeight = priceOfWeight;
        if (totalWeight > 0) {
            initPriceOfWeight += ((calPendingFactoryReward() * tenK) / totalWeight);
        }

        require(
            IApeXPool(_pool).lastYieldPriceOfWeight() >= initPriceOfWeight,
            "spf.registerApeXPool: CANT_MINE_EARLIER"
        );
        _registerPool(_pool, _weight, poolToken);
    }

    function _registerPool(
        address _pool,
        uint256 _weight,
        address _poolToken
    ) internal {
        require(poolTokenMap[_pool] == address(0), "spf.registerPool: POOL_REGISTERED");
        require(pools[_poolToken].pool == address(0), "spf.registerPool: POOL_TOKEN_REGISTERED");

        if (totalWeight != 0) {
            priceOfWeight += ((calPendingFactoryReward() * tenK) / totalWeight);
            lastTimeUpdatePriceOfWeight = block.timestamp;
        }

        pools[_poolToken] = PoolInfo({pool: _pool, weight: _weight});
        poolTokenMap[_pool] = _poolToken;
        totalWeight += _weight;

        emit PoolRegistered(msg.sender, _poolToken, _pool, _weight);
    }

    function unregisterPool(address _pool) external override onlyOwner {
        require(poolTokenMap[_pool] != address(0), "spf.unregisterPool: POOL_NOT_REGISTERED");
        address poolToken = IStakingPool(_pool).poolToken();

        priceOfWeight += ((calPendingFactoryReward() * tenK) / totalWeight);
        lastTimeUpdatePriceOfWeight = block.timestamp;

        totalWeight -= pools[poolToken].weight;
        delete pools[poolToken];
        delete poolTokenMap[_pool];

        emit PoolUnRegistered(msg.sender, poolToken, _pool);
    }

    function changePoolWeight(address _pool, uint256 _weight) external override onlyOwner {
        address poolToken = poolTokenMap[_pool];
        require(poolToken != address(0), "spf.changePoolWeight: POOL_NOT_EXIST");
        require(_weight != 0, "spf.changePoolWeight: CANT_CHANGE_TO_ZERO_WEIGHT");

        if (totalWeight != 0) {
            priceOfWeight += ((calPendingFactoryReward() * tenK) / totalWeight);
            lastTimeUpdatePriceOfWeight = block.timestamp;
        }

        totalWeight = totalWeight + _weight - pools[poolToken].weight;
        pools[poolToken].weight = _weight;

        emit WeightUpdated(msg.sender, _pool, _weight);
    }

    function updateApeXPerSec() external override {
        uint256 currentTimestamp = block.timestamp;
        require(currentTimestamp >= lastUpdateTimestamp + secSpanPerUpdate, "spf.updateApeXPerSec: TOO_FREQUENT");
        require(currentTimestamp <= endTimestamp, "spf.updateApeXPerSec: END");

        apeXPerSec = (apeXPerSec * 97) / 100;
        lastUpdateTimestamp = currentTimestamp;

        emit UpdateApeXPerSec(apeXPerSec);
    }

    function transferYieldTo(address _to, uint256 _amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "spf.transferYieldTo: ACCESS_DENIED");

        emit TransferYieldTo(msg.sender, _to, _amount);
        IERC20(apeX).transfer(_to, _amount);
    }

    function transferYieldToTreasury(uint256 _amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "spf.transferYieldToTreasury: ACCESS_DENIED");

        address _treasury = treasury;
        emit TransferYieldToTreasury(msg.sender, _treasury, _amount);
        IERC20(apeX).transfer(_treasury, _amount);
    }

    function transferEsApeXTo(address _to, uint256 _amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "spf.transferEsApeXTo: ACCESS_DENIED");

        emit TransferEsApeXTo(msg.sender, _to, _amount);
        IERC20(esApeX).transfer(_to, _amount);
    }

    function transferEsApeXFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external override {
        require(poolTokenMap[msg.sender] != address(0), "spf.transferEsApeXFrom: ACCESS_DENIED");

        emit TransferEsApeXFrom(_from, _to, _amount);
        IERC20(esApeX).transferFrom(_from, _to, _amount);
    }

    function burnEsApeX(address from, uint256 amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "spf.burnEsApeX: ACCESS_DENIED");
        IERC20Extend(esApeX).burn(from, amount);
    }

    function mintEsApeX(address to, uint256 amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "spf.mintEsApeX: ACCESS_DENIED");
        IERC20Extend(esApeX).mint(to, amount);
    }

    function burnVeApeX(address from, uint256 amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "spf.burnVeApeX: ACCESS_DENIED");
        IERC20Extend(veApeX).burn(from, amount);
    }

    function mintVeApeX(address to, uint256 amount) external override {
        require(poolTokenMap[msg.sender] != address(0), "spf.mintVeApeX: ACCESS_DENIED");
        IERC20Extend(veApeX).mint(to, amount);
    }

    function setLockTime(uint256 _lockTime) external onlyOwner {
        lockTime = _lockTime;

        emit SetYieldLockTime(_lockTime);
    }

    function setMinRemainRatioAfterBurn(uint256 _minRemainRatioAfterBurn) external override onlyOwner {
        require(_minRemainRatioAfterBurn <= tenK, "spf.setMinRemainRatioAfterBurn: INVALID_VALUE");
        minRemainRatioAfterBurn = _minRemainRatioAfterBurn;
    }

    function setRemainForOtherVest(uint256 _remainForOtherVest) external override onlyOwner {
        require(_remainForOtherVest <= 100, "spf.setRemainForOtherVest: INVALID_VALUE");
        remainForOtherVest = _remainForOtherVest;
    }

    function calPendingFactoryReward() public view returns (uint256 reward) {
        uint256 currentTimestamp = block.timestamp;
        uint256 secPassed = currentTimestamp > endTimestamp
            ? endTimestamp - lastTimeUpdatePriceOfWeight
            : currentTimestamp - lastTimeUpdatePriceOfWeight;
        reward = secPassed * apeXPerSec;
    }

    function calPendingPriceOfWeight() external view returns (uint256) {
        return priceOfWeight + ((calPendingFactoryReward() * tenK) / totalWeight);
    }

    function calStakingPoolApeXReward(uint256 _lastYieldPriceOfWeight, address _poolToken)
        external
        view
        override
        returns (uint256 reward, uint256 newPriceOfWeight)
    {
        newPriceOfWeight = priceOfWeight;
        if (totalWeight > 0) {
            newPriceOfWeight += ((calPendingFactoryReward() * tenK) / totalWeight);
        }
        reward = (pools[_poolToken].weight * (newPriceOfWeight - _lastYieldPriceOfWeight)) / tenK;
    }

    function shouldUpdateRatio() external view override returns (bool) {
        uint256 currentTimestamp = block.timestamp;
        return currentTimestamp > endTimestamp ? false : currentTimestamp >= lastUpdateTimestamp + secSpanPerUpdate;
    }

    function getPoolAddress(address _poolToken) external view override returns (address) {
        return pools[_poolToken].pool;
    }

    function setEsApeX(address _esApeX) external override onlyOwner {
        require(esApeX == address(0), "spf.setEsApeX: INVALID_ADDRESS");
        esApeX = _esApeX;

        emit SetEsApeX(_esApeX);
    }

    function setVeApeX(address _veApeX) external override onlyOwner {
        require(veApeX == address(0), "spf.setVeApeX: INVALID_ADDRESS");
        veApeX = _veApeX;

        emit SetVeApeX(_veApeX);
    }
}
