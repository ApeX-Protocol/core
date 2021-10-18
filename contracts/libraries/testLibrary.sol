// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import {Math} from "./Math.sol";
import {Decimal} from "./Decimal.sol";
import {SignedDecimal} from "./SignedDecimal.sol";

contract TestLibrary {
    constructor() {}

    function mathMin(int256 a, int256 b) external pure returns (int256) {
        return Math.min(a, b);
    }

    function mathMinU(uint256 a, uint256 b) external pure returns (uint256) {
        return Math.minU(a, b);
    }

    function decimalAdd(uint256 a, uint256 b) external pure returns (uint256) {
        return Decimal.add(a, b);
    }

    function decimalSub(uint256 a, uint256 b) external pure returns (uint256) {
        return Decimal.sub(a, b);
    }

    function decimalDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return Decimal.div(a, b);
    }

    function decimalMul(uint256 a, uint256 b) external pure returns (uint256) {
        return Decimal.mul(a, b);
    }

    function decimalOppo(uint256 a) external pure returns (int256) {
        return Decimal.oppo(a);
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
