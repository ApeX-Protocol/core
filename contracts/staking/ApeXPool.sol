// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IApeXPool.sol";
import "./interfaces/IStakingPoolFactory.sol";
import "../core/interfaces/IERC20.sol";
import "../utils/Reentrant.sol";

contract ApeXPool is IApeXPool, Reentrant {
    uint256 internal constant WEIGHT_MULTIPLIER = 1e6;
    uint256 internal constant MAX_TIME_STAKE_WEIGHT_MULTIPLIER = 2 * WEIGHT_MULTIPLIER;
    uint256 internal constant REWARD_PER_WEIGHT_MULTIPLIER = 1e12;

    address public immutable override poolToken;
    IStakingPoolFactory public immutable factory;
    uint256 public lastYieldDistribution; //timestamp
    uint256 public yieldRewardsPerWeight;
    uint256 public usersLockingWeight;
    mapping(address => User) public users;

    constructor(
        address _factory,
        address _apeX,
        uint256 _initTimestamp
    ) {
        require(_factory != address(0), "cp: INVALID_FACTORY");
        require(_initTimestamp > 0, "cp: INVALID_INIT_TIMESTAMP");
        require(_apeX != address(0), "cp: INVALID_POOL_TOKEN");

        factory = IStakingPoolFactory(_factory);
        poolToken = _apeX;
        lastYieldDistribution = _initTimestamp;
    }

    function stake(uint256 _amount, uint256 _lockUntil) external override nonReentrant {
        _stake(_amount, _lockUntil, false);
        IERC20(poolToken).transferFrom(msg.sender, address(this), _amount);
    }

    function stakeEsApeX(uint256 _amount, uint256 _lockUntil) external override {
        _stake(_amount, _lockUntil, true);
        factory.transferEsApeXFrom(msg.sender, address(factory), _amount);
    }

    function _stake(
        uint256 _amount,
        uint256 _lockUntil,
        bool _isEsApeX
    ) internal {
        require(_amount > 0, "sp.stake: INVALID_AMOUNT");
        uint256 now256 = block.timestamp;
        uint256 lockTime = factory.lockTime();
        require(
            _lockUntil == 0 || (_lockUntil > now256 && _lockUntil <= now256 + lockTime),
            "sp._stake: INVALID_LOCK_INTERVAL"
        );

        address _staker = msg.sender;
        User storage user = users[_staker];
        _processRewards(_staker, user);

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

        if (_isEsApeX) {
            user.esDeposits.push(deposit);
        } else {
            user.deposits.push(deposit);
        }

        factory.mintVeApeX(_staker, stakeWeight / WEIGHT_MULTIPLIER);
        user.tokenAmount += _amount;
        user.totalWeight += stakeWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        usersLockingWeight += stakeWeight;

        emit Staked(_staker, depositId, _isEsApeX, _amount, lockFrom, _lockUntil);
    }

    function batchWithdraw(
        uint256[] memory depositIds,
        uint256[] memory depositAmounts,
        uint256[] memory yieldIds,
        uint256[] memory yieldAmounts,
        uint256[] memory esDepositIds,
        uint256[] memory esDepositAmounts
    ) external override {
        require(depositIds.length == depositAmounts.length, "sp.batchWithdraw: INVALID_DEPOSITS_AMOUNTS");
        require(yieldIds.length == yieldAmounts.length, "sp.batchWithdraw: INVALID_YIELDS_AMOUNTS");
        require(esDepositIds.length == esDepositAmounts.length, "sp.batchWithdraw: INVALID_ESDEPOSITS_AMOUNTS");

        User storage user = users[msg.sender];
        _processRewards(msg.sender, user);
        emit BatchWithdraw(
            msg.sender,
            depositIds,
            depositAmounts,
            yieldIds,
            yieldAmounts,
            esDepositIds,
            esDepositAmounts
        );
        uint256 lockTime = factory.lockTime();

        uint256 _amount;
        uint256 _id;
        uint256 stakeAmount;
        uint256 newWeight;
        uint256 deltaUsersLockingWeight;
        Deposit memory stakeDeposit;
        for (uint256 i = 0; i < depositIds.length; i++) {
            _amount = depositAmounts[i];
            _id = depositIds[i];
            require(_amount != 0, "sp.batchWithdraw: INVALID_DEPOSIT_AMOUNT");
            stakeDeposit = user.deposits[_id];
            require(
                stakeDeposit.lockFrom == 0 || block.timestamp > stakeDeposit.lockUntil,
                "sp.batchWithdraw: DEPOSIT_LOCKED"
            );
            require(stakeDeposit.amount >= _amount, "sp.batchWithdraw: EXCEED_DEPOSIT_STAKED");

            newWeight =
                (((stakeDeposit.lockUntil - stakeDeposit.lockFrom) * WEIGHT_MULTIPLIER) /
                    lockTime +
                    WEIGHT_MULTIPLIER) *
                (stakeDeposit.amount - _amount);

            stakeAmount += _amount;
            deltaUsersLockingWeight += (stakeDeposit.weight - newWeight);

            if (stakeDeposit.amount == _amount) {
                delete user.deposits[_id];
            } else {
                stakeDeposit.amount -= _amount;
                stakeDeposit.weight = newWeight;
                user.deposits[_id] = stakeDeposit;
            }
        }
        {
            uint256 esStakeAmount;
            for (uint256 i = 0; i < esDepositIds.length; i++) {
                _amount = esDepositAmounts[i];
                _id = esDepositIds[i];
                require(_amount != 0, "sp.batchWithdraw: INVALID_ESDEPOSIT_AMOUNT");
                stakeDeposit = user.esDeposits[_id];
                require(
                    stakeDeposit.lockFrom == 0 || block.timestamp > stakeDeposit.lockUntil,
                    "sp.batchWithdraw: ESDEPOSIT_LOCKED"
                );
                require(stakeDeposit.amount >= _amount, "sp.batchWithdraw: EXCEED_ESDEPOSIT_STAKED");

                newWeight =
                    (((stakeDeposit.lockUntil - stakeDeposit.lockFrom) * WEIGHT_MULTIPLIER) /
                        lockTime +
                        WEIGHT_MULTIPLIER) *
                    (stakeDeposit.amount - _amount);

                esStakeAmount += _amount;
                deltaUsersLockingWeight += (stakeDeposit.weight - newWeight);

                if (stakeDeposit.amount == _amount) {
                    delete user.esDeposits[_id];
                } else {
                    stakeDeposit.amount -= _amount;
                    stakeDeposit.weight = newWeight;
                    user.esDeposits[_id] = stakeDeposit;
                }
            }
            if (esStakeAmount > 0) {
                user.tokenAmount -= esStakeAmount;
                factory.transferEsApeXTo(msg.sender, esStakeAmount);
            }
        }

        factory.burnVeApeX(msg.sender, deltaUsersLockingWeight / WEIGHT_MULTIPLIER);
        user.totalWeight -= deltaUsersLockingWeight;
        usersLockingWeight -= deltaUsersLockingWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;

        {
            uint256 yieldAmount;
            Yield memory stakeYield;
            for (uint256 i = 0; i < yieldIds.length; i++) {
                _amount = yieldAmounts[i];
                _id = yieldIds[i];
                require(_amount != 0, "sp.batchWithdraw: INVALID_YIELD_AMOUNT");
                stakeYield = user.yields[_id];
                require(block.timestamp > stakeYield.lockUntil, "sp.batchWithdraw: YIELD_LOCKED");
                require(stakeYield.amount >= _amount, "sp.batchWithdraw: EXCEED_YIELD_STAKED");

                yieldAmount += _amount;

                if (stakeYield.amount == _amount) {
                    delete user.yields[_id];
                } else {
                    stakeYield.amount -= _amount;
                    user.yields[_id] = stakeYield;
                }
            }

            if (yieldAmount > 0) {
                user.tokenAmount -= yieldAmount;
                factory.transferYieldTo(msg.sender, yieldAmount);
            }
        }

        if (stakeAmount > 0) {
            user.tokenAmount -= stakeAmount;
            IERC20(poolToken).transfer(msg.sender, stakeAmount);
        }
    }

    function forceWithdraw(uint256[] memory _yieldIds) external override {
        uint256 minRemainRatio = factory.minRemainRatioAfterBurn();
        address _staker = msg.sender;
        uint256 now256 = block.timestamp;

        User storage user = users[_staker];

        uint256 deltaTotalAmount;
        uint256 yieldAmount;

        //force withdraw vesting or vested rewards
        Yield memory yield;
        for (uint256 i = 0; i < _yieldIds.length; i++) {
            yield = user.yields[_yieldIds[i]];
            deltaTotalAmount += yield.amount;

            if (now256 >= yield.lockUntil) {
                yieldAmount += yield.amount;
            } else {
                yieldAmount +=
                    (yield.amount *
                        (minRemainRatio +
                            ((10000 - minRemainRatio) * (now256 - yield.lockFrom)) /
                            factory.lockTime())) /
                    10000;
            }
            delete user.yields[_yieldIds[i]];
        }

        uint256 remainApeX = deltaTotalAmount - yieldAmount;

        //half of remaining esApeX to boost remain vester
        uint256 remainForOtherVest = factory.remainForOtherVest();
        uint256 newYieldRewardsPerWeight = yieldRewardsPerWeight +
            ((remainApeX * REWARD_PER_WEIGHT_MULTIPLIER) * remainForOtherVest) /
            100 /
            usersLockingWeight;
        yieldRewardsPerWeight = newYieldRewardsPerWeight;

        //half of remaining esApeX to transfer to treasury in apeX
        factory.transferYieldToTreasury(remainApeX - (remainApeX * remainForOtherVest) / 100);

        user.tokenAmount -= deltaTotalAmount;
        factory.burnEsApeX(address(this), deltaTotalAmount);
        if (yieldAmount > 0) {
            factory.transferYieldTo(_staker, yieldAmount);
        }

        emit ForceWithdraw(_staker, _yieldIds);
    }

    //only can extend lock time
    function updateStakeLock(
        uint256 _id,
        uint256 _lockUntil,
        bool _isEsApeX
    ) external override {
        uint256 now256 = block.timestamp;
        require(_lockUntil > now256, "sp.updateStakeLock: INVALID_LOCK_UNTIL");

        uint256 lockTime = factory.lockTime();
        address _staker = msg.sender;
        User storage user = users[_staker];
        _processRewards(_staker, user);

        Deposit storage stakeDeposit;
        if (_isEsApeX) {
            stakeDeposit = user.esDeposits[_id];
        } else {
            stakeDeposit = user.deposits[_id];
        }
        require(_lockUntil > stakeDeposit.lockUntil, "sp.updateStakeLock: INVALID_NEW_LOCK");

        if (stakeDeposit.lockFrom == 0) {
            require(_lockUntil <= now256 + lockTime, "sp.updateStakeLock: EXCEED_MAX_LOCK_PERIOD");
            stakeDeposit.lockFrom = now256;
        } else {
            require(_lockUntil <= stakeDeposit.lockFrom + lockTime, "sp.updateStakeLock: EXCEED_MAX_LOCK");
        }

        uint256 oldWeight = stakeDeposit.weight;
        uint256 newWeight = (((_lockUntil - stakeDeposit.lockFrom) * WEIGHT_MULTIPLIER) /
            lockTime +
            WEIGHT_MULTIPLIER) * stakeDeposit.amount;

        factory.mintVeApeX(_staker, (newWeight - oldWeight) / WEIGHT_MULTIPLIER);
        stakeDeposit.lockUntil = _lockUntil;
        stakeDeposit.weight = newWeight;
        user.totalWeight = user.totalWeight - oldWeight + newWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        usersLockingWeight = usersLockingWeight - oldWeight + newWeight;

        emit UpdateStakeLock(_staker, _id, _isEsApeX, stakeDeposit.lockFrom, _lockUntil);
    }

    function processRewards() external override {
        address staker = msg.sender;
        User storage user = users[staker];

        _processRewards(staker, user);
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
    }

    function syncWeightPrice() public {
        if (factory.shouldUpdateRatio()) {
            factory.updateApeXPerSec();
        }

        uint256 endTimestamp = factory.endTimestamp();
        uint256 currentTimestamp = block.timestamp;
        if (lastYieldDistribution >= endTimestamp || lastYieldDistribution >= currentTimestamp) {
            return;
        }
        if (usersLockingWeight == 0) {
            lastYieldDistribution = currentTimestamp;
            return;
        }

        uint256 apeXReward = factory.calStakingPoolApeXReward(lastYieldDistribution, poolToken);
        yieldRewardsPerWeight += (apeXReward * REWARD_PER_WEIGHT_MULTIPLIER) / usersLockingWeight;
        lastYieldDistribution = currentTimestamp > endTimestamp ? endTimestamp : currentTimestamp;

        emit Synchronized(msg.sender, yieldRewardsPerWeight, lastYieldDistribution);
    }

    //update weight price, then if apeX, add deposits; if not, stake as pool.
    function _processRewards(address _staker, User storage user) internal {
        syncWeightPrice();

        //if no yield
        if (user.totalWeight == 0) return;
        uint256 yieldAmount = (user.totalWeight * yieldRewardsPerWeight) /
            REWARD_PER_WEIGHT_MULTIPLIER -
            user.subYieldRewards;
        if (yieldAmount == 0) return;

        //mint esApeX to _staker
        factory.mintEsApeX(_staker, yieldAmount);
    }

    function vest(uint256 vestAmount) external override {
        User storage user = users[msg.sender];
        _processRewards(msg.sender, user);

        uint256 now256 = block.timestamp;
        uint256 lockUntil = now256 + factory.lockTime();
        emit YieldClaimed(msg.sender, user.yields.length, vestAmount, now256, lockUntil);

        user.yields.push(Yield({amount: vestAmount, lockFrom: now256, lockUntil: lockUntil}));
        user.tokenAmount += vestAmount;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;

        factory.transferEsApeXFrom(msg.sender, address(this), vestAmount);
    }

    function pendingYieldRewards(address _staker) external view returns (uint256 pending) {
        uint256 newYieldRewardsPerWeight = yieldRewardsPerWeight;

        if (block.timestamp > lastYieldDistribution && usersLockingWeight != 0) {
            uint256 apeXReward = factory.calStakingPoolApeXReward(lastYieldDistribution, poolToken);
            newYieldRewardsPerWeight += (apeXReward * REWARD_PER_WEIGHT_MULTIPLIER) / usersLockingWeight;
        }

        User memory user = users[_staker];
        pending = (user.totalWeight * newYieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER - user.subYieldRewards;
    }

    function getStakeInfo(address _user)
        external
        view
        override
        returns (
            uint256 tokenAmount,
            uint256 totalWeight,
            uint256 subYieldRewards
        )
    {
        User memory user = users[_user];
        return (user.tokenAmount, user.totalWeight, user.subYieldRewards);
    }

    function getDeposit(address _user, uint256 _id) external view override returns (Deposit memory) {
        return users[_user].deposits[_id];
    }

    function getDepositsLength(address _user) external view override returns (uint256) {
        return users[_user].deposits.length;
    }

    function getYield(address _user, uint256 _yieldId) external view override returns (Yield memory) {
        return users[_user].yields[_yieldId];
    }

    function getYieldsLength(address _user) external view override returns (uint256) {
        return users[_user].yields.length;
    }

    function getEsDeposit(address _user, uint256 _id) external view override returns (Deposit memory) {
        return users[_user].esDeposits[_id];
    }

    function getEsDepositsLength(address _user) external view override returns (uint256) {
        return users[_user].esDeposits.length;
    }
}
