// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "../core/Margin.sol";

contract MockFactory {
    address public config;
    Margin public margin;

    constructor(address _config) {
        config = _config;
    }

    function createPair() public {
        margin = new Margin();
    }

    function initialize(
        address baseToken_,
        address quoteToken_,
        address amm_
    ) public {
        margin.initialize(baseToken_, quoteToken_, amm_);
    }
}
