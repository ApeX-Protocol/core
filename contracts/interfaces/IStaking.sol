// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IStaking {
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    function factory() external view returns (address);

    function stakingToken() external view returns (address);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;
}
