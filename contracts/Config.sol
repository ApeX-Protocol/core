// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/Ownable.sol";
import "hardhat/console.sol";

contract Config is Ownable {
    uint256 public initMarginRatio; //if 10, means margin ratio >= 10%
    uint256 public liquidateThreshold; //if 100, means debt ratio < 100%
    uint256 public liquidateFeeRatio; //if 1, means liquidator bot get 1% as fee

    constructor(
        uint256 _initMarginRatio,
        uint256 _liquidateThreshold,
        uint256 _liquidateFeeRatio
    ) {
        initMarginRatio = _initMarginRatio;
        liquidateThreshold = _liquidateThreshold;
        liquidateFeeRatio = _liquidateFeeRatio;
    }

    function setInitMarginRatio(uint256 _initMarginRatio) external onlyOwner {
        require(_initMarginRatio >= 10, "ratio >= 10");
        initMarginRatio = _initMarginRatio;
    }

    function setLiquidateThreshold(uint256 _liquidateThreshold) external onlyOwner {
        require(_liquidateThreshold > 90 && _liquidateThreshold <= 100, "90 < liquidateThreshold <= 100");
        liquidateThreshold = _liquidateThreshold;
    }

    function setLiquidateFeeRatio(uint256 _liquidateFeeRatio) external onlyOwner {
        require(_liquidateFeeRatio > 0 && _liquidateFeeRatio <= 10, "0 < liquidateFeeRatio <= 10");
        liquidateFeeRatio = _liquidateFeeRatio;
    }
}
