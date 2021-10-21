// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/Ownable.sol";
import "hardhat/console.sol";

import "./interfaces/IConfig.sol";

contract Config is IConfig, Ownable {
    address public priceOracle;
    uint256 public rebasePriceGap;
    uint256 public initMarginRatio; //if 10, means margin ratio >= 10%
    uint256 public liquidateThreshold; //if 100, means debt ratio < 100%
    uint256 public liquidateFeeRatio; //if 1, means liquidator bot get 1% as fee

    constructor() public {
        owner = msg.sender;
    }

    function setPriceOracle(address newOracle) external {
        require(newOracle != address(0), "Config: ZERO_ADDRESS");
        emit PriceOracleChanged(priceOracle, newOracle);
        priceOracle = newOracle;
    }

    function setRebasePriceGap(uint256 newGap) external {
        require(newGap > 0, "Config: ZERO_GAP");
        emit RebasePriceGapChanged(rebasePriceGap, newGap);
        rebasePriceGap = newGap;
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
