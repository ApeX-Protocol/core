// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

library Math {
    function min(int256 x, int256 y) internal pure returns (int256) {
        if (x > y) {
            return y;
        }
        return x;
    }

    function minU(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x > y) {
            return y;
        }
        return x;
    }
}
