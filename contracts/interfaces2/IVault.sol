pragma solidity ^0.8.0;

interface IVault {
    event Deposit(address indexed caller, uint amount);
    event Withdraw(address indexed caller, uint amount);

    function baseToken() external view returns (address);
    function factory() external view returns (address);
    function amm() external view returns (address);
    function margin() external view returns (address);
    function getReserve() external view returns (uint);

    // only factory can call this function
    function initialize(address baseToken, address amm, address margin) external;
    // only amm or margin can call this function
    function deposit(uint amount) external;
    // only amm or margin can call this function
    function withdraw(uint amount) external;
}