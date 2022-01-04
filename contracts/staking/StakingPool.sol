// SPDX-License-Identifier: GPL-2.0-or-later
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
        require(_amount > 0, "cp.stake: INVALID_AMOUNT");
        uint256 now256 = block.timestamp;
        //tocheck if must be 6 month, can hardcode
        uint256 lockTime = factory.lockTime();
        require(
            _lockUntil == 0 || (_lockUntil > now256 && _lockUntil <= now256 + lockTime),
            "cp._stake: INVALID_LOCK_INTERVAL"
        );

        address _staker = msg.sender;
        User storage user = users[_staker];
        _processRewards(_staker, user);

        IERC20(poolToken).transferFrom(_staker, address(this), _amount);
        //if 0, not lock
        uint256 lockFrom = _lockUntil > 0 ? now256 : 0;
        uint256 stakeWeight = (((_lockUntil - lockFrom) * WEIGHT_MULTIPLIER) / lockTime + WEIGHT_MULTIPLIER) * _amount;
        uint256 depositId = user.deposits.length;
        Deposit memory deposit = Deposit({
            amount: _amount,
            weight: stakeWeight,
            lockFrom: lockFrom,
            lockUntil: _lockUntil
        });

        user.deposits.push(deposit);
        user.tokenAmount += _amount;
        user.totalWeight += stakeWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        usersLockingWeight += stakeWeight;

        emit Staked(_staker, depositId, _amount, lockFrom, _lockUntil);
    }

    function batchWithdraw(
        uint256[] memory depositIds,
        uint256[] memory amounts,
        uint256[] memory yieldIds,
        uint256[] memory yieldAmounts
    ) external override {
        require(depositIds.length == amounts.length, "cp.batchWithdraw: INVALID_DEPOSITS_AMOUNTS");
        require(yieldIds.length == yieldAmounts.length, "cp.batchWithdraw: INVALID_YIELDS_AMOUNTS");
        User storage user = users[msg.sender];
        _processRewards(msg.sender, user);
        emit UnstakeBatch(msg.sender, depositIds, amounts);
        uint256 lockTime = factory.lockTime();

        uint256 yieldAmount;
        uint256 stakeAmount;
        uint256 _amount;
        uint256 _id;
        uint256 previousWeight;
        uint256 newWeight;
        uint256 deltaUsersLockingWeight;
        Deposit memory stakeDeposit;
        for (uint256 i = 0; i < depositIds.length; i++) {
            _amount = amounts[i];
            _id = depositIds[i];
            require(_amount != 0, "cp.batchWithdraw: INVALID_AMOUNT");
            stakeDeposit = user.deposits[_id];
            require(
                stakeDeposit.lockFrom == 0 || block.timestamp > stakeDeposit.lockUntil,
                "cp.batchWithdraw: DEPOSIT_LOCKED"
            );
            require(stakeDeposit.amount >= _amount, "cp.batchWithdraw: EXCEED_STAKED");

            previousWeight = stakeDeposit.weight;
            //tocheck if lockTime is not 1 year?
            newWeight =
                (((stakeDeposit.lockUntil - stakeDeposit.lockFrom) * WEIGHT_MULTIPLIER) /
                    lockTime +
                    WEIGHT_MULTIPLIER) *
                (stakeDeposit.amount - _amount);

            stakeAmount += _amount;
            user.totalWeight -= (previousWeight - newWeight);
            deltaUsersLockingWeight += (previousWeight - newWeight);

            user.tokenAmount -= _amount;
            if (stakeDeposit.amount == _amount) {
                delete user.deposits[_id];
            } else {
                stakeDeposit.amount -= _amount;
                stakeDeposit.weight = newWeight;
            }
            user.deposits[_id] = stakeDeposit;
        }
        usersLockingWeight -= deltaUsersLockingWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;

        Yield memory stakeYield;
        for (uint256 i = 0; i < yieldIds.length; i++) {
            _amount = yieldAmounts[i];
            _id = yieldIds[i];
            require(_amount != 0, "cp.batchWithdraw: INVALID_AMOUNT");
            stakeYield = user.yields[_id];
            require(
                stakeYield.lockFrom == 0 || block.timestamp > stakeYield.lockUntil,
                "cp.batchWithdraw: DEPOSIT_LOCKED"
            );
            require(stakeYield.amount >= _amount, "cp.batchWithdraw: EXCEED_STAKED");

            yieldAmount += _amount;

            user.tokenAmount -= _amount;
            if (stakeYield.amount == _amount) {
                delete user.yields[_id];
            } else {
                stakeYield.amount -= _amount;
            }
            user.yields[_id] = stakeYield;
        }

        if (yieldAmount > 0) {
            factory.transferYieldTo(msg.sender, yieldAmount);
        }
        if (stakeAmount > 0) {
            IERC20(poolToken).transfer(msg.sender, stakeAmount);
        }
    }

    function forceWithdraw(uint256[] memory _yieldIds) external override {
        require(poolToken == apex, "cp.forceWithdraw: INVALID_POOL_TOKEN");
        uint256 minRemainRatio = factory.minRemainRatioAfterBurn();
        address _staker = msg.sender;
        uint256 now256 = block.timestamp;
        syncWeightPrice();
        User storage user = users[_staker];

        uint256 deltaTotalAmount;
        uint256 yieldAmount;
        uint256 yieldId;
        //force withdraw existing rewards
        for (uint256 i = 0; i < _yieldIds.length; i++) {
            yieldId = _yieldIds[i];
            deltaTotalAmount += user.yields[yieldId].amount;

            if (now256 >= user.yields[yieldId].lockUntil) {
                yieldAmount += user.yields[yieldId].amount;
            } else {
                yieldAmount +=
                    (user.yields[yieldId].amount *
                        (minRemainRatio +
                            ((10000 - minRemainRatio) * (now256 - user.yields[yieldId].lockFrom)) /
                            factory.lockTime())) /
                    10000;
            }
            delete user.yields[yieldId];
        }
        //force withdraw new reward
        uint256 newYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        yieldAmount += ((newYieldRewards - user.subYieldRewards) * minRemainRatio) / 10000;
        user.subYieldRewards = newYieldRewards;

        user.tokenAmount -= deltaTotalAmount;
        if (yieldAmount > 0) {
            factory.transferYieldTo(_staker, yieldAmount);
        }
    }

    //called by other staking pool to stake yield rewards into apeX pool
    function stakeAsPool(address _staker, uint256 _amount) external override {
        require(factory.poolTokenMap(msg.sender) != address(0), "cp.stakeAsPool: ACCESS_DENIED");
        syncWeightPrice(); //need sync apexStakingPool

        User storage user = users[_staker];

        uint256 latestYieldReward = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        uint256 pendingYield = latestYieldReward - user.subYieldRewards;
        user.subYieldRewards = latestYieldReward;

        uint256 yieldAmount = _amount + pendingYield;
        uint256 now256 = block.timestamp;
        uint256 lockUntil = now256 + factory.lockTime();
        uint256 yieldId = user.yields.length;
        Yield memory newYield = Yield({amount: yieldAmount, lockFrom: now256, lockUntil: lockUntil});
        user.yields.push(newYield);

        user.tokenAmount += yieldAmount;

        emit StakeAsPool(msg.sender, _staker, yieldId, _amount, yieldAmount, now256, lockUntil);
    }

    //only can extend lock time
    function updateStakeLock(uint256 _depositId, uint256 _lockUntil) external override {
        uint256 now256 = block.timestamp;
        require(_lockUntil > now256, "cp.updateStakeLock: INVALID_LOCK_UNTIL");

        uint256 lockTime = factory.lockTime();
        address _staker = msg.sender;
        User storage user = users[_staker];
        Deposit storage stakeDeposit = user.deposits[_depositId];
        require(_lockUntil > stakeDeposit.lockUntil, "cp.updateStakeLock: INVALID_NEW_LOCK");

        if (stakeDeposit.lockFrom == 0) {
            require(_lockUntil <= now256 + lockTime, "cp.updateStakeLock: EXCEED_MAX_LOCK_PERIOD");
            stakeDeposit.lockFrom = now256;
        } else {
            require(_lockUntil <= stakeDeposit.lockFrom + lockTime, "cp.updateStakeLock: EXCEED_MAX_LOCK");
        }

        stakeDeposit.lockUntil = _lockUntil;
        uint256 newWeight = (((stakeDeposit.lockUntil - stakeDeposit.lockFrom) * WEIGHT_MULTIPLIER) /
            lockTime +
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
            uint256 now256 = block.timestamp;
            uint256 lockUntil = now256 + factory.lockTime();
            uint256 yieldId = user.yields.length;
            Yield memory newYield = Yield({amount: yieldAmount, lockFrom: now256, lockUntil: lockUntil});
            user.yields.push(newYield);
            user.tokenAmount += yieldAmount;
            emit YieldClaimed(_staker, yieldId, yieldAmount, now256, lockUntil);
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
