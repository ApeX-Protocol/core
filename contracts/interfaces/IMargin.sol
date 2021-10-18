// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IMargin {
    function addMargin(address _trader, uint256 _depositAmount) external;

    function removeMargin(uint256 _withdrawAmount) external;

    function openPosition(
        uint8 _side, //0 is long, 1 is short
        uint256 _baseAmount
    ) external;
}
