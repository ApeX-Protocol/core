// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../core/interfaces/IERC20.sol";
import "./interfaces/IAlpPool.sol";
import "./interfaces/IRewardDistributor.sol";
import "../utils/Ownable.sol";
import "../utils/Reentrant.sol";

contract AlpPool is IAlpPool, IERC20, Reentrant, Ownable {
    uint256 internal constant PRECISION = 1e30;
    uint256 internal constant vestSpan = 180 days;
    uint8 public constant override decimals = 18;

    bool public isInitialized;

    string public override name; //esApeX Token
    string public override symbol; //esApeX
    uint256 public override totalSupply;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    address public stakingPool; //can transfer esApeX
    address public distributor; //contract about rewards
    address public alpToken; //staked token
    uint256 public totalStakedAmount; //all users' alpToken staked amount

    uint256 public cumulativeRewardPerAlp;
    mapping(address => uint256) public override stakedAmounts;
    mapping(address => uint256) public claimableReward;
    mapping(address => uint256) public previousCumulatedRewardPerAlp;

    mapping(address => User) public users;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function initialize(
        address _alpToken,
        address _distributor,
        address _stakingPool
    ) external onlyOwner {
        require(!isInitialized, "AlpStaking: already initialized");
        isInitialized = true;
        alpToken = _alpToken;
        distributor = _distributor;
        stakingPool = _stakingPool;
    }

    function stake(uint256 _amount) external override nonReentrant {
        _stake(msg.sender, msg.sender, _amount);
    }

    function unstake(uint256 _amount) external override nonReentrant {
        _unstake(msg.sender, _amount, msg.sender);
    }

    //claim all esApeX reward to sender
    function claim() external override nonReentrant returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    function vest(uint256 amount) external override {
        _transferFrom(msg.sender, address(this), amount);

        User storage user = users[msg.sender];
        user.vests.push(VestItem({amount: amount, lockUntil: block.timestamp + vestSpan}));
        user.total += amount;

        emit Vest(msg.sender, amount);
    }

    function withdrawApeX(uint256[] memory vestIds, uint256[] memory vestAmounts) external override {
        require(vestIds.length == vestAmounts.length, "invalid list");
        User storage user = users[msg.sender];
        uint256 _amount;
        uint256 _id;
        VestItem memory _vest;
        uint256 _burnTokenAmount;
        for (uint256 i = 0; i < vestIds.length; i++) {
            _amount = vestAmounts[i];
            _id = vestIds[i];
            _vest = user.vests[_id];
            require(block.timestamp > _vest.lockUntil, "withdrawApeX: VEST_LOCKED");
            _burnTokenAmount += _amount;
            if (_vest.amount == _amount) {
                delete user.vests[_id];
            } else {
                _vest.amount -= _amount;
            }
        }

        _burn(address(this), _burnTokenAmount);
        user.total -= _burnTokenAmount;

        //trans _burnTokenAmount ApeX to sender
        IRewardDistributor(distributor).transferApeX(msg.sender, _burnTokenAmount);

        emit WithdrawApeX(msg.sender, vestIds, vestAmounts);
    }

    function getVestTotal() external view returns (uint256) {
        User memory user = users[msg.sender];
        return user.total;
    }

    function getOneVest(uint256 id) external view returns (VestItem memory) {
        User memory user = users[msg.sender];
        return user.vests[id];
    }

    //esApeX
    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        require(msg.sender == stakingPool, "transfer: no authority");

        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external override returns (bool) {
        require(msg.sender == stakingPool, "transfer: no authority");
        return _transferFrom(_sender, _recipient, _amount);
    }

    function _transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender] - _amount;

        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function claimable(address _account) external view override returns (uint256) {
        uint256 stakedAmount = stakedAmounts[_account];
        if (stakedAmount == 0) {
            return claimableReward[_account];
        }

        uint256 pendingRewards = IRewardDistributor(distributor).pendingRewards() * PRECISION;
        uint256 nextCumulativeRewardPerAlp = cumulativeRewardPerAlp + (pendingRewards / totalStakedAmount);
        //claimable reward
        return
            claimableReward[_account] +
            ((stakedAmount * (nextCumulativeRewardPerAlp - previousCumulatedRewardPerAlp[_account])) / PRECISION);
    }

    function _claim(address _account, address _receiver) private returns (uint256) {
        //update first
        _updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        //claim all
        claimableReward[_account] = 0;

        if (tokenAmount > 0) {
            _mint(_receiver, tokenAmount);
            emit Claim(_account, tokenAmount);
        }

        return tokenAmount;
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "AlpStaking: mint to the zero address");

        totalSupply += _amount;
        balances[_account] += _amount;

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "AlpStaking: burn from the zero address");

        balances[_account] -= _amount;
        totalSupply -= _amount;

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        require(_sender != address(0), "AlpStaking: transfer from the zero address");
        require(_recipient != address(0), "AlpStaking: transfer to the zero address");

        balances[_sender] -= _amount;
        balances[_recipient] += _amount;

        emit Transfer(_sender, _recipient, _amount);
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(_owner != address(0), "RewardTracker: approve from the zero address");
        require(_spender != address(0), "RewardTracker: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _stake(
        address _fundingAccount,
        address _account,
        uint256 _amount
    ) private {
        require(_amount > 0, "AlpStaking: invalid _amount");
        IERC20(alpToken).transferFrom(_fundingAccount, address(this), _amount);
        //update first
        _updateRewards(_account);

        stakedAmounts[_account] += _amount;
        totalStakedAmount += _amount;
        emit Stake(msg.sender, _amount);
    }

    function _unstake(
        address _account,
        uint256 _amount,
        address _receiver
    ) private {
        require(_amount > 0, "AlpStaking: invalid _amount");
        require(_amount <= stakedAmounts[_account], "AlpStaking: insufficient");
        //update first
        _updateRewards(_account);

        stakedAmounts[_account] -= _amount;
        totalStakedAmount -= _amount;

        emit Unstake(msg.sender, _amount);
        //return receiver's alpToken
        IERC20(alpToken).transfer(_receiver, _amount);
    }

    function _updateRewards(address _account) private {
        //distribute distributor's pendingRewards
        uint256 blockReward = IRewardDistributor(distributor).distribute();

        uint256 totalStakedAmount_ = totalStakedAmount;
        uint256 _cumulativeRewardPerAlp = cumulativeRewardPerAlp;

        if (totalStakedAmount_ > 0 && blockReward > 0) {
            _cumulativeRewardPerAlp = _cumulativeRewardPerAlp + ((blockReward * PRECISION) / totalStakedAmount_);
            cumulativeRewardPerAlp = _cumulativeRewardPerAlp;
        }

        //claim reward to private account
        claimableReward[_account] +=
            (stakedAmounts[_account] * (_cumulativeRewardPerAlp - (previousCumulatedRewardPerAlp[_account]))) /
            PRECISION;
        //record the latest reward price of private account
        previousCumulatedRewardPerAlp[_account] = _cumulativeRewardPerAlp;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).transfer(_account, _amount);
    }
}
