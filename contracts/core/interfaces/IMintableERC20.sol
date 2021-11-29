//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IMintableERC20 is IERC20 {
    function mint(address to, uint256 value) external;
}
