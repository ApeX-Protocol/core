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

    //example:
    //int is -100 -> 100, uint is 0 -> 200,
    //so 100 -> 200 is -100 -> 0
    function oppo(uint256 x) internal pure returns (int256) {
        int256 _x = 0 - int256(x);
        require(uint256(_x) >= x, "overflow");
        return _x;
    }
}
