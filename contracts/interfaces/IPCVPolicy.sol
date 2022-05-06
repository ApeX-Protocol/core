// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IPCVPolicy {
    function execute(address lpToken, uint256 amount, bytes calldata data) external;
}
