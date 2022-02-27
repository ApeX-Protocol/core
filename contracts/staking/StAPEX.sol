// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract StAPEX is ERC20Votes {
    address public stakingPoolFactory;

    constructor(address _stakingPoolFactory) ERC20("stApeX token", "stApeX") ERC20Permit("stApeX token") {
        stakingPoolFactory = _stakingPoolFactory;
    }

    function mint(address account, uint256 amount) external {
        require(msg.sender == stakingPoolFactory, "stApeX.mint: NO_AUTHORITY");
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(msg.sender == stakingPoolFactory, "stApeX.burn: NO_AUTHORITY");
        _burn(account, amount);
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert("stApeX.approve: stToken is non-transferable");
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert("stApeX.transfer: stToken is non-transferable");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("stApeX.transferFrom: stToken is non-transferable");
    }

    function decreaseAllowance(address, uint256) public pure override returns (bool) {
        revert("stApeX.decreaseAllowance: stToken is non-transferable");
    }

    function increaseAllowance(address, uint256) public pure override returns (bool) {
        revert("stApeX.increaseAllowance: stToken is non-transferable");
    }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }
}
