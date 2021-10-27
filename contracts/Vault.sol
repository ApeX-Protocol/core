// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IVault.sol";
import "./utils/Reentrant.sol";

contract Vault is IVault, Reentrant {
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
        require(msg.sender == factory, "Vault: REQUIRE_FACTORY");
        baseToken = _baseToken;
        amm = _amm;
        margin = _margin;
    }

    function withdraw(address _receiver, uint256 _amount) external override nonReentrant {
        require(msg.sender == margin || msg.sender == amm, "Vault: REQUIRE_AMM_OR_MARGIN");
        require(_amount > 0, "Vault: AMOUNT_IS_ZERO");
        IERC20(baseToken).transfer(_receiver, _amount);
        emit Withdraw(msg.sender, _receiver, _amount);
    }
}
