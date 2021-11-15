//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./interfaces/IStaking.sol";
import "./interfaces/ILiquidityERC20.sol";
import "./utils/Reentrant.sol";

contract Staking is IStaking, Reentrant {
    address public override factory;
    address public override config;
    address public override stakingToken;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;

    constructor(address config_, address stakingToken_) {
        factory = msg.sender;
        config = config_;
        stakingToken = stakingToken_;
    }

    function stake(uint256 amount) external override nonReentrant {
        require(amount > 0, "Staking: Cannot stake 0");
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        ILiquidityERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external override nonReentrant {}
}
