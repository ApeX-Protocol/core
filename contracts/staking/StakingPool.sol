// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IStakingPool.sol";
import "./interfaces/IStakingPoolFactory.sol";
import "../core/interfaces/IERC20.sol";
import "../utils/Reentrant.sol";

contract StakingPool is IStakingPool, Reentrant {
    uint256 internal constant WEIGHT_MULTIPLIER = 1e6;
    uint256 internal constant MAX_TIME_STAKE_WEIGHT_MULTIPLIER = 2 * WEIGHT_MULTIPLIER;
    uint256 internal constant REWARD_PER_WEIGHT_MULTIPLIER = 1e12;

    address public immutable apex;
    address public immutable override poolToken;
    IStakingPoolFactory public immutable factory;
    uint256 public lastYieldDistribution; //blockNumber
    uint256 public yieldRewardsPerWeight;
    uint256 public usersLockingWeight;
    mapping(address => User) public users;

    constructor(
        address _factory,
        address _poolToken,
        address _apex,
        uint256 _initBlock
    ) {
        require(_factory != address(0), "cp: INVALID_FACTORY");
        require(_apex != address(0), "cp: INVALID_APEX_TOKEN");
        require(_initBlock > 0, "cp: INVALID_INIT_BLOCK");
        require(_poolToken != address(0), "cp: INVALID_POOL_TOKEN");

        apex = _apex;
        factory = IStakingPoolFactory(_factory);
        poolToken = _poolToken;
        lastYieldDistribution = _initBlock;
    }

    function stake(uint256 _amount, uint256 _lockUntil) external override nonReentrant {
        require(_amount > 0, "cp._stake: INVALID_AMOUNT");
        uint256 now256 = block.timestamp;
        //tocheck if must be 6 month, can hardcode
        uint256 yieldLockTime = factory.yieldLockTime();
        require(
            _lockUntil == 0 || (_lockUntil > now256 && _lockUntil <= now256 + yieldLockTime),
            "cp._stake: INVALID_LOCK_INTERVAL"
        );

        address _staker = msg.sender;
        User storage user = users[_staker];
        _processRewards(_staker, user);

        IERC20(poolToken).transferFrom(_staker, address(this), _amount);
        //if 0, not lock
        uint256 lockFrom = _lockUntil > 0 ? now256 : 0;
        uint256 stakeWeight = (((_lockUntil - lockFrom) * WEIGHT_MULTIPLIER) / yieldLockTime + WEIGHT_MULTIPLIER) *
            _amount;

        Deposit memory deposit = Deposit({
            amount: _amount,
            weight: stakeWeight,
            lockFrom: lockFrom,
            lockUntil: _lockUntil,
            isYield: false
        });

        user.deposits.push(deposit);
        user.tokenAmount += _amount;
        user.totalWeight += stakeWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        usersLockingWeight += stakeWeight;

        emit Staked(_staker, _amount, lockFrom, _lockUntil);
    }

    function unstakeBatch(uint256[] memory _depositIds, uint256[] memory _amounts) external override {
        require(_depositIds.length == _amounts.length, "cp.unstakeBatch: INVALID_DEPOSITS_AMOUNTS");
        address _staker = msg.sender;
        uint256 now256 = block.timestamp;
        User storage user = users[_staker];
        _processRewards(_staker, user);
        uint256 yieldLockTime = factory.yieldLockTime();

        uint256 yieldAmount;
        uint256 stakeAmount;
        uint256 _amount;
        uint256 _depositId;
        uint256 previousWeight;
        uint256 newWeight;
        uint256 deltaUsersLockingWeight;
        Deposit memory stakeDeposit;
        for (uint256 i = 0; i < _depositIds.length; i++) {
            _amount = _amounts[i];
            _depositId = _depositIds[i];
            require(_amount != 0, "cp.unstakeBatch: INVALID_AMOUNT");
            stakeDeposit = user.deposits[_depositId];
            require(stakeDeposit.lockFrom == 0 || now256 > stakeDeposit.lockUntil, "cp.unstakeBatch: DEPOSIT_LOCKED");
            require(stakeDeposit.amount >= _amount, "cp.unstakeBatch: EXCEED_STAKED");

            previousWeight = stakeDeposit.weight;
            //tocheck if lockTime is not 1 year?
            newWeight =
                (((stakeDeposit.lockUntil - stakeDeposit.lockFrom) * WEIGHT_MULTIPLIER) /
                    yieldLockTime +
                    WEIGHT_MULTIPLIER) *
                (stakeDeposit.amount - _amount);
            if (stakeDeposit.isYield) {
                yieldAmount += _amount;
            } else {
                stakeAmount += _amount;
            }
            if (stakeDeposit.amount == _amount) {
                delete user.deposits[_depositId];
            } else {
                stakeDeposit.amount -= _amount;
                stakeDeposit.weight = newWeight;
            }

            user.deposits[_depositId] = stakeDeposit;
            user.tokenAmount -= _amount;
            user.totalWeight -= (previousWeight - newWeight);
            deltaUsersLockingWeight += (previousWeight - newWeight);
        }
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        usersLockingWeight -= deltaUsersLockingWeight;

        if (yieldAmount > 0) {
            factory.transferYieldTo(_staker, yieldAmount);
        }
        if (stakeAmount > 0) {
            IERC20(poolToken).transfer(_staker, stakeAmount);
        }
    }

    //called by other staking pool to stake yield rewards into apeX pool
    function stakeAsPool(address _staker, uint256 _amount) external override {
        require(factory.poolTokenMap(msg.sender) != address(0), "cp.stakeAsPool: ACCESS_DENIED");
        syncWeightPrice(); //need sync apexStakingPool

        User storage user = users[_staker];

        uint256 pendingYield = (user.totalWeight * yieldRewardsPerWeight) /
            REWARD_PER_WEIGHT_MULTIPLIER -
            user.subYieldRewards;
        uint256 yieldAmount = _amount + pendingYield;
        uint256 yieldWeight = yieldAmount * MAX_TIME_STAKE_WEIGHT_MULTIPLIER;
        uint256 now256 = block.timestamp;
        uint256 lockUntil = now256 + factory.yieldLockTime();
        Deposit memory newDeposit = Deposit({
            amount: yieldAmount,
            weight: yieldWeight,
            lockFrom: now256,
            lockUntil: lockUntil,
            isYield: true
        });
        user.deposits.push(newDeposit);

        user.tokenAmount += yieldAmount;
        user.totalWeight += yieldWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        usersLockingWeight += yieldWeight;

        emit StakeAsPool(msg.sender, _staker, _amount, yieldAmount, now256, lockUntil);
    }

    //only can extend lock time
    function updateStakeLock(uint256 _depositId, uint256 _lockUntil) external override {
        uint256 now256 = block.timestamp;
        require(_lockUntil > now256, "cp.updateStakeLock: INVALID_LOCK_UNTIL");

        uint256 yieldLockTime = factory.yieldLockTime();
        address _staker = msg.sender;
        User storage user = users[_staker];
        Deposit storage stakeDeposit = user.deposits[_depositId];
        require(_lockUntil > stakeDeposit.lockUntil, "cp.updateStakeLock: INVALID_NEW_LOCK");

        if (stakeDeposit.lockFrom == 0) {
            require(_lockUntil <= now256 + yieldLockTime, "cp.updateStakeLock: EXCEED_MAX_LOCK_PERIOD");
            stakeDeposit.lockFrom = now256;
        } else {
            require(_lockUntil <= stakeDeposit.lockFrom + yieldLockTime, "cp.updateStakeLock: EXCEED_MAX_LOCK");
        }

        stakeDeposit.lockUntil = _lockUntil;
        uint256 newWeight = (((stakeDeposit.lockUntil - stakeDeposit.lockFrom) * WEIGHT_MULTIPLIER) /
            yieldLockTime +
            WEIGHT_MULTIPLIER) * stakeDeposit.amount;
        uint256 previousWeight = stakeDeposit.weight;
        stakeDeposit.weight = newWeight;
        user.totalWeight = user.totalWeight - previousWeight + newWeight;
        usersLockingWeight = usersLockingWeight - previousWeight + newWeight;

        emit UpdateStakeLock(_staker, _depositId, stakeDeposit.lockFrom, _lockUntil);
    }

    function processRewards() external override {
        address staker = msg.sender;
        User storage user = users[staker];

        _processRewards(staker, user);
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
    }

    function syncWeightPrice() public {
        if (factory.shouldUpdateRatio()) {
            factory.updateApeXPerBlock();
        }

        uint256 endBlock = factory.endBlock();
        uint256 currentBlockNumber = block.number;
        if (lastYieldDistribution >= endBlock || lastYieldDistribution >= currentBlockNumber) {
            return;
        }
        if (usersLockingWeight == 0) {
            lastYieldDistribution = currentBlockNumber;
            return;
        }
        //@notice: if nobody sync this stakingPool for a long time, this stakingPool reward shrink
        uint256 apexReward = factory.calStakingPoolApeXReward(lastYieldDistribution, poolToken);
        yieldRewardsPerWeight += (apexReward * REWARD_PER_WEIGHT_MULTIPLIER) / usersLockingWeight;
        lastYieldDistribution = currentBlockNumber > endBlock ? endBlock : currentBlockNumber;

        emit Synchronized(msg.sender, yieldRewardsPerWeight, lastYieldDistribution);
    }

    //update weight price, then if apex, add deposits; if not, stake as pool.
    function _processRewards(address _staker, User storage user) internal {
        syncWeightPrice();

        //if no yield
        if (user.tokenAmount == 0) return;
        uint256 yieldAmount = (user.totalWeight * yieldRewardsPerWeight) /
            REWARD_PER_WEIGHT_MULTIPLIER -
            user.subYieldRewards;
        if (yieldAmount == 0) return;

        //if self is apeX pool, lock the yield reward; if not, stake the yield reward to apeX pool.
        if (poolToken == apex) {
            uint256 yieldWeight = yieldAmount * MAX_TIME_STAKE_WEIGHT_MULTIPLIER;
            uint256 now256 = block.timestamp;
            uint256 lockUntil = now256 + factory.yieldLockTime();
            Deposit memory newDeposit = Deposit({
                amount: yieldAmount,
                weight: yieldWeight,
                lockFrom: now256,
                lockUntil: lockUntil,
                isYield: true
            });
            user.deposits.push(newDeposit);
            user.tokenAmount += yieldAmount;
            user.totalWeight += yieldWeight;
            usersLockingWeight += yieldWeight;
            emit YieldClaimed(_staker, _staker, yieldAmount, now256, lockUntil);
        } else {
            address apexStakingPool = factory.getPoolAddress(apex);
            IStakingPool(apexStakingPool).stakeAsPool(_staker, yieldAmount);
        }
    }

    function pendingYieldRewards(address _staker) external view returns (uint256 pending) {
        uint256 newYieldRewardsPerWeight = yieldRewardsPerWeight;

        if (block.number > lastYieldDistribution && usersLockingWeight != 0) {
            uint256 apexReward = factory.calStakingPoolApeXReward(lastYieldDistribution, poolToken);
            newYieldRewardsPerWeight += (apexReward * REWARD_PER_WEIGHT_MULTIPLIER) / usersLockingWeight;
        }

        User memory user = users[_staker];
        pending = (user.totalWeight * newYieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER - user.subYieldRewards;
    }

    function getDeposit(address _user, uint256 _depositId) external view returns (Deposit memory) {
        return users[_user].deposits[_depositId];
    }

    function getDepositsLength(address _user) external view returns (uint256) {
        return users[_user].deposits.length;
    }
}
