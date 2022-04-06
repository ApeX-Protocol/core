// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../utils/Initializable.sol";

contract NewPoolTemplate is Initializable {
    address public poolToken;
    address public factory;

    function initialize(address _factory, address _poolToken) external initializer {
        factory = _factory;
        poolToken = _poolToken;
    }

    function getDepositsLength(address _user) external view returns (uint256) {
        return 10000;
    }
}
