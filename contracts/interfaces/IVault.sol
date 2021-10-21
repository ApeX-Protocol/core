// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IVault {
    event Withdraw(address indexed caller, address indexed to, uint256 amount);

    function baseToken() external view returns (address);

    function factory() external view returns (address);

    function amm() external view returns (address);

    function margin() external view returns (address);

    // only factory can call this function
    function initialize(address _baseToken, address _amm) external;

    function setMargin(address _margin) external;

    // only amm or margin can call this function
    function withdraw(address to, uint256 amount) external;
}
