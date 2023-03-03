// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockQuoteToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
