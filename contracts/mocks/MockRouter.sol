// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../core/interfaces/IMargin.sol";
import "../core/interfaces/IWETH.sol";

contract MockRouter {
    IMargin public margin;
    IERC20 public baseToken;
    IWETH public WETH;

    constructor(address _baseToken, address _weth) {
        baseToken = IERC20(_baseToken);
        WETH = IWETH(_weth);
    }

    receive() external payable {
        assert(msg.sender == address(WETH)); // only accept ETH via fallback from the WETH contract
    }

    function setMarginContract(address _marginContract) external {
        margin = IMargin(_marginContract);
    }

    function addMargin(address _receiver, uint256 _amount) external {
        baseToken.transferFrom(msg.sender, address(margin), _amount);
        margin.addMargin(_receiver, _amount);
    }

    function removeMargin(uint256 _amount) external {
        margin.removeMargin(msg.sender, msg.sender, _amount);
    }

    function withdrawETH(address quoteToken, uint256 amount) external {
        margin.removeMargin(msg.sender, msg.sender, amount);
        IWETH(WETH).withdraw(amount);
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
                margin.removeMargin(msg.sender, msg.sender, withdrawAmount);
                IWETH(WETH).withdraw(withdrawAmount);
            }
        }
    }
}
