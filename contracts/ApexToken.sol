// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ApexToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20("Apex Token", "apex") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
