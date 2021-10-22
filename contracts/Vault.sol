// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IVault.sol";
import "./utils/Reentrant.sol";
import "./utils/Ownable.sol";
import "hardhat/console.sol";

contract Vault is IVault, Reentrant, Ownable {
    address public override baseToken;
    address public override margin;
    address public override amm;
    address public override factory;

    constructor() {
        factory = msg.sender;
    }

    function initialize(address _baseToken, address _amm, address _margin) external override onlyFactory {
        baseToken = _baseToken;
        amm = _amm;
        margin = _margin;
    }

    function withdraw(address _receiver, uint256 _amount) external override nonReentrant vAmmOrMargin {
        IERC20(baseToken).transfer(_receiver, _amount);
        emit Withdraw(msg.sender, _receiver, _amount);
    }

    function setMargin(address _margin) external override onlyAdmin {
        margin = _margin;
    }

    function setAmm(address _amm) external onlyAdmin {
        amm = _amm;
    }

    modifier vAmmOrMargin() {
        require(msg.sender == margin || msg.sender == amm, "vAmm or margin");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory);
        _;
    }
}
