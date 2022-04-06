// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IPairFactory.sol";
import "../libraries/TransferHelper.sol";
import "../utils/Reentrant.sol";

contract Migrator is Reentrant {
    event Migrate(address indexed user, uint256 oldLiquidity, uint256 newLiquidity, uint256 baseAmount);

    IRouter public oldRouter;
    IRouter public newRouter;
    IPairFactory public oldFactory;
    IPairFactory public newFactory;

    constructor(IRouter oldRouter_, IRouter newRouter_) {
        oldRouter = oldRouter_;
        newRouter = newRouter_;
        oldFactory = IPairFactory(oldRouter.pairFactory());
        newFactory = IPairFactory(newRouter.pairFactory());
    }

    function migrate(address baseToken, address quoteToken) external nonReentrant {
        address oldAmm = oldFactory.getAmm(baseToken, quoteToken);
        uint256 oldLiquidity = IERC20(oldAmm).balanceOf(msg.sender);
        require(oldLiquidity > 0, "ZERO_LIQUIDITY");
        TransferHelper.safeTransferFrom(oldAmm, msg.sender, oldAmm, oldLiquidity);
        (uint256 baseAmount, , ) = IAmm(oldAmm).burn(address(this));
        require(baseAmount > 0, "ZERO_BASE_AMOUNT");

        address newAmm = newFactory.getAmm(baseToken, quoteToken);
        TransferHelper.safeTransfer(baseToken, newAmm, baseAmount);
        ( , , uint256 newLiquidity) = IAmm(newAmm).mint(msg.sender);
        emit Migrate(msg.sender, oldLiquidity, newLiquidity, baseAmount);
    }
}