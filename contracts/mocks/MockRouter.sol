// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMargin} from "../interfaces/IMargin.sol";

contract MockRouter {
    IMargin public margin;
    IERC20 public baseToken;

    constructor(address _baseToken) {
        baseToken = IERC20(_baseToken);
    }

    function setMarginContract(address _marginContract) external {
        margin = IMargin(_marginContract);
    }

    function addMargin(address _receiver, uint256 _amount) external {
        baseToken.transferFrom(msg.sender, address(margin), _amount);
        margin.addMargin(_receiver, _amount);
    }

    function removeMargin(uint256 _amount) external {
        margin.removeMargin(_amount);
    }
}
