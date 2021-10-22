// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IConfig.sol";
import "./utils/Ownable.sol";

contract Config is IConfig, Ownable {
    address public override priceOracle;
    uint256 public override rebasePriceGap;
    uint256 public override initMarginRatio; //if 1000, means margin ratio >= 10%
    uint256 public override liquidateThreshold; //if 10000, means debt ratio < 100%
    uint256 public override liquidateFeeRatio; //if 100, means liquidator bot get 1% as fee

    uint256 public override liquidateIncentive;
    bool public override onlyPCV;
    uint8 public override beta; // 50-100

    constructor() {}

    function admin() external view override returns (address) {
        return _admin;
    }

    function pendingAdmin() external view override returns (address) {
        return _pendingAdmin;
    }

    function acceptAdmin() external override {
        _acceptAdmin();
    }

    function setPendingAdmin(address newPendingAdmin) external override {
        _setPendingAdmin(newPendingAdmin);
    }

    function setLiquidateIncentive(uint256 newIncentive) external override {}

    function setPriceOracle(address newOracle) external override {
        require(newOracle != address(0), "Config: ZERO_ADDRESS");
        emit PriceOracleChanged(priceOracle, newOracle);
        priceOracle = newOracle;
    }

    function setRebasePriceGap(uint256 newGap) external override {
        require(newGap > 0, "Config: ZERO_GAP");
        emit RebasePriceGapChanged(rebasePriceGap, newGap);
        rebasePriceGap = newGap;
    }

    function setInitMarginRatio(uint256 _initMarginRatio) external onlyAdmin {
        require(_initMarginRatio >= 500, "ratio >= 500");
        initMarginRatio = _initMarginRatio;
    }

    function setLiquidateThreshold(uint256 _liquidateThreshold) external onlyAdmin {
        require(_liquidateThreshold > 9000 && _liquidateThreshold <= 10000, "9000 < liquidateThreshold <= 10000");
        liquidateThreshold = _liquidateThreshold;
    }

    function setLiquidateFeeRatio(uint256 _liquidateFeeRatio) external onlyAdmin {
        require(_liquidateFeeRatio > 0 && _liquidateFeeRatio <= 2000, "0 < liquidateFeeRatio <= 2000");
        liquidateFeeRatio = _liquidateFeeRatio;
    }

    function setBeta(uint8 _beta) external override onlyAdmin {
        beta = _beta;
    }
}
