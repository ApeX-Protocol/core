// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

library SignedDecimal {
    function abs(int256 x) internal pure returns (uint256) {
        if (x < 0) {
            return uint256(0 - x);
        }
        return uint256(x);
    }

    function add(int256 x, int256 y) internal pure returns (int256) {
        return x + y;
    }

    function sub(int256 x, int256 y) internal pure returns (int256) {
        return x - y;
    }

    function mul(int256 x, int256 y) internal pure returns (int256) {
        return x * y;
    }

    function div(int256 x, int256 y) internal pure returns (int256) {
        return x / y;
    }

    function addU(int256 x, uint256 y) internal pure returns (int256) {
        return x + int256(y);
    }

    function subU(int256 x, uint256 y) internal pure returns (int256) {
        return x - int256(y);
    }

    function mulU(int256 x, uint256 y) internal pure returns (int256) {
        return x * int256(y);
    }

    function divU(int256 x, uint256 y) internal pure returns (int256) {
        return x / int256(y);
    }
}
