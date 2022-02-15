// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract StAPEX is ERC20Votes {
    address public stakingPoolFactory;

    constructor(address _stakingPoolFactory) ERC20("stApeX token", "stApeX") ERC20Permit("stApeX token") {
        stakingPoolFactory = _stakingPoolFactory;
    }

    function mint(address account, uint256 amount) external {
        require(msg.sender == stakingPoolFactory, "stApeX: NO_AUTHORITY");
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(msg.sender == stakingPoolFactory, "stApeX: NO_AUTHORITY");
        _burn(account, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(msg.sender == stakingPoolFactory, "stApeX: NO_AUTHORITY");
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        require(msg.sender == stakingPoolFactory, "stApeX: NO_AUTHORITY");
        return super.transferFrom(sender, recipient, amount);
    }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }
}
