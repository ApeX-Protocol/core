pragma solidity ^0.8.0;

interface IVault {
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, address indexed receiver, uint256 amount);

    function deposit(address user, uint256 amount) external;

    function withdraw(
        address user,
        address receiver,
        uint256 amount
    ) external;

    function reserve() external view returns (uint256);
}
