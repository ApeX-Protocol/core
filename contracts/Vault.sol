// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IVault.sol";
import "./utils/Reentrant.sol";
import "./utils/Ownable.sol";

contract Vault is IVault, Reentrant, Ownable {
    address public override baseToken;
    address public override margin;
    address public override amm;
    address public override factory;

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        address _baseToken,
        address _amm,
        address _margin
    ) external override {
        _checkFactory();
        baseToken = _baseToken;
        amm = _amm;
        margin = _margin;
    }

    function withdraw(address _receiver, uint256 _amount) external override nonReentrant {
        _checkVAmmOrMargin();
        IERC20(baseToken).transfer(_receiver, _amount);
        emit Withdraw(msg.sender, _receiver, _amount);
    }

    function setMargin(address _margin) external override {
        _checkAdmin();
        margin = _margin;
    }

    function setAmm(address _amm) external override {
        _checkAdmin();
        amm = _amm;
    }

    function _checkVAmmOrMargin() private view {
        require(msg.sender == margin || msg.sender == amm, "vAmm or margin");
    }

    function _checkFactory() private view {
        require(msg.sender == factory, "factory");
    }
}
