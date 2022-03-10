// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";

contract MockToken is ERC20, ERC20FlashMint {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        require(token == address(this), "ERC20FlashMint: wrong token");
        return amount / 10;
    }

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
