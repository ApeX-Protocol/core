// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import {Math} from "./Math.sol";
import {SignedDecimal} from "./SignedDecimal.sol";

contract TestLibrary {
    constructor() {}

    function mathMin(int256 a, int256 b) external pure returns (int256) {
        return Math.min(a, b);
    }

    function mathMinU(uint256 a, uint256 b) external pure returns (uint256) {
        return Math.minU(a, b);
    }

    function signedDecimalAbs(int256 x) external pure returns (uint256) {
        return SignedDecimal.abs(x);
    }

    function signedDecimalAdd(int256 x, int256 y) external pure returns (int256) {
        return SignedDecimal.add(x, y);
    }

    function signedDecimalSub(int256 x, int256 y) external pure returns (int256) {
        return SignedDecimal.sub(x, y);
    }

    function signedDecimalMul(int256 x, int256 y) external pure returns (int256) {
        return SignedDecimal.mul(x, y);
    }

    function signedDecimalDiv(int256 x, int256 y) external pure returns (int256) {
        return SignedDecimal.div(x, y);
    }

    function signedDecimalAddU(int256 x, uint256 y) external pure returns (int256) {
        return SignedDecimal.addU(x, y);
    }

    function signedDecimalSubU(int256 x, uint256 y) external pure returns (int256) {
        return SignedDecimal.subU(x, y);
    }

    function signedDecimalMulU(int256 x, uint256 y) external pure returns (int256) {
        return SignedDecimal.mulU(x, y);
    }

    function signedDecimalDivU(int256 x, uint256 y) external pure returns (int256) {
        return SignedDecimal.divU(x, y);
    }
}
