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

    constructor() {}

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
        require(_initMarginRatio >= 500, "ratio >= 500");
        initMarginRatio = _initMarginRatio;
    }

    function setLiquidateThreshold(uint256 _liquidateThreshold) external onlyOwner {
        require(_liquidateThreshold > 9000 && _liquidateThreshold <= 10000, "9000 < liquidateThreshold <= 10000");
        liquidateThreshold = _liquidateThreshold;
    }

    function setLiquidateFeeRatio(uint256 _liquidateFeeRatio) external onlyOwner {
        require(_liquidateFeeRatio > 0 && _liquidateFeeRatio <= 2000, "0 < liquidateFeeRatio <= 2000");
        liquidateFeeRatio = _liquidateFeeRatio;
    }
}
