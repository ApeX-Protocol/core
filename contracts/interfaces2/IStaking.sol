pragma solidity ^0.8.0;

interface IStaking {
    event Staked(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);

    function factory() external view returns (address);
    function amm() external view returns (address);
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);

    function stake(uint amount) external;
    function withdraw(uint amount) external;
}