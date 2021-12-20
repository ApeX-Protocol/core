// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../core/interfaces/IMargin.sol";
import "../core/interfaces/IWETH.sol";

contract MockRouter {
    IMargin public margin;
    IERC20 public baseToken;
    IWETH public WETH;

    constructor(address _baseToken) {
        baseToken = IERC20(_baseToken);
        WETH = IWETH(_baseToken);
    }

    function setMarginContract(address _marginContract) external {
        margin = IMargin(_marginContract);
    }

    function addMargin(address _receiver, uint256 _amount) external {
        baseToken.transferFrom(msg.sender, address(margin), _amount);
        margin.addMargin(_receiver, _amount);
    }

    function removeMargin(uint256 _amount) external {
        margin.removeMargin(msg.sender, _amount, false);
    }

    function withdrawETH(address quoteToken, uint256 amount) external {
        margin.removeMargin(msg.sender, amount);
        IWETH(WETH).withdrawTo(msg.sender, amount);
    }

    function closePositionETH(
        address quoteToken,
        uint256 quoteAmount,
        uint256 deadline,
        bool autoWithdraw
    ) external returns (uint256 baseAmount, uint256 withdrawAmount) {
        baseAmount = margin.closePosition(msg.sender, quoteAmount);
        if (autoWithdraw) {
            withdrawAmount = margin.getWithdrawable(msg.sender);
            if (withdrawAmount > 0) {
                margin.removeMargin(msg.sender, withdrawAmount);
                IWETH(WETH).withdrawTo(msg.sender, withdrawAmount);
            }
        }
    }
}
