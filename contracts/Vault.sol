// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./utils/Ownable.sol";
import "hardhat/console.sol";

contract Vault is ReentrancyGuard, Ownable {
    IERC20 public token;
    address public margin;
    address public vAmm;
    address public factory;

    event Withdraw(address indexed receiver, uint256 amount);

    constructor(address _baseToken, address _vAmm) {
        factory = msg.sender;
        token = IERC20(_baseToken);
        vAmm = _vAmm;
    }

    function initialize() external onlyFactory {}

    function withdraw(address _receiver, uint256 _amount) external nonReentrant vAmmOrMargin {
        token.transfer(_receiver, _amount);
        emit Withdraw(_receiver, _amount);
    }

    function setMargin(address _margin) external onlyOwner {
        margin = _margin;
    }

    function setAmm(address _amm) external onlyOwner {
        vAmm = _amm;
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
