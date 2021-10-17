pragma solidity ^0.8.0;

interface IVault {
    event Withdraw(address indexed caller, address indexed to, uint amount);

    function baseToken() external view returns (address);
    function factory() external view returns (address);
    function amm() external view returns (address);
    function margin() external view returns (address);
    function getReserve() external view returns (uint);

    // only factory can call this function
    function initialize(address baseToken, address amm, address margin) external;
    // only amm or margin can call this function
    function withdraw(address to, uint amount) external;
}