// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockBaseToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    receive() external payable {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external payable {
        _burn(msg.sender, msg.value);
        payable(msg.sender).transfer(amount);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
