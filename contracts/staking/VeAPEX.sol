// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract VeAPEX is ERC20Votes {
    address public stakingPoolFactory;
    event Mint(address, uint256);
    event Burn(address, uint256);

    constructor(address _stakingPoolFactory) ERC20("veApeX token", "veApeX") ERC20Permit("veApeX token") {
        stakingPoolFactory = _stakingPoolFactory;
    }

    function mint(address account, uint256 amount) external {
        require(msg.sender == stakingPoolFactory, "veApeX.mint: NO_AUTHORITY");
        _mint(account, amount);

        emit Mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(msg.sender == stakingPoolFactory, "veApeX.burn: NO_AUTHORITY");
        _burn(account, amount);

        emit Burn(account, amount);
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert("veApeX.approve: veToken is non-transferable");
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert("veApeX.transfer: veToken is non-transferable");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert("veApeX.transferFrom: veToken is non-transferable");
    }

    function decreaseAllowance(address, uint256) public pure override returns (bool) {
        revert("veApeX.decreaseAllowance: veToken is non-transferable");
    }

    function increaseAllowance(address, uint256) public pure override returns (bool) {
        revert("veApeX.increaseAllowance: veToken is non-transferable");
    }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }
}
