// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "../bonding/interfaces/IPCVPolicy.sol";

contract MockPCVPolicy is IPCVPolicy {
    function execute(
        address lpToken_,
        uint256 amount,
        bytes calldata data
    ) external override {}
}
