// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IPCVPolicy.sol";
import "../core/interfaces/IAmm.sol";
import "../core/interfaces/IERC20.sol";
import "../core/interfaces/IPairFactory.sol";
import "../libraries/TransferHelper.sol";

contract PCVPolicyForMigrator is IPCVPolicy {
    event Migrate(address indexed user, uint256 oldLiquidity, uint256 newLiquidity, uint256 baseAmount);

    address public pcvTreasury;
    address public newFactory;

    constructor(address treasury, address newFactory_) {
        pcvTreasury = treasury;
        newFactory = newFactory_;
    }

    function execute(address lpToken, uint256 amount, bytes calldata data) external override {
        require(msg.sender == pcvTreasury, "FORBIDDEN");
        uint256 maxBurnLiquidity = IAmm(lpToken).getTheMaxBurnLiquidity();
        require(amount <= maxBurnLiquidity, "GREATER_THAN_MAX_BURN_LIQUIDITY");
        TransferHelper.safeTransfer(lpToken, lpToken, amount);
        (uint256 baseAmount, , ) = IAmm(lpToken).burn(address(this));
        require(baseAmount > 0, "ZERO_BASE_AMOUNT");

        address baseToken = IAmm(lpToken).baseToken();
        address quoteToken = IAmm(lpToken).quoteToken();
        address newAmm = IPairFactory(newFactory).getAmm(baseToken, quoteToken);
        TransferHelper.safeTransfer(baseToken, newAmm, baseAmount);
        ( , , uint256 newLiquidity) = IAmm(newAmm).mint(pcvTreasury);
        emit Migrate(pcvTreasury, amount, newLiquidity, baseAmount);
    }
}