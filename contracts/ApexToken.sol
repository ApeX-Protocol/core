// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ApexToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address minter) ERC20("Apex Token", "apex") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, minter);
    }

    function mint(address account, uint256 amount) external {
        require(hasRole(MINTER_ROLE, msg.sender), "APEX: CALLER_NOT_MINTER");
        _mint(account, amount);
    }
}
