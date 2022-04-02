// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IStakingPool.sol";
import "./interfaces/IStakingPoolFactory.sol";
import "../core/interfaces/IERC20.sol";
import "../utils/Reentrant.sol";
import "../utils/Initializable.sol";

contract StakingPool is IStakingPool, Reentrant, Initializable {
    uint256 internal constant WEIGHT_MULTIPLIER = 1e6;
    uint256 internal constant MAX_TIME_STAKE_WEIGHT_MULTIPLIER = 2 * WEIGHT_MULTIPLIER;
    uint256 internal constant REWARD_PER_WEIGHT_MULTIPLIER = 1e12;

    address public override poolToken;
    IStakingPoolFactory public factory;
    uint256 public yieldRewardsPerWeight;
    uint256 public usersLockingWeight;
    mapping(address => User) public users;

    function initialize(address _factory, address _poolToken) external override initializer {
        factory = IStakingPoolFactory(_factory);
        poolToken = _poolToken;
    }

    function stake(uint256 _amount, uint256 _lockUntil) external override nonReentrant {
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

        user.deposits.push(deposit);
        user.tokenAmount += _amount;
        user.totalWeight += stakeWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        usersLockingWeight += stakeWeight;

        emit Staked(_staker, depositId, _amount, lockFrom, _lockUntil);
        IERC20(poolToken).transferFrom(msg.sender, address(this), _amount);
    }

    function batchWithdraw(uint256[] memory depositIds, uint256[] memory depositAmounts) external override {
        require(depositIds.length == depositAmounts.length, "sp.batchWithdraw: INVALID_DEPOSITS_AMOUNTS");

        User storage user = users[msg.sender];
        _processRewards(msg.sender, user);
        emit BatchWithdraw(msg.sender, depositIds, depositAmounts);
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

        user.totalWeight -= deltaUsersLockingWeight;
        usersLockingWeight -= deltaUsersLockingWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;

        if (stakeAmount > 0) {
            user.tokenAmount -= stakeAmount;
            IERC20(poolToken).transfer(msg.sender, stakeAmount);
        }
    }

    function updateStakeLock(uint256 _id, uint256 _lockUntil) external override {
        uint256 now256 = block.timestamp;
        require(_lockUntil > now256, "sp.updateStakeLock: INVALID_LOCK_UNTIL");

        uint256 lockTime = factory.lockTime();
        address _staker = msg.sender;
        User storage user = users[_staker];
        _processRewards(_staker, user);

        Deposit storage stakeDeposit;

        stakeDeposit = user.deposits[_id];

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

        stakeDeposit.lockUntil = _lockUntil;
        stakeDeposit.weight = newWeight;
        user.totalWeight = user.totalWeight - oldWeight + newWeight;
        user.subYieldRewards = (user.totalWeight * yieldRewardsPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
        usersLockingWeight = usersLockingWeight - oldWeight + newWeight;

        emit UpdateStakeLock(_staker, _id, stakeDeposit.lockFrom, _lockUntil);
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

        uint256 apeXReward = factory.syncYieldPriceOfWeight();

        if (usersLockingWeight == 0) {
            return;
        }

        yieldRewardsPerWeight += (apeXReward * REWARD_PER_WEIGHT_MULTIPLIER) / usersLockingWeight;
        emit Synchronized(msg.sender, yieldRewardsPerWeight);
    }

    function _processRewards(address _staker, User storage user) internal {
        syncWeightPrice();

        //if no yield
        if (user.totalWeight == 0) return;
        uint256 yieldAmount = (user.totalWeight * yieldRewardsPerWeight) /
            REWARD_PER_WEIGHT_MULTIPLIER -
            user.subYieldRewards;
        if (yieldAmount == 0) return;

        factory.mintEsApeX(_staker, yieldAmount);
        emit MintEsApeX(_staker, yieldAmount);
    }

    function pendingYieldRewards(address _staker) external view returns (uint256 pending) {
        uint256 newYieldRewardsPerWeight = yieldRewardsPerWeight;

        if (usersLockingWeight != 0) {
            (uint256 apeXReward, ) = factory.calStakingPoolApeXReward(poolToken);
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
}
