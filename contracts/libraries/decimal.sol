// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

library Decimal {
    function add(uint256 x, uint256 y) internal pure returns (uint256) {
        return x + y;
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256) {
        return x - y;
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return x * y;
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256) {
        return x / y;
    }
}
