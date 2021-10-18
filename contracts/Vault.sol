// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract Vault {
    IERC20 public token;
    address public margin;
    address public vAmm;
    address public factory;

    event Withdraw(address indexed receiver, uint256 amount);

    constructor(address baseToken, address _vAmm) {
        factory = msg.sender;
        token = IERC20(baseToken);
        vAmm = _vAmm;
    }

    function initialize() external onlyFactory {}

    function setMargin(address _margin) external {
        margin = _margin;
    }

    function withdraw(address _receiver, uint256 _amount) external vAmmOrMargin {
        token.transfer(_receiver, _amount);
        emit Withdraw(_receiver, _amount);
    }

    modifier vAmmOrMargin() {
        require(msg.sender == margin || msg.sender == vAmm, "vAmm or margin");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory);
        _;
    }
}
